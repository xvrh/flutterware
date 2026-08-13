/// Setting what the OS holds, and proving it landed.
///
/// One rule governs this whole file, and it is not a style preference:
/// **every write is followed by a read, and the answer is the state after.**
/// S-P1 measured `pm grant` of an undeclared permission exiting 0, printing
/// nothing, and granting nothing; `simctl`'s help under-reports its own
/// surface; `granted=` under-reports Android's state. Nothing here can be
/// trusted from an exit code, so nothing here reports one.
///
/// Two platform differences are encoded rather than smoothed over:
///
/// - **Android needs the flags, not just grant/revoke.** `pm revoke` alone
///   produces a state indistinguishable from never-asked, so `denied` and
///   `denied forever` are composed from `set-permission-flags`.
/// - **iOS has no denied-forever.** A TCC row set to denied already means the
///   app cannot re-prompt; asking for `deniedForever` there gets `denied` and
///   is *said*, not silently downgraded.
///
/// And one that is a refusal rather than a difference: **`pm
/// reset-permissions` is global** — it takes no package argument and its help
/// says *all* runtime permissions. `first-run` for one app is composed per
/// permission instead. Resetting every app on somebody's device because they
/// asked about one is not a thing this will do.
library;

import 'dart:io';

import 'native/adb_driver.dart';
import 'permission_state.dart';
import 'permissions.dart';

/// A named set of states to put an app into.
enum PermissionProfile {
  /// Everything undetermined — the app will prompt. The state the whole
  /// feature exists for, and the one that is hardest to reach by hand.
  firstRun('first-run', 'First run'),
  granted('granted', 'All granted'),
  denied('denied', 'All denied'),
  deniedForever('denied-forever', 'Denied forever');

  const PermissionProfile(this.id, this.label);

  final String id;
  final String label;

  static PermissionProfile? byId(String id) {
    for (var profile in values) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  HeldState get target => switch (this) {
    firstRun => HeldState.undetermined,
    granted => HeldState.granted,
    denied => HeldState.denied,
    deniedForever => HeldState.deniedForever,
  };
}

/// One command that was run, and what it was for.
class PermissionWriteStep {
  const PermissionWriteStep({
    required this.command,
    required this.ok,
    this.error,
  });

  final String command;
  final bool ok;
  final String? error;
}

/// What a write did, and — the part that matters — what is true now.
class PermissionWriteResult {
  const PermissionWriteResult({
    required this.after,
    this.steps = const [],
    this.refused = const [],
    this.unavailable,
  });

  /// The read-back. Never the request echoed.
  final HeldPermissions after;

  final List<PermissionWriteStep> steps;

  /// Things asked for that this platform cannot express, each with its reason.
  /// Reported rather than dropped, because a request that quietly became
  /// something else is the failure this design is built to avoid.
  final List<String> refused;

  final String? unavailable;
}

/// The `pm` commands that put one Android permission into [target].
///
/// Pure, so the composition is testable without a device — and the
/// composition is the part with the reasoning in it.
///
/// The flags are cleared *first* in every case. Going from denied-forever to
/// granted by `pm grant` alone leaves `USER_FIXED` sitting on the permission,
/// and the next read reports a granted permission the user supposedly refused
/// permanently.
List<List<String>> androidCommandsFor(String identifier, HeldState target) {
  const flags = ['user-set', 'user-fixed'];
  return switch (target) {
    HeldState.granted => [
      ['clear-permission-flags', identifier, ...flags],
      ['grant', identifier],
    ],
    HeldState.undetermined => [
      ['revoke', identifier],
      ['clear-permission-flags', identifier, ...flags],
    ],
    HeldState.denied => [
      ['revoke', identifier],
      ['clear-permission-flags', identifier, 'user-fixed'],
      ['set-permission-flags', identifier, 'user-set'],
    ],
    HeldState.deniedForever => [
      ['revoke', identifier],
      ['set-permission-flags', identifier, 'user-set', 'user-fixed'],
    ],
    // Nothing to do, and nothing that could be done: `unknown` is the absence
    // of an answer, not a state anything can be put into.
    HeldState.unknown => const [],
  };
}

/// The `simctl privacy` verb for [target], or null when iOS has no such state.
String? simctlVerbFor(HeldState target) => switch (target) {
  HeldState.granted => 'grant',
  HeldState.denied || HeldState.deniedForever => 'revoke',
  HeldState.undetermined => 'reset',
  HeldState.unknown => null,
};

/// Puts [wanted] into effect on [device], then reads back.
Future<PermissionWriteResult> writePermissions({
  required String device,
  required String packageRoot,
  required Map<String, HeldState> wanted,
  required Future<HeldPermissions> Function() readBack,
  String? adbPath,
  bool isSimulator = false,
}) async {
  var adb = adbPath ?? AdbNativeDriver.findAdb();
  if (adb != null && await AdbNativeDriver.owns(device, adb)) {
    var identity = androidIdentity(packageRoot);
    if (identity == null) {
      return PermissionWriteResult(
        after: await readBack(),
        unavailable:
            "Could not work out this app's application id, so there is "
            'nothing safe to write to. Build it once first.',
      );
    }
    return _writeAndroid(
      adb: adb,
      serial: device,
      identity: identity,
      wanted: wanted,
      readBack: readBack,
    );
  }
  if (isSimulator) {
    var identity = appleIdentity(packageRoot);
    if (identity == null) {
      return PermissionWriteResult(
        after: await readBack(),
        unavailable: 'Could not find a bundle id in ios/Runner.xcodeproj.',
      );
    }
    return _writeSimulator(
      udid: device,
      identity: identity,
      wanted: wanted,
      readBack: readBack,
    );
  }
  return PermissionWriteResult(
    after: await readBack(),
    unavailable:
        'Nothing on this machine can set what "$device" holds. Android '
        'devices and booted simulators are the two that can be written to; '
        'macOS writes cannot be verified and a physical iPhone has no '
        'host-side store at all.',
  );
}

Future<PermissionWriteResult> _writeAndroid({
  required String adb,
  required String serial,
  required AppIdentity identity,
  required Map<String, HeldState> wanted,
  required Future<HeldPermissions> Function() readBack,
}) async {
  var steps = <PermissionWriteStep>[];
  var refused = <String>[];
  for (var entry in wanted.entries) {
    var capability = Capability.all.where((e) => e.id == entry.key).firstOrNull;
    if (capability == null || capability.android.isEmpty) {
      refused.add(
        '${entry.key} has no Android permission behind it, so there is '
        'nothing to set.',
      );
      continue;
    }
    for (var identifier in capability.android) {
      for (var command in androidCommandsFor(identifier, entry.value)) {
        var result = await Process.run(adb, [
          '-s',
          serial,
          'shell',
          'pm',
          ...command.take(1),
          identity.id,
          ...command.skip(1),
        ]);
        // The exit code is recorded and *not* believed — see the library doc.
        // Only the read-back below decides what happened.
        steps.add(
          PermissionWriteStep(
            command:
                'pm ${command.first} ${identity.id} ${command.skip(1).join(' ')}',
            ok: result.exitCode == 0,
            error: result.exitCode == 0
                ? null
                : '${result.stderr}'.trim().isEmpty
                ? 'exit ${result.exitCode}'
                : '${result.stderr}'.trim(),
          ),
        );
      }
    }
  }
  return PermissionWriteResult(
    after: await readBack(),
    steps: steps,
    refused: refused,
  );
}

Future<PermissionWriteResult> _writeSimulator({
  required String udid,
  required AppIdentity identity,
  required Map<String, HeldState> wanted,
  required Future<HeldPermissions> Function() readBack,
}) async {
  var steps = <PermissionWriteStep>[];
  var refused = <String>[];
  for (var entry in wanted.entries) {
    var service = tccServices[entry.key];
    if (service == null) {
      refused.add(
        "${entry.key} is not in the simulator's TCC database, so it cannot "
        'be set from the host. '
        '${entry.key == 'location' ? simulatorLocationNote : ''}'
        '${entry.key == 'notifications' ? simulatorNotificationNote : ''}',
      );
      continue;
    }
    if (entry.value == HeldState.deniedForever) {
      // Said, not silently downgraded. A denied TCC row already stops the app
      // re-prompting, so the *effect* is right — but the caller asked for a
      // state this platform does not have and deserves to know.
      refused.add(
        'iOS has no separate denied-forever state; a denied permission '
        'already cannot be re-prompted. Set to denied instead.',
      );
    }
    var verb = simctlVerbFor(entry.value);
    if (verb == null) continue;
    var result = await Process.run('xcrun', [
      'simctl',
      'privacy',
      udid,
      verb,
      _simctlService(entry.key),
      identity.id,
    ]);
    steps.add(
      PermissionWriteStep(
        command: 'simctl privacy $udid $verb ${_simctlService(entry.key)}',
        ok: result.exitCode == 0,
        error: result.exitCode == 0 ? null : '${result.stderr}'.trim(),
      ),
    );
  }
  return PermissionWriteResult(
    after: await readBack(),
    steps: steps,
    refused: refused,
  );
}

/// The word `simctl privacy` takes for a capability.
///
/// Not the TCC service name and not the capability id — a third spelling,
/// which is why it is a table rather than a transformation.
String _simctlService(String capability) => switch (capability) {
  'photosAdd' => 'photos-add',
  'mediaLibrary' => 'media-library',
  _ => capability,
};

/// The states a profile wants, for the capabilities an app actually declares.
///
/// Driven by the declared rows rather than by the catalogue: "all granted"
/// means all of *this app's* permissions, and granting something it never
/// asked for would be both useless and a lie about what the app does.
///
/// [on] narrows that to the platform being written to, and passing it is what
/// keeps a profile quiet. Without it an app that declares
/// `NSFaceIDUsageDescription` sent faceId to the Android writer on every
/// launch with a wish in force, got back *"faceId has no Android permission
/// behind it"*, and that sentence rode into the launch note — a refusal for a
/// capability nobody asked to set, that is simply not an Android concept.
///
/// **Only profiles narrow.** `permissionSet camera` on a device where camera
/// has no identifier is still refused loudly: there the caller named the
/// capability, and silence would be the write that did nothing and said so.
Map<String, HeldState> profileTargets(
  PermissionProfile profile,
  Iterable<PermissionRow> declared, {
  PermissionPlatform? on,
}) => {
  for (var row in declared)
    if (row.known && (on == null || row.platforms.contains(on)))
      row.capability: profile.target,
};

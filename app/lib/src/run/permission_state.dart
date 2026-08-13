/// What the **OS currently records** for an app — the *held* third.
///
/// Everything here is read-only and host-side: `dumpsys package` over `adb`,
/// the simulator's own `TCC.db` with `sqlite3`. Nothing is written, and
/// nothing needs the app to be running or to cooperate.
///
/// The shape follows what the spikes measured
/// (`docs/superpowers/specs/2026-08-12-run-permissions-spike-findings.md`), and
/// two of those findings are load-bearing here:
///
/// - **`granted=` is only two of the four states.** After a `pm revoke`, a
///   revoked permission and a never-touched one are byte-identical in that
///   field. The `flags` are the vocabulary — `USER_SET` means the user was
///   asked, `USER_FIXED` means they will not be asked again.
/// - **An empty parse is an error, not an empty answer.** `dumpsys` output is
///   not a contract, and "this app holds nothing" must never be indistinguish-
///   able from "this device could not be read".
///
/// Parsing is separated from the shelling out on purpose: the parsers are pure
/// and tested against captured output, so none of this needs a device in CI.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'native/adb_driver.dart';
import 'permissions.dart';

/// What the OS records for one capability.
enum HeldState {
  granted('granted'),
  denied('denied'),

  /// Denied and the platform will not ask again — Android's
  /// `USER_SET|USER_FIXED`. The state most apps handle worst.
  deniedForever('denied forever'),

  /// Never asked. The app will prompt.
  undetermined('undetermined'),

  /// This platform, or this store, cannot say. **Not the same as
  /// [undetermined]** — that is an answer, this is the absence of one.
  unknown('unknown');

  const HeldState(this.label);

  final String label;
}

/// Which app the host-side commands are talking about, and how that was
/// decided.
class AppIdentity {
  const AppIdentity({
    required this.id,
    required this.source,
    this.exact = true,
  });

  /// `com.example.app.dev` — the application id, **not** the Dart package
  /// name, which is what `RunHandle.package` carries.
  final String id;

  /// A phrase for where it came from, shown rather than implied so a wrong id
  /// is correctable instead of mysterious.
  final String source;

  /// False when this is a guess from source that the build could contradict.
  final bool exact;
}

/// One device's answer about one app.
class HeldPermissions {
  const HeldPermissions({
    this.byCapability = const {},
    this.raw = const {},
    this.sources = const [],
    this.notes = const [],
    this.identity,
    this.unavailable,
  });

  /// Keyed by [Capability.id], so it joins straight onto a declared row.
  final Map<String, HeldState> byCapability;

  /// The platform's own keys and states, kept because the moment somebody acts
  /// on one — a `pm grant` — the capability name is in the way.
  final Map<String, HeldState> raw;

  final List<String> sources;

  /// Why particular capabilities read as [HeldState.unknown] on this device.
  /// Separate from [unavailable], which is about the whole device.
  final List<String> notes;

  final AppIdentity? identity;

  /// Why there is nothing, when there is nothing. Present exactly when this
  /// device cannot answer, so an empty map is never ambiguous.
  final String? unavailable;

  bool get available => unavailable == null;
}

// --- Android -----------------------------------------------------------------

/// Reads the four states out of `dumpsys package <id>`.
///
/// Returns null when the output has no `runtime permissions:` section at all —
/// which means the package is not installed, or `dumpsys` said something this
/// does not understand. Either way it is not "the app holds nothing".
Map<String, HeldState>? parseAndroidHeld(String dumpsys) {
  if (!dumpsys.contains('runtime permissions:')) return null;
  var held = <String, HeldState>{};
  var inSection = false;
  for (var line in const LineSplitter().convert(dumpsys)) {
    var trimmed = line.trim();
    if (trimmed == 'runtime permissions:') {
      inSection = true;
      continue;
    }
    if (!inSection) continue;
    // The section ends at the first line that is not a `permission: granted=…`
    // row. Blank lines inside it are tolerated because some builds emit them.
    if (trimmed.isEmpty) continue;
    var match = RegExp(
      r'^([\w.]+):\s*granted=(true|false)(?:,\s*flags=\[([^\]]*)\])?',
    ).firstMatch(trimmed);
    if (match == null) break;
    var flags = match.group(3) ?? '';
    held[match.group(1)!] = switch (match.group(2)) {
      'true' => HeldState.granted,
      // Order matters: USER_FIXED implies USER_SET, and the stronger state is
      // the one worth reporting.
      _ when flags.contains('USER_FIXED') => HeldState.deniedForever,
      _ when flags.contains('USER_SET') => HeldState.denied,
      _ => HeldState.undetermined,
    };
  }
  return held;
}

/// The application id this package builds, best source first.
///
/// The ladder from the design's Decision 2, minus the two rungs that need a
/// running app or a person: the merged manifest is exact and free (it is
/// already read for declarations), and the Gradle `applicationId` is a regexp
/// over a program, so it is marked as a guess.
AppIdentity? androidIdentity(String packageRoot) {
  var merged = newestMergedManifestPath(packageRoot);
  if (merged != null) {
    try {
      var document = XmlDocument.parse(File(merged).readAsStringSync());
      if (document.rootElement.getAttribute('package') case var id?
          when id.isNotEmpty) {
        return AppIdentity(id: id, source: 'the merged manifest');
      }
    } on Object {
      // Fall through to the guess rather than failing: a manifest that will
      // not parse is not a reason to have no id at all.
    }
  }
  for (var name in ['build.gradle.kts', 'build.gradle']) {
    var file = File(p.join(packageRoot, 'android', 'app', name));
    if (!file.existsSync()) continue;
    var match = RegExp(
      r'''applicationId\s*=?\s*["']([\w.]+)["']''',
    ).firstMatch(file.readAsStringSync());
    if (match != null) {
      return AppIdentity(
        id: match.group(1)!,
        source: 'android/app/$name',
        exact: false,
      );
    }
  }
  return null;
}

/// Asks a connected Android device what it holds for [identity].
Future<HeldPermissions> readAndroidHeld({
  required String serial,
  required AppIdentity identity,
  String? adbPath,
}) async {
  var adb = adbPath ?? AdbNativeDriver.findAdb();
  if (adb == null) {
    return const HeldPermissions(
      unavailable:
          'No adb on this machine, so nothing can be read from an Android '
          'device. Install the Android SDK platform-tools.',
    );
  }
  ProcessResult result;
  try {
    result = await Process.run(adb, [
      '-s',
      serial,
      'shell',
      'dumpsys',
      'package',
      identity.id,
    ]);
  } on ProcessException catch (e) {
    return HeldPermissions(unavailable: 'Could not run adb: ${e.message}');
  }
  if (result.exitCode != 0) {
    return HeldPermissions(
      identity: identity,
      unavailable: 'adb could not read $serial: ${'${result.stderr}'.trim()}',
    );
  }
  var parsed = parseAndroidHeld('${result.stdout}');
  if (parsed == null) {
    return HeldPermissions(
      identity: identity,
      unavailable:
          '${identity.id} is not installed on $serial, or dumpsys answered '
          'something this cannot read. Run the app once and try again.',
    );
  }
  return HeldPermissions(
    byCapability: heldByCapability(parsed),
    raw: parsed,
    sources: ['dumpsys package ${identity.id}'],
    identity: identity,
  );
}

// --- iOS simulator -----------------------------------------------------------

/// The TCC service each capability is stored under.
///
/// Measured 2026-08-13 by granting every service `simctl privacy` accepts on a
/// throwaway simulator and reading the row back, rather than recalled. Both
/// location variants are deliberately absent: they write **no TCC row at all**
/// (see [simulatorLocationNote]).
const tccServices = <String, String>{
  'camera': 'kTCCServiceCamera',
  'microphone': 'kTCCServiceMicrophone',
  'photos': 'kTCCServicePhotos',
  'photosAdd': 'kTCCServicePhotosAdd',
  'contacts': 'kTCCServiceAddressBook',
  'calendar': 'kTCCServiceCalendar',
  'reminders': 'kTCCServiceReminders',
  'motion': 'kTCCServiceMotion',
  'mediaLibrary': 'kTCCServiceMediaLibrary',
};

/// Why iOS location has no state here, said once and reused.
/// Why notifications are unknown on a simulator.
const simulatorNotificationNote =
    'Notification authorization is not in TCC either, and `simctl privacy` '
    'refuses the service outright — measured. Only the app can report it.';

const simulatorLocationNote =
    "Location is not in the simulator's TCC database — it lives in "
    "locationd's own store, which only has an entry once the app has "
    'registered with it, and on a fresh simulator has no file at all. Not '
    'read here rather than guessed at.';

/// Turns `service|auth_value` rows into states.
///
/// **An absent row means undetermined** — that is what a fresh app looks like,
/// and it is why this takes the whole result set rather than asking per
/// service. `auth_value` is 0 denied, 2 allowed, 3 allowed-but-limited.
Map<String, HeldState> parseTccRows(Map<String, int> rows) {
  var byService = {
    for (var entry in rows.entries)
      entry.key: switch (entry.value) {
        0 => HeldState.denied,
        2 || 3 => HeldState.granted,
        _ => HeldState.unknown,
      },
  };
  return {
    for (var entry in tccServices.entries)
      entry.key: byService[entry.value] ?? HeldState.undetermined,
  };
}

/// Reads a booted simulator's TCC database directly.
///
/// The file is world-readable and needs no Full Disk Access — measured, and
/// the reason there is a read path on iOS at all, since `simctl privacy`
/// writes but cannot read.
Future<HeldPermissions> readSimulatorHeld({
  required String udid,
  required AppIdentity identity,
  String? home,
}) async {
  var root = home ?? Platform.environment['HOME'] ?? '';
  var db = p.join(
    root,
    'Library/Developer/CoreSimulator/Devices',
    udid,
    'data/Library/TCC/TCC.db',
  );
  if (!File(db).existsSync()) {
    return HeldPermissions(
      identity: identity,
      unavailable:
          'No TCC database for simulator $udid. It appears once the device '
          'has been booted.',
    );
  }
  ProcessResult result;
  try {
    result = await Process.run('sqlite3', [
      db,
      "select service, auth_value from access where client='${identity.id}';",
    ]);
  } on ProcessException catch (e) {
    return HeldPermissions(
      identity: identity,
      unavailable: 'Could not run sqlite3: ${e.message}',
    );
  }
  if (result.exitCode != 0) {
    return HeldPermissions(
      identity: identity,
      unavailable: 'Could not read $db: ${'${result.stderr}'.trim()}',
    );
  }
  var rows = <String, int>{};
  for (var line in const LineSplitter().convert('${result.stdout}')) {
    var parts = line.split('|');
    if (parts.length != 2) continue;
    if (int.tryParse(parts[1].trim()) case var value?) {
      rows[parts[0].trim()] = value;
    }
  }
  return HeldPermissions(
    byCapability: {
      ...parseTccRows(rows),
      // Named as unknown rather than left absent. A missing entry would read
      // as "no device asked"; these were asked about and the store genuinely
      // does not cover them, which is a third thing.
      'location': HeldState.unknown,
      'locationAlways': HeldState.unknown,
      'notifications': HeldState.unknown,
    },
    notes: [simulatorLocationNote, simulatorNotificationNote],
    raw: {
      for (var entry in rows.entries)
        entry.key: switch (entry.value) {
          0 => HeldState.denied,
          2 || 3 => HeldState.granted,
          _ => HeldState.unknown,
        },
    },
    sources: ['TCC.db'],
    identity: identity,
  );
}

/// The panel a `PermissionAdapter` serves, and the state it offers.
///
/// Named here rather than typed in three places: the app side of this pair is
/// `lib/src/devbar/plugins/permissions.dart`, and the two halves have to agree
/// on the strings or the column is silently always empty.
const permissionsPanelId = 'permissions';
const permissionsStatusStateId = 'status';

/// Turns that panel's reply into states, keyed by capability.
///
/// The wire words are the same five [HeldState] uses — deliberately, so no
/// translation table has to be kept in step. Anything unrecognised reads as
/// [HeldState.unknown] rather than being dropped, because a row that vanishes
/// is indistinguishable from a row nobody asked about.
Map<String, HeldState> parseObservedPermissions(Map<String, Object?> reply) {
  if (reply['permissions'] case Map raw) {
    return {
      for (var entry in raw.entries)
        '${entry.key}':
            HeldState.values
                .where((e) => e.name == '${entry.value}')
                .firstOrNull ??
            HeldState.unknown,
    };
  }
  return const {};
}

/// The bundle id from the Xcode project, or null.
///
/// A regexp over the pbxproj rather than a parse: the project file is a format
/// nobody should take a dependency on, and every configuration in a stock
/// Flutter project carries the same value. Marked inexact for the cases where
/// they differ.
AppIdentity? appleIdentity(String packageRoot, {String dir = 'ios'}) {
  var project = File(
    p.join(packageRoot, dir, 'Runner.xcodeproj', 'project.pbxproj'),
  );
  if (!project.existsSync()) return null;
  var matches = RegExp(
    r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([\w.\-]+)\s*;',
  ).allMatches(project.readAsStringSync());
  var ids = {for (var match in matches) match.group(1)!}
    ..removeWhere((e) => e.endsWith('.RunnerTests'));
  if (ids.isEmpty) return null;
  return AppIdentity(
    id: ids.first,
    source: '$dir/Runner.xcodeproj',
    exact: ids.length == 1,
  );
}

/// Collapses per-identifier states onto capabilities, most-granted wins.
Map<String, HeldState> heldByCapability(Map<String, HeldState> byIdentifier) {
  var held = <String, HeldState>{};
  for (var entry in byIdentifier.entries) {
    var capability = Capability.forIdentifier(entry.key);
    if (capability == null) continue;
    // A capability with several identifiers — fine *and* coarse location — is
    // as granted as its most granted member: holding coarse is holding
    // location, and reporting "denied" because the fine one is not held would
    // describe an app that is currently reading the user's position.
    var current = held[capability.id];
    held[capability.id] = current == null
        ? entry.value
        : _strongest(current, entry.value);
  }
  return held;
}

/// Ranks by **how much the app can still do**, not by how bad it looks.
///
/// `undetermined` outranks `denied` and `denied` outranks `deniedForever`
/// because each is one dialog closer to working: an app whose coarse location
/// is merely denied can still prompt and end up with location, and reporting
/// the fine permission's `deniedForever` would say the capability is closed
/// when it is not.
HeldState _strongest(HeldState a, HeldState b) {
  const order = [
    HeldState.granted,
    HeldState.undetermined,
    HeldState.denied,
    HeldState.deniedForever,
    HeldState.unknown,
  ];
  return order.indexOf(a) <= order.indexOf(b) ? a : b;
}

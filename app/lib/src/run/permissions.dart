/// What an app *asks for*, read from what it ships.
///
/// This is the **declared** third of a permission — the one that needs no
/// device, no run and no build, because `AndroidManifest.xml` and
/// `Info.plist` are checked-in files. Held state (what the OS records) and
/// observed state (what the app believes) come later and from elsewhere; see
/// `docs/superpowers/specs/2026-08-12-run-permissions-design.md`.
///
/// Two rules shape everything here:
///
/// - **The row is the capability, not the identifier.**
///   `NSCameraUsageDescription` and `android.permission.CAMERA` are one thing
///   seen from two platforms, and a reader who has to re-learn the list per
///   platform is reading two reports. The native identifier stays visible on
///   the row, because the moment you act on one — a `pm grant`, a plist edit —
///   the abstraction is in the way.
/// - **Never a catalogue.** Only what this app declares is listed. A grid of
///   every permission the platform has ever defined, mostly greyed out, would
///   be longer and say less. Anything declared that this file has no name for
///   is still reported, under its raw identifier — see [Capability.other].
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Which of an app's shipped descriptions a declaration was read from.
enum PermissionPlatform {
  android('Android'),
  ios('iOS'),
  macos('macOS');

  const PermissionPlatform(this.label);

  final String label;
}

/// One capability, and the identifiers each platform knows it by.
///
/// Android maps to several identifiers for one capability more often than not
/// (fine *and* coarse location), which is why these are lists: the row says
/// "Location", and carries whichever of them the app actually asked for.
class Capability {
  const Capability(
    this.id,
    this.label, {
    this.android = const [],
    this.apple = const [],
    this.entitlements = const [],
  });

  final String id;
  final String label;
  final List<String> android;

  /// The `NS…UsageDescription` keys, which on Apple platforms *are* the
  /// declaration — there is no separate list of requested permissions.
  final List<String> apple;

  /// macOS sandbox entitlements. A sandboxed Mac app that omits these cannot
  /// reach the hardware however many usage descriptions it ships.
  final List<String> entitlements;

  /// The row for something declared that this catalogue has no name for.
  ///
  /// Reported rather than dropped: a permission nobody here anticipated is
  /// exactly the one worth seeing, and silently omitting it would make the
  /// list a lie in the one case that matters.
  static Capability other(String identifier) =>
      Capability(identifier, identifier);

  static const camera = Capability(
    'camera',
    'Camera',
    android: ['android.permission.CAMERA'],
    apple: ['NSCameraUsageDescription'],
    entitlements: ['com.apple.security.device.camera'],
  );
  static const microphone = Capability(
    'microphone',
    'Microphone',
    android: ['android.permission.RECORD_AUDIO'],
    apple: ['NSMicrophoneUsageDescription'],
    entitlements: ['com.apple.security.device.audio-input'],
  );
  static const location = Capability(
    'location',
    'Location, when in use',
    android: [
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
    ],
    apple: ['NSLocationWhenInUseUsageDescription'],
    entitlements: ['com.apple.security.personal-information.location'],
  );
  static const locationAlways = Capability(
    'locationAlways',
    'Location, always',
    android: ['android.permission.ACCESS_BACKGROUND_LOCATION'],
    apple: [
      'NSLocationAlwaysAndWhenInUseUsageDescription',
      'NSLocationAlwaysUsageDescription',
    ],
  );
  static const notifications = Capability(
    'notifications',
    'Notifications',
    android: ['android.permission.POST_NOTIFICATIONS'],
    // Deliberately empty: iOS has no plist key for notifications. The absence
    // is why the cross-platform lint skips this row.
  );
  static const photos = Capability(
    'photos',
    'Photo library',
    android: [
      'android.permission.READ_MEDIA_IMAGES',
      'android.permission.READ_MEDIA_VIDEO',
      'android.permission.READ_EXTERNAL_STORAGE',
    ],
    apple: ['NSPhotoLibraryUsageDescription'],
    entitlements: ['com.apple.security.personal-information.photos-library'],
  );
  static const photosAdd = Capability(
    'photosAdd',
    'Photo library, adding',
    apple: ['NSPhotoLibraryAddUsageDescription'],
  );
  static const contacts = Capability(
    'contacts',
    'Contacts',
    android: [
      'android.permission.READ_CONTACTS',
      'android.permission.WRITE_CONTACTS',
    ],
    apple: ['NSContactsUsageDescription'],
    entitlements: ['com.apple.security.personal-information.addressbook'],
  );
  static const calendar = Capability(
    'calendar',
    'Calendar',
    android: [
      'android.permission.READ_CALENDAR',
      'android.permission.WRITE_CALENDAR',
    ],
    apple: [
      'NSCalendarsUsageDescription',
      'NSCalendarsFullAccessUsageDescription',
    ],
    entitlements: ['com.apple.security.personal-information.calendars'],
  );
  static const reminders = Capability(
    'reminders',
    'Reminders',
    apple: [
      'NSRemindersUsageDescription',
      'NSRemindersFullAccessUsageDescription',
    ],
  );
  static const bluetooth = Capability(
    'bluetooth',
    'Bluetooth',
    android: [
      'android.permission.BLUETOOTH_SCAN',
      'android.permission.BLUETOOTH_CONNECT',
      'android.permission.BLUETOOTH_ADVERTISE',
    ],
    apple: [
      'NSBluetoothAlwaysUsageDescription',
      'NSBluetoothPeripheralUsageDescription',
    ],
    entitlements: ['com.apple.security.device.bluetooth'],
  );
  static const motion = Capability(
    'motion',
    'Motion and fitness',
    android: ['android.permission.ACTIVITY_RECOGNITION'],
    apple: ['NSMotionUsageDescription'],
  );
  static const speech = Capability(
    'speech',
    'Speech recognition',
    apple: ['NSSpeechRecognitionUsageDescription'],
  );
  static const tracking = Capability(
    'tracking',
    'Tracking',
    apple: ['NSUserTrackingUsageDescription'],
  );
  static const mediaLibrary = Capability(
    'mediaLibrary',
    'Media library',
    apple: ['NSAppleMusicUsageDescription'],
  );
  static const faceId = Capability(
    'faceId',
    'Face ID',
    apple: ['NSFaceIDUsageDescription'],
  );
  static const localNetwork = Capability(
    'localNetwork',
    'Local network',
    apple: ['NSLocalNetworkUsageDescription'],
  );

  static const all = [
    camera,
    microphone,
    location,
    locationAlways,
    notifications,
    photos,
    photosAdd,
    contacts,
    calendar,
    reminders,
    bluetooth,
    motion,
    speech,
    tracking,
    mediaLibrary,
    faceId,
    localNetwork,
  ];

  /// The capability an identifier belongs to, or null when nothing claims it.
  static Capability? forIdentifier(String identifier) {
    for (var capability in all) {
      if (capability.android.contains(identifier) ||
          capability.apple.contains(identifier) ||
          capability.entitlements.contains(identifier)) {
        return capability;
      }
    }
    return null;
  }
}

/// One identifier an app declares, and where it was read from.
class DeclaredPermission {
  const DeclaredPermission({
    required this.identifier,
    required this.platform,
    required this.source,
    this.usage,
    this.maxSdkVersion,
    this.fromDependency = false,
  });

  /// `android.permission.CAMERA`, `NSCameraUsageDescription`, or an
  /// entitlement key.
  final String identifier;

  final PermissionPlatform platform;

  /// Package-relative path of the file this was read from, `/`-separated.
  final String source;

  /// The Apple usage description, verbatim. Null on Android, where there is
  /// nothing to say. Empty string is *not* null and is a lint — App Review
  /// rejects a blank reason.
  final String? usage;

  /// `android:maxSdkVersion`, when the manifest caps one.
  final String? maxSdkVersion;

  /// True when the merged manifest has it and the app's own does not — a
  /// permission some dependency contributed. These are the ones people meet
  /// for the first time at store review.
  final bool fromDependency;
}

/// How serious a finding is. Nothing here is fatal; the app builds either way.
enum PermissionLintSeverity { problem, warning, note }

/// One disagreement between what the app ships and what it will need.
class PermissionLint {
  const PermissionLint({
    required this.id,
    required this.severity,
    required this.message,
    this.capability,
    this.platform,
  });

  final String id;
  final PermissionLintSeverity severity;

  /// Written to be read on its own, because it travels to `fw` and MCP where
  /// there is no row next to it for context.
  final String message;

  final String? capability;
  final PermissionPlatform? platform;
}

/// One capability the app declares, gathered across every platform it ships.
class PermissionRow {
  const PermissionRow({
    required this.capability,
    required this.label,
    required this.declarations,
    required this.known,
  });

  final String capability;
  final String label;
  final List<DeclaredPermission> declarations;

  /// Whether the catalogue named this, or it is being reported under its raw
  /// identifier.
  ///
  /// The split exists because of what the unknown ones turned out to be. Every
  /// Flutter app declares `INTERNET` and a generated
  /// `…DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, neither of which a user is
  /// ever asked to grant — and in the first render of this field they were two
  /// of five rows, one of them wrapping onto two lines. They are still
  /// reported, because dropping a declaration would make the list a lie; they
  /// are just not what the field is *about*.
  final bool known;

  Iterable<PermissionPlatform> get platforms => {
    for (var d in declarations) d.platform,
  };
}

/// Everything one package declares, and what is wrong with it.
class PermissionDeclarations {
  const PermissionDeclarations({
    required this.rows,
    required this.lints,
    required this.sources,
    required this.platformsPresent,
    this.merged = false,
  });

  final List<PermissionRow> rows;
  final List<PermissionLint> lints;

  /// The files actually read, package-relative. Shown rather than implied: a
  /// report that names its sources can be checked, and one that does not has
  /// to be trusted.
  final List<String> sources;

  /// Which platform directories this package actually has. An app with no
  /// `ios/` is not an app that forgot its usage descriptions, and the
  /// cross-platform lint has to know the difference.
  final List<PermissionPlatform> platformsPresent;

  /// True when an Android merged manifest was found and read, so the list
  /// includes what dependencies contribute. False means the list is the app's
  /// own — complete as far as it goes, and it grows after the first build.
  final bool merged;

  bool get isEmpty => rows.isEmpty;
}

/// Reads everything [packageRoot] declares.
///
/// Never throws for a missing or malformed file: a package with no `android/`
/// is a normal package, and a manifest that will not parse is reported as a
/// source that could not be read rather than as an app with no permissions.
/// **An empty result and a failed read must not look the same** — the same
/// rule the device-side readers live under.
PermissionDeclarations readDeclarations(String packageRoot) {
  var declarations = <DeclaredPermission>[];
  var sources = <String>[];
  var lints = <PermissionLint>[];
  var present = <PermissionPlatform>[];

  void unreadable(String relative, Object error) {
    lints.add(
      PermissionLint(
        id: 'unreadable',
        severity: PermissionLintSeverity.problem,
        message:
            'Could not read $relative, so anything it declares is missing '
            'from this list: $error',
      ),
    );
  }

  // --- Android -------------------------------------------------------------
  var androidDir = Directory(p.join(packageRoot, 'android'));
  var merged = false;
  if (androidDir.existsSync()) {
    present.add(PermissionPlatform.android);
    var relative = 'android/app/src/main/AndroidManifest.xml';
    var manifest = File(p.join(packageRoot, relative));
    var own = <String>{};
    if (manifest.existsSync()) {
      sources.add(relative);
      try {
        var found = _readAndroidManifest(manifest.readAsStringSync(), relative);
        declarations.addAll(found);
        own.addAll(found.map((e) => e.identifier));
      } on Object catch (e) {
        unreadable(relative, e);
      }
    }

    // The merged manifest is the only place a dependency's permissions show
    // up, so it is worth the look — but it exists only after a build, which is
    // why the list "grows once" rather than starting complete.
    //
    // **Only when the build is newer than the source.** `fromDependency` is
    // inferred from "in the merged manifest, not in this app's" — and a merged
    // manifest built before the last edit makes that inference a lie. Caught
    // by looking at the field: a permission deleted from the source seconds
    // earlier was still listed, attributed to a dependency that had never
    // asked for it.
    if (_newestMergedManifest(packageRoot) case (var path, var mergedRelative)?
        when !_isStale(manifest, path)) {
      sources.add(mergedRelative);
      try {
        merged = true;
        for (var entry in _readAndroidManifest(
          File(path).readAsStringSync(),
          mergedRelative,
        )) {
          if (own.contains(entry.identifier)) continue;
          declarations.add(
            DeclaredPermission(
              identifier: entry.identifier,
              platform: entry.platform,
              source: entry.source,
              maxSdkVersion: entry.maxSdkVersion,
              fromDependency: true,
            ),
          );
        }
      } on Object catch (e) {
        merged = false;
        unreadable(mergedRelative, e);
      }
    }
  }

  // --- Apple ---------------------------------------------------------------
  for (var (dir, platform, plist, entitlements) in [
    ('ios', PermissionPlatform.ios, 'ios/Runner/Info.plist', <String>[]),
    (
      'macos',
      PermissionPlatform.macos,
      'macos/Runner/Info.plist',
      [
        'macos/Runner/DebugProfile.entitlements',
        'macos/Runner/Release.entitlements',
      ],
    ),
  ]) {
    if (!Directory(p.join(packageRoot, dir)).existsSync()) continue;
    present.add(platform);
    var file = File(p.join(packageRoot, plist));
    if (file.existsSync()) {
      sources.add(plist);
      try {
        declarations.addAll(
          _readPlist(file.readAsStringSync(), platform, plist, usage: true),
        );
      } on Object catch (e) {
        unreadable(plist, e);
      }
    }
    for (var relative in entitlements) {
      var entitlementFile = File(p.join(packageRoot, relative));
      if (!entitlementFile.existsSync()) continue;
      sources.add(relative);
      try {
        declarations.addAll(
          _readPlist(
            entitlementFile.readAsStringSync(),
            platform,
            relative,
            usage: false,
          ),
        );
      } on Object catch (e) {
        unreadable(relative, e);
      }
    }
  }

  var rows = _group(declarations);
  lints.addAll(_lint(rows, present));
  return PermissionDeclarations(
    rows: rows,
    lints: lints,
    sources: sources,
    platformsPresent: present,
    merged: merged,
  );
}

List<DeclaredPermission> _readAndroidManifest(String xml, String source) {
  var document = XmlDocument.parse(xml);
  return [
    for (var element
        in document
            .findAllElements('uses-permission')
            .followedBy(document.findAllElements('uses-permission-sdk-23')))
      if (element.getAttribute('android:name') case var name?)
        DeclaredPermission(
          identifier: name,
          platform: PermissionPlatform.android,
          source: source,
          maxSdkVersion: element.getAttribute('android:maxSdkVersion'),
        ),
  ];
}

/// Reads an XML property list — which is what the checked-in `Info.plist` and
/// `.entitlements` are.
///
/// The *built* plist inside a `.app` is usually binary and is deliberately not
/// read here: converting it needs `plutil`, which is macOS-only, and this
/// whole file is meant to work on any host with nothing installed.
List<DeclaredPermission> _readPlist(
  String xml,
  PermissionPlatform platform,
  String source, {
  required bool usage,
}) {
  var document = XmlDocument.parse(xml);
  var dict = document.findAllElements('dict').firstOrNull;
  if (dict == null) return const [];
  var found = <DeclaredPermission>[];
  // A plist dict is a flat alternation of <key> and its value, so the value is
  // the next element sibling rather than a child — walking children in order
  // is the only way to pair them up.
  var children = dict.childElements.toList();
  for (var i = 0; i < children.length; i++) {
    var node = children[i];
    if (node.name.local != 'key') continue;
    var key = node.innerText.trim();
    // A usage description is a declaration by definition — every `NS…` key is
    // the app telling the user why. An entitlement is not: `com.apple.security`
    // also covers JIT, network sockets and file-picker access, none of which
    // is a permission anyone is granted. So entitlements are kept only where
    // they gate a capability this catalogue names, which is exactly where they
    // act as the sandbox half of a permission the app already declares.
    var interesting = usage
        ? key.startsWith('NS') && key.endsWith('UsageDescription')
        : Capability.forIdentifier(key) != null;
    if (!interesting) continue;
    var value = i + 1 < children.length ? children[i + 1] : null;
    if (!usage && value?.name.local != 'true') continue;
    found.add(
      DeclaredPermission(
        identifier: key,
        platform: platform,
        source: source,
        usage: usage ? (value?.innerText ?? '') : null,
      ),
    );
  }
  return found;
}

/// The newest merged manifest under `build/`, absolute, or null.
///
/// Public because the identity ladder wants the same file for a different
/// reason: it carries the `package=` attribute, which is the application id
/// the last build actually produced.
String? newestMergedManifestPath(String packageRoot) =>
    _newestMergedManifest(packageRoot)?.$1;

/// Whether [built] predates [source] — i.e. the last build is older than the
/// manifest it was built from.
///
/// Errs towards stale: a file whose time cannot be read is not evidence that
/// the build is current, and the cost of being wrong in this direction is a
/// shorter list rather than a false attribution.
bool _isStale(File source, String built) {
  try {
    if (!source.existsSync()) return false;
    return source.statSync().modified.isAfter(File(built).statSync().modified);
  } on FileSystemException {
    return true;
  }
}

/// The newest merged manifest under `build/`, with its package-relative path.
///
/// Newest rather than a named variant: which variant was built last is the one
/// that describes the app somebody is actually running, and guessing `debug`
/// would be wrong for every flavoured project.
(String, String)? _newestMergedManifest(String packageRoot) {
  var root = Directory(
    p.join(packageRoot, 'build', 'app', 'intermediates', 'merged_manifests'),
  );
  if (!root.existsSync()) return null;
  File? newest;
  try {
    for (var entry in root.listSync(recursive: true)) {
      if (entry is! File || p.basename(entry.path) != 'AndroidManifest.xml') {
        continue;
      }
      if (newest == null ||
          entry.statSync().modified.isAfter(newest.statSync().modified)) {
        newest = entry;
      }
    }
  } on FileSystemException {
    return null;
  }
  if (newest == null) return null;
  return (
    newest.path,
    p.split(p.relative(newest.path, from: packageRoot)).join('/'),
  );
}

List<PermissionRow> _group(List<DeclaredPermission> declarations) {
  var byCapability = <String, List<DeclaredPermission>>{};
  var labels = <String, String>{};
  var known = <String>{};
  for (var declaration in declarations) {
    var named = Capability.forIdentifier(declaration.identifier);
    var capability = named ?? Capability.other(declaration.identifier);
    byCapability.putIfAbsent(capability.id, () => []).add(declaration);
    labels[capability.id] = capability.label;
    if (named != null) known.add(capability.id);
  }
  var rows = [
    for (var entry in byCapability.entries)
      PermissionRow(
        capability: entry.key,
        label: labels[entry.key]!,
        declarations: entry.value,
        known: known.contains(entry.key),
      ),
  ];
  // Catalogue order first so the familiar rows read in a stable order, then
  // whatever the catalogue did not know, alphabetically.
  var order = [for (var c in Capability.all) c.id];
  rows.sort((a, b) {
    var ai = order.indexOf(a.capability);
    var bi = order.indexOf(b.capability);
    if (ai == -1 && bi == -1) return a.label.compareTo(b.label);
    if (ai == -1) return 1;
    if (bi == -1) return -1;
    return ai.compareTo(bi);
  });
  return rows;
}

List<PermissionLint> _lint(
  List<PermissionRow> rows,
  List<PermissionPlatform> present,
) {
  var lints = <PermissionLint>[];
  var identifiers = {
    for (var row in rows)
      for (var declaration in row.declarations)
        (declaration.platform, declaration.identifier),
  };
  bool has(PermissionPlatform platform, String identifier) =>
      identifiers.contains((platform, identifier));

  // Android background location without a foreground one: the prompt never
  // appears, because the platform will not ask for the background grade until
  // the foreground grade is held.
  if (has(
        PermissionPlatform.android,
        'android.permission.ACCESS_BACKGROUND_LOCATION',
      ) &&
      !has(
        PermissionPlatform.android,
        'android.permission.ACCESS_FINE_LOCATION',
      ) &&
      !has(
        PermissionPlatform.android,
        'android.permission.ACCESS_COARSE_LOCATION',
      )) {
    lints.add(
      const PermissionLint(
        id: 'backgroundLocationWithoutForeground',
        severity: PermissionLintSeverity.problem,
        capability: 'locationAlways',
        platform: PermissionPlatform.android,
        message:
            'ACCESS_BACKGROUND_LOCATION is declared with no foreground '
            'location permission. Android will not prompt for background '
            'location until the app holds fine or coarse location, so this '
            'never grants.',
      ),
    );
  }

  // The Apple twin of the same mistake, for the same reason.
  for (var platform in [PermissionPlatform.ios, PermissionPlatform.macos]) {
    if (!present.contains(platform)) continue;
    var always =
        has(platform, 'NSLocationAlwaysAndWhenInUseUsageDescription') ||
        has(platform, 'NSLocationAlwaysUsageDescription');
    if (always && !has(platform, 'NSLocationWhenInUseUsageDescription')) {
      lints.add(
        PermissionLint(
          id: 'locationAlwaysWithoutWhenInUse',
          severity: PermissionLintSeverity.problem,
          capability: 'locationAlways',
          platform: platform,
          message:
              'An always-on location usage description is present without '
              'NSLocationWhenInUseUsageDescription. iOS requires both, and '
              'without the when-in-use key the prompt never appears.',
        ),
      );
    }
  }

  // A usage description is what the user reads in the prompt. An empty one is
  // a rejected build review, and it is invisible in a diff.
  for (var row in rows) {
    for (var declaration in row.declarations) {
      if (declaration.usage case var usage? when usage.trim().isEmpty) {
        lints.add(
          PermissionLint(
            id: 'emptyUsageDescription',
            severity: PermissionLintSeverity.problem,
            capability: row.capability,
            platform: declaration.platform,
            message:
                '${declaration.identifier} has no text. App Review rejects a '
                'blank reason, and the prompt shows the user nothing.',
          ),
        );
      }
    }
  }

  // Declared on one platform and not the other. Only worth saying when the app
  // actually ships both, and never for a capability one platform has no way to
  // declare — notifications on iOS being the standing example.
  var shipsAndroid = present.contains(PermissionPlatform.android);
  var shipsIos = present.contains(PermissionPlatform.ios);
  if (shipsAndroid && shipsIos) {
    for (var row in rows) {
      var capability = Capability.forIdentifier(
        row.declarations.first.identifier,
      );
      if (capability == null) continue;
      if (capability.android.isEmpty || capability.apple.isEmpty) continue;
      var onAndroid = row.platforms.contains(PermissionPlatform.android);
      var onIos = row.platforms.contains(PermissionPlatform.ios);
      if (onAndroid == onIos) continue;
      lints.add(
        PermissionLint(
          id: 'platformMismatch',
          severity: PermissionLintSeverity.warning,
          capability: row.capability,
          platform: onAndroid
              ? PermissionPlatform.ios
              : PermissionPlatform.android,
          message:
              '${row.label} is declared on ${onAndroid ? 'Android' : 'iOS'} '
              'but not on ${onAndroid ? 'iOS' : 'Android'}. If the feature '
              'ships on both, the other platform will refuse it at runtime.',
        ),
      );
    }
  }

  // Not a mistake — a heads-up. Somebody should know a dependency asked for
  // this on their behalf, because the store will ask them about it.
  //
  // **Only for capabilities this file has a name for.** Run against the real
  // example, the unfiltered version's first two findings were
  // `android.permission.INTERNET` and Flutter's own generated
  // `…DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` — both contributed by the
  // engine's manifest for every Flutter app ever built. They stay as *rows*,
  // because they are genuinely declared and hiding them would make the list a
  // lie; they do not get a *finding*, because a finding is a thing to act on
  // and there is nothing to do about either.
  for (var row in rows) {
    if (Capability.forIdentifier(row.declarations.first.identifier) == null) {
      continue;
    }
    var contributed = [
      for (var declaration in row.declarations)
        if (declaration.fromDependency) declaration.identifier,
    ];
    if (contributed.isEmpty) continue;
    lints.add(
      PermissionLint(
        id: 'fromDependency',
        severity: PermissionLintSeverity.note,
        capability: row.capability,
        platform: PermissionPlatform.android,
        message:
            "${contributed.join(', ')} comes from a dependency's manifest, "
            "not from this app's. It ships in the built APK all the same.",
      ),
    );
  }

  return lints;
}

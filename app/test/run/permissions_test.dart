import 'dart:io';

import 'package:flutterware_app/src/run/permissions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Writes a throwaway package with whichever platform files a case needs.
///
/// Real files rather than an injected filesystem, because the thing under test
/// is mostly "does this find the file where the platform actually puts it",
/// and a fake that answers yes proves nothing about that.
String _package({
  String? androidManifest,
  String? iosPlist,
  String? macosPlist,
  String? macosEntitlements,
  String? mergedManifest,
}) {
  var root = Directory.systemTemp.createTempSync('fw-permissions-').path;
  void write(String relative, String contents) {
    var file = File(p.join(root, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  if (androidManifest != null) {
    write('android/app/src/main/AndroidManifest.xml', androidManifest);
  }
  if (mergedManifest != null) {
    write(
      'build/app/intermediates/merged_manifests/debug/AndroidManifest.xml',
      mergedManifest,
    );
  }
  if (iosPlist != null) write('ios/Runner/Info.plist', iosPlist);
  if (macosPlist != null) write('macos/Runner/Info.plist', macosPlist);
  if (macosEntitlements != null) {
    write('macos/Runner/DebugProfile.entitlements', macosEntitlements);
  }
  return root;
}

String _manifest(List<String> permissions) =>
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
    '${permissions.map((e) => '<uses-permission android:name="$e"/>').join()}'
    '<application android:label="x"/></manifest>';

String _plist(Map<String, String> entries) =>
    '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>'
    '${entries.entries.map((e) => '<key>${e.key}</key><string>${e.value}</string>').join()}'
    '</dict></plist>';

void main() {
  test('a capability is one row across both platforms', () {
    var root = _package(
      androidManifest: _manifest(['android.permission.CAMERA']),
      iosPlist: _plist({'NSCameraUsageDescription': 'To scan receipts'}),
    );

    var result = readDeclarations(root);

    expect(result.rows, hasLength(1));
    expect(result.rows.single.capability, 'camera');
    expect(result.rows.single.label, 'Camera');
    expect(
      result.rows.single.platforms,
      unorderedEquals([PermissionPlatform.android, PermissionPlatform.ios]),
    );
    // Both identifiers stay visible on the row — the abstraction is for
    // reading, not for hiding what you have to act on.
    expect(
      result.rows.single.declarations.map((e) => e.identifier),
      unorderedEquals([
        'android.permission.CAMERA',
        'NSCameraUsageDescription',
      ]),
    );
  });

  test('an identifier the catalogue does not know is still reported', () {
    var root = _package(androidManifest: _manifest(['com.acme.CUSTOM_THING']));

    var result = readDeclarations(root);

    expect(result.rows.single.capability, 'com.acme.CUSTOM_THING');
    expect(result.rows.single.label, 'com.acme.CUSTOM_THING');
  });

  test(
    'a package with no platform directories reports nothing, not an error',
    () {
      var result = readDeclarations(_package());

      expect(result.isEmpty, isTrue);
      expect(result.lints, isEmpty);
      expect(result.platformsPresent, isEmpty);
      expect(result.sources, isEmpty);
    },
  );

  test('an unreadable manifest is a lint, not an empty list', () {
    var root = _package(androidManifest: 'this is not xml <<<');

    var result = readDeclarations(root);

    // The rule the device-side readers live under: a failed parse and an app
    // with no permissions must never render the same.
    expect(result.rows, isEmpty);
    expect(result.lints.single.id, 'unreadable');
    expect(result.lints.single.severity, PermissionLintSeverity.problem);
    expect(result.lints.single.message, contains('AndroidManifest.xml'));
  });

  group('lints', () {
    test('background location with no foreground location', () {
      var root = _package(
        androidManifest: _manifest([
          'android.permission.ACCESS_BACKGROUND_LOCATION',
        ]),
      );

      var lints = readDeclarations(root).lints;

      expect(
        lints.map((e) => e.id),
        contains('backgroundLocationWithoutForeground'),
      );
    });

    test('and not when the foreground one is there', () {
      var root = _package(
        androidManifest: _manifest([
          'android.permission.ACCESS_BACKGROUND_LOCATION',
          'android.permission.ACCESS_COARSE_LOCATION',
        ]),
      );

      var lints = readDeclarations(root).lints;

      expect(
        lints.map((e) => e.id),
        isNot(contains('backgroundLocationWithoutForeground')),
      );
    });

    test('always-on location without the when-in-use key', () {
      var root = _package(
        iosPlist: _plist({
          'NSLocationAlwaysAndWhenInUseUsageDescription': 'To track deliveries',
        }),
      );

      var lints = readDeclarations(root).lints;

      expect(
        lints.map((e) => e.id),
        contains('locationAlwaysWithoutWhenInUse'),
      );
    });

    test('an empty usage description', () {
      var root = _package(
        iosPlist: _plist({'NSCameraUsageDescription': '   '}),
      );

      var lints = readDeclarations(root).lints;

      var lint = lints.singleWhere((e) => e.id == 'emptyUsageDescription');
      expect(lint.severity, PermissionLintSeverity.problem);
      expect(lint.message, contains('NSCameraUsageDescription'));
    });

    test('declared on one platform but not the other', () {
      var root = _package(
        androidManifest: _manifest(['android.permission.CAMERA']),
        iosPlist: _plist({'NSMicrophoneUsageDescription': 'To record'}),
      );

      var lints = readDeclarations(
        root,
      ).lints.where((e) => e.id == 'platformMismatch');

      expect(
        lints.map((e) => e.capability),
        unorderedEquals(['camera', 'microphone']),
      );
    });

    test('but never for a capability the platform cannot declare', () {
      // Notifications have no iOS plist key at all, so a one-sided declaration
      // is the only shape available and is not a mistake.
      var root = _package(
        androidManifest: _manifest(['android.permission.POST_NOTIFICATIONS']),
        iosPlist: _plist({'NSCameraUsageDescription': 'To scan'}),
      );

      var lints = readDeclarations(
        root,
      ).lints.where((e) => e.id == 'platformMismatch');

      expect(lints.map((e) => e.capability), isNot(contains('notifications')));
    });

    test('and not when the app ships only one platform', () {
      var root = _package(
        androidManifest: _manifest(['android.permission.CAMERA']),
      );

      var lints = readDeclarations(root).lints;

      expect(lints.map((e) => e.id), isNot(contains('platformMismatch')));
    });
  });

  group('the merged manifest', () {
    test('adds what a dependency contributed, marked as such', () {
      var root = _package(
        androidManifest: _manifest(['android.permission.CAMERA']),
        mergedManifest: _manifest([
          'android.permission.CAMERA',
          'android.permission.ACCESS_FINE_LOCATION',
        ]),
      );

      var result = readDeclarations(root);

      expect(result.merged, isTrue);
      var location = result.rows.singleWhere((e) => e.capability == 'location');
      expect(location.declarations.single.fromDependency, isTrue);
      // The app's own permission is not relabelled as a dependency's just
      // because the merged manifest also lists it.
      var camera = result.rows.singleWhere((e) => e.capability == 'camera');
      expect(camera.declarations.every((e) => !e.fromDependency), isTrue);
      expect(result.lints.map((e) => e.id), contains('fromDependency'));
    });

    test('is absent before a build, and the list says so', () {
      var root = _package(
        androidManifest: _manifest(['android.permission.CAMERA']),
      );

      expect(readDeclarations(root).merged, isFalse);
    });

    test('is ignored when the source manifest is newer than the build', () {
      // Otherwise `fromDependency` — which means "in the merged manifest and
      // not in this app's" — reports a permission the developer just deleted
      // as something a dependency asked for. Seen happening in the cockpit.
      var root = _package(
        androidManifest: _manifest(['android.permission.CAMERA']),
        mergedManifest: _manifest([
          'android.permission.CAMERA',
          'android.permission.ACCESS_FINE_LOCATION',
        ]),
      );
      File(
        p.join(root, 'android/app/src/main/AndroidManifest.xml'),
      ).setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));

      var result = readDeclarations(root);

      expect(result.merged, isFalse);
      expect(result.rows.map((e) => e.capability), isNot(contains('location')));
      expect(result.lints.map((e) => e.id), isNot(contains('fromDependency')));
    });
  });

  test('macOS entitlements count as declarations', () {
    var root = _package(
      macosPlist: _plist({'NSCameraUsageDescription': 'To scan'}),
      macosEntitlements:
          '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>'
          '<key>com.apple.security.device.camera</key><true/>'
          '<key>com.apple.security.network.client</key><true/>'
          '</dict></plist>',
    );

    var result = readDeclarations(root);

    var camera = result.rows.singleWhere((e) => e.capability == 'camera');
    expect(
      camera.declarations.map((e) => e.identifier),
      containsAll([
        'NSCameraUsageDescription',
        'com.apple.security.device.camera',
      ]),
    );
    // But build plumbing is not a permission. Every Flutter macOS app ships
    // network and JIT entitlements; listing them as things a user grants would
    // pad the report with rows nobody can act on.
    expect(
      result.rows.map((e) => e.capability),
      isNot(contains('com.apple.security.network.client')),
    );
  });

  test('a manifest permission the catalogue does not know is still a row', () {
    // The asymmetry with entitlements above is deliberate: a `uses-permission`
    // is always something the app asked for, so an unrecognised one is exactly
    // the row worth seeing.
    var root = _package(
      androidManifest: _manifest(['android.permission.INTERNET']),
    );

    expect(
      readDeclarations(root).rows.map((e) => e.capability),
      contains('android.permission.INTERNET'),
    );
  });

  test('the example app reads as the fixture it was made into', () {
    // Guards the fixture as much as the parser: examples/example carries these
    // four permissions so the permission spikes have something to grant.
    var root = p.normalize(
      p.join(Directory.current.path, '..', 'examples', 'example'),
    );
    if (!Directory(p.join(root, 'android')).existsSync()) {
      markTestSkipped('examples/example is not beside this checkout');
      return;
    }

    var result = readDeclarations(root);

    expect(
      result.rows.map((e) => e.capability),
      containsAll(['camera', 'location', 'notifications']),
    );
    expect(
      result.sources,
      contains('android/app/src/main/AndroidManifest.xml'),
    );
    expect(result.sources, contains('ios/Runner/Info.plist'));
  });
}

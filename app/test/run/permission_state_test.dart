import 'dart:io';

import 'package:flutterware_app/src/run/permission_state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Captured from `adb shell dumpsys package` on an API 35 emulator during
/// S-P1, verbatim including the leading indentation — the shape is the thing
/// under test, so re-typing it tidily would test something else.
const _dumpsys = '''
Packages:
  Package [com.example.flutterware_example] (7de4a3):
    userId=10206
    requested permissions:
      android.permission.CAMERA
      android.permission.INTERNET
    install permissions:
      android.permission.INTERNET: granted=true
    User 0: ceDataInode=377241 installed=true hidden=false
      gids=[3003]
      runtime permissions:
        android.permission.POST_NOTIFICATIONS: granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED]
        android.permission.ACCESS_FINE_LOCATION: granted=true, flags=[ USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED]
        android.permission.ACCESS_COARSE_LOCATION: granted=false, flags=[ USER_SET|USER_SENSITIVE_WHEN_GRANTED]
        android.permission.CAMERA: granted=false, flags=[ USER_SET|USER_FIXED|USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED]
''';

void main() {
  group('the Android four states', () {
    test('are read from granted= and the flags together', () {
      var held = parseAndroidHeld(_dumpsys)!;

      expect(
        held['android.permission.ACCESS_FINE_LOCATION'],
        HeldState.granted,
      );
      // The finding that made this necessary: `granted=false` alone cannot
      // tell these three apart, and they behave completely differently.
      expect(
        held['android.permission.POST_NOTIFICATIONS'],
        HeldState.undetermined,
      );
      expect(
        held['android.permission.ACCESS_COARSE_LOCATION'],
        HeldState.denied,
      );
      expect(held['android.permission.CAMERA'], HeldState.deniedForever);
    });

    test(
      'an app with no runtime permissions section reads as null, not empty',
      () {
        // Not installed, or output this does not understand. Either way it must
        // not render as "this app holds nothing".
        expect(parseAndroidHeld('Packages:\n  (nothing here)\n'), isNull);
        expect(parseAndroidHeld(''), isNull);
      },
    );

    test('an empty section is an answer, and an empty one', () {
      var held = parseAndroidHeld(
        'runtime permissions:\n\nUser 1: something else\n',
      );

      expect(held, isNotNull);
      expect(held, isEmpty);
    });
  });

  group('capability grouping', () {
    test('takes the most-granted member of a multi-identifier capability', () {
      // Holding coarse location *is* holding location. Reporting "denied"
      // because the fine one is not held would describe an app that is at that
      // moment reading the user's position.
      var held = heldByCapability(parseAndroidHeld(_dumpsys)!);

      expect(held['location'], HeldState.granted);
      expect(held['camera'], HeldState.deniedForever);
      expect(held['notifications'], HeldState.undetermined);
    });

    test('and plain denied beats denied-forever, because a prompt survives', () {
      var held = heldByCapability({
        'android.permission.ACCESS_FINE_LOCATION': HeldState.deniedForever,
        'android.permission.ACCESS_COARSE_LOCATION': HeldState.denied,
      });

      // The ranking is "how much can this app still do", not "how bad does
      // this look": coarse is denied but *not* fixed, so the app can still
      // prompt for it and end up with location. Reporting denied-forever would
      // say the capability is closed when it is one dialog away.
      expect(held['location'], HeldState.denied);
    });

    test('and undetermined beats denied for the same reason', () {
      var held = heldByCapability({
        'android.permission.ACCESS_FINE_LOCATION': HeldState.denied,
        'android.permission.ACCESS_COARSE_LOCATION': HeldState.undetermined,
      });

      expect(held['location'], HeldState.undetermined);
    });

    test('drops identifiers no capability claims', () {
      var held = heldByCapability({'com.acme.PRIVATE': HeldState.granted});

      expect(held, isEmpty);
    });
  });

  group('the simulator TCC read', () {
    test('an absent row is undetermined, which is what a fresh app is', () {
      var held = parseTccRows({});

      expect(held['camera'], HeldState.undetermined);
      expect(held['photos'], HeldState.undetermined);
    });

    test('0 is denied, 2 is granted, 3 is granted-but-limited', () {
      var held = parseTccRows({
        'kTCCServiceCamera': 2,
        'kTCCServiceMicrophone': 0,
        'kTCCServiceAddressBook': 3,
      });

      expect(held['camera'], HeldState.granted);
      expect(held['microphone'], HeldState.denied);
      expect(held['contacts'], HeldState.granted);
      expect(held['photos'], HeldState.undetermined);
    });

    test('location is deliberately not in the service map', () {
      // It writes no TCC row at all — measured. Claiming "undetermined" for it
      // would be inventing an answer the database never gave.
      expect(tccServices.containsKey('location'), isFalse);
      expect(tccServices.containsKey('locationAlways'), isFalse);
      expect(simulatorLocationNote, contains('locationd'));
    });
  });

  group('identity', () {
    test('prefers the merged manifest, which is exact', () {
      var root = _packageWith(
        merged:
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
            'package="com.example.app.dev"><application/></manifest>',
        gradle: 'android { applicationId = "com.example.app" }',
      );

      var identity = androidIdentity(root)!;

      expect(identity.id, 'com.example.app.dev');
      expect(identity.exact, isTrue);
      expect(identity.source, contains('merged manifest'));
    });

    test('falls back to Gradle, and says it is a guess', () {
      var root = _packageWith(
        gradle: 'android { applicationId = "com.example.app" }',
      );

      var identity = androidIdentity(root)!;

      expect(identity.id, 'com.example.app');
      expect(identity.exact, isFalse);
    });

    test('is null when nothing declares one', () {
      expect(androidIdentity(_packageWith()), isNull);
    });

    test('reads the bundle id out of the Xcode project', () {
      var root = _packageWith(
        pbxproj: '''
          PRODUCT_BUNDLE_IDENTIFIER = com.example.flutterwareExample;
          PRODUCT_BUNDLE_IDENTIFIER = com.example.flutterwareExample.RunnerTests;
          PRODUCT_BUNDLE_IDENTIFIER = com.example.flutterwareExample;
        ''',
      );

      var identity = appleIdentity(root)!;

      // The test target's id is not the app's, and every real project has one.
      expect(identity.id, 'com.example.flutterwareExample');
      expect(identity.exact, isTrue);
    });
  });

  test('the real example resolves on both platforms', () {
    var root = p.normalize(
      p.join(Directory.current.path, '..', 'examples', 'example'),
    );
    if (!Directory(p.join(root, 'android')).existsSync()) {
      markTestSkipped('examples/example is not beside this checkout');
      return;
    }

    expect(androidIdentity(root)?.id, 'com.example.flutterware_example');
    expect(appleIdentity(root)?.id, 'com.example.flutterwareExample');
  });
}

String _packageWith({String? merged, String? gradle, String? pbxproj}) {
  var root = Directory.systemTemp.createTempSync('fw-held-').path;
  void write(String relative, String contents) {
    var file = File(p.join(root, relative))..parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  if (merged != null) {
    write(
      'build/app/intermediates/merged_manifests/debug/AndroidManifest.xml',
      merged,
    );
  }
  if (gradle != null) write('android/app/build.gradle.kts', gradle);
  if (pbxproj != null) write('ios/Runner.xcodeproj/project.pbxproj', pbxproj);
  return root;
}

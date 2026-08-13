import 'package:flutterware_app/src/run/permission_state.dart';
import 'package:flutterware_app/src/run/permission_write.dart';
import 'package:flutterware_app/src/run/permissions.dart';
import 'package:test/test.dart';

void main() {
  group('the Android command plan', () {
    test('clears the flags before granting', () {
      // Going denied-forever → granted with `pm grant` alone leaves USER_FIXED
      // in place, and the next read shows a granted permission the user
      // supposedly refused permanently.
      var commands = androidCommandsFor(
        'android.permission.CAMERA',
        HeldState.granted,
      );

      expect(commands.first.first, 'clear-permission-flags');
      expect(commands.last.first, 'grant');
    });

    test(
      'undetermined revokes and clears, so nothing says the user was asked',
      () {
        var commands = androidCommandsFor(
          'android.permission.CAMERA',
          HeldState.undetermined,
        );

        expect(commands.map((e) => e.first), [
          'revoke',
          'clear-permission-flags',
        ]);
        expect(commands.last, contains('user-set'));
        expect(commands.last, contains('user-fixed'));
      },
    );

    test('denied sets user-set but clears user-fixed', () {
      // Otherwise "denied" inherits a previous "denied forever" and the app
      // silently stops being able to prompt.
      var commands = androidCommandsFor(
        'android.permission.CAMERA',
        HeldState.denied,
      );

      expect(commands.map((e) => e.first), [
        'revoke',
        'clear-permission-flags',
        'set-permission-flags',
      ]);
      expect(commands[1], contains('user-fixed'));
      expect(commands[1], isNot(contains('user-set')));
      expect(commands[2], contains('user-set'));
    });

    test('denied forever sets both flags', () {
      var commands = androidCommandsFor(
        'android.permission.CAMERA',
        HeldState.deniedForever,
      );

      expect(commands.last, containsAll(['user-set', 'user-fixed']));
    });

    test('never composes pm reset-permissions, which is global', () {
      // It takes no package argument. Using it to give one app a first run
      // would reset every app on the device.
      for (var state in HeldState.values) {
        for (var command in androidCommandsFor(
          'android.permission.CAMERA',
          state,
        )) {
          expect(command.first, isNot('reset-permissions'));
        }
      }
    });

    test('unknown asks for nothing, because it is not a state', () {
      expect(
        androidCommandsFor('android.permission.CAMERA', HeldState.unknown),
        isEmpty,
      );
    });
  });

  group('the simulator verb', () {
    test('maps the three states iOS has', () {
      expect(simctlVerbFor(HeldState.granted), 'grant');
      expect(simctlVerbFor(HeldState.denied), 'revoke');
      expect(simctlVerbFor(HeldState.undetermined), 'reset');
    });

    test('treats denied-forever as denied, which is what iOS can express', () {
      expect(simctlVerbFor(HeldState.deniedForever), 'revoke');
    });
  });

  group('profiles', () {
    var declared = [
      const PermissionRow(
        capability: 'camera',
        label: 'Camera',
        declarations: [],
        known: true,
      ),
      const PermissionRow(
        capability: 'location',
        label: 'Location',
        declarations: [],
        known: true,
      ),
      // Flutter's own generated permission — declared, but not something a
      // profile should be setting.
      const PermissionRow(
        capability: 'android.permission.INTERNET',
        label: 'android.permission.INTERNET',
        declarations: [],
        known: false,
      ),
    ];

    test('cover what the app declares, and only that', () {
      var targets = profileTargets(PermissionProfile.granted, declared);

      expect(targets.keys, unorderedEquals(['camera', 'location']));
      expect(targets.values, everyElement(HeldState.granted));
    });

    test('first-run is undetermined, which is the point of it', () {
      var targets = profileTargets(PermissionProfile.firstRun, declared);

      expect(targets['camera'], HeldState.undetermined);
    });

    // The refusal this stops: an app declaring an Apple-only capability used
    // to send it to the Android writer, which answered "faceId has no Android
    // permission behind it" — and that sentence rode into the launch note of
    // every single launch with a wish in force.
    test('narrow to the platform being written to', () {
      var mixed = [
        _row('camera', [PermissionPlatform.android, PermissionPlatform.ios]),
        _row('faceId', [PermissionPlatform.ios]),
      ];

      expect(
        profileTargets(
          PermissionProfile.granted,
          mixed,
          on: PermissionPlatform.android,
        ).keys,
        ['camera'],
      );
      expect(
        profileTargets(
          PermissionProfile.granted,
          mixed,
          on: PermissionPlatform.ios,
        ).keys,
        unorderedEquals(['camera', 'faceId']),
      );
    });

    // A device the cached list cannot name has no platform to narrow by, and
    // dropping capabilities on that guess would be the quiet version of the
    // bug above.
    test('narrow nothing when the platform is unknown', () {
      var mixed = [
        _row('camera', [PermissionPlatform.android]),
        _row('faceId', [PermissionPlatform.ios]),
      ];

      expect(
        profileTargets(PermissionProfile.granted, mixed).keys,
        unorderedEquals(['camera', 'faceId']),
      );
    });

    test('are addressable by the id the CLI and MCP use', () {
      expect(PermissionProfile.byId('first-run'), PermissionProfile.firstRun);
      expect(
        PermissionProfile.byId('denied-forever'),
        PermissionProfile.deniedForever,
      );
      expect(PermissionProfile.byId('nonsense'), isNull);
    });
  });
}

/// A declared row on the given platforms. The identifiers do not matter here —
/// [profileTargets] narrows on `row.platforms`, which is derived from them.
PermissionRow _row(String capability, List<PermissionPlatform> platforms) =>
    PermissionRow(
      capability: capability,
      label: capability,
      known: true,
      declarations: [
        for (var platform in platforms)
          DeclaredPermission(
            identifier: '$capability.$platform',
            platform: platform,
            source: 'fixture',
          ),
      ],
    );

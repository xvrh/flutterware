import 'package:flutterware_app/src/run/inventory.dart';
import 'package:flutterware_app/src/utils/daemon/commands.dart';
import 'package:flutterware_app/src/utils/daemon/device.dart';
import 'package:test/test.dart';

void main() {
  group('DaemonEmulator.tryRead', () {
    test('reads what the daemon actually sends', () {
      var emulator = DaemonEmulator.tryRead(const {
        'id': 'Medium_Phone_API_35',
        'name': 'Medium Phone API 35',
        'category': 'mobile',
        'platformType': 'android',
      });

      expect(emulator!.id, 'Medium_Phone_API_35');
      expect(emulator.displayName, 'Medium Phone API 35');
      expect(emulator.platformType, 'android');
    });

    test('an entry with only an id still reads', () {
      // Same posture as DaemonDevice: a tool we do not version must not be able
      // to make a bootable emulator vanish by renaming a field.
      var emulator = DaemonEmulator.tryRead(const {'id': 'x'});
      expect(emulator!.displayName, 'x');
      expect(emulator.platformType, isNull);
    });

    test('an entry with no id is refused', () {
      expect(DaemonEmulator.tryRead(const {'name': 'nameless'}), isNull);
      expect(DaemonEmulator.tryRead(const {'id': ''}), isNull);
    });
  });

  group('isEmulatorBooted', () {
    const android = DaemonEmulator(
      id: 'Medium_Phone_API_35',
      name: 'Medium Phone API 35',
      platformType: 'android',
    );

    test('an Android device names the emulator it booted from', () {
      expect(
        isEmulatorBooted(android, const [
          DaemonDevice(
            id: 'emulator-5554',
            name: 'sdk gphone64',
            emulator: true,
            emulatorId: 'Medium_Phone_API_35',
          ),
        ]),
        isTrue,
      );
    });

    test('falls back to the name when the daemon sent no emulatorId', () {
      expect(
        isEmulatorBooted(android, const [
          DaemonDevice(
            id: 'emulator-5554',
            name: 'Medium Phone API 35',
            emulator: true,
          ),
        ]),
        isTrue,
      );
    });

    test('a physical phone of the same name is not it', () {
      expect(
        isEmulatorBooted(android, const [
          DaemonDevice(id: 'real', name: 'Medium Phone API 35'),
        ]),
        isFalse,
      );
    });

    test('an unbooted Android emulator says so plainly', () {
      expect(isEmulatorBooted(android, const []), isFalse);
    });

    test('the iOS row answers null, because the question does not apply', () {
      // The daemon lists exactly one iOS entry — a door to the Simulator, not
      // a machine. The Simulator can already be running `iPhone 16e` under a
      // name that links back to nothing, so reporting `false` would claim an
      // offline simulator while `devices` listed a booted one.
      const ios = DaemonEmulator(
        id: 'apple_ios_simulator',
        name: 'iOS Simulator',
        platformType: 'ios',
      );

      expect(isEmulatorBooted(ios, const []), isNull);
      expect(
        isEmulatorBooted(ios, const [
          DaemonDevice(id: '575104B7', name: 'iPhone 16e', emulator: true),
        ]),
        isNull,
      );
    });
  });

  group('commands', () {
    test('getEmulators asks for nothing and decodes tolerantly', () {
      const command = EmulatorGetEmulatorsCommand();
      expect(command.methodName, 'emulator.getEmulators');
      expect(command.toJson(), isEmpty);
      expect(
        command
            .decodeResult([
              {'id': 'a', 'name': 'A'},
              {'name': 'no id'},
              'not a map',
            ])
            .map((e) => e.id),
        ['a'],
      );
      expect(command.decodeResult(null), isEmpty);
    });

    test('launch sends coldBoot only when it is wanted', () {
      expect(const EmulatorLaunchCommand('a').toJson(), {'emulatorId': 'a'});
      expect(const EmulatorLaunchCommand('a', coldBoot: true).toJson(), {
        'emulatorId': 'a',
        'coldBoot': true,
      });
      expect(const EmulatorLaunchCommand('a').methodName, 'emulator.launch');
    });
  });
}

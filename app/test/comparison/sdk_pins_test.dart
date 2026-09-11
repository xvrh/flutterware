import 'dart:io';

import 'package:flutterware_app/src/comparison/sdk_pins.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Which Flutter each side of a comparison asked for — read to say something
/// when the two differ, and never to choose an SDK.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw_sdk_pins'));
  tearDown(() => root.deleteSync(recursive: true));

  String checkout(String name, Map<String, String> files) {
    var dir = Directory(p.join(root.path, name))..createSync(recursive: true);
    files.forEach((relative, content) {
      File(p.join(dir.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    });
    return dir.path;
  }

  group('a pin is read from', () {
    test("fvm's .fvmrc", () {
      var pin = SdkPin.of(checkout('a', {'.fvmrc': '{"flutter": "3.47.0"}'}));

      expect(pin?.version, '3.47.0');
      expect(pin?.file, '.fvmrc');
    });

    test("fvm's older config", () {
      var pin = SdkPin.of(
        checkout('a', {
          '.fvm/fvm_config.json': '{"flutterSdkVersion": "3.24.5"}',
        }),
      );

      expect(pin?.version, '3.24.5');
    });

    test('.tool-versions, among the other tools', () {
      var pin = SdkPin.of(
        checkout('a', {
          '.tool-versions': 'ruby 3.3.0\nflutter 3.48.0-stable\n',
        }),
      );

      expect(pin?.version, '3.48.0-stable');
    });

    test('the nearest file above the package', () {
      var top = checkout('a', {
        '.fvmrc': '{"flutter": "3.47.0"}',
        'apps/shop/.fvmrc': '{"flutter": "3.48.0"}',
        'apps/admin/pubspec.yaml': '',
      });

      expect(SdkPin.of(top, packagePath: 'apps/shop')?.version, '3.48.0');
      expect(SdkPin.of(top, packagePath: 'apps/admin')?.version, '3.47.0');
    });

    test('nowhere, when nothing pins', () {
      expect(SdkPin.of(checkout('a', {'pubspec.yaml': ''})), isNull);
    });

    test('nowhere, when the file is not what it claims', () {
      expect(SdkPin.of(checkout('a', {'.fvmrc': 'not json'})), isNull);
    });
  });

  group('the caveat', () {
    test('names both pins and the SDK that drew both sides', () {
      var caveat = SdkPin.caveat(
        base: const SdkPin(version: '3.47.0', file: '.fvmrc'),
        head: const SdkPin(version: '3.48.0', file: '.fvmrc'),
        running: '3.48.0',
      );

      expect(caveat, contains('3.47.0'));
      expect(caveat, contains('this branch 3.48.0'));
      expect(caveat, contains('(.fvmrc)'));
      expect(caveat, contains('rendered with Flutter 3.48.0'));
    });

    test('is silent when the two agree', () {
      expect(
        SdkPin.caveat(
          base: const SdkPin(version: 'stable', file: '.fvmrc'),
          head: const SdkPin(version: 'stable', file: '.fvmrc'),
        ),
        isNull,
      );
    });

    // A missing pin is not a different one: a branch that adds `.fvmrc` to a
    // project that had none changed nothing about the SDK the base ran on.
    test('is silent when either side pins nothing', () {
      expect(
        SdkPin.caveat(
          base: null,
          head: const SdkPin(version: '3.48.0', file: '.fvmrc'),
        ),
        isNull,
      );
    });
  });
}

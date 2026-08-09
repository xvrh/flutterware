import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/splash/model/config.dart';
import 'package:flutterware_app/src/splash/model/writer.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The writer, held to the one promise that makes it usable on a `pubspec.yaml`:
/// everything it did not touch comes back byte-for-byte.
///
/// The value tests matter more than they look. A splash colour is six hex
/// digits, and `000000` is also a perfectly good YAML integer — a writer that
/// emits it unquoted writes a config that parses back as the number 0.
void main() {
  group('editSplashConfig', () {
    test('replaces one value and leaves the rest alone', () {
      var source = '''
# The splash, kept here rather than in the pubspec.
flutter_native_splash:
  color: "FFFFFF"   # the light one
  image: assets/logo.png

  # Dark is a chain of its own.
  color_dark: "101418"
''';
      var edited = editSplashConfig(source, [
        const SplashWrite('color_dark', '000000'),
      ]);

      expect(edited, contains('# The splash, kept here rather than in'));
      expect(edited, contains('# the light one'));
      expect(edited, contains('# Dark is a chain of its own.'));
      expect(edited, contains('image: assets/logo.png'));
      expect(edited, isNot(contains('101418')));
    });

    test('a six-digit colour survives the round trip as a string', () {
      // `color: 000000` unquoted is the integer 0. The generator would then read
      // 0 and pad it back to "000000", but only by accident — and `color: 123456`
      // would come back as 123456 with nothing to pad. Quoting is not cosmetic.
      var edited = editSplashConfig(
        'flutter_native_splash:\n  color: "FFFFFF"\n',
        [const SplashWrite('color', '000000')],
      );

      var raw = loadYaml(edited) as Map;
      var section = raw['flutter_native_splash'] as Map;
      expect(section['color'], '000000');
      expect(section['color'], isA<String>());
    });

    test('creates the android_12 section when there is none', () {
      var source = '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''';
      var edited = editSplashConfig(source, [
        const SplashWrite('android_12.image', 'assets/android12.png'),
      ]);

      var section = (loadYaml(edited) as Map)['flutter_native_splash'] as Map;
      expect((section['android_12'] as Map)['image'], 'assets/android12.png');
      // The keys that were already there are untouched.
      expect(section['image'], 'assets/logo.png');
    });

    test('writes into an android_12 section that already exists', () {
      var source = '''
flutter_native_splash:
  android_12:
    # Sized for the 2/3 mask.
    image: assets/android12.png
''';
      var edited = editSplashConfig(source, [
        const SplashWrite('android_12.image_dark', 'assets/android12_dark.png'),
      ]);

      expect(edited, contains('# Sized for the 2/3 mask.'));
      var android12 =
          ((loadYaml(edited) as Map)['flutter_native_splash']
                  as Map)['android_12']
              as Map;
      expect(android12['image'], 'assets/android12.png');
      expect(android12['image_dark'], 'assets/android12_dark.png');
    });

    test('an empty android_12: is replaced rather than traversed into', () {
      // `android_12:` with nothing under it parses to null, not to a map, and
      // `update` on a child of it throws.
      var edited = editSplashConfig('flutter_native_splash:\n  android_12:\n', [
        const SplashWrite('android_12.color', '101418'),
      ]);

      var android12 =
          ((loadYaml(edited) as Map)['flutter_native_splash']
                  as Map)['android_12']
              as Map;
      expect(android12['color'], '101418');
    });

    test('creates the section itself in a file that has none', () {
      var edited = editSplashConfig('', [const SplashWrite('color', 'FFFFFF')]);

      var section = (loadYaml(edited) as Map)['flutter_native_splash'] as Map;
      expect(section['color'], 'FFFFFF');
    });

    test('removes a key, and removing an absent one is not an error', () {
      var source = '''
flutter_native_splash:
  color: "FFFFFF"
  colour_dark: "101418"
''';
      var edited = editSplashConfig(source, [
        const SplashWrite.remove('colour_dark'),
        // Already gone — a rename whose old key was written twice asks for this.
        const SplashWrite.remove('colour_dark'),
      ]);

      var section = (loadYaml(edited) as Map)['flutter_native_splash'] as Map;
      expect(section.containsKey('colour_dark'), isFalse);
      expect(section['color'], 'FFFFFF');
    });

    test('a rename is a remove and a set, in that order', () {
      var edited = editSplashConfig(
        'flutter_native_splash:\n  colour_dark: "101418"\n',
        [
          const SplashWrite.remove('colour_dark'),
          const SplashWrite('color_dark', '101418'),
        ],
      );

      var section = (loadYaml(edited) as Map)['flutter_native_splash'] as Map;
      expect(section.containsKey('colour_dark'), isFalse);
      expect(section['color_dark'], '101418');
    });

    test('writes an int as an int', () {
      var edited = editSplashConfig(
        'flutter_native_splash:\n  branding: assets/brand.png\n',
        [const SplashWrite('branding_bottom_padding_ios', 34)],
      );

      var section = (loadYaml(edited) as Map)['flutter_native_splash'] as Map;
      expect(section['branding_bottom_padding_ios'], 34);
    });
  });

  group('SplashWriter', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('splash_writer'));
    tearDown(() => root.deleteSync(recursive: true));

    void write(String relative, String content) =>
        File(p.join(root.path, relative)).writeAsStringSync(content);

    String read(String relative) =>
        File(p.join(root.path, relative)).readAsStringSync();

    test(
      'edits the pubspec in place and leaves the rest of it alone',
      () async {
        write('pubspec.yaml', '''
name: sample
description: A sample.

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

flutter_native_splash:
  color: "FFFFFF"

flutter:
  uses-material-design: true
''');

        var writer = SplashWriter(
          packageRoot: root.path,
          config: SplashConfig(
            raw: {'color': 'FFFFFF'},
            kind: SplashConfigKind.pubspec,
            path: 'pubspec.yaml',
          ),
        );
        var path = await writer.apply([
          const SplashWrite('color_dark', '101418'),
        ]);

        expect(path, 'pubspec.yaml');
        var after = read('pubspec.yaml');
        expect(after, contains('name: sample'));
        expect(after, contains('uses-material-design: true'));
        expect(after, contains('sdk: flutter'));
        var section = (loadYaml(after) as Map)['flutter_native_splash'] as Map;
        expect(section['color_dark'], '101418');
      },
    );

    test('writes to the flavor file the config came from', () async {
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      write('flutter_native_splash-staging.yaml', '''
flutter_native_splash:
  color: "00FF00"
''');

      var writer = SplashWriter(
        packageRoot: root.path,
        config: SplashConfig(
          raw: {'color': '00FF00'},
          kind: SplashConfigKind.flavorFile,
          path: 'flutter_native_splash-staging.yaml',
          flavor: 'staging',
        ),
      );
      await writer.apply([const SplashWrite('color_dark', '003300')]);

      // The one a flavored project reads, and only that one.
      expect(read('flutter_native_splash-staging.yaml'), contains('003300'));
      expect(read('flutter_native_splash.yaml'), isNot(contains('003300')));
    });

    test('re-reads the file rather than trusting the scanned config', () async {
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
      var config = SplashConfig(
        raw: {'color': 'FFFFFF'},
        kind: SplashConfigKind.file,
        path: 'flutter_native_splash.yaml',
      );
      var writer = SplashWriter(packageRoot: root.path, config: config);

      // Somebody types in their editor between the scan and the fix.
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');

      await writer.apply([const SplashWrite('color_dark', '101418')]);

      var after = read('flutter_native_splash.yaml');
      expect(after, contains('image: assets/logo.png'));
      expect(after, contains('101418'));
    });

    test('an empty write list touches nothing', () async {
      write('flutter_native_splash.yaml', 'flutter_native_splash:\n');
      var before = File(
        p.join(root.path, 'flutter_native_splash.yaml'),
      ).statSync().modified;

      await SplashWriter(
        packageRoot: root.path,
        config: SplashConfig(
          raw: const {},
          kind: SplashConfigKind.file,
          path: 'flutter_native_splash.yaml',
        ),
      ).apply(const []);

      expect(
        File(
          p.join(root.path, 'flutter_native_splash.yaml'),
        ).statSync().modified,
        before,
      );
    });
  });
}

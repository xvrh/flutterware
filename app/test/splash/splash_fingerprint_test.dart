import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/splash/model/fingerprint.dart';
import 'package:flutterware_app/src/splash/model/scan.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// The fingerprint is what decides whether the picture on screen is still true,
/// so the interesting cases are all the ones where a naive digest would say
/// "unchanged" and be wrong.
///
/// Every edit here changes a file's **length**, not only its mtime. That is not
/// a property of the fingerprint — it hashes both — but a property of the test:
/// a filesystem with coarse mtime granularity would otherwise make a same-length
/// rewrite inside one second look identical, and flake.
void main() {
  late Directory root;

  String fingerprint() => splashFingerprint(
    packageRoot: root.path,
    scan: scanSplash(packageRoot: root.path, packagePath: '.'),
  );

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void writePng(String relative, int width, int height) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      img.encodePng(img.Image(width: width, height: height)),
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('splash_fingerprint_test');
    write('pubspec.yaml', '''
name: sample
environment:
  sdk: ^3.0.0
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('is stable when nothing moves', () {
    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
    expect(fingerprint(), fingerprint());
  });

  test('moves when the config is edited', () {
    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
    var before = fingerprint();

    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  color_dark: "101418"
''');
    expect(fingerprint(), isNot(before));
  });

  test('moves when a referenced image is re-exported', () {
    // The case a watch on the config alone would never see, and the reason this
    // is a fingerprint over a set rather than a hash of one file.
    writePng('assets/logo.png', 1024, 1024);
    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');
    var before = fingerprint();

    writePng('assets/logo.png', 512, 512);
    expect(fingerprint(), isNot(before));
  });

  test('moves when a config file appears where there was none', () {
    // Nothing references it yet, so it has to be checked unconditionally — a
    // project growing a config mid-session is otherwise invisible until restart.
    var before = fingerprint();
    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
    expect(fingerprint(), isNot(before));
  });

  test('moves when the config is deleted', () {
    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
    var before = fingerprint();

    File(p.join(root.path, 'flutter_native_splash.yaml')).deleteSync();
    expect(fingerprint(), isNot(before));
  });

  test('moves when a flavor file appears', () {
    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
    var before = fingerprint();

    write('flutter_native_splash-production.yaml', '''
flutter_native_splash:
  color: "112233"
''');
    expect(fingerprint(), isNot(before));
  });

  test('moves when a generated artifact appears', () {
    // `create` run in another terminal. The artifact was not in the previous
    // scan, so only the directory's own mtime can carry it.
    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
    Directory(
      p.join(root.path, 'android', 'app', 'src', 'main', 'res', 'drawable'),
    ).createSync(recursive: true);
    var before = fingerprint();

    writePng('android/app/src/main/res/drawable/splash.png', 8, 8);
    expect(fingerprint(), isNot(before));
  });

  test('survives a package with nothing in it at all', () {
    var empty = Directory.systemTemp.createTempSync('splash_fingerprint_empty');
    addTearDown(() => empty.deleteSync(recursive: true));
    expect(splashFingerprint(packageRoot: empty.path, scan: null), isNotEmpty);
  });
}

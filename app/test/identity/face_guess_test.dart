import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/identity/face_guess.dart';
import 'package:path/path.dart' as p;

/// Guessing which package represents a repository.
///
/// The guess only ever runs once, at `init`, and its answer is written into
/// `tool/flutterware.dart` for a human to correct — so these tests are about it
/// being *usefully* right, not authoritative.
void main() {
  var repoRoot = p.normalize(p.join(Directory.current.path, '..'));

  test('this repository is its GUI, not its library or its fixture', () {
    // `.` is a published library with no platform directories, and
    // `examples/example` is a stock `flutter create` project — so the only
    // package here with an icon of its own is the app.
    expect(guessFacePackage(repoRoot), 'app');
  });

  test('a tree with no packages at all has no answer', () async {
    var dir = await Directory.systemTemp.createTemp('face_guess');
    addTearDown(() => dir.delete(recursive: true));
    expect(guessFacePackage(dir.path), isNull);
  });

  test('a package with no platform directories is not a candidate', () async {
    var dir = await Directory.systemTemp.createTemp('face_guess');
    addTearDown(() => dir.delete(recursive: true));
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: lib_only');
    expect(guessFacePackage(dir.path), isNull);
  });

  /// The case that made the whole scan worth writing: a project can have every
  /// platform and still be undressed, and then it is not the repository's face.
  test('platform directories alone do not make a face', () async {
    var dir = await Directory.systemTemp.createTemp('face_guess');
    addTearDown(() => dir.delete(recursive: true));
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: bare');
    for (var platform in ['android', 'ios', 'macos', 'web']) {
      Directory(p.join(dir.path, platform)).createSync();
    }
    expect(guessFacePackage(dir.path), isNull);
  });

  test('a package whose icon is really drawn wins', () async {
    var dir = await Directory.systemTemp.createTemp('face_guess');
    addTearDown(() => dir.delete(recursive: true));

    // Two candidates, both apps; only one has an icon of its own.
    for (var name in ['bare_app', 'real_app']) {
      var root = p.join(dir.path, 'packages', name);
      Directory(root).createSync(recursive: true);
      File(p.join(root, 'pubspec.yaml')).writeAsStringSync('name: $name');
      Directory(p.join(root, 'macos')).createSync();
    }

    var icons = p.join(
      dir.path,
      'packages/real_app/macos/Runner/Assets.xcassets/AppIcon.appiconset',
    );
    Directory(icons).createSync(recursive: true);
    // Copied from this repo's own app, which is exactly a non-stock icon.
    File(
      p.join(
        Directory.current.path,
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
      ),
    ).copySync(p.join(icons, 'app_icon_1024.png'));
    // Required, and not test scaffolding: an appiconset without a
    // `Contents.json` is one Xcode does not ship either, so the scan is right
    // to ignore it.
    File(p.join(icons, 'Contents.json')).writeAsStringSync(
      '{"images":[{"size":"512x512","idiom":"mac",'
      '"filename":"app_icon_1024.png","scale":"2x"}],'
      '"info":{"version":1,"author":"xcode"}}',
    );

    expect(guessFacePackage(dir.path), 'packages/real_app');
  });
}

// Discovery: a scene file declares itself with its marker, so finding one is
// a walk and a first line — no compile, no analysis, no daemon.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/discovery.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('scene_discovery'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, String source) {
    var file = File('${dir.path}/$name')..writeAsStringSync(source);
    return file.path;
  }

  test('finds scene files and reads the class each declares', () {
    var pair = emitSceneFile(
      coffeeBannerDraft(),
      className: 'BannerScene',
      motions: {'BannerIntro': coffeeIntroDraft()},
    );
    write('banner.scene.dart', pair);
    write(
      'other.scene.dart',
      emitSceneFile(coffeeBannerDraft(), className: 'OtherScene'),
    );
    var found = discoverScenes(dir.path);
    expect(found.map((e) => e.className).toSet(), {
      'BannerScene',
      'OtherScene',
    });
    expect(found.every((e) => e.path.endsWith('.scene.dart')), true);
  });

  test('the scene class is the one that extends nothing', () {
    // A motion class sits in the same file and must never be mistaken for
    // the scene it animates.
    var source = emitSceneFile(
      coffeeBannerDraft(),
      className: 'BannerScene',
      motions: {'BannerIntro': coffeeIntroDraft()},
    );
    expect(source, contains('class BannerIntro('));
    expect(sceneClassNameOf(source), 'BannerScene');
  });

  test('an unmarked file is not a scene file, and says nothing about it', () {
    write('plain.scene.dart', 'class NotAScene {}\n');
    expect(discoverScenes(dir.path), isEmpty);
  });

  test('a scene broken inside still appears — opening it is what refuses', () {
    write(
      'broken.scene.dart',
      '$sceneFileMarker\nclass BrokenScene {\n  late final root = Frame(nope: 1);\n}\n',
    );
    var found = discoverScenes(dir.path);
    expect(found.single.className, 'BrokenScene');
    var opened = SceneFileOpenProbe.open(found.single.path);
    expect(
      opened,
      isNotEmpty,
      reason: 'the door refuses, the listing does not',
    );
  });

  test('a missing directory is empty, not an error', () {
    expect(discoverScenes('${dir.path}/nope'), isEmpty);
  });
}

/// Opening is the parse door — the listing never pays it.
class SceneFileOpenProbe {
  static List<SceneRefusal> open(String path) =>
      parseSceneFile(File(path).readAsStringSync()).refusals;
}

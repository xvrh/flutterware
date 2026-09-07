// Discovery: a scene file declares itself with its marker, so finding one is
// a walk and a first line — no compile, no analysis, no daemon.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/discovery.dart';
import 'package:flutterware_app/src/scene/group_file.dart';
import 'package:flutterware_app/src/scene/skeletons.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('scene_discovery'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, String source) {
    var file = File('${dir.path}/$name')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(source);
    return file.path;
  }

  test('finds scene files and reads the class each declares', () {
    var scene = coffeeBannerDraft();
    var pair = emitSceneFile(
      scene,
      className: 'BannerScene',
      motions: {'BannerIntro': coffeeIntroDraft(scene)},
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
    var scene = coffeeBannerDraft();
    var source = emitSceneFile(
      scene,
      className: 'BannerScene',
      motions: {'BannerIntro': coffeeIntroDraft(scene)},
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
    expect(discoverPackage('${dir.path}/nope').groups, isEmpty);
  });

  group('a package', () {
    String scene(String name) =>
        emitSceneFile(coffeeBannerDraft(), className: name);

    test('is groups by folder, the nearest group above a scene owning it', () {
      Directory('${dir.path}/lib/marketing/nested').createSync(recursive: true);
      Directory('${dir.path}/lib/store').createSync(recursive: true);
      write('lib/marketing/$sceneGroupFileName', emitGroupSkeleton());
      write('lib/marketing/banner.scene.dart', scene('Banner'));
      write('lib/marketing/nested/$sceneGroupFileName', emitGroupSkeleton());
      write('lib/marketing/nested/deep.scene.dart', scene('Deep'));
      write('lib/store/$sceneGroupFileName', emitGroupSkeleton());
      write('lib/store/card.scene.dart', scene('Card'));
      write('lib/loose.scene.dart', scene('Loose'));
      // A file called scenes.dart with no marker is not a group.
      write('lib/other.dart', 'final scenes = 1;');
      var scan = discoverPackage(dir.path);
      expect(scan.groups.map((g) => g.name), ['marketing', 'nested', 'store']);
      expect(
        scan.groups.map((g) => g.scenes.map((s) => s.className).toList()),
        [
          ['Banner'],
          ['Deep'],
          ['Card'],
        ],
      );
      expect(scan.strayScenes, 1);
      expect(
        scan.groupOf('${dir.path}/lib/marketing/nested/deep.scene.dart')?.name,
        'nested',
      );
      expect(scan.groupOf('${dir.path}/lib/loose.scene.dart'), isNull);
    });

    test('finds libraries wherever they were written, by marker', () {
      Directory('${dir.path}/lib/design').createSync(recursive: true);
      write('lib/design/brand.tokens.dart', emitTokensSkeleton('brandTokens'));
      write('lib/design/store_front.tokens.dart', emitTokensSkeleton('x'));
      write('lib/design/plain.tokens.dart', 'final plainTokens = [];');
      var scan = discoverPackage(dir.path);
      expect(scan.libraries.map((l) => l.symbol), [
        'brandTokens',
        'storeFrontTokens',
      ]);
      expect(
        scan.librarySymbolAt('${dir.path}/lib/design/plain.tokens.dart'),
        isNull,
      );
    });

    test('stops at a nested package', () {
      Directory('${dir.path}/example/lib').createSync(recursive: true);
      write('example/pubspec.yaml', 'name: nested');
      write('example/lib/$sceneGroupFileName', emitGroupSkeleton());
      write('example/lib/x.scene.dart', scene('X'));
      write(sceneGroupFileName, emitGroupSkeleton());
      write('mine.scene.dart', scene('Mine'));
      var scan = discoverPackage(dir.path);
      expect(scan.groups.single.scenes.single.className, 'Mine');
      expect(scan.strayScenes, 0);
    });
  });
}

/// Opening is the parse door — the listing never pays it.
class SceneFileOpenProbe {
  static List<SceneRefusal> open(String path) =>
      parseSceneFile(File(path).readAsStringSync()).refusals;
}

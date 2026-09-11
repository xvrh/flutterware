import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scene/model_assets.dart';
import 'package:path/path.dart' as p;

/// The example's model files, read the way the inspector reads them: the
/// nodes that carry a mesh and the clips with their lengths, off the glTF
/// tables alone.
void main() {
  var packageRoot = p.normalize(
    p.join(Directory.current.path, '..', 'fixtures', 'probe_app'),
  );

  test('the Blender rig names its three meshes and its one clip', () {
    var info = readModelAsset(
      File(p.join(packageRoot, 'assets/models/probe_rig_blender.glb')),
    )!;
    expect(info.meshes, ['Body', 'Lid', 'Screen']);
    expect(info.clips.map((c) => c.name), ['Open']);
    expect(info.clips.single.seconds, closeTo(2.04, 0.01));
  });

  test('the fox carries one mesh node and three clips with lengths', () {
    var info = readModelAsset(
      File(p.join(packageRoot, 'assets/models/fox.glb')),
    )!;
    expect(info.meshes, ['fox']);
    expect(info.clips.map((c) => c.name), ['Survey', 'Walk', 'Run']);
    expect(info.clips.map((c) => c.seconds.toStringAsFixed(2)), [
      '3.42',
      '0.71',
      '1.16',
    ]);
  });

  test('the package lists its model files by the path a scene spells', () {
    var assets = listModelAssets(packageRoot);
    expect(assets, contains('assets/models/fox.glb'));
    expect(assets, contains('assets/models/probe_rig_blender.glb'));
    expect(assets.every((a) => a.startsWith('assets/')), isTrue);
  });

  test('the cache answers the same until the file changes, and null for '
      'nothing', () {
    var cache = ModelAssets.shared;
    var a = cache.info(packageRoot, 'assets/models/fox.glb');
    var b = cache.info(packageRoot, 'assets/models/fox.glb');
    expect(identical(a, b), isTrue);
    expect(cache.info(packageRoot, 'assets/models/nope.glb'), isNull);
    expect(cache.info(packageRoot, ''), isNull);
  });

  test('a file that is not a model reads as none', () {
    expect(
      readModelAsset(File(p.join(packageRoot, 'assets/models/NOTICE.md'))),
      isNull,
    );
  });
}

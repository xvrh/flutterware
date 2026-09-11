@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/embedder/build_directory.dart';
import 'package:flutterware_app/src/previews/catalog_render.dart';
import 'package:flutterware_app/src/previews/devices.dart';
import 'package:flutterware_app/src/previews/discovery.dart';
import 'package:flutterware_app/src/previews/test_runner.dart';
import 'package:flutterware_app/src/previews/tester_renderer.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// The showcase scenes — a 3D view as an external node, then as a node
/// kind with a model and two surfaces, orbited and scrubbed by their
/// motions — walked the way `scene video` walks them, with the tester's log
/// in view. The surface probe is the still that settles which way a
/// surface faces and whose slot it shows; its frames are dumped beside the
/// others for looking at.
void main() {
  for (var (file, frames) in const [
    ('showcase.scene.dart', 20),
    ('showcase3d.scene.dart', 20),
    ('surface_probe.scene.dart', 5),
  ]) {
    test('$file walks through the scene player', () => _walk(file, frames));
  }
}

Future<void> _walk(String file, int atLeast) async {
  {
    var flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    var packageRoot = p.normalize(
      p.join(Directory.current.path, '..', 'fixtures', 'probe_app'),
    );
    var opened = parseSceneFile(
      File(p.join(packageRoot, 'demo', file)).readAsStringSync(),
    );
    expect(opened.ok, isTrue, reason: opened.refusals.join('\n'));
    var pair =
        File(
          p.join(
            Directory.systemTemp.createTempSync('fw-$file').path,
            'pair.json',
          ),
        )..writeAsStringSync(
          jsonEncode(
            sceneFileToJson(
              opened.doc!,
              className: opened.className!,
              motions: opened.motions,
            ),
          ),
        );

    var scan = CatalogScanner(
      projectRoot: packageRoot,
      roots: const ['demo'],
    ).scan();
    var entry = scan.entries.singleWhere(
      (entry) => entry.id == 'demo/scene_args.dart#scenePlayer',
    );
    var runner = PreviewTestRunner(
      packageRoot: packageRoot,
      flutterSdkRoot: flutterRoot,
      read: () => (entries: [entry], canvases: const []),
      onLog: (line) => print('tester: $line'),
      buildDirectory: claimBuildDirectory(
        packageRoot,
        root: comparisonBuildRoot,
      ),
    );
    try {
      var clock = Stopwatch()..start();
      var walk = await TesterRenderer(runner: runner).walk(
        CatalogWalk(
          entryId: entry.id,
          fps: 10,
          viewport: const CaptureViewport(width: 1024, height: 576),
          knobs: {'pair': pair.path},
        ),
      );
      var frames = await walk.frames.toList();
      print(
        '${frames.length} frames of ${walk.durationMs}ms in '
        '${clock.elapsedMilliseconds}ms',
      );
      var out = Directory.systemTemp.createTempSync('fw-$file-frames');
      for (var frame in [
        frames.first,
        frames[frames.length ~/ 2],
        frames.last,
      ]) {
        var picture = img.Image.fromBytes(
          width: frame.width,
          height: frame.height,
          bytes: frame.pixels.buffer,
          numChannels: 4,
        );
        File(p.join(out.path, 't${frame.t.toStringAsFixed(2)}.png'))
            .writeAsBytesSync(img.encodePng(picture));
      }
      print('frames: ${out.path}');
      expect(frames.length, greaterThan(atLeast));
    } finally {
      await runner.dispose();
    }
  }
}

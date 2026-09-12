// A reel's scene stage draws a shader pass at the reel's time. The stage
// applies its motion itself rather than handing it to the view, so the clock
// has to be handed over on its own — without it `uTime` sat at zero on every
// frame of a reel and of a scene video.
//
// Here and not beside the root package's stage tests: the probe shader is
// declared by this package, and a test bundle holds only its own package's
// programs.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/reel.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

const _probe = 'test/scene/shaders/probe.frag';
const _size = Size(200, 20);

/// The mean red of the fully inked pixels, 0–1. The probe in mode 1 writes
/// `fract(uTime)` as red, and the test font draws every glyph as a box.
Future<double> _red(ui.Image image) async {
  var bytes = (await image.toByteData())!;
  var (sum, n) = (0, 0);
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    if (bytes.getUint8(i + 3) != 255) continue;
    sum += bytes.getUint8(i);
    n++;
  }
  expect(n, greaterThan(0), reason: 'nothing was inked');
  return sum / n / 255;
}

StageFrame _at(int ms) => StageFrame(
  screen: null,
  screenSize: _size,
  at: Duration(milliseconds: ms),
  pointer: null,
  down: false,
  sincePress: null,
  touch: false,
);

void main() {
  testWidgets("a reel frame draws a shader pass at the reel's time", (
    tester,
  ) async {
    var text = TextNode('MMMMMMMMMM', name: 'glow', width: _size.width)
      ..fontSize = 20
      ..layers = [
        const FillLayer(
          paint: ShaderPaint(
            _probe,
            uniforms: {
              'uMode': [1],
            },
          ),
        ),
      ];
    var root = FrameNode(name: 'root')
      ..width = _size.width
      ..height = _size.height
      ..children.add(text);
    var scene = SceneDocument(root);
    // Nothing on the timeline: the clock is the motion's only effect.
    var motion = BoundMotion.bind(
      MotionDocument(sceneClassName: 'Probe'),
      scene,
    );
    await tester.runAsync(() => precacheSceneShaders(scene));
    var stage = MountedStage(
      SceneStage(scene, motion: motion),
      screenSize: _size,
      scale: 1,
      touch: false,
    );
    addTearDown(stage.dispose);

    await tester.runAsync(() async {
      var early = await _red(stage.render(_at(250)));
      var later = await _red(stage.render(_at(750)));
      expect(early, closeTo(0.25, 0.02));
      expect(later, closeTo(0.75, 0.02));
    });
    expect(stage.errors, isEmpty);
  });
}

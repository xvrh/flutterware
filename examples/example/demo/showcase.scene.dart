//@flutterware:scene=0.8
// Owned by the flutterware scene editor, which reads and writes this whole
// file. Hand edits are welcome inside the grammar: every node is a
// `late final` field (the field name is the node's identity), placed exactly
// once in a children list; a parameter is a `final` in the class header
// whose default is the mockup. Anything outside the grammar is refused with
// a line number rather than silently dropped.
//
// This is ordinary Dart: it compiles, it analyzes, and an app mounts it.
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class ShowcaseScene extends SceneDefinition {
  late final headline = TextNode(
    'Built for the turn',
    x: 64,
    y: 96,
    style: SceneTextStyle(
      fontSize: 48,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFFFFFFFF),
    ),
  );
  late final tagline = TextNode(
    'A model from Blender. A camera from the timeline.',
    x: 64,
    y: 164,
    style: SceneTextStyle(fontSize: 20, color: SceneColor(0xFFB9C2D0)),
  );
  late final model = ExternalNode(
    const ModelViewArgs(
      asset: 'assets/models/probe_rig.glb',
      yaw: -40,
      pitch: 12,
      distance: 5.5,
      fov: 40,
      clip: 'Open',
      clipTime: 0,
    ),
    x: 470,
    y: 28,
    width: 520,
    height: 520,
  );
  @override
  late final root = FrameNode(
    width: 1024,
    height: 576,
    fill: SceneColor(0xFF161A22),
    children: [headline, tagline, model],
  );
}

class ShowcaseSpin(super.scene) extends SceneMotion<ShowcaseScene> {
  late final orbit = scene.model.animate(
    args: ModelViewTracks(
      yaw: MotionTrack([
        MotionKey(at: 0.ms, value: -40),
        MotionKey(at: 2400.ms, value: 40, curve: SceneCurves.easeInOut),
      ]),
      distance: MotionTrack([
        MotionKey(at: 0.ms, value: 5.5),
        MotionKey(at: 2400.ms, value: 3.8, curve: SceneCurves.easeOut),
      ]),
      clipTime: MotionTrack([
        MotionKey(at: 0.ms, value: 0),
        MotionKey(at: 600.ms, value: 0),
        MotionKey(at: 2400.ms, value: 2, curve: SceneCurves.easeInOut),
      ]),
    ),
  );
  late final headlineIn = scene.headline.animate(
    opacity: MotionTrack([
      MotionKey(at: 0.ms, value: 0),
      MotionKey(at: 400.ms, value: 1, curve: SceneCurves.easeOut),
    ]),
    translateY: MotionTrack([
      MotionKey(at: 0.ms, value: 24),
      MotionKey(at: 400.ms, value: 0, curve: SceneCurves.easeOut),
    ]),
  );
  late final taglineIn = scene.tagline.animate(
    opacity: MotionTrack([
      MotionKey(at: 200.ms, value: 0),
      MotionKey(at: 700.ms, value: 1, curve: SceneCurves.easeOut),
    ]),
  );
  @override
  late final timeline = ParExpr([orbit, headlineIn, taglineIn]);
  ShowcaseSpin copy(ShowcaseScene scene) => copyStateInto(ShowcaseSpin(scene));
}

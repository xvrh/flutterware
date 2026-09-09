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

class Showcase3D extends SceneDefinition {
  late final headline = TextNode(
    'A view, a model, two surfaces',
    x: 64,
    y: 96,
    style: SceneTextStyle(
      fontSize: 48,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFFFFFFFF),
    ),
  );
  late final tagline = TextNode(
    'Three kinds described as data. Camera, clip and placements are rows; a surface shows a child of the scene.',
    x: 64,
    y: 164,
    width: 380,
    style: SceneTextStyle(fontSize: 20, color: SceneColor(0xFFB9C2D0)),
  );
  late final fox = ModelNode(asset: 'assets/models/fox.glb', animation: 'Run');
  late final screen = SceneRefNode(const PhoneHomeArgs());
  late final phone = SurfaceNode(
    asset: 'assets/models/probe_rig_blender.glb',
    positionX: -70,
    positionY: 40,
    size: 45,
    animation: 'Open',
    mesh: 'Screen',
    children: [screen],
  );
  late final label = TextNode(
    'a plain quad',
    style: SceneTextStyle(
      fontSize: 40,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFF161A22),
    ),
  );
  late final card = FrameNode(
    width: 320,
    height: 200,
    fill: SceneColor(0xFFFFD166),
    corner: 24,
    layout: NodeLayout.column,
    mainAlign: SceneMainAxisAlignment.center,
    children: [label],
  );
  late final floating = SurfaceNode(
    positionX: 40,
    positionY: 110,
    positionZ: -60,
    rotationY: -25,
    size: 40,
    tint: SceneColor(0xFFFF9C9C),
    children: [card],
  );
  late final view = View3DNode(
    x: 470,
    y: 28,
    width: 520,
    height: 520,
    yaw: -4.5,
    pitch: 22.5,
    distance: 260,
    fov: 50,
    targetY: 40,
    light: 2,
    lightYaw: -30,
    lightPitch: 55,
    children: [fox, phone, floating],
  );
  @override
  late final root = FrameNode(
    width: 1024,
    height: 576,
    fill: SceneColor(0xFF161A22),
    children: [headline, tagline, view],
  );
}

class Showcase3DSpin(super.scene) extends SceneMotion<Showcase3D> {
  late final orbit = scene.view.animate(
    yaw: MotionTrack([
      MotionKey(at: 0.ms, value: -70),
      MotionKey(at: 2400.ms, value: 70, curve: SceneCurves.easeInOut),
    ]),
    distance: MotionTrack([
      MotionKey(at: 0.ms, value: 300),
      MotionKey(at: 2400.ms, value: 220, curve: SceneCurves.easeOut),
    ]),
  );
  late final foxGait = scene.fox.animate(
    animationTime: ClipBlocks([
      ClipBlock(clip: 'Walk', at: 0.ms, length: 1200.ms),
      ClipBlock(clip: 'Run', at: 900.ms, length: 1500.ms),
      ClipBlock(clip: 'Walk', at: 3336.ms, length: 708.ms),
      ClipBlock(clip: 'Run', at: 4662.ms, length: 1158.ms),
      ClipBlock(clip: 'Survey', at: 6509.ms, length: 3417.ms),
    ]),
  );
  late final phoneOpen = scene.phone.animate(
    animationTime: ClipBlocks([
      ClipBlock(at: 0.ms, length: 2000.ms),
      ClipBlock(clip: 'Open', at: 3147.ms, length: 2042.ms, offset: 1378.ms),
    ]),
  );
  late final drift = scene.floating.animate(
    rotationY: MotionTrack([
      MotionKey(at: 0.ms, value: -25),
      MotionKey(at: 2400.ms, value: 20, curve: SceneCurves.easeInOut),
    ]),
  );
  late final headlineIn = scene.headline.animate(
    opacity: MotionTrack([
      MotionKey(at: 0.ms, value: 0),
      MotionKey(at: 400.ms, value: 1, curve: SceneCurves.easeOut),
    ]),
  );
  @override
  late final timeline = ParExpr([orbit, foxGait, phoneOpen, drift, headlineIn]);
  Showcase3DSpin copy(Showcase3D scene) => copyStateInto(Showcase3DSpin(scene));
}

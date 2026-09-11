//@flutterware:scene=0.9
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

class StoreHero({
  final String headline = 'Your coffee,\nready before you are',
  final String subtitle = 'Order ahead. Skip the line. Earn rewards.',
  final String cta = 'Get the app',
  final String shotFront = 'build/flutterware/store/flutterware_probes/unframed/app-store/iphone-6-9/en-US/01-welcome.png',
  final String shotBack = 'build/flutterware/store/flutterware_probes/unframed/app-store/iphone-6-9/en-US/02-menu.png',
  final SceneTokens tokens = const SceneTokens(),
}) extends SceneDefinition {
  late final glow = ShapeNode(
    x: 560,
    y: -150,
    width: 520,
    height: 520,
    fill: tokens.brand,
    opacity: 0.14,
    circle: true,
  );
  late final title = TextNode(
    headline,
    style: tokens.title.copyWith(
      fontSize: 46,
      lineHeight: 1.1,
      color: tokens.ink,
    ),
  );
  late final sub = TextNode(subtitle, style: tokens.body);
  late final ctaLabel = TextNode(
    cta,
    style: SceneTextStyle(
      fontSize: 17,
      weight: SceneFontWeight.w600,
      color: SceneColor(0xFFFFFFFF),
    ),
  );
  late final ctaBox = FrameNode(
    fill: tokens.brand,
    corner: tokens.radius,
    layout: NodeLayout.row,
    padding: 16,
    children: [ctaLabel],
  );
  late final copy = FrameNode(
    x: 64,
    y: 118,
    width: 460,
    layout: NodeLayout.column,
    gap: 18,
    crossAlign: SceneCrossAxisAlignment.start,
    children: [title, sub, ctaBox],
  );
  late final backPixels = ExternalNode(
    ShotArgs(path: shotBack),
    width: 360,
    height: 780,
  );
  late final frontPixels = ExternalNode(
    ShotArgs(path: shotFront),
    width: 360,
    height: 780,
  );
  late final phoneBack = SurfaceNode(
    asset: 'assets/models/phone.glb',
    mesh: 'Screen',
    positionX: 46,
    positionY: 12,
    positionZ: -70,
    rotationY: -20,
    rotationZ: 5,
    size: 96,
    children: [backPixels],
  );
  late final phoneFront = SurfaceNode(
    asset: 'assets/models/phone.glb',
    mesh: 'Screen',
    positionX: -42,
    positionY: -4,
    rotationY: 16,
    rotationZ: -4,
    size: 122,
    children: [frontPixels],
  );
  late final stage = View3DNode(
    x: 500,
    y: 0,
    width: 524,
    height: 500,
    yaw: 0,
    pitch: 6,
    distance: 300,
    fov: 46,
    targetY: 0,
    ambient: 0.55,
    light: 2.4,
    lightYaw: -34,
    lightPitch: 42,
    children: [phoneBack, phoneFront],
  );
  @override
  late final root = FrameNode(
    width: 1024,
    height: 500,
    fill: tokens.espresso,
    children: [glow, stage, copy],
  );
}

/// What the store video is: the camera arriving, the phones settling, and the
/// copy landing after them.
///
/// Every row here is a row the inspector shows and the timeline keys — the
/// camera's `yaw` and `distance` on the window, `rotationY` and `positionY` on
/// each placement. Nothing in the model file moves; the phone carries no clip
/// on purpose, so this file is the only place the motion lives.
class StoreHeroReveal(super.scene) extends SceneMotion<StoreHero> {
  late final camera = scene.stage.animate(
    yaw: MotionTrack([
      MotionKey(at: 0.ms, value: -22),
      MotionKey(at: 3200.ms, value: 0, curve: SceneCurves.easeInOut),
    ]),
    distance: MotionTrack([
      MotionKey(at: 0.ms, value: 372),
      MotionKey(at: 3200.ms, value: 300, curve: SceneCurves.easeOut),
    ]),
  );
  late final frontSettles = scene.phoneFront.animate(
    positionY: MotionTrack([
      MotionKey(at: 0.ms, value: -74),
      MotionKey(at: 1100.ms, value: -6, curve: SceneCurves.easeOut),
    ]),
    rotationY: MotionTrack([
      MotionKey(at: 0.ms, value: 34),
      MotionKey(at: 2400.ms, value: 16, curve: SceneCurves.easeInOut),
    ]),
  );
  late final backSettles = scene.phoneBack.animate(
    positionY: MotionTrack([
      MotionKey(at: 200.ms, value: -92),
      MotionKey(at: 1500.ms, value: 8, curve: SceneCurves.easeOut),
    ]),
    rotationY: MotionTrack([
      MotionKey(at: 200.ms, value: -44),
      MotionKey(at: 2600.ms, value: -20, curve: SceneCurves.easeInOut),
    ]),
  );
  late final titleIn = scene.title.animate(
    opacity: MotionTrack([
      MotionKey(at: 700.ms, value: 0),
      MotionKey(at: 1200.ms, value: 1, curve: SceneCurves.easeOut),
    ]),
    translateY: MotionTrack([
      MotionKey(at: 700.ms, value: 22),
      MotionKey(at: 1200.ms, value: 0, curve: SceneCurves.easeOut),
    ]),
  );
  late final subIn = scene.sub.animate(
    opacity: MotionTrack([
      MotionKey(at: 1000.ms, value: 0),
      MotionKey(at: 1500.ms, value: 1, curve: SceneCurves.easeOut),
    ]),
    translateY: MotionTrack([
      MotionKey(at: 1000.ms, value: 18),
      MotionKey(at: 1500.ms, value: 0, curve: SceneCurves.easeOut),
    ]),
  );
  late final ctaIn = scene.ctaBox.animate(
    opacity: MotionTrack([
      MotionKey(at: 1400.ms, value: 0),
      MotionKey(at: 1900.ms, value: 1, curve: SceneCurves.easeOut),
    ]),
    scale: MotionTrack([
      MotionKey(at: 1400.ms, value: 0.9),
      MotionKey(at: 1900.ms, value: 1, curve: SceneCurves.easeOutBack),
    ]),
  );
  @override
  late final timeline = ParExpr([
    camera,
    frontSettles,
    backSettles,
    titleIn,
    subIn,
    ctaIn,
  ]);
  StoreHeroReveal copy(StoreHero scene) =>
      copyStateInto(StoreHeroReveal(scene));
}

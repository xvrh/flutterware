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

class BannerScene extends SceneDefinition {
  late final glow = ShapeNode(
    x: 600,
    y: -110,
    width: 480,
    height: 480,
    fill: SceneColor(0xFF4A2F1F),
    opacity: 0.7,
    circle: true,
  );
  late final cup = TextNode('☕', x: 690, y: 110, fontSize: 190);
  late final headline = TextNode(
    'Fresh coffee, faster',
    fontSize: 54,
    weight: SceneFontWeight.w700,
    color: SceneColor(0xFFFFFFFF),
  );
  late final subtitle = TextNode(
    'Order ahead. Skip the line. Earn rewards.',
    fontSize: 20,
    color: SceneColor(0xFFD8C9BD),
  );
  late final ctaLabel = TextNode(
    'Get the app',
    fontSize: 17,
    weight: SceneFontWeight.w600,
    color: SceneColor(0xFFFFFFFF),
  );
  late final cta = FrameNode(
    fill: SceneColor(0xFFE8632B),
    corner: 28,
    layout: NodeLayout.row,
    padding: 16,
    children: [ctaLabel],
  );
  late final copy = FrameNode(
    x: 64,
    y: 120,
    width: 500,
    layout: NodeLayout.column,
    gap: 16,
    crossAlign: SceneCrossAxisAlignment.start,
    children: [headline, subtitle, cta],
  );
  late final badge = ExternalNode(
    const DrinkBadgeArgs(size: 140),
    x: 560,
    y: 290,
    width: 140,
    height: 140,
  );
  late final loading = ExternalNode(
    const SpinnerArgs(size: 40),
    x: 950,
    y: 430,
    width: 40,
    height: 40,
  );
  late final order = ExternalNode(
    const OrderButtonArgs(label: 'Order now'),
    x: 830,
    y: 400,
    width: 150,
    height: 44,
  );
  late final promo = SceneRefNode(
    const PromoBadgeArgs(label: 'Now open'),
    x: 64,
    y: 48,
  );
  @override
  late final root = FrameNode(
    width: 1024,
    height: 500,
    fill: SceneColor(0xFF2B1B12),
    children: [glow, cup, copy, badge, loading, order, promo],
  );
}

class BannerIntro(super.scene, {final double slideFrom = 24})
    extends SceneMotion<BannerScene> {
  late final headlineIn = scene.headline.animate(
    opacity: MotionTrack([
      MotionKey(at: 0.ms, value: 0),
      MotionKey(at: 260.ms, value: 1, curve: SceneCurves.easeOut),
    ]),
    translateY: MotionTrack([
      MotionKey(at: 0.ms, value: slideFrom),
      MotionKey(at: 260.ms, value: 0, curve: SceneCurves.easeOut),
    ]),
  );
  late final glowMood = scene.glow.animate(
    opacity: MotionTrack([
      MotionKey(at: 0.ms, value: 1),
      MotionKey(at: 900.ms, value: 0.85),
      MotionKey(at: 1800.ms, value: 1),
    ]),
  );
  late final badgePop = scene.badge.animate(
    scale: MotionTrack([
      MotionKey(at: 0.ms, value: 0.6),
      MotionKey(at: 240.ms, value: 1, curve: SceneCurves.easeOutBack),
    ]),
    args: DrinkBadgeTracks(
      size: MotionTrack([
        MotionKey(at: 0.ms, value: 110),
        MotionKey(at: 300.ms, value: 140, curve: SceneCurves.easeOut),
      ]),
    ),
  );
  late final tapPulse = scene.cta.animate(
    scale: MotionTrack([
      MotionKey(at: 0.ms, value: 1),
      MotionKey(at: 120.ms, value: 1.06),
      MotionKey(at: 240.ms, value: 1),
    ]),
  );
  @override
  late final timeline = ParExpr([
    headlineIn,
    AtExpr(400.ms, badgePop),
    glowMood,
  ]);
  BannerIntro copy(BannerScene scene) =>
      copyStateInto(BannerIntro(scene, slideFrom: slideFrom));
}

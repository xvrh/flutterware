//@flutterware:scene=0.9
import 'package:flutterware/scene_authoring.dart';

import 'scene_args.dart';

class StoreBanner({
  final String headline = 'Fresh coffee, faster',
  final String subtitle = 'Order ahead. Skip the line. Earn rewards.',
  final String cta = 'Get the app',
  final SceneColor tint = const SceneColor(0xFFE8632B),
  final SceneTokens tokens = const SceneTokens(),
}) extends SceneDefinition {
  late final glow = ShapeNode(
    x: 620,
    y: -90,
    width: 460,
    height: 460,
    fill: tokens.shopBrand,
    opacity: 0.7,
    circle: true,
  );
  late final cup = TextNode(
    '☕',
    style: SceneTextStyle(fontSize: 180),
    x: 700,
    y: 120,
  );
  late final title = TextNode(
    headline,
    style: tokens.title.copyWith(color: tokens.ink),
  );
  late final sub = TextNode(subtitle, style: tokens.shopSubtitle);
  late final ctaLabel = TextNode(
    cta,
    style: SceneTextStyle(
      fontSize: 17,
      weight: SceneFontWeight.w600,
      color: tokens.ink,
    ),
  );
  late final ctaBox = FrameNode(
    fill: tint,
    corner: tokens.radius,
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
    children: [title, sub, ctaBox],
  );
  @override
  late final root = FrameNode(
    width: 1024,
    height: 500,
    fill: tokens.espresso,
    children: [glow, cup, copy],
  );
}

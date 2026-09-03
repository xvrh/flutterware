//@flutterware:scene=0.7
// Owned by the flutterware scene editor, which reads and writes this whole
// file. Hand edits are welcome inside the grammar: every node is a
// `late final` field (the field name is the node's identity), placed exactly
// once in a children list; a parameter is a `final` in the class header
// whose default is the mockup. Anything outside the grammar is refused with
// a line number rather than silently dropped.
//
// This is ordinary Dart: it compiles, it analyzes, and an app mounts it.
import 'package:flutterware/scene_authoring.dart';

class Onboarding({
  final String title = 'Skip the queue',
  final String body = 'Order before you arrive and pick it up from the counter. Every tenth coffee is on us.',
  final String cta = 'Get started',
  final SceneColor tint = const SceneColor(0xFFE8632B),
}) extends SceneDefinition {
  late final cup = TextNode('☕', fontSize: 96);
  late final art = FrameNode(
    width: 200,
    height: 200,
    fill: SceneColor(0xFFF3E9E1),
    corner: 100,
    layout: NodeLayout.row,
    mainAlign: SceneMainAxisAlignment.center,
    children: [cup],
  );
  late final heading = TextNode(
    title,
    fontSize: 30,
    weight: SceneFontWeight.w700,
    color: SceneColor(0xFF1B1210),
  );
  late final copy = TextNode(body, color: SceneColor(0xFF6B5A52));
  late final ctaLabel = TextNode(
    cta,
    y: 13.579370847176051,
    fontSize: 17,
    weight: SceneFontWeight.w600,
    color: SceneColor(0xFFFFFFFF),
  );
  late final text1 = TextNode(
    'HERE!',
    fill: SceneColor(0xFF4A64D0),
    fontSize: 29.902395833333323,
    weight: SceneFontWeight.w900,
    color: SceneColor(0xFFF2B705),
  );
  late final ctaBox = FrameNode(
    width: double.infinity,
    fill: tint,
    corner: 28,
    layout: NodeLayout.row,
    padding: 16,
    mainAlign: SceneMainAxisAlignment.center,
    children: [ctaLabel, text1],
  );
  @override
  late final root = FrameNode(
    width: double.infinity,
    height: double.infinity,
    fill: SceneColor(0xFFFFFBF8),
    layout: NodeLayout.column,
    gap: 24,
    padding: 32,
    mainAlign: SceneMainAxisAlignment.center,
    crossAlign: SceneCrossAxisAlignment.start,
    children: [art, heading, copy, ctaBox],
  );
}

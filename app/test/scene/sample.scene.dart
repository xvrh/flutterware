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

class SampleScene({
  final String headline = 'Fresh coffee, faster',
  final SceneColor tint = const SceneColor(0xFFE8632B),
}) extends SceneDefinition {
  late final badge = ShapeNode(width: 24, height: 24, fill: tint, circle: true);
  late final title = TextNode(
    headline,
    fontSize: 32,
    weight: SceneFontWeight.w700,
    color: SceneColor(0xFFFFFFFF),
  );
  late final bar = FrameNode(
    layout: NodeLayout.row,
    gap: 12,
    padding: 16,
    children: [badge, title],
  );
  @override
  late final root = FrameNode(
    width: 400,
    height: 120,
    fill: SceneColor(0xFF2B1B12),
    children: [bar],
  );
}

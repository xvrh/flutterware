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

class PromoBadge({
  final String label = 'New',
  final SceneColor tint = const SceneColor(0xFFE8632B),
}) extends SceneDefinition {
  late final text = TextNode(
    label,
    style: SceneTextStyle(
      fontSize: 14,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFFFFFFFF),
    ),
  );
  @override
  late final root = FrameNode(
    width: 96,
    height: 32,
    fill: tint,
    corner: 16,
    layout: NodeLayout.row,
    mainAlign: SceneMainAxisAlignment.center,
    children: [text],
  );
}

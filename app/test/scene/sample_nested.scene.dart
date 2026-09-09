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

class SampleBadge({
  final String label = 'New',
  final SceneTokens tokens = const SceneTokens(),
}) extends SceneDefinition {
  late final text = TextNode(
    label,
    style: SceneTextStyle(
      fontSize: 11,
      weight: SceneFontWeight.w700,
      color: tokens.ink,
    ),
  );
  @override
  late final root = FrameNode(
    width: 70,
    height: 22,
    fill: SceneColor(0xFFE8632B),
    corner: 11,
    layout: NodeLayout.row,
    mainAlign: SceneMainAxisAlignment.center,
    children: [text],
  );
}

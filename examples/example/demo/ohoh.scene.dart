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

class Ohoh extends SceneDefinition {
  @override
  late final root = FrameNode(
    width: 1024,
    height: 500,
    fill: SceneColor(0xFFFFFFFF),
  );
}

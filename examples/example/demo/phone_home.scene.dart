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

class PhoneHome extends SceneDefinition {
  late final time = TextNode(
    '09:41',
    x: 24,
    y: 20,
    style: SceneTextStyle(
      fontSize: 22,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFFFFFFFF),
    ),
  );
  late final greeting = TextNode(
    'Good morning',
    x: 24,
    y: 120,
    style: SceneTextStyle(
      fontSize: 44,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFFFFFFFF),
    ),
  );
  late final sub = TextNode(
    'Two orders on their way',
    x: 24,
    y: 178,
    style: SceneTextStyle(fontSize: 20, color: SceneColor(0xFFB9C2D0)),
  );
  late final cardTitle = TextNode(
    'Flat white',
    style: SceneTextStyle(
      fontSize: 24,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFF161A22),
    ),
  );
  late final cardSub = TextNode(
    'arrives in 4 min',
    style: SceneTextStyle(fontSize: 18, color: SceneColor(0xFF5A6270)),
  );
  late final card = FrameNode(
    x: 24,
    y: 260,
    width: 312,
    height: 120,
    fill: SceneColor(0xFFF2B705),
    corner: 20,
    layout: NodeLayout.column,
    gap: 6,
    padding: 20,
    children: [cardTitle, cardSub],
  );
  late final card2Title = TextNode(
    'Croissant',
    style: SceneTextStyle(
      fontSize: 24,
      weight: SceneFontWeight.w700,
      color: SceneColor(0xFFFFFFFF),
    ),
  );
  late final card2Sub = TextNode(
    'arrives in 11 min',
    style: SceneTextStyle(fontSize: 18, color: SceneColor(0xFFB9C2D0)),
  );
  late final card2 = FrameNode(
    x: 24,
    y: 400,
    width: 312,
    height: 120,
    fill: SceneColor(0xFF4A64D0),
    corner: 20,
    layout: NodeLayout.column,
    gap: 6,
    padding: 20,
    children: [card2Title, card2Sub],
  );
  late final home = ShapeNode(
    x: 120,
    y: 750,
    width: 120,
    height: 6,
    fill: SceneColor(0xFFFFFFFF),
    corner: 3,
  );
  @override
  late final root = FrameNode(
    width: 360,
    height: 780,
    fill: SceneColor(0xFF1C2230),
    children: [time, greeting, sub, card, card2, home],
  );
}

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

class ArcadePoster({
  final String title = 'GAME OVER',
  final String kicker = 'insert coin to continue',
  final String score = '00128400',
  final SceneColor neon = const SceneColor(0xFFFF2D95),
}) extends SceneDefinition {
  late final glow = ShapeNode(
    x: 60,
    y: 396,
    width: 960,
    height: 540,
    fill: SceneColor(0xFF3A1466),
    corner: 270,
    opacity: 0.55,
  );
  late final kickerLine = TextNode(
    kicker,
    style: SceneTextStyle(
      fontSize: 30,
      weight: SceneFontWeight.w700,
      letterSpacing: 11,
      color: SceneColor(0xFF9BE7FF),
      textCase: SceneTextCase.upper,
      layers: [
        FillLayer(paint: SolidPaint(SceneColor(0xFF9BE7FF)), blur: 14),
        FillLayer(),
      ],
    ),
  );
  late final titleLine = TextNode(
    title,
    style: SceneTextStyle(
      fontSize: 166,
      weight: SceneFontWeight.w900,
      letterSpacing: -4,
      lineHeight: 0.95,
      color: SceneColor(0xFFFFF3B0),
      textCase: SceneTextCase.upper,
      layers: [
        FillLayer(paint: SolidPaint(SceneColor(0xFF120720)), dx: 9, dy: 9),
        FillLayer(paint: SolidPaint(SceneColor(0xFF120720)), dx: 8, dy: 8),
        FillLayer(paint: SolidPaint(SceneColor(0xFF120720)), dx: 7, dy: 7),
        FillLayer(paint: SolidPaint(SceneColor(0xFF120720)), dx: 6, dy: 6),
        FillLayer(paint: SolidPaint(SceneColor(0xFF120720)), dx: 5, dy: 5),
        FillLayer(paint: SolidPaint(SceneColor(0xFF120720)), dx: 4, dy: 4),
        FillLayer(paint: SolidPaint(SceneColor(0xFF120720)), dx: 3, dy: 3),
        FillLayer(paint: SolidPaint(SceneColor(0xFF120720)), dx: 2, dy: 2),
        StrokeLayer(width: 16, paint: SolidPaint(SceneColor(0xFF120720))),
        StrokeLayer(width: 6, paint: SolidPaint(SceneColor(0xFFFF2D95))),
        FillLayer(
          paint: LinearPaint(
            colors: [
              SceneColor(0xFFFFFBE8),
              SceneColor(0xFFFFD34E),
              SceneColor(0xFFFF9A1F),
            ],
            stops: [0, 0.55, 1],
          ),
        ),
      ],
    ),
    align: SceneTextAlign.center,
  );
  late final scoreLine = TextNode(
    score,
    style: SceneTextStyle(
      fontSize: 46,
      weight: SceneFontWeight.w700,
      letterSpacing: 14,
      color: SceneColor(0xFFFFFFFF),
      layers: [
        FillLayer(paint: SolidPaint(SceneColor(0xCC120720)), blur: 6, dy: 4),
        FillLayer(),
      ],
    ),
  );
  late final press = TextNode(
    'press start',
    style: SceneTextStyle(
      fontSize: 22,
      weight: SceneFontWeight.w600,
      letterSpacing: 6,
      color: SceneColor(0xFF120720),
      textCase: SceneTextCase.upper,
    ),
  );
  late final button = FrameNode(
    fill: neon,
    corner: 40,
    layout: NodeLayout.row,
    paddingLeft: 44,
    paddingTop: 20,
    paddingRight: 44,
    paddingBottom: 20,
    children: [press],
  );
  late final stack = FrameNode(
    width: 1080,
    height: 1350,
    layout: NodeLayout.column,
    gap: 58,
    mainAlign: SceneMainAxisAlignment.center,
    children: [kickerLine, titleLine, scoreLine, button],
  );
  @override
  late final root = FrameNode(
    width: 1080,
    height: 1350,
    fill: SceneColor(0xFF1B0F26),
    clip: true,
    children: [glow, stack],
  );
}

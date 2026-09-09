import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

/// A text's paint stack, in the four shapes it is actually reached for.
///
/// Each of these is the same one list with different numbers in it — an
/// outline is a stroke beneath the fill, a sticker is stroke-stroke-fill, a
/// shadow is a blurred offset fill, an extrusion is a run of offset fills
/// under a gradient one. That combinatorial reach is the argument for a list
/// over a `shadows` property and a `stroke` property, which are two points in
/// it and do not compose (master plan §4.5).
///
/// It is a picture rather than a test because that is what it answers: does a
/// 14px stroke survive a tight counter, does an extrusion read as depth, is
/// the gradient measured against the box or the glyph.
@Preview(name: 'Text layers', group: 'Scene')
Widget sceneLayers() => const _Layers();

const _ink = SceneColor(0xFF120720);
const _neon = SceneColor(0xFFFF2D95);
const _gold = LinearPaint(
  colors: [SceneColor(0xFFFFF3B0), SceneColor(0xFFFFB020)],
);

/// The stack for each specimen, with what it is called in a design tool.
const _specimens = <(String, List<TextLayer>)>[
  ('plain', []),
  (
    'outline',
    [
      StrokeLayer(width: 8, paint: SolidPaint(_ink)),
      FillLayer(paint: SolidPaint(SceneColor(0xFFFFC400))),
    ],
  ),
  (
    'sticker',
    [
      StrokeLayer(width: 20, paint: SolidPaint(SceneColor(0xFFFFFFFF))),
      StrokeLayer(width: 10, paint: SolidPaint(_ink)),
      FillLayer(paint: SolidPaint(SceneColor(0xFFFFC400))),
    ],
  ),
  (
    'shadow',
    [
      FillLayer(
        paint: SolidPaint(SceneColor(0xCC000000)),
        dx: 4,
        dy: 6,
        blur: 8,
      ),
      FillLayer(paint: SolidPaint(SceneColor(0xFFFFFFFF))),
    ],
  ),
  (
    'neon',
    [
      FillLayer(paint: SolidPaint(_neon), blur: 24),
      FillLayer(paint: SolidPaint(_neon), blur: 10),
      FillLayer(paint: SolidPaint(SceneColor(0xFFFFFFFF))),
    ],
  ),
  // One pixel a step: a depth is a run of offsets close enough to read as a
  // solid side, and two apart is where it starts to band instead.
  (
    'extruded',
    [
      FillLayer(paint: SolidPaint(_ink), dx: 8, dy: 8),
      FillLayer(paint: SolidPaint(_ink), dx: 7, dy: 7),
      FillLayer(paint: SolidPaint(_ink), dx: 6, dy: 6),
      FillLayer(paint: SolidPaint(_ink), dx: 5, dy: 5),
      FillLayer(paint: SolidPaint(_ink), dx: 4, dy: 4),
      FillLayer(paint: SolidPaint(_ink), dx: 3, dy: 3),
      FillLayer(paint: SolidPaint(_ink), dx: 2, dy: 2),
      FillLayer(paint: SolidPaint(_ink), dx: 1, dy: 1),
      FillLayer(paint: _gold),
    ],
  ),
];

class _Layers extends StatelessWidget {
  const _Layers();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ColoredBox(
      color: const Color(0xFF1B0F26),
      child: Align(
        alignment: Alignment.topLeft,
        child: SceneView.document(_specimenSheet()),
      ),
    ),
  );
}

SceneDocument _specimenSheet() {
  var rows = <SceneNode>[];
  for (var (name, layers) in _specimens) {
    var label = TextNode(
      name,
      name: 'label_$name',
      style: const SceneTextStyle(
        fontSize: 11,
        letterSpacing: 2,
        textCase: SceneTextCase.upper,
        color: SceneColor(0xFF7A6A88),
      ),
    );
    var word = TextNode(
      'Layers',
      name: 'word_$name',
      style: SceneTextStyle(
        fontSize: 54,
        weight: SceneFontWeight.w900,
        letterSpacing: -1,
        color: const SceneColor(0xFFFFFFFF),
        layers: layers,
      ),
    );
    rows.add(
      FrameNode(name: 'row_$name', layout: NodeLayout.column)
        ..gap = 2
        ..crossAlign = SceneCrossAxisAlignment.start
        ..children.addAll([label, word]),
    );
  }
  var root = FrameNode(name: 'root', layout: NodeLayout.column)
    ..width = 380
    ..height = 620
    ..fill = const SceneColor(0xFF1B0F26)
    ..padding = const SceneEdges.all(24)
    ..gap = 18
    ..children.addAll(rows);
  return SceneDocument(root);
}

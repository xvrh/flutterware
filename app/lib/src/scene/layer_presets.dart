// The seeded stacks.
//
// A paint stack is powerful and BLANK: facing "add a layer" with a kind, a
// paint, a width, a blur, an offset and an opacity, nobody arrives at sticker
// type, and nobody guesses that three strokes in decreasing width are what
// makes one. A preset teaches the mechanism by producing an instance of it
// that you then take apart.
//
// It is deliberately NOT a binding. Applying one writes the layers and walks
// away: no link, no inheritance to explain, everything editable the moment it
// lands. A stack that several texts should share is a STYLE, and that is the
// token system's job — starting dumb means the shared version is additive
// rather than a migration.
//
// Every structural pass leaves its paint null where it means "the text's own
// colour", so a preset shapes the treatment without dictating the palette.
import 'package:flutterware/scene_authoring.dart';

/// A named stack, and the font size its numbers were drawn for.
class LayerPreset {
  const LayerPreset(this.name, this.layers, {this.authoredAt = 54});

  final String name;
  final List<TextLayer> layers;

  /// A stroke of 20 that is right on a 54px title is a blob on a 13px label,
  /// so the numbers are scaled on the way in. This is the size they read
  /// correctly at — the one piece of cleverness in the whole feature, kept in
  /// one function rather than spread over the values.
  final double authoredAt;

  List<TextLayer> forSize(double fontSize) {
    var k = fontSize / authoredAt;
    if (k == 1) return [...layers];
    return [for (var l in layers) _scaled(l, k)];
  }
}

TextLayer _scaled(TextLayer l, double k) {
  var scaled = l.copyWith(
    blur: _round(l.blur * k),
    dx: _round(l.dx * k),
    dy: _round(l.dy * k),
  );
  return switch (scaled) {
    StrokeLayer s => s.copyWith(width: _round(s.width * k)),
    FillLayer f => f,
  };
}

/// A preset authored at one size, retold at another: a stroke of 3 on a
/// 21-point face becomes `21.9486607142857` at 54 unless somebody says
/// otherwise. Nobody chose those digits, and they end up in the library
/// file and in the generated class, so the arithmetic rounds where the
/// fields that edit it round.
double _round(double v) => (v * 100).roundToDouble() / 100;

const _ink = SceneColor(0xFF141018);
const _paper = SceneColor(0xFFFFFFFF);

const layerPresets = <LayerPreset>[
  LayerPreset('Outline', [
    StrokeLayer(width: 8, paint: SolidPaint(_ink)),
    FillLayer(),
  ]),
  LayerPreset('Sticker', [
    StrokeLayer(width: 20, paint: SolidPaint(_paper)),
    StrokeLayer(width: 10, paint: SolidPaint(_ink)),
    FillLayer(),
  ]),
  LayerPreset('Shadow', [
    FillLayer(paint: SolidPaint(SceneColor(0xCC000000)), dx: 4, dy: 6, blur: 8),
    FillLayer(),
  ]),
  LayerPreset('Neon', [
    FillLayer(blur: 24),
    FillLayer(blur: 10),
    FillLayer(paint: SolidPaint(_paper)),
  ]),
  LayerPreset('Extruded', [
    FillLayer(paint: SolidPaint(_ink), dx: 8, dy: 8),
    FillLayer(paint: SolidPaint(_ink), dx: 7, dy: 7),
    FillLayer(paint: SolidPaint(_ink), dx: 6, dy: 6),
    FillLayer(paint: SolidPaint(_ink), dx: 5, dy: 5),
    FillLayer(paint: SolidPaint(_ink), dx: 4, dy: 4),
    FillLayer(paint: SolidPaint(_ink), dx: 3, dy: 3),
    FillLayer(paint: SolidPaint(_ink), dx: 2, dy: 2),
    FillLayer(paint: SolidPaint(_ink), dx: 1, dy: 1),
    FillLayer(),
  ]),
  LayerPreset('Letterpress', [
    FillLayer(paint: SolidPaint(SceneColor(0x66FFFFFF)), dy: 1),
    FillLayer(paint: SolidPaint(SceneColor(0x55000000)), dy: -1),
    FillLayer(),
  ]),
];

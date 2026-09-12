// What an edit to a paint is, as arithmetic — kept apart from the widgets so
// every rule (stops stay sorted, two colours at least, a converted paint
// keeps what it can) is a unit test rather than a drag in a test harness.
import 'dart:math' as math;

import 'package:flutterware/scene_authoring.dart';

/// The six things a pass can be painted with, as the picker offers them.
enum ScenePaintKind {
  text('Text colour'),
  solid('Colour'),
  linear('Linear'),
  radial('Radial'),
  sweep('Sweep'),
  shader('Shader');

  const ScenePaintKind(this.label);

  final String label;

  static ScenePaintKind of(ScenePaint? p) => switch (p) {
    null => text,
    SolidPaint() => solid,
    LinearPaint() => linear,
    RadialPaint() => radial,
    SweepPaint() => sweep,
    ShaderPaint() => shader,
  };
}

/// [from] as a paint of [kind], keeping what carries over: a gradient's
/// colours and stops survive a change of shape, a colour becomes a gradient
/// that fades out of it, and a gradient becomes its first colour. [own] is
/// the text's colour, which is what "no paint" means.
ScenePaint? convertPaint(
  ScenePaint? from,
  ScenePaintKind kind, {
  required SceneColor own,
}) {
  if (ScenePaintKind.of(from) == kind) return from;
  var (List<SceneColor> colors, List<double>? stops) = switch (from) {
    SceneGradient g => (g.colors, g.stops),
    SolidPaint(:var color) => ([color, _clear(color)], null),
    ShaderPaint() || null => ([own, _clear(own)], null),
  };
  return switch (kind) {
    ScenePaintKind.text => null,
    ScenePaintKind.solid => SolidPaint(colors.first),
    ScenePaintKind.linear => LinearPaint(colors: colors, stops: stops),
    ScenePaintKind.radial => RadialPaint(colors: colors, stops: stops),
    ScenePaintKind.sweep => SweepPaint(colors: colors, stops: stops),
    ScenePaintKind.shader => const ShaderPaint(''),
  };
}

SceneColor _clear(SceneColor c) => SceneColor(c.argb & 0x00FFFFFF);

/// The colour [g] paints at [t], 0..1 along it — what a stop added there
/// starts as, so adding one changes nothing until it is moved or recoloured.
SceneColor colorAt(SceneGradient g, double t) {
  var stops = g.resolvedStops;
  var colors = g.colors;
  if (t <= stops.first) return colors.first;
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i]) {
      var span = stops[i] - stops[i - 1];
      var k = span == 0 ? 0.0 : (t - stops[i - 1]) / span;
      return SceneColor.lerp(colors[i - 1], colors[i], k);
    }
  }
  return colors.last;
}

/// An edit's result: the next gradient, and where the stop being edited is
/// now — a sort can move it.
typedef StopEdit = ({SceneGradient gradient, int index});

StopEdit addStop(SceneGradient g, double t) {
  var at = _round(t.clamp(0.0, 1.0));
  return _sorted(
    g,
    [...g.colors, colorAt(g, at)],
    [...g.resolvedStops, at],
    g.colors.length,
  );
}

StopEdit moveStop(SceneGradient g, int index, double t) {
  var stops = [...g.resolvedStops];
  stops[index] = _round(t.clamp(0.0, 1.0));
  return _sorted(g, g.colors, stops, index);
}

StopEdit recolorStop(SceneGradient g, int index, SceneColor color) {
  var colors = [...g.colors];
  colors[index] = color;
  // Stops left as they were: recolouring an even spread is no reason to
  // start writing its positions into the file.
  return (gradient: g.withStops(colors, g.stops), index: index);
}

/// Refused below two colours: a gradient of one is a solid, and the kind
/// picker is where that change is made.
StopEdit removeStop(SceneGradient g, int index) {
  if (g.colors.length <= 2) return (gradient: g, index: index);
  var colors = [...g.colors]..removeAt(index);
  var stops = [...g.resolvedStops]..removeAt(index);
  return (
    gradient: g.withStops(
      colors,
      _evenSpread(stops, colors.length) ? null : stops,
    ),
    index: math.min(index, colors.length - 1),
  );
}

/// Whether [stops] is exactly the spread [SceneGradient.resolvedStops] would
/// compute for [count] colours on its own — nothing left for a removal to
/// say, so nothing is written.
bool _evenSpread(List<double> stops, int count) {
  if (stops.length != count) return false;
  for (var i = 0; i < count; i++) {
    if (stops[i] != (count == 1 ? 0.0 : i / (count - 1))) return false;
  }
  return true;
}

/// [colors] at [stops], put in order, with [follow] tracked to wherever the
/// sort puts it. Ties keep their order: `List.sort` is not stable, and a tie
/// broken by the old position is.
StopEdit _sorted(
  SceneGradient g,
  List<SceneColor> colors,
  List<double> stops,
  int follow,
) {
  var order = List.generate(stops.length, (i) => i)
    ..sort((a, b) {
      var c = stops[a].compareTo(stops[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  return (
    gradient: g.withStops(
      [for (var i in order) colors[i]],
      [for (var i in order) stops[i]],
    ),
    index: order.indexOf(follow),
  );
}

/// Three decimals: a dragged stop would otherwise write 0.4372093 into the
/// file, and nobody chose those digits.
double _round(double v) => (v * 1000).roundToDouble() / 1000;

/// A linear gradient's direction as one number, the way a design tool shows
/// it: degrees clockwise from pointing up, so 180 runs top to bottom — the
/// default — and 90 left to right. The dial under the field draws the same.
double linearAngle(LinearPaint p) {
  var dx = p.end.x - p.begin.x;
  var dy = p.end.y - p.begin.y;
  if (dx == 0 && dy == 0) return 180;
  var degrees = math.atan2(dx, -dy) * 180 / math.pi;
  return ((degrees * 10).roundToDouble() / 10 + 360) % 360;
}

/// [p] pointed at [degrees], through the middle of the box and out to its
/// edge, so 45° runs corner to corner. A hand-written begin and end that did
/// not pass through the middle are re-centred by this: an angle is one
/// number, and one number cannot also say where.
LinearPaint withLinearAngle(LinearPaint p, double degrees) {
  var r = degrees * math.pi / 180;
  var x = math.sin(r);
  var y = -math.cos(r);
  var k = 1 / math.max(x.abs(), y.abs());
  var end = SceneAlignment(_tidy(x * k), _tidy(y * k));
  return LinearPaint(
    colors: p.colors,
    stops: p.stops,
    begin: SceneAlignment(-end.x + 0, -end.y + 0),
    end: end,
  );
}

/// Four decimals and no negative zero, so 90° is `centerLeft` to
/// `centerRight` and the file spells it by name.
double _tidy(double v) {
  var r = (v * 10000).roundToDouble() / 10000;
  return r == 0 ? 0 : r;
}

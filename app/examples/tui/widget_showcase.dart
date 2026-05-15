// Stage 4 widget-layer showcase. Run in a real terminal:
//   cd app && dart run examples/tui/widget_showcase.dart
// ←/→ or 1-5 switch scenes · space pauses · q quits.

import 'dart:async';

import 'package:flutterware_app/src/tui/tui.dart';

/// Signature for [Painted]'s free-form paint callback. [size] is the box size.
typedef PaintCallback = void Function(Painter painter, CellSize size);

/// A leaf widget that hands a [Painter] to a callback — the demo's escape
/// hatch into free-form, per-cell painting. It is defined here, in the
/// example, on purpose: it shows a consumer can drop down to a custom
/// [RenderObject] without any framework change.
class Painted extends LeafRenderObjectWidget {
  const Painted(this.onPaint, {super.key});

  final PaintCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPainted(onPaint);

  @override
  void updateRenderObject(BuildContext context, RenderPainted renderObject) {
    renderObject.onPaint = onPaint;
  }
}

/// The [RenderBox] behind [Painted]: fills whatever space it is given and
/// defers painting to the callback.
class RenderPainted extends RenderBox {
  RenderPainted(this._onPaint);

  PaintCallback _onPaint;
  PaintCallback get onPaint => _onPaint;
  set onPaint(PaintCallback value) {
    _onPaint = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  void performResize() {
    size = constraints.biggest;
  }

  @override
  void performLayout() {}

  @override
  void paint(Painter painter) => _onPaint(painter, size);
}

/// HSV → [Color]. [h], [s], [v] are all 0..1. Used for plasma and gradients.
Color hsv(double h, double s, double v) {
  var hue = (h % 1.0) * 6.0;
  var i = hue.floor();
  var f = hue - i;
  var p = v * (1 - s);
  var q = v * (1 - s * f);
  var t = v * (1 - s * (1 - f));
  var (r, g, b) = switch (i % 6) {
    0 => (v, t, p),
    1 => (q, v, p),
    2 => (p, v, t),
    3 => (p, q, v),
    4 => (t, p, v),
    _ => (v, p, q),
  };
  return Color.rgb((r * 255).round(), (g * 255).round(), (b * 255).round());
}

/// Linearly interpolates between two RGB colors. [t] is 0..1.
Color lerpColor(Color a, Color b, double t) {
  int mix(int x, int y) => (x + (y - x) * t).round();
  return Color.rgb(mix(a.r, b.r), mix(a.g, b.g), mix(a.b, b.b));
}

/// Maps a 0..1 fraction to a partial-block rune ` ▁▂▃▄▅▆▇█` for sub-cell
/// precision in bar/area charts.
int eighthBlock(double frac) {
  var level = (frac.clamp(0.0, 1.0) * 8).round();
  if (level <= 0) return 0x20; // space
  return 0x2580 + level; // 0x2581..0x2588
}

/// Root of the showcase. Owns the animation clock and (later) input + scenes.
class ShowcaseApp extends StatefulWidget {
  const ShowcaseApp({super.key});

  @override
  State<ShowcaseApp> createState() => _ShowcaseState();
}

class _ShowcaseState extends State<ShowcaseApp> {
  Timer? _timer;
  double _time = 0;

  @override
  void initState() {
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      setState(() => _time += 0.033);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    var t = _time;
    return Painted((painter, size) {
      for (var row = 0; row < size.rows; row++) {
        for (var col = 0; col < size.cols; col++) {
          var c = hsv(
              (col / size.cols + row / size.rows + t * 0.2) % 1.0, 0.7, 0.9);
          painter.fillRect(
              CellRect.fromTLWH(row, col, 1, 1), Cell(rune: 0x20, bg: c));
        }
      }
    });
  }
}

Future<void> main() => runApp(const ShowcaseApp());

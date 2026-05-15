// Stage 4 widget-layer showcase. Run in a real terminal:
//   cd app && dart run examples/tui/widget_showcase.dart
// ←/→ or 1-5 switch scenes · space pauses · q quits.

import 'dart:async';
import 'dart:math' as math;

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

/// Scene 1: a full-screen RGB sine-plasma field, painted at 2x vertical
/// resolution with the half-block trick.
class PlasmaScene extends StatelessWidget {
  const PlasmaScene({required this.time, super.key});

  final double time;

  Color _pixel(int px, int py, double t) {
    var v = math.sin(px / 8 + t) +
        math.sin(py / 6 + t * 1.3) +
        math.sin((px + py) / 10 + t * 0.7);
    var n = (v + 3) / 6; // normalize -3..3 → 0..1
    return hsv(n, 1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    var t = time;
    return Painted((painter, size) {
      for (var row = 0; row < size.rows; row++) {
        for (var col = 0; col < size.cols; col++) {
          var top = _pixel(col, row * 2, t);
          var bottom = _pixel(col, row * 2 + 1, t);
          painter.fillRect(CellRect.fromTLWH(row, col, 1, 1),
              Cell(rune: 0x2580, fg: top, bg: bottom));
        }
      }
    });
  }
}

/// Scene 2: a 3D parallax starfield warping past the camera.
class StarfieldScene extends StatelessWidget {
  const StarfieldScene({required this.time, super.key});

  final double time;

  static final List<({double x, double y, double z})> _stars = () {
    var rng = math.Random(42);
    return List.generate(
        140,
        (_) => (
              x: rng.nextDouble() * 2 - 1,
              y: rng.nextDouble() * 2 - 1,
              z: rng.nextDouble(),
            ));
  }();

  @override
  Widget build(BuildContext context) {
    var t = time;
    return Painted((painter, size) {
      var black = Color.rgb(0, 0, 0);
      painter.fill(Cell(rune: 0x20, bg: black));
      var cx = size.cols / 2;
      var cyPix = size.rows; // half-block: rows*2 pixels tall, center at rows
      for (var s in _stars) {
        var z = (s.z - t * 0.25) % 1.0;
        var d = z * 0.95 + 0.05;
        var sx = (cx + s.x / d * cx).round();
        var syPix = (cyPix + s.y / d * cyPix).round();
        if (sx < 0 || sx >= size.cols) continue;
        var cellRow = syPix ~/ 2;
        if (cellRow < 0 || cellRow >= size.rows) continue;
        var b = (1 - z).clamp(0.0, 1.0);
        var c = lerpColor(black, Color.rgb(255, 255, 255), b);
        var top = syPix.isEven ? c : black;
        var bottom = syPix.isEven ? black : c;
        painter.fillRect(CellRect.fromTLWH(cellRow, sx, 1, 1),
            Cell(rune: 0x2580, fg: top, bg: bottom));
      }
    });
  }
}

/// Scene 3: a [Row] of two bordered panels — left is a custom-paint area chart,
/// right is an animated bar chart built entirely from real widgets.
///
/// [maxBarRows] is a fixed budget for the bar chart value→height mapping;
/// the area chart uses the real [size.rows] from its [Painted] callback.
class ChartsScene extends StatelessWidget {
  const ChartsScene({required this.time, super.key});

  final double time;

  // Fixed height budget for the bar chart bars (in terminal rows).
  static const int _maxBarRows = 12;
  static const int _barCount = 7;

  @override
  Widget build(BuildContext context) {
    var t = time;

    // --- Left panel: custom-paint area chart ---
    var leftBody = Painted((painter, size) {
      for (var x = 0; x < size.cols; x++) {
        var f = (0.5 +
                0.3 * math.sin(x * 0.3 + t * 2) +
                0.15 * math.sin(x * 0.7 - t))
            .clamp(0.0, 1.0);
        // Total filled height in pixels (rows * 1 pixel per row here).
        var filledPixels = f * size.rows;
        var fullRows = filledPixels.floor();
        var crestFrac = filledPixels - fullRows;

        // Fill full rows from the bottom up.
        for (var row = 0; row < fullRows; row++) {
          var cellRow = size.rows - 1 - row;
          var heightFrac = (row + 1) / size.rows;
          // Green at the bottom, cyan at the top.
          var cellColor = lerpColor(
              Color.rgb(0, 200, 80), Color.rgb(0, 220, 220), heightFrac);
          painter.fillRect(CellRect.fromTLWH(cellRow, x, 1, 1),
              Cell(rune: 0x2588, fg: cellColor, bg: Color.rgb(0, 0, 0)));
        }

        // Crest cell with eighth-block precision.
        if (crestFrac > 0 && fullRows < size.rows) {
          var cellRow = size.rows - 1 - fullRows;
          var heightFrac = (fullRows + crestFrac) / size.rows;
          var crestColor = lerpColor(
              Color.rgb(0, 200, 80), Color.rgb(0, 220, 220), heightFrac);
          var rune = eighthBlock(crestFrac);
          // Eighth-block runes grow upward: rune is rendered as fg on bg.
          painter.fillRect(CellRect.fromTLWH(cellRow, x, 1, 1),
              Cell(rune: rune, fg: crestColor, bg: Color.rgb(0, 0, 0)));
        }
      }
    });

    // --- Right panel: real-widget bar chart ---
    // Each bar: value v in 0..1, mapped to height h in 1..maxBarRows.
    // A flex spacer above the bar bottom-aligns it.
    var bars = <Widget>[];
    for (var i = 0; i < _barCount; i++) {
      var v = (1 + math.sin(t * 1.5 + i * 0.6)) / 2;
      var h = (v * _maxBarRows).round().clamp(1, _maxBarRows);
      var gap = (_maxBarRows - h).clamp(1, _maxBarRows - 1);
      var barColor = hsv(i / _barCount, 0.8, 0.9);
      if (i > 0) bars.add(SizedBox(width: 1));
      bars.add(
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: gap, child: SizedBox()),
              SizedBox(
                height: h,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    fill: Cell(rune: 0x20, bg: barColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    var rightBody = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: bars,
    );

    // Helper to wrap content in a bordered panel with a title.
    Widget panel(String title, Widget body, Color accent) {
      return Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: BoxBorder(chars: BorderChars.rounded(), fg: accent),
          ),
          child: Padding(
            padding: EdgeInsets.all(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, fg: accent, style: TextStyle.bold),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panel('signal · custom paint', leftBody, Color.cyan),
        panel('bars · flex layout', rightBody, Color.magenta),
      ],
    );
  }
}

/// Scene 4: a live view of the layout engine — [MainAxisAlignment] cycling and
/// morphing [Expanded] flex factors. No [Painted]; real widgets only.
class LayoutLabScene extends StatelessWidget {
  const LayoutLabScene({required this.time, super.key});

  final double time;

  // The six MainAxisAlignment values in order.
  static const _alignments = [
    MainAxisAlignment.start,
    MainAxisAlignment.center,
    MainAxisAlignment.end,
    MainAxisAlignment.spaceBetween,
    MainAxisAlignment.spaceAround,
    MainAxisAlignment.spaceEvenly,
  ];

  // Four distinct box colors for the alignment demo row.
  static const _boxColors = [
    Color.rgb(255, 100, 100),
    Color.rgb(100, 220, 100),
    Color.rgb(100, 160, 255),
    Color.rgb(255, 200, 80),
  ];

  @override
  Widget build(BuildContext context) {
    var t = time;

    // Cycle through alignments once every ~1.6 s.
    var alignIndex = (t / 1.6).floor() % _alignments.length;
    var align = _alignments[alignIndex];

    // Fixed-size colored boxes for the alignment demo.
    var boxes = [
      for (var i = 0; i < _boxColors.length; i++)
        SizedBox(
          width: 8,
          height: 3,
          child: DecoratedBox(
            decoration:
                BoxDecoration(fill: Cell(rune: 0x20, bg: _boxColors[i])),
          ),
        ),
    ];

    // Morph flex factors: flexA 1..7, flexB = 8 - flexA so they always sum to 8.
    var flexA = (1 + ((1 + math.sin(t)) * 3).round()).clamp(1, 7);
    var flexB = 8 - flexA;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('mainAxisAlignment', style: TextStyle.bold),
        Row(mainAxisAlignment: align, children: boxes),
        Text('  ${align.name}'),
        SizedBox(height: 1),
        Text('flex factors', style: TextStyle.bold),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: flexA,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  fill: Cell(rune: 0x20, bg: Color.rgb(80, 180, 255)),
                ),
                child: Text(
                  '$flexA',
                  hAlign: HorizontalAlign.center,
                  vAlign: VerticalAlign.center,
                  style: TextStyle.bold,
                ),
              ),
            ),
            Expanded(
              flex: flexB,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  fill: Cell(rune: 0x20, bg: Color.rgb(255, 120, 180)),
                ),
                child: Text(
                  '$flexB',
                  hAlign: HorizontalAlign.center,
                  vAlign: VerticalAlign.center,
                  style: TextStyle.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Scene 5: a typography showcase — a gradient wordmark, a bobbing character
/// wave, and a row of [TextStyle] samples.
class TypeScene extends StatelessWidget {
  const TypeScene({required this.time, super.key});

  final double time;

  @override
  Widget build(BuildContext context) {
    var t = time;
    var wordmark = 'flutterware';

    // 1. Gradient wordmark: one bold Text per character with hsv fg.
    var wordmarkChars = <Widget>[
      for (var i = 0; i < wordmark.length; i++)
        Text(
          wordmark[i],
          fg: hsv((i / wordmark.length + t * 0.3) % 1.0, 1.0, 1.0),
          style: TextStyle.bold,
        ),
    ];

    // 2. Wave: each character bobs via a SizedBox height spacer above it.
    var waveStr = '~ widget layer ~';
    var waveWidgets = <Widget>[
      for (var i = 0; i < waveStr.length; i++)
        Column(
          children: [
            SizedBox(
                height: (1 + math.sin(i * 0.5 + t * 3)).round().clamp(0, 2)),
            Text(waveStr[i]),
          ],
        ),
    ];

    // 3. Style sampler.
    var styleSampler = <Widget>[
      Text('bold', style: TextStyle.bold),
      Text('dim', style: TextStyle.dim),
      Text('italic', style: TextStyle.italic),
      Text('underline', style: TextStyle.underline),
      Text('reverse', style: TextStyle.reverse),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: wordmarkChars),
        SizedBox(height: 1),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: waveWidgets),
        SizedBox(height: 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: styleSampler,
        ),
      ],
    );
  }
}

/// Scene name labels, indexed 0–4, used by [Header] tabs and the build switch.
const _sceneNames = ['Plasma', 'Stars', 'Charts', 'Layout', 'Type'];

/// Persistent chrome header: a 3-row fixed-height region showing the app title,
/// scene tabs, and an animated color gradient bar.
class Header extends StatelessWidget {
  const Header({required this.time, required this.scene, super.key});

  final double time;
  final int scene;

  @override
  Widget build(BuildContext context) {
    var t = time;

    // Row 2: five scene tabs; active one bold+bright, others dim.
    var tabs = <Widget>[];
    for (var i = 0; i < _sceneNames.length; i++) {
      if (i > 0) tabs.add(SizedBox(width: 2));
      var isActive = i == scene;
      tabs.add(Text(
        '${i + 1} ${_sceneNames[i]}',
        fg: isActive ? Color.brightWhite : Color.brightBlack,
        style: isActive ? TextStyle.bold : 0,
      ));
    }

    // Row 3: animated 1-cell-tall gradient bar.
    var gradientBar = ConstrainedBox(
      constraints: BoxConstraints.tightFor(height: 1),
      child: Painted((painter, size) {
        for (var col = 0; col < size.cols; col++) {
          painter.fillRect(
            CellRect.fromTLWH(0, col, 1, 1),
            Cell(
              rune: 0x20,
              bg: hsv((col / size.cols + t * 0.3) % 1.0, 0.8, 0.7),
            ),
          );
        }
      }),
    );

    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(height: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'flutterware · widget showcase',
            fg: Color.brightWhite,
            style: TextStyle.bold,
            hAlign: HorizontalAlign.center,
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: tabs),
          gradientBar,
        ],
      ),
    );
  }
}

/// Persistent chrome footer: a 1-row fixed-height region with key hints on the
/// left and live FPS (or PAUSED) on the right.
class Footer extends StatelessWidget {
  const Footer({required this.fps, required this.paused, super.key});

  final int fps;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    var rightText = paused
        ? Text('PAUSED', fg: Color.brightYellow)
        : Text('$fps fps', fg: Color.brightBlack);

    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(height: 1),
      child: Row(
        children: [
          Text(
            '←/→ scene · 1-5 jump · space pause · q quit',
            fg: Color.brightBlack,
          ),
          Expanded(child: SizedBox()),
          rightText,
        ],
      ),
    );
  }
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
  int _scene = 0;
  bool _paused = false;
  double _fps = 0;
  StreamSubscription<KeyEvent>? _keySub;
  bool _subscribed = false;

  @override
  void initState() {
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      setState(() {
        if (!_paused) _time += 0.033;
        // Smoothed FPS estimate: target is 1000ms / 33ms ≈ 30.3 fps.
        _fps = _fps * 0.9 + (1000 / 33) * 0.1;
      });
    });
  }

  @override
  void didChangeDependencies() {
    if (_subscribed) return;
    _subscribed = true;
    var app = TerminalApp.of(context);
    _keySub = app.keys.listen((event) {
      if (event is CharKey) {
        var r = event.rune;
        if (r == 0x71 /* q */) {
          app.exit();
        } else if (r == 0x20 /* space */) {
          setState(() => _paused = !_paused);
        } else if (r >= 0x31 && r <= 0x35 /* '1'..'5' */) {
          setState(() => _scene = r - 0x31);
        }
      } else if (event is SpecialKey) {
        if (event.code == SpecialKeyCode.right) {
          setState(() => _scene = (_scene + 1) % 5);
        } else if (event.code == SpecialKeyCode.left) {
          setState(() => _scene = (_scene - 1 + 5) % 5);
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_keySub?.cancel());
  }

  @override
  Widget build(BuildContext context) {
    var scene = switch (_scene) {
      0 => PlasmaScene(time: _time),
      1 => StarfieldScene(time: _time),
      2 => ChartsScene(time: _time),
      3 => LayoutLabScene(time: _time),
      _ => TypeScene(time: _time),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Header(time: _time, scene: _scene),
        Expanded(flex: 1, child: scene),
        Footer(fps: _fps.round(), paused: _paused),
      ],
    );
  }
}

Future<void> main() => runApp(const ShowcaseApp());

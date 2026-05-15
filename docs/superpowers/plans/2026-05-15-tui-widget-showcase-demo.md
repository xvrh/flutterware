# TUI Widget-Layer Showcase Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `app/examples/tui/widget_showcase.dart` — a flashy, animated, full-screen demo of the Stage 4 TUI widget layer: a five-scene showcase reel (plasma, starfield, charts, layout lab, typography) with keyboard navigation.

**Architecture:** One self-contained example file. A `ShowcaseApp` `StatefulWidget` drives a 30 fps animation loop via `Timer.periodic` + `setState`, handles keyboard input, and renders chrome (header/footer) around the active scene. A demo-defined `Painted` widget (`LeafRenderObjectWidget` + custom `RenderBox`) exposes a paint callback for free-form per-cell effects. No framework (`lib/`) code changes.

**Tech Stack:** Pure Dart. The demo imports only `package:flutterware_app/src/tui/tui.dart` (and `dart:async`, `dart:math`). Runs with `cd app && dart run examples/tui/widget_showcase.dart`.

**Spec:** `docs/superpowers/specs/2026-05-15-tui-widget-showcase-demo-design.md` — read it before starting; it is the source of truth for every scene and behavior.

**Conventions** (from `CLAUDE.md`): prefer `var` for locals, NO `final` on function/constructor *parameters* (widget instance fields ARE `final` — required and correct), single quotes, `prefer_interpolation_to_compose_strings`, wrap fire-and-forget futures in `unawaited(...)`, don't litter `const`. Match the style of existing examples in `app/examples/tui/` (read `widget_demo.dart` and `render_tree_demo.dart`).

**No automated tests.** Examples are not unit-tested in this repo. Per-task verification is `dart analyze` cleanliness; the whole-app `flutter test` run is a regression guard (the demo touches no `lib/` code). Manual smoke in a real terminal is the final acceptance gate and is the user's responsibility — subagents cannot run a TTY.

---

## Relevant API reference

All from `package:flutterware_app/src/tui/tui.dart` unless noted. Confirm against the source if anything is unclear.

- **`runApp(Widget app)`** → `Future<void>`. Entry point. (`widgets/binding.dart`)
- **`TerminalApp.of(BuildContext)`** → `TerminalApp` with `Stream<KeyEvent> keys`, `CellSize size`, `void Function() exit`.
- **`StatefulWidget`/`State`** — lifecycle `initState`, `didChangeDependencies`, `dispose`, `setState(fn)`, `build(context)`. `StatelessWidget` — `build(context)`.
- **Widgets:** `Text(String, {Color fg, Color bg, int style, HorizontalAlign hAlign, VerticalAlign vAlign, bool wrap})`, `Padding({EdgeInsets padding, Widget? child})`, `ConstrainedBox({BoxConstraints constraints, Widget? child})`, `SizedBox({int? width, int? height, Widget? child})`, `DecoratedBox({BoxDecoration decoration, Widget? child})`, `Row`/`Column`/`Flex({MainAxisAlignment mainAxisAlignment, CrossAxisAlignment crossAxisAlignment, MainAxisSize mainAxisSize, List<Widget> children})`, `Expanded({int flex, required Widget child})`, `Flexible`.
- **Custom render objects:** `LeafRenderObjectWidget` (override `createRenderObject`/`updateRenderObject`), `RenderObject`, `RenderBox` (override `sizedByParent`, `performResize`, `performLayout`, `paint(Painter)`; `size` setter, `constraints` getter, `markNeedsPaint()`), `BoxConstraints` (`.biggest`, `.tightFor({width,height})`).
- **Geometry:** `CellSize(rows, cols)`, `CellRect.fromTLWH(top, left, width, height)`, `CellOffset`.
- **Painting:** `Painter` — `fill(Cell)`, `fillRect(CellRect, Cell)`, `drawText(CellRect, String, {Color fg, Color bg, int style, HorizontalAlign hAlign, VerticalAlign vAlign, bool wrap})`, `drawHLine`/`drawVLine`/`drawBorder`.
- **`Cell({int rune, Color fg, Color bg, int style})`** — `rune` is a Unicode code point.
- **`Color`** — `Color.rgb(int r, int g, int b)` (0–255), plus named `Color.black/red/green/.../white/brightBlack/...brightWhite`, `Color.defaultFg`, `Color.defaultBg`.
- **`TextStyle`** — int bitfield: `TextStyle.bold` (1), `dim` (2), `italic` (4), `underline` (8), `reverse` (16). Combine with `|`.
- **`HorizontalAlign.{left,center,right}`**, **`VerticalAlign.{top,center,bottom}`**.
- **Input:** `KeyEvent` (sealed) → `CharKey` (`int rune`) and `SpecialKey` (`SpecialKeyCode code`). `SpecialKeyCode.{left,right,up,down,...}`.
- **`BoxDecoration({Cell? fill, BoxBorder? border})`**, **`BoxBorder({BorderChars chars, Color fg})`**, **`BorderChars.rounded()`/`.single()`**.
- **`EdgeInsets.all(int)`/`.symmetric(...)`/`.only(...)`**.

Useful runes: `0x2580` `▀` upper-half block; `0x2581`–`0x2588` `▁▂▃▄▅▆▇█` eighth blocks; `0x20` space.

---

## File Structure

- **Create** `app/examples/tui/widget_showcase.dart` — the entire demo, one file, built up across Tasks 1–6 in this section order:
  1. file header comment + imports
  2. `Painted` / `RenderPainted`
  3. paint helpers (`hsv`, `eighthBlock`, `lerpColor`)
  4. the five scene widgets
  5. `Header` / `Footer` chrome widgets
  6. `ShowcaseApp` / `_ShowcaseState`
  7. `main()`
- **Modify** `app/lib/src/tui/README.md` — one line adding `widget_showcase.dart` to the examples mention (Task 7).

Each task leaves the file `dart analyze`-clean and (from Task 1 on) runnable.

---

## Task 1: Scaffold — `Painted` widget, helpers, animation loop

End state: a runnable demo that fills the screen with an animated full-color gradient. This proves the `Painted` custom render object, the `Timer` loop, and `runApp` integration all work before any scene exists.

**Files:**
- Create: `app/examples/tui/widget_showcase.dart`

- [ ] **Step 1: Create the file with header, imports, `Painted`, helpers**

```dart
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
```

Note: `Color` exposes `.r`/`.g`/`.b` int fields (see `cell.dart`) — confirm; `lerpColor` and `hsv` rely on it. If `Color` does not expose RGB getters for *named* colors, that is fine: `lerpColor` is only ever called on `Color.rgb(...)` values in this demo.

- [ ] **Step 2: Add a temporary `ShowcaseApp` + `main` that animates a gradient**

Append:

```dart
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
          var c = hsv((col / size.cols + row / size.rows + t * 0.2) % 1.0,
              0.7, 0.9);
          painter.fillRect(
              CellRect.fromTLWH(row, col, 1, 1), Cell(rune: 0x20, bg: c));
        }
      }
    });
  }
}

Future<void> main() => runApp(const ShowcaseApp());
```

- [ ] **Step 3: Verify analyze**

Run: `cd app && dart analyze examples/tui/widget_showcase.dart`
Expected: `No issues found!`

If `Color` has no public `.r`/`.g`/`.b` getters, the analyzer will flag `lerpColor`/`hsv`. In that case read `app/lib/src/tui/cell.dart`, find how RGB channels are exposed, and adjust — do not guess.

- [ ] **Step 4: Sanity-run (optional)**

Run: `cd app && dart run examples/tui/widget_showcase.dart`
Expected: the ONLY error is a startup `StdinException` (no TTY in CI). That proves the file compiled and `runApp` was reached. A `StdinException` here is NOT a failure.

- [ ] **Step 5: Regression guard + commit**

Run: `cd app && flutter test` → expect all 329 tests pass (the demo touches no `lib/` code).

```bash
git add app/examples/tui/widget_showcase.dart
git commit -m "Add showcase demo scaffold: Painted widget and animation loop"
```

(The pre-commit hook may print "deps not resolved" — benign, the commit still succeeds.)

---

## Task 2: Plasma and Starfield scenes

**Files:**
- Modify: `app/examples/tui/widget_showcase.dart`

- [ ] **Step 1: Add `PlasmaScene`**

Insert before `ShowcaseApp`. A `StatelessWidget` taking `double time`. It returns a `Painted`. Use the **half-block trick** — each cell renders two vertically-stacked pixels via `▀` (`0x2580`): `fg` = top pixel color, `bg` = bottom pixel color. So a cell at `(row, col)` covers pixels `(2*row, col)` and `(2*row+1, col)`.

```dart
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
```

- [ ] **Step 2: Add `StarfieldScene`**

A `StatelessWidget` taking `double time`. A fixed star list built once (`static final`), each star a `(x, y, z0)` with `x, y` in `-1..1` and `z0` an initial depth in `0..1`. Animate depth: `z = ((z0 - time * speed) % 1.0)`, then map to a usable depth `d = z * maxDepth + 0.1`. Project: `sx = cx + x / d * cx`, `sy = cy + y / d * cy` (cx/cy are half the size). Brightness `b = (1 - z).clamp(0,1)` → grey via `lerpColor(Color.rgb(0,0,0), Color.rgb(255,255,255), b)` or `hsv(0,0,b)`. Plot each visible star as a half-block pixel: pixel `(sx, sy2)` where `sy2` is the 2x-resolution row; the cell is `(sy2 ~/ 2, sx)` and you set `fg` if `sy2` is even, `bg` if odd — paint the cell with rune `0x2580` and the other half left black. Because you cannot read back, paint a black background first (`painter.fill(Cell(rune: 0x20, bg: Color.rgb(0,0,0)))`), then for each star fill its cell with `Cell(rune: 0x2580, fg: starColor or black, bg: black or starColor)`.

Implementation guidance — keep it correct and simple:

```dart
/// Scene 2: a 3D parallax starfield warping past the camera.
class StarfieldScene extends StatelessWidget {
  const StarfieldScene({required this.time, super.key});

  final double time;

  static final List<({double x, double y, double z})> _stars = () {
    var rng = math.Random(42);
    return List.generate(140, (_) => (
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
```

- [ ] **Step 3: Wire scenes into `ShowcaseApp` temporarily**

Change `_ShowcaseState.build` to show the two new scenes alternating so they can be eyeballed: e.g. return `((_time ~/ 4) % 2 == 0) ? PlasmaScene(time: _time) : StarfieldScene(time: _time)`. (This is temporary; Task 5 replaces it with real scene dispatch.)

- [ ] **Step 4: Verify analyze**

Run: `cd app && dart analyze examples/tui/widget_showcase.dart` → `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/examples/tui/widget_showcase.dart
git commit -m "Add plasma and starfield showcase scenes"
```

---

## Task 3: Charts scene

**Files:**
- Modify: `app/examples/tui/widget_showcase.dart`

- [ ] **Step 1: Add `ChartsScene`**

A `StatelessWidget` taking `double time`. Returns a `Row` (`crossAxisAlignment: CrossAxisAlignment.stretch`) of two `Expanded` panels. Each panel is a bordered `DecoratedBox` (`BoxBorder(chars: BorderChars.rounded(), fg: <accent>)`) wrapping `Padding(EdgeInsets.all(1))` wrapping a `Column` of a bold title `Text` and an `Expanded` body.

- **Left panel body** — a `Painted` area chart. For each column `x` (0..size.cols-1), compute `f = 0.5 + 0.3*sin(x*0.3 + time*2) + 0.15*sin(x*0.7 - time)`, clamp 0..1. The filled height in pixels is `f * size.rows`. Fill that column from the bottom: full `█` (`0x2588`) cells for whole rows, and one `eighthBlock(fractional)` rune for the crest cell. Color each filled cell with a gradient via `hsv` or `lerpColor` keyed on height (e.g. green at the bottom → cyan at the top). Leave cells above the signal at the background.

- **Right panel body** — an animated bar chart from **real widgets only** (no `Painted`). A `Row` (`crossAxisAlignment: stretch`) of N (say 7) `Expanded` children; each child is a `Column` of `[Expanded(flex: gap, child: SizedBox()), bar]` where `bar` is a `SizedBox(height: h, child: DecoratedBox(decoration: BoxDecoration(fill: Cell(rune: 0x20, bg: barColor))))`. Compute, per bar `i`, a value `v = (1 + sin(time*1.5 + i*0.6)) / 2` (0..1); `h = (v * maxBarRows).round().clamp(1, maxBarRows)` and `gap` = the remaining space as a flex weight (e.g. `flex: maxBarRows - h` on the spacer's `Expanded`, `flex` ≥ 1; the bar is non-flex with tight height `h`). Add a 1-column gap between bars with small `SizedBox(width: 1)` spacers or `Padding`. Bar colors cycle via `hsv(i / N, 0.8, 0.9)`.

You will need the panel's pixel height to size the area chart and the bar `maxBarRows`. Since a `StatelessWidget` does not know its size at build time, pick a reasonable fixed `maxBarRows` (e.g. 12) for the bar chart's value→height mapping and let layout clip/scale; for the area chart, the `Painted` callback receives the real `size`, so use `size.rows` there. Document this in a comment.

Title texts: left `'signal · custom paint'`, right `'bars · flex layout'`. Accent colors: left cyan-ish, right magenta-ish (match the repo's existing demo palette — see `render_tree_demo.dart`).

- [ ] **Step 2: Show the charts scene temporarily**

Temporarily change `_ShowcaseState.build` to `return ChartsScene(time: _time);` so it can be eyeballed.

- [ ] **Step 3: Verify analyze**

Run: `cd app && dart analyze examples/tui/widget_showcase.dart` → `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add app/examples/tui/widget_showcase.dart
git commit -m "Add charts showcase scene (custom-paint area chart + flex bars)"
```

---

## Task 4: Layout-lab and Type scenes

**Files:**
- Modify: `app/examples/tui/widget_showcase.dart`

- [ ] **Step 1: Add `LayoutLabScene`**

A `StatelessWidget` taking `double time`. Real widgets only — no `Painted`. Returns a `Column` (`crossAxisAlignment: stretch`) of:

1. A title `Text` `'mainAxisAlignment'` (bold).
2. A `Row` whose `mainAxisAlignment` is chosen by `(time / 1.6).floor() % 6` indexing into `[MainAxisAlignment.start, .center, .end, .spaceBetween, .spaceAround, .spaceEvenly]`. Children: four `SizedBox(width: 8, height: 3, child: DecoratedBox(...))` boxes in four distinct colors. `mainAxisSize` left at default (`max`) so alignment is visible.
3. A `Text` showing the current alignment's name (derive from the enum value, e.g. `align.name`).
4. A spacer (`SizedBox(height: 1)`).
5. A title `Text` `'flex factors'` (bold).
6. A `Row` of two `Expanded` children whose `flex` morphs: `flexA = 1 + ((1 + sin(time)) * 3).round()` (1..7), `flexB = 8 - flexA` (so they always sum to 8). Each `Expanded` wraps a `DecoratedBox` in a distinct color with a centered `Text` showing its current `flex` value.

This scene is entirely the Stage 3/4 layout engine reacting to `setState`.

- [ ] **Step 2: Add `TypeScene`**

A `StatelessWidget` taking `double time`. Returns a `Column` (`crossAxisAlignment: stretch`, `mainAxisAlignment: center`) of:

1. **Gradient wordmark** — a `Row` (`mainAxisAlignment: center`) of one `Text` per character of `'flutterware'`, each character bold with `fg: hsv((i / 11 + time * 0.3) % 1.0, 1.0, 1.0)`.
2. A `SizedBox(height: 1)` spacer.
3. **Wave** — a `Row` (`mainAxisAlignment: center`) of one widget per character of a string (e.g. `'~ widget layer ~'`); each character is `Column(children: [SizedBox(height: waveOffset), Text(char)])` with `waveOffset = (1 + sin(i * 0.5 + time * 3)).round()` (0..2). Give the `Column` a small fixed height (e.g. via the natural size — a `Column` of a `SizedBox` + `Text` sizes to content; that is fine).
4. A `SizedBox(height: 1)` spacer.
5. **Style sampler** — a `Row` (`mainAxisAlignment: spaceEvenly`) of five `Text`s, each demonstrating one `TextStyle`: `Text('bold', style: TextStyle.bold)`, `Text('dim', style: TextStyle.dim)`, `Text('italic', style: TextStyle.italic)`, `Text('underline', style: TextStyle.underline)`, `Text('reverse', style: TextStyle.reverse)`.

- [ ] **Step 3: Show the scenes temporarily**

Temporarily set `_ShowcaseState.build` to alternate `LayoutLabScene` and `TypeScene` like Task 2 did (`(_time ~/ 5) % 2`), so they can be eyeballed.

- [ ] **Step 4: Verify analyze**

Run: `cd app && dart analyze examples/tui/widget_showcase.dart` → `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/examples/tui/widget_showcase.dart
git commit -m "Add layout-lab and typography showcase scenes"
```

---

## Task 5: Chrome and final layout

**Files:**
- Modify: `app/examples/tui/widget_showcase.dart`

- [ ] **Step 1: Add scene metadata**

Add a small top-level list pairing scene index → label, used by both the dispatch and the tabs:

```dart
const _sceneNames = ['Plasma', 'Stars', 'Charts', 'Layout', 'Type'];
```

- [ ] **Step 2: Add `Header`**

A `StatelessWidget` with fields `double time`, `int scene`. Returns a `ConstrainedBox(constraints: BoxConstraints.tightFor(height: 3), child: Column(...))` with three rows:

1. A centered bold `Text` `'flutterware · widget showcase'`, bright white.
2. A `Row` (`mainAxisAlignment: center`) of the five tabs — one `Text` per scene, content `'<n> <name>'` (e.g. `'1 Plasma'`), separated by `SizedBox(width: 2)`. The active scene's tab is `style: TextStyle.bold`, `fg: Color.brightWhite`; the others `fg: Color.brightBlack` (dim).
3. A 1-cell-tall `Painted` gradient bar: for each column, `painter.fillRect(CellRect.fromTLWH(0, col, 1, 1), Cell(rune: 0x20, bg: hsv((col / size.cols + time * 0.3) % 1.0, 0.8, 0.7)))`.

- [ ] **Step 3: Add `Footer`**

A `StatelessWidget` with fields `int fps`, `bool paused`. Returns a `ConstrainedBox(constraints: BoxConstraints.tightFor(height: 1), child: Row(...))`: a left dim `Text` `'←/→ scene · 1-5 jump · space pause · q quit'`, an `Expanded(child: SizedBox())` spacer, and a right `Text` showing `paused ? 'PAUSED' : '$fps fps'` (paused in e.g. `Color.brightYellow`, fps dim).

- [ ] **Step 4: Wire the final layout in `_ShowcaseState`**

Add `int _scene = 0;` and `double _fps = 0;` fields. Replace `build` with the real chrome layout:

```dart
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
```

Add a `bool _paused = false;` field (input wiring is Task 6 — for now it stays false). Update the timer tick to also track FPS: keep a smoothed estimate, e.g. `_fps = _fps * 0.9 + (1000 / 33) * 0.1;` — or compute from real elapsed time with a `Stopwatch`. A simple smoothed constant is acceptable for the demo; if you want real fps, measure wall-clock delta between ticks. Keep `_time += 0.033` only when `!_paused`.

- [ ] **Step 5: Verify analyze**

Run: `cd app && dart analyze examples/tui/widget_showcase.dart` → `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/examples/tui/widget_showcase.dart
git commit -m "Add showcase chrome (header tabs + footer) and final layout"
```

---

## Task 6: Keyboard navigation

**Files:**
- Modify: `app/examples/tui/widget_showcase.dart`

- [ ] **Step 1: Subscribe to keys and handle input**

In `_ShowcaseState`, add a `StreamSubscription<KeyEvent>? _keySub;` field and a `bool _subscribed = false;`. Override `didChangeDependencies`:

```dart
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
```

Update `dispose` to cancel the subscription as well as the timer:

```dart
@override
void dispose() {
  _timer?.cancel();
  unawaited(_keySub?.cancel());
}
```

(`_keySub?.cancel()` returns `Future<void>?`; wrap in `unawaited` to satisfy the `unawaited_futures` lint. Import of `unawaited` comes from `dart:async`, already imported.)

- [ ] **Step 2: Verify analyze**

Run: `cd app && dart analyze examples/tui/widget_showcase.dart` → `No issues found!`

- [ ] **Step 3: Sanity-run**

Run: `cd app && dart run examples/tui/widget_showcase.dart` → expect the only error is the startup `StdinException` (no TTY). Confirms it still compiles and reaches `runApp`.

- [ ] **Step 4: Commit**

```bash
git add app/examples/tui/widget_showcase.dart
git commit -m "Add keyboard navigation to the showcase demo"
```

---

## Task 7: README + final verification

**Files:**
- Modify: `app/lib/src/tui/README.md`

- [ ] **Step 1: Update the README**

In `app/lib/src/tui/README.md`, find the line mentioning examples (currently `Examples live in app/examples/tui/.` or similar, near the file table). Add a sentence pointing at the new demo, e.g.: append to that area — `The richest is widget_showcase.dart, an animated five-scene showcase reel (plasma, starfield, charts, layout lab, typography).` Keep it to one or two sentences; match the surrounding prose style. Do not restructure the README.

- [ ] **Step 2: Full verification**

Run, expecting the stated results:
- `cd app && dart analyze examples/tui/widget_showcase.dart` → `No issues found!`
- `cd app && flutter analyze` → `No issues found!`
- `cd app && flutter test` → all 329 tests pass.
- `dart tool/prepare_submit.dart` (from repo root) → no diff. If it reformats `widget_showcase.dart`, that means the file was not formatted — stage the reformatted version (the committed state must be `prepare_submit`-clean).

- [ ] **Step 3: Commit**

```bash
git add app/lib/src/tui/README.md app/examples/tui/widget_showcase.dart
git commit -m "Mention the widget showcase demo in the TUI README"
```

(If `prepare_submit.dart` did not touch `widget_showcase.dart`, just `git add app/lib/src/tui/README.md`.)

- [ ] **Step 4: Note manual smoke for the user**

Manual smoke cannot be run here (no TTY). Report to the controller that the user should run `cd app && dart run examples/tui/widget_showcase.dart` in a real terminal and verify: all five scenes render and animate; `←`/`→` and `1`–`5` switch scenes and the active tab updates; space pauses (footer shows `PAUSED`); resize re-lays out; `q` exits cleanly.

---

## Self-Review notes

- **Spec coverage:** `Painted` widget + helpers (T1); animation loop (T1); Plasma + Starfield (T2); Charts — custom-paint area chart + real-widget bars (T3); Layout lab + Type (T4); chrome header/footer + final `Column` layout (T5); keyboard navigation, pause, quit (T6); README + verification (T7). All five scenes, chrome, controls, and the success criteria are mapped.
- **No-test rationale:** stated in the header — examples are not unit-tested in this repo; `dart analyze` is the per-task gate, `flutter test` a regression guard, manual smoke the final acceptance gate (user-run).
- **Type consistency:** scene widgets are all `StatelessWidget`s with a `double time` field and a `const` constructor `({required this.time, super.key})`; `_ShowcaseState` fields are `_timer`, `_time`, `_scene`, `_paused`, `_fps`, `_keySub`, `_subscribed`; `Header(time, scene)`, `Footer(fps, paused)`; `_sceneNames` has 5 entries matching the 5-way `switch`.
- **Open risk:** `Color`'s public RGB-channel accessors (`.r`/`.g`/`.b`) are assumed by `hsv`/`lerpColor`. Task 1 Step 3 explicitly tells the implementer to check `cell.dart` and adjust if the accessors differ — this is the one place the demo reaches into a Stage 1 type.

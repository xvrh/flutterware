# TUI widget-layer showcase demo

**Status:** Draft
**Date:** 2026-05-15
**Scope:** A flashy, animated demo for the Stage 4 widget layer — a full-screen
TUI "showcase reel" that cycles through five animated scenes, each showing off
a different capability of the widget layer and the engine beneath it.

**Relates to:** [`2026-05-15-tui-stage4-widget-layer-design.md`](./2026-05-15-tui-stage4-widget-layer-design.md)

---

## Context

Stage 4 delivered the reactive widget layer (`Widget`/`Element`/`State`,
`setState`, `InheritedWidget`, `RenderObjectWidget`, `runApp`). The existing
`app/examples/tui/widget_demo.dart` is a minimal correctness demo — it rebuilds
the Stage 3 render-tree screen as `StatefulWidget`s. It proves the layer works
but is not exciting.

This demo is the opposite goal: **make the framework look good.** It is a
single self-contained example that animates, uses 24-bit color, and is
navigable — the kind of thing you run to feel that the framework is real. It
also serves as a worked example of two things the minimal demo does not cover:
driving animation from a `Timer`, and dropping down to a **custom
`RenderObject`** for free-form painting.

Nothing in the framework (`lib/`) changes. This is pure example code under
`app/examples/tui/`.

## Goals

1. A new example `app/examples/tui/widget_showcase.dart`, runnable with
   `cd app && dart run examples/tui/widget_showcase.dart`.
2. A 30 fps animation loop driven by `Timer.periodic` + `setState`.
3. A custom `Painted` widget (a `LeafRenderObjectWidget` + `RenderBox`) that
   exposes a paint callback — demonstrating the framework is extensible down to
   the render layer, and unlocking free-form per-cell effects.
4. Five animated scenes: **Plasma**, **Starfield**, **Charts**, **Layout lab**,
   **Type**.
5. Persistent chrome (header with scene tabs, footer with key hints + live FPS)
   and keyboard navigation between scenes.
6. Clean exit, resize handling, and `dart analyze` cleanliness.

## Non-goals

- **No framework changes.** Everything lives in the one example file. The
  `Painted` widget is defined *in the example*, subclassing the public
  `LeafRenderObjectWidget`/`RenderBox` — that is the point (it shows a consumer
  can do this), not a new library widget.
- **No new tests.** Consistent with every other `examples/tui/` demo: examples
  are not unit-tested. The widget layer itself already has 329 tests. The gate
  here is `dart analyze` + manual smoke.
- **No scene transitions/wipes**, no mouse, no sound. Scene switches are
  instant.
- **No second file.** One readable, top-to-bottom example file.
- `widget_demo.dart` is kept as-is — this is an additional demo.

## Architecture

One file, `app/examples/tui/widget_showcase.dart`, in these sections:

```
1. The Painted widget   — Painted (LeafRenderObjectWidget) + RenderPainted
2. Paint helpers        — half-block plotter, hsv→Color, eighth-blocks
3. The five scenes      — PlasmaScene, StarfieldScene, ChartsScene,
                          LayoutLabScene, TypeScene  (all StatelessWidget)
4. Chrome               — Header, Footer
5. ShowcaseApp          — the StatefulWidget controller (timer + input)
6. main()               — runApp(const ShowcaseApp())
```

### The animation model

`ShowcaseApp` is a `StatefulWidget`; its `State`:

- **`initState`** — starts `Timer.periodic(Duration(milliseconds: 33), ...)`.
  Each tick: if not paused, `_time += 0.033`; recompute a smoothed `_fps`;
  `setState(() {})`. A fixed per-tick delta (not wall-clock) keeps animation
  math simple and makes pause trivial.
- **`didChangeDependencies`** — subscribes once (guarded by a `bool`) to
  `TerminalApp.of(context).keys`. Inherited-widget lookup is only safe here,
  not in `initState`.
- **`dispose`** — cancels the timer and the key subscription.
- **State fields:** `double _time`, `int _scene` (0–4), `bool _paused`,
  `double _fps`.
- **Input handling:** `SpecialKey` left/right → previous/next scene (wrapping);
  `CharKey` `'1'`–`'5'` → jump to scene; `' '` (space) → toggle `_paused`;
  `'q'` → `TerminalApp.of(context).exit()`.
- **`build`** — a `Column` (crossAxisAlignment `stretch`) of: `Header`
  (fixed height 3), `Expanded(flex: 1, child: <active scene>)`, `Footer`
  (fixed height 1). The active scene is chosen by `_scene` and constructed with
  `time: _time` so it rebuilds every tick.

Each tick rebuilds the whole tree and repaints; the engine's `encodeDiff`
emits ANSI only for changed cells, so this is cheap enough at 30 fps for a
local terminal.

### The `Painted` widget

```dart
typedef PaintCallback = void Function(Painter painter, CellSize size);

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
```

Each tick the scene rebuilds, producing a fresh `Painted` with a new closure
capturing the new `time`; `updateRenderObject` swaps it and `markNeedsPaint`s.
The `Painter` handed to `paint` is already translated to the box origin, so
the callback paints in local `(0,0)`-based coordinates.

### Paint helpers

- **`plotHalf(Painter p, int col, int row2, Color c)`** — the half-block
  trick: the terminal cell is twice as tall as wide, so each cell renders
  *two* vertically-stacked "pixels" via `▀` (U+2580) with `fg` = top pixel,
  `bg` = bottom pixel. `plotHalf` takes a pixel coordinate at 2× vertical
  resolution, computes the cell `(row2 ~/ 2, col)`, reads/sets the right
  half. Because `Painter` has no read-back, the plotter is fed by scenes that
  paint top+bottom together — concretely, scenes iterate cell rows and for each
  cell compute both pixel colors, then `p.fillRect(CellRect.fromTLWH(cellRow,
  col, 1, 1), Cell(rune: 0x2580, fg: topColor, bg: bottomColor))`. (`plotHalf`
  is therefore a *cell* helper `paintHalfCell(p, cellRow, col, top, bottom)`;
  name it for what it does.)
- **`hsv(double h, double s, double v) -> Color`** — HSV→RGB returning
  `Color.rgb(r, g, b)` with 0–255 channels. Used by plasma and the gradient
  chrome.
- **`eighthBlock(double frac) -> int`** — maps `0.0–1.0` to one of
  ` ▁▂▃▄▅▆▇█` (U+2581…U+2588, plus space) for sub-cell-precise bar tops in the
  charts scene.

## The scenes

Every scene is a `StatelessWidget` with a `const` constructor taking
`double time`. Scenes that need free-form painting return a `Painted`; scenes
that demo layout return real widgets.

### 1. `PlasmaScene` — `Painted`

Classic sine plasma. For each cell, for each of its two half-block pixels at
`(px, py)`:
`v = sin(px/8 + time) + sin(py/6 + time*1.3) + sin((px+py)/10 + time*0.7)`,
normalized to `0..1`, fed through `hsv(v, 1, 1)`. Paints every cell with
`▀` + top/bottom colors. Full-screen, full-color, continuously morphing.

### 2. `StarfieldScene` — `Painted`

A 3D parallax starfield. A fixed list of stars, each `(x, y, z)` with `x,y` in
`-1..1` and `z` a depth; `z` decreases with `time` (modulo wrap). Project to
screen: `sx = cx + x/z * scale`, `sy = cy + y/z * scale`; brightness ∝ `1/z`.
Stars are drawn as half-block pixels (white→grey by depth). The star list is a
`static final` built once; only `time` drives motion (state-free scene).

### 3. `ChartsScene` — `Row` of two panels

Demonstrates custom paint and the real flex layout engine side by side.

- **Left panel** — a scrolling area chart in a `Painted`: a signal
  `f(x) = 0.5 + 0.3*sin(x*0.3 + time*2) + 0.15*sin(x*0.7 - time)` sampled per
  column; fill the column from the bottom up, the top cell using
  `eighthBlock` for a sub-cell-smooth crest; gradient fg by height.
- **Right panel** — an animated bar chart built from **real widgets**: a
  `Row` of `Expanded` children, each a `Column(children: [Expanded(flex:
  topGap), DecoratedBox(...) sized to barHeight])` — the bar height animates
  per bar via `sin(time + i)`, and the flex spacer pushes it to the bottom.
  No `Painted` here: this is the Stage 3/4 layout engine doing the work.

Each panel is wrapped in a bordered `DecoratedBox` + `Padding` with a title
`Text`.

### 4. `LayoutLabScene` — real widgets only

A live view of the layout engine. Four colored `DecoratedBox` boxes (fixed
small sizes) inside a `Row`. Every ~1.6 s (`(time/1.6).floor() % 6`) the
`Row`'s `mainAxisAlignment` cycles through all six values
(`start, center, end, spaceBetween, spaceAround, spaceEvenly`); a `Text` label
shows the current value's name. Below it, a second `Row` where two boxes'
`Expanded` flex factors morph (`flex` derived from `sin(time)` mapped to small
integers) so the boxes visibly grow and shrink. This scene contains *no*
custom painting — it is entirely the real widget/layout machinery reacting to
`setState`.

### 5. `TypeScene` — `Text` widgets

- **Gradient wordmark** — the string `flutterware` rendered as a `Row` of
  one bold `Text` per character, each character's `fg` set from
  `hsv((charIndex/11 + time*0.3) % 1, 1, 1)` so a rainbow sweeps across it.
- **Wave** — a second string where each character is a
  `Column(children: [SizedBox(height: waveOffset), Text(char)])` and
  `waveOffset = (1 + sin(charIndex*0.5 + time*3)).round()` (0–2) so the
  characters bob in a travelling wave.
- **Style sampler** — a `Row` of `Text`s, one per `TextStyle`
  (bold, dim, italic, underline, reverse — whichever the engine's `TextStyle`
  bitfield provides), each labelled.

All three stacked in a `Column`.

## Chrome

- **`Header`** (fixed height 3, via `ConstrainedBox` tight height) — a
  `Column`: row 1 a centered bold title `Text` `flutterware · widget
  showcase`; row 2 the scene tabs — a `Row` of `Text`s `1 Plasma`,
  `2 Stars`, `3 Charts`, `4 Layout`, `5 Type`, the active one bold and bright,
  the rest dim; row 3 a 1-cell-tall `Painted` gradient bar that animates
  (an `hsv` sweep scrolling with `time`).
- **`Footer`** (fixed height 1) — a `Row`: left a dim `Text`
  `←/→ scene · 1-5 jump · space pause · q quit`; right a `Text` showing
  `<fps> fps` (and `PAUSED` when paused). `Expanded` between them.

Header and Footer take whatever they need (`time`, active scene index,
`_fps`, `_paused`) as constructor params.

## Controls

| Key | Action |
|-----|--------|
| `←` / `→` (`SpecialKey`) | previous / next scene (wraps) |
| `1`–`5` (`CharKey`) | jump to scene |
| space | toggle pause |
| `q` | quit (`TerminalApp.of(context).exit()`) |

Unrecognized keys are ignored.

## Files touched

- **Create** `app/examples/tui/widget_showcase.dart`.
- **Modify** `app/lib/src/tui/README.md` — add `widget_showcase.dart` to the
  examples mention (one line).

## Testing strategy

No automated tests — consistent with all other `examples/tui/` demos and with
the Stage 4 plan's treatment of `widget_demo.dart`. Verification:

1. `cd app && dart analyze examples/tui/widget_showcase.dart` → no errors or
   warnings.
2. `cd app && flutter test` → all 329 existing tests still pass (the example
   touches no library code, so this is a guard against accidental edits).
3. `dart tool/prepare_submit.dart` → no diff.
4. **Manual smoke** in a real terminal (`dart run examples/tui/widget_showcase.dart`):
   - All five scenes render and animate smoothly.
   - `←`/`→` and `1`–`5` switch scenes; the active tab updates.
   - Space pauses/resumes; the footer shows `PAUSED`.
   - Resizing the terminal re-lays out every scene without artifacts.
   - `q` exits cleanly; the terminal is restored.

## Success criteria

1. `widget_showcase.dart` exists, `dart analyze` is clean, the 329 tests pass,
   `prepare_submit.dart` is a no-op.
2. The demo runs at a smooth ~30 fps in a real terminal and all five scenes,
   the chrome, navigation, pause, resize, and quit behave as described.
3. The `Painted` widget is a faithful, minimal custom `RenderObject`
   integration — no framework code changed.

## Open questions deferred

- **A real `Ticker`/`SchedulerBinding`.** The demo uses a bare `Timer`; proper
  frame scheduling with tickers is a deferred framework stage. The demo is the
  motivating use case but does not pull it forward.
- **A library `CustomPaint`/`Painted` widget.** If more than one consumer
  wants free-form painting, promote the demo's `Painted` into `basic.dart`.
  Not now — one use site.
- **Wide-character width.** Half-block and box-drawing glyphs are all
  single-width; no emoji is used, so the Stage 1 single-width assumption holds.

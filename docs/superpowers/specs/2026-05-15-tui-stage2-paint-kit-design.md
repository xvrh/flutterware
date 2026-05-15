# TUI Stage 2 — Paint kit

**Status:** Draft
**Date:** 2026-05-15
**Scope:** Add the stage 2 "paint kit" to the TUI engine — `CellOffset` /
`CellSize` / `CellRect` geometry, a functional `Painter` that paints into a
shared `CellBuffer` through an offset and clip, and procedural paint helpers
(fill, lines, border, wrapped text).

**Extends:** [`2026-05-14-tui-step1-engine-design.md`](./2026-05-14-tui-step1-engine-design.md)

---

## Context

Stage 1 delivered the engine: `Terminal` lifecycle, the `CellBuffer` grid,
diff-to-ANSI, key parsing. The only way to put content on screen today is
`CellBuffer.writeAt` / `set` / `fillRect` — bare `(row, col)` writes against
absolute buffer coordinates.

Stage 3 (the render tree) needs more. Flutter's `RenderObject.paint` receives a
*shared* canvas and an *offset*; a parent positions a child by handing it the
same canvas translated by the child's offset, and clips subtrees as it
descends. If stage 2 ships only absolute-coordinate helpers, every stage 3
render object has to add offsets by hand and clipping has to be bolted on
later — un-Flutter-like and error-prone.

So stage 2 introduces the surface stage 3 will consume unchanged: a `Painter`
carrying an offset and a clip, plus the geometry types the layout protocol will
also use. `CellBuffer` stays a pure data grid.

## Goals

1. Geometry value types: `CellOffset`, `CellSize`, `CellRect`.
2. A `Painter` that wraps a `CellBuffer` with a translation offset and a clip
   rectangle, composable via `translate` and `clip`.
3. Procedural paint helpers on `Painter`: `fill`, `fillRect`, `drawHLine`,
   `drawVLine`, `drawBorder`, `drawText`.
4. A `BorderChars` value class with named box-drawing presets.
5. A pure `wrapText` function (word-wrap with hard-break fallback).
6. A demo (`paint_kit_demo.dart`) exercising borders, wrapped text, and a
   nested translate+clip panel.

## Non-goals (for this round)

- **No render objects, layout, or widgets.** Those are stages 3–4. The
  `Painter` is consumed by stage 3 but no render machinery is built here.
- **No mutable transform/clip stack.** The `Painter` is functional: `translate`
  and `clip` return new `Painter` instances. A cell grid supports only integer
  translation and rectangular clipping — there is no rotation/scale, so a
  save/restore stack would buy nothing and only adds balancing bugs.
- **No wide-character / emoji width handling.** Every cell is one column,
  consistent with stage 1. `wrapText` measures width in runes.
- **No styled-span text.** `drawText` paints one `(fg, bg, style)` for the
  whole string. Rich text waits for the stage 4 `Text` widget.
- **No changes to `CellBuffer` or `Cell`.** The paint kit sits entirely on top.

## Architecture

```
CellBuffer  (stage 1, unchanged — dumb row-major grid, clips out-of-bounds)
    ▲
    │  wrapped by
    │
Painter     (stage 2 — origin offset + clip rect; all writes go through _put)
    ├── fill / fillRect
    ├── drawHLine / drawVLine
    ├── drawBorder   (uses BorderChars)
    └── drawText     (uses wrapText + Horizontal/VerticalAlign)
```

A `Painter` holds three things:

- the target `CellBuffer` (shared — never copied),
- `_origin` — a `CellOffset` added to every local coordinate, in buffer space,
- `_clip` — a `CellRect` in buffer space; writes outside it are dropped.

`translate(offset)` returns a new `Painter` with `_origin + offset`, same
buffer and clip. `clip(rect)` returns a new `Painter` with `_clip` intersected
with `rect` (the argument is in local coordinates and is shifted by `_origin`
before intersecting). Both share the underlying buffer, so all painting lands
on the same grid — the "shared canvas" model.

Every helper ultimately calls one private chokepoint:

```dart
void _put(int localRow, int localCol, Cell cell) {
  final r = localRow + _origin.row;
  final c = localCol + _origin.col;
  if (!_clip.contains(CellOffset(r, c))) return;
  _buffer.set(r, c, cell);
}
```

Because clipping happens here, no helper can paint outside its clip, and a
child `Painter` handed down in stage 3 physically cannot draw over a sibling.

## Geometry types — `geometry.dart`

All coordinates are `int` (cells, not logical pixels).

```dart
/// A position on the cell grid. row grows downward, col grows rightward.
class CellOffset {
  final int row;
  final int col;
  const CellOffset(this.row, this.col);

  static const CellOffset zero = CellOffset(0, 0);

  CellOffset operator +(CellOffset other) => ...;
  CellOffset operator -(CellOffset other) => ...;
  // structural == / hashCode / toString
}

/// A size on the cell grid. Non-negative by convention; not enforced.
class CellSize {
  final int rows;
  final int cols;
  const CellSize(this.rows, this.cols);

  static const CellSize zero = CellSize(0, 0);

  bool get isEmpty => rows <= 0 || cols <= 0;
  // structural == / hashCode / toString
}

/// A rectangle on the cell grid. Half-open: a rect at (top,left) of size
/// (h,w) covers rows [top, top+h) and cols [left, left+w).
class CellRect {
  final int top;
  final int left;
  final int width;
  final int height;

  /// row-first to match the (row, col) convention used everywhere else.
  const CellRect.fromTLWH(this.top, this.left, this.width, this.height);
  CellRect.fromOffsetSize(CellOffset offset, CellSize size) : ...;

  int get bottom => top + height;   // exclusive
  int get right => left + width;    // exclusive
  CellOffset get offset => CellOffset(top, left);
  CellSize get size => CellSize(height, width);
  bool get isEmpty => height <= 0 || width <= 0;

  bool contains(CellOffset p) =>
      p.row >= top && p.row < bottom && p.col >= left && p.col < right;

  /// Intersection of two rects. Returns an empty rect if they do not overlap.
  CellRect intersect(CellRect other) => ...;

  /// This rect translated by [delta].
  CellRect shift(CellOffset delta) => ...;

  /// This rect inset by [amount] cells on every side. A rect too small to
  /// inset becomes empty (clamped, never negative-sized).
  CellRect deflate(int amount) => ...;

  // structural == / hashCode / toString
}
```

`contains` uses the half-open convention so an empty rect contains nothing and
`intersect` composes cleanly. `deflate(1)` on a bordered box yields the
content area inside the border.

## `Painter` — `painter.dart`

```dart
class Painter {
  final CellBuffer _buffer;
  final CellOffset _origin;
  final CellRect _clip;

  /// A painter over the whole [buffer]: identity offset, clip = full buffer.
  Painter(CellBuffer buffer)
      : _buffer = buffer,
        _origin = CellOffset.zero,
        _clip = CellRect.fromTLWH(0, 0, buffer.cols, buffer.rows);

  Painter._(this._buffer, this._origin, this._clip);

  /// The visible region in *local* coordinates (the clip, un-shifted by the
  /// origin). Helpers that "fill everything" target this.
  CellRect get bounds =>
      _clip.shift(CellOffset(-_origin.row, -_origin.col));

  /// A painter whose local origin is shifted by [offset].
  Painter translate(CellOffset offset) =>
      Painter._(_buffer, _origin + offset, _clip);

  /// A painter clipped to [rect] (given in local coordinates), intersected
  /// with the current clip.
  Painter clip(CellRect rect) =>
      Painter._(_buffer, _origin, _clip.intersect(rect.shift(_origin)));

  void _put(int row, int col, Cell cell) { ... } // chokepoint, see Architecture

  // --- helpers ---
  void fill(Cell cell);
  void fillRect(CellRect rect, Cell cell);
  void drawHLine(CellOffset start, int length,
      {int rune = 0x2500, Color fg, Color bg, int style});
  void drawVLine(CellOffset start, int length,
      {int rune = 0x2502, Color fg, Color bg, int style});
  void drawBorder(CellRect rect,
      {BorderChars chars, Color fg, Color bg, int style});
  void drawText(CellRect rect, String text,
      {Color fg, Color bg, int style,
       HorizontalAlign hAlign = HorizontalAlign.left,
       VerticalAlign vAlign = VerticalAlign.top,
       bool wrap = true});
}
```

### Helper semantics

- **`fill(cell)`** — fills `bounds` with `cell`. **`fillRect(rect, cell)`** —
  fills `rect` (local coords). Both clip naturally via `_put`.
- **`drawHLine` / `drawVLine`** — draw a run of `length` cells from `start`.
  `length <= 0` draws nothing. Default runes are `─` / `│`.
- **`drawBorder(rect, ...)`** — draws the four corners and edges of `rect`'s
  perimeter using `chars`. A rect with `width < 2` or `height < 2` degrades
  gracefully: a 1-wide rect draws a vertical line, a 1-tall rect a horizontal
  line, a smaller rect draws what cells it can. The interior is left untouched
  (callers `fillRect(rect.deflate(1), ...)` if they want a filled box).
- **`drawText(rect, text, ...)`** — lays text out inside `rect`:
  1. If `wrap`, run `wrapText(text, rect.width)`; else split only on `\n` and
     leave long lines to be clipped horizontally.
  2. Drop or keep lines per `vAlign`: the block of `min(lines.length,
     rect.height)` rows is positioned top / center / bottom within `rect`.
     Lines that overflow `rect.height` are dropped (bottom-most when
     top-aligned, etc.).
  3. Each line is positioned horizontally within `rect.width` per `hAlign`.
  4. Cells are written via `_put`, so anything past the clip is dropped.

## `BorderChars` — in `painter.dart`

```dart
/// The six glyphs that make up a box border.
class BorderChars {
  final String topLeft, topRight, bottomLeft, bottomRight;
  final String horizontal; // top and bottom edges
  final String vertical;   // left and right edges

  const BorderChars({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.horizontal,
    required this.vertical,
  });

  const BorderChars.single()   // ┌─┐ │ └─┘
  const BorderChars.double()   // ╔═╗ ║ ╚═╝
  const BorderChars.rounded()  // ╭─╮ │ ╰─╯
  const BorderChars.thick()    // ┏━┓ ┃ ┗━┛
  const BorderChars.ascii()    // +-+ | +-+
}
```

`drawBorder` defaults to `BorderChars.single()`. Each glyph is a one-rune
string; `drawBorder` writes `glyph.runes.first`.

## Alignment enums — in `painter.dart`

```dart
enum HorizontalAlign { left, center, right }
enum VerticalAlign { top, center, bottom }
```

Center rounds toward the top-left when padding is odd (floor division), so a
1-cell-too-wide gap puts the extra cell on the right / bottom.

## `wrapText` — `text_wrap.dart`

```dart
/// Wrap [text] to lines no wider than [width] runes.
///
/// Splits on existing '\n' first, then word-wraps each segment on spaces.
/// A single word longer than [width] is hard-broken at the width boundary.
/// [width] <= 0 returns the segments split only on '\n'.
List<String> wrapText(String text, int width);
```

Pure, no I/O, no dependency on the rest of the kit — the primary unit-test
target. Width is measured in runes (`String.runes.length`), consistent with
the one-column-per-cell model.

## Files touched

- **Create** `app/lib/src/tui/geometry.dart` — `CellOffset`, `CellSize`,
  `CellRect`.
- **Create** `app/lib/src/tui/painter.dart` — `Painter`, `BorderChars`,
  `HorizontalAlign`, `VerticalAlign`.
- **Create** `app/lib/src/tui/text_wrap.dart` — `wrapText`.
- **Create** `app/examples/tui/paint_kit_demo.dart` — the demo.
- **Modify** `app/lib/src/tui/tui.dart` — export the new public types.
- **Create** `app/test/tui/geometry_test.dart` — rect intersect / shift /
  deflate / contains, offset arithmetic.
- **Create** `app/test/tui/painter_test.dart` — paints into a `CellBuffer` and
  asserts cell contents: translate/clip composition, clip drops out-of-range
  writes, border degenerate cases, text alignment.
- **Create** `app/test/tui/text_wrap_test.dart` — word wrap, hard-break,
  newline handling, edge widths.
- **Modify** `docs/superpowers/tui-roadmap.md` — mark stage 2 done, link this
  spec.

## Testing strategy

`Painter` is fully testable without a tty: construct a `CellBuffer`, wrap it in
a `Painter`, paint, and read cells back with `CellBuffer.get`. No `Terminal`,
no ANSI, no golden files needed. `wrapText` and the geometry types are pure.
The only thing requiring a real terminal is the demo, covered by manual smoke.

Key cases:

- `CellRect.intersect` — overlap, no overlap (empty result), containment.
- `CellRect.deflate` — normal inset, inset past collapse → empty.
- `Painter.translate` then paint — content lands at the offset.
- `Painter.clip` then paint outside the clip — writes dropped.
- `translate` and `clip` composed — a clip set before a translate still
  applies in the right buffer location.
- `drawBorder` on a 1×N and N×1 rect — degrades to a line, no crash.
- `drawText` — left/center/right and top/center/bottom positioning; wrapped
  vs. unwrapped; overflow lines dropped.
- `wrapText` — plain wrap, word longer than width, embedded `\n`, width 0.

## Success criteria

1. All existing tests still pass; `flutter analyze` is clean.
2. `geometry_test.dart`, `painter_test.dart`, `text_wrap_test.dart` pass.
3. `dart tool/prepare_submit.dart` produces no diff.
4. `paint_kit_demo.dart` runs in a real terminal:
   - Bordered, titled panels render with correct corners and edges.
   - A wrapped paragraph fills its panel and respects alignment.
   - A nested `translate`+`clip` panel visibly clips content that overflows
     its rect — overflow does not bleed onto neighboring panels.
   - Pressing `q` exits cleanly; the terminal is restored.

## Open questions deferred

- Styled-span / rich text in `drawText` — arrives with the stage 4 `Text`
  widget.
- Wide-character width in `wrapText` and the cell model — deferred with the
  stage 1 limitation.
- A `drawText` that reports how many rows it consumed (useful for flow layout)
  — add if stage 3 needs it.
- Diagonal / arbitrary line drawing — not needed by a box-layout TUI; skipped.

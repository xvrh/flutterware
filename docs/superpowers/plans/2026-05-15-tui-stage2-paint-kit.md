# TUI Stage 2 — Paint Kit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the stage 2 paint kit to the TUI engine — `CellOffset`/`CellSize`/`CellRect` geometry, a functional `Painter` that paints into a shared `CellBuffer` through an offset and clip, and procedural paint helpers (fill, lines, border, wrapped text).

**Architecture:** `CellBuffer` (stage 1) stays an untouched dumb grid. A new `Painter` wraps it with a translation offset and a clip rect; `translate` and `clip` return new `Painter` instances sharing the same buffer (functional, no save/restore stack). Every helper routes through one private `_put` chokepoint that translates local coords by the offset and drops anything outside the clip. A pure `wrapText` function does word-wrapping for `drawText`.

**Tech Stack:** Pure Dart (`dart:core` only — no `dart:io`), `package:test` run via `flutter test`. No new dependencies.

**Spec:** [docs/superpowers/specs/2026-05-15-tui-stage2-paint-kit-design.md](../specs/2026-05-15-tui-stage2-paint-kit-design.md)

---

## File Structure

- `app/lib/src/tui/geometry.dart` — **create**: `CellOffset`, `CellSize`, `CellRect` value types.
- `app/lib/src/tui/text_wrap.dart` — **create**: pure `wrapText` function.
- `app/lib/src/tui/painter.dart` — **create**: `Painter`, `BorderChars`, `HorizontalAlign`, `VerticalAlign`.
- `app/lib/src/tui/tui.dart` — **modify**: export the new public types.
- `app/examples/tui/paint_kit_demo.dart` — **create**: full-screen demo.
- `app/test/tui/geometry_test.dart` — **create**: geometry unit tests.
- `app/test/tui/text_wrap_test.dart` — **create**: `wrapText` unit tests.
- `app/test/tui/painter_test.dart` — **create**: `Painter` unit tests.
- `docs/superpowers/tui-roadmap.md` — **modify**: mark stage 2 done.

### Conventions to follow

- Tests use `package:test` and import via `package:flutterware_app/src/tui/<file>.dart` (see `app/test/tui/buffer_test.dart`).
- Run tests with `cd app && flutter test test/tui/<file>.dart`.
- Lint (`analysis_options.yaml`): `prefer_single_quotes` on, `omit_local_variable_types` (use `var`/`final`, never `final int`), `avoid_final_parameters` (no `final` on parameters). `prefer_const_constructors` is **off** — only add `const` where required (e.g. default parameter values).
- Before running any test, ensure deps are resolved: `cd app && flutter pub get` (the pre-commit hook also warns if this is missing).

### Testability note

`Painter`, `wrapText`, and the geometry types are pure — no tty, no `Terminal`, no ANSI. They are fully unit-tested by painting into a `CellBuffer` and reading cells back. Only the demo (Task 7) needs a real terminal; it is covered by manual smoke.

---

## Task 1: Geometry value types

`CellOffset`, `CellSize`, `CellRect` — the integer-cell geometry used by the `Painter` and (later) the stage 3 layout protocol. `CellRect` is half-open: a rect at `(top,left)` size `(width,height)` covers rows `[top, top+height)` and cols `[left, left+width)`.

**Files:**
- Create: `app/lib/src/tui/geometry.dart`
- Test: `app/test/tui/geometry_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `app/test/tui/geometry_test.dart`:

```dart
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:test/test.dart';

void main() {
  group('CellOffset', () {
    test('addition and subtraction', () {
      expect(CellOffset(1, 2) + CellOffset(3, 4), CellOffset(4, 6));
      expect(CellOffset(5, 5) - CellOffset(1, 2), CellOffset(4, 3));
    });

    test('zero constant', () {
      expect(CellOffset.zero, CellOffset(0, 0));
    });

    test('structural equality', () {
      expect(CellOffset(2, 3), CellOffset(2, 3));
      expect(CellOffset(2, 3) == CellOffset(3, 2), isFalse);
    });
  });

  group('CellSize', () {
    test('isEmpty when a dimension is non-positive', () {
      expect(CellSize(0, 5).isEmpty, isTrue);
      expect(CellSize(5, 0).isEmpty, isTrue);
      expect(CellSize(-1, 5).isEmpty, isTrue);
      expect(CellSize(3, 4).isEmpty, isFalse);
    });
  });

  group('CellRect', () {
    test('derived edges and accessors', () {
      var r = CellRect.fromTLWH(2, 3, 10, 5); // top,left,width,height
      expect(r.top, 2);
      expect(r.left, 3);
      expect(r.width, 10);
      expect(r.height, 5);
      expect(r.bottom, 7);
      expect(r.right, 13);
      expect(r.offset, CellOffset(2, 3));
      expect(r.size, CellSize(5, 10));
    });

    test('fromOffsetSize', () {
      var r = CellRect.fromOffsetSize(CellOffset(2, 3), CellSize(5, 10));
      expect(r, CellRect.fromTLWH(2, 3, 10, 5));
    });

    test('contains uses the half-open convention', () {
      var r = CellRect.fromTLWH(0, 0, 3, 3); // covers rows/cols 0..2
      expect(r.contains(CellOffset(0, 0)), isTrue);
      expect(r.contains(CellOffset(2, 2)), isTrue);
      expect(r.contains(CellOffset(3, 0)), isFalse);
      expect(r.contains(CellOffset(0, 3)), isFalse);
      expect(r.contains(CellOffset(-1, 0)), isFalse);
    });

    test('isEmpty', () {
      expect(CellRect.fromTLWH(0, 0, 0, 5).isEmpty, isTrue);
      expect(CellRect.fromTLWH(0, 0, 5, 0).isEmpty, isTrue);
      expect(CellRect.fromTLWH(0, 0, 5, 5).isEmpty, isFalse);
    });

    test('intersect of overlapping rects', () {
      var a = CellRect.fromTLWH(0, 0, 10, 10);
      var b = CellRect.fromTLWH(5, 5, 10, 10);
      expect(a.intersect(b), CellRect.fromTLWH(5, 5, 5, 5));
    });

    test('intersect of disjoint rects is empty', () {
      var a = CellRect.fromTLWH(0, 0, 2, 2);
      var b = CellRect.fromTLWH(10, 10, 2, 2);
      expect(a.intersect(b).isEmpty, isTrue);
    });

    test('shift translates the rect', () {
      var r = CellRect.fromTLWH(1, 1, 4, 4);
      expect(r.shift(CellOffset(2, 3)), CellRect.fromTLWH(3, 4, 4, 4));
    });

    test('deflate insets every side', () {
      var r = CellRect.fromTLWH(0, 0, 10, 8);
      expect(r.deflate(1), CellRect.fromTLWH(1, 1, 8, 6));
    });

    test('deflate past collapse yields an empty rect', () {
      var r = CellRect.fromTLWH(0, 0, 3, 3);
      expect(r.deflate(5).isEmpty, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/tui/geometry_test.dart`
Expected: FAIL — compile error, `geometry.dart` does not exist.

- [ ] **Step 3: Create the implementation**

Create `app/lib/src/tui/geometry.dart`:

```dart
/// Integer-cell geometry for the TUI paint kit.
library;

/// A position on the cell grid. [row] grows downward, [col] grows rightward.
class CellOffset {
  final int row;
  final int col;

  const CellOffset(this.row, this.col);

  static const CellOffset zero = CellOffset(0, 0);

  CellOffset operator +(CellOffset other) =>
      CellOffset(row + other.row, col + other.col);

  CellOffset operator -(CellOffset other) =>
      CellOffset(row - other.row, col - other.col);

  @override
  bool operator ==(Object other) =>
      other is CellOffset && row == other.row && col == other.col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'CellOffset($row, $col)';
}

/// A size on the cell grid. Non-negative by convention; not enforced.
class CellSize {
  final int rows;
  final int cols;

  const CellSize(this.rows, this.cols);

  static const CellSize zero = CellSize(0, 0);

  bool get isEmpty => rows <= 0 || cols <= 0;

  @override
  bool operator ==(Object other) =>
      other is CellSize && rows == other.rows && cols == other.cols;

  @override
  int get hashCode => Object.hash(rows, cols);

  @override
  String toString() => 'CellSize($rows, $cols)';
}

/// A rectangle on the cell grid. Half-open: covers rows [top, top+height)
/// and cols [left, left+width).
class CellRect {
  final int top;
  final int left;
  final int width;
  final int height;

  /// row-first to match the (row, col) convention used everywhere else.
  const CellRect.fromTLWH(this.top, this.left, this.width, this.height);

  const CellRect.fromOffsetSize(CellOffset offset, CellSize size)
      : top = offset.row,
        left = offset.col,
        width = size.cols,
        height = size.rows;

  int get bottom => top + height; // exclusive
  int get right => left + width; // exclusive
  CellOffset get offset => CellOffset(top, left);
  CellSize get size => CellSize(height, width);
  bool get isEmpty => height <= 0 || width <= 0;

  bool contains(CellOffset p) =>
      p.row >= top && p.row < bottom && p.col >= left && p.col < right;

  /// Intersection of two rects. Returns an empty rect if they do not overlap.
  CellRect intersect(CellRect other) {
    var t = top > other.top ? top : other.top;
    var l = left > other.left ? left : other.left;
    var b = bottom < other.bottom ? bottom : other.bottom;
    var r = right < other.right ? right : other.right;
    return CellRect.fromTLWH(t, l, r - l, b - t);
  }

  /// This rect translated by [delta].
  CellRect shift(CellOffset delta) =>
      CellRect.fromTLWH(top + delta.row, left + delta.col, width, height);

  /// This rect inset by [amount] cells on every side. A rect too small to
  /// inset becomes empty (clamped, never negative-sized).
  CellRect deflate(int amount) {
    var w = width - 2 * amount;
    var h = height - 2 * amount;
    return CellRect.fromTLWH(
      top + amount,
      left + amount,
      w < 0 ? 0 : w,
      h < 0 ? 0 : h,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CellRect &&
      top == other.top &&
      left == other.left &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(top, left, width, height);

  @override
  String toString() => 'CellRect.fromTLWH($top, $left, $width, $height)';
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/tui/geometry_test.dart`
Expected: PASS — all tests green.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/geometry.dart app/test/tui/geometry_test.dart
git commit -m "Add CellOffset/CellSize/CellRect geometry (TUI stage 2)"
```

---

## Task 2: `wrapText`

A pure word-wrap function. Splits on existing `\n` first, then word-wraps each segment on spaces. A word longer than `width` is hard-broken at the width boundary. `width <= 0` returns the segments split only on `\n`. Width is measured in runes.

**Files:**
- Create: `app/lib/src/tui/text_wrap.dart`
- Test: `app/test/tui/text_wrap_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `app/test/tui/text_wrap_test.dart`:

```dart
import 'package:flutterware_app/src/tui/text_wrap.dart';
import 'package:test/test.dart';

void main() {
  group('wrapText', () {
    test('short text fits on one line', () {
      expect(wrapText('hello', 20), ['hello']);
    });

    test('wraps on spaces at the width boundary', () {
      expect(wrapText('one two three', 7), ['one two', 'three']);
    });

    test('preserves explicit newlines', () {
      expect(wrapText('a\nb', 20), ['a', 'b']);
    });

    test('preserves blank lines from consecutive newlines', () {
      expect(wrapText('a\n\nb', 20), ['a', '', 'b']);
    });

    test('hard-breaks a word longer than width', () {
      expect(wrapText('abcdefg', 3), ['abc', 'def', 'g']);
    });

    test('hard-break flushes the pending line first', () {
      expect(wrapText('hi abcdefg', 3), ['hi', 'abc', 'def', 'g']);
    });

    test('width <= 0 splits only on newlines', () {
      expect(wrapText('one two\nthree', 0), ['one two', 'three']);
    });

    test('empty string yields one empty line', () {
      expect(wrapText('', 10), ['']);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/tui/text_wrap_test.dart`
Expected: FAIL — compile error, `text_wrap.dart` does not exist.

- [ ] **Step 3: Create the implementation**

Create `app/lib/src/tui/text_wrap.dart`:

```dart
/// Word-wrapping for the TUI paint kit.
library;

/// Wrap [text] to lines no wider than [width] runes.
///
/// Splits on existing '\n' first, then word-wraps each segment on spaces.
/// A single word longer than [width] is hard-broken at the width boundary.
/// When [width] <= 0, returns the segments split only on '\n'.
List<String> wrapText(String text, int width) {
  var segments = text.split('\n');
  if (width <= 0) return segments;

  var lines = <String>[];
  for (var segment in segments) {
    var current = '';
    for (var word in segment.split(' ')) {
      var w = word;
      // Hard-break a word that cannot fit even on its own line.
      while (w.runes.length > width) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }
        lines.add(String.fromCharCodes(w.runes.take(width)));
        w = String.fromCharCodes(w.runes.skip(width));
      }
      if (current.isEmpty) {
        current = w;
      } else if (current.runes.length + 1 + w.runes.length <= width) {
        current = '$current $w';
      } else {
        lines.add(current);
        current = w;
      }
    }
    lines.add(current);
  }
  return lines;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/tui/text_wrap_test.dart`
Expected: PASS — all tests green.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/text_wrap.dart app/test/tui/text_wrap_test.dart
git commit -m "Add wrapText word-wrap helper (TUI stage 2)"
```

---

## Task 3: `Painter` core — translate, clip, fill, lines

The `Painter` wraps a `CellBuffer` with an origin offset and a clip rect. `translate` and `clip` return new `Painter`s sharing the buffer. All writes go through the private `_put` chokepoint. This task also adds `BorderChars` and the alignment enums (used by later tasks) and the `fill`/`fillRect`/`drawHLine`/`drawVLine` helpers.

**Files:**
- Create: `app/lib/src/tui/painter.dart`
- Test: `app/test/tui/painter_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `app/test/tui/painter_test.dart`:

```dart
import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:test/test.dart';

/// Renders a buffer to a list of strings, one per row, for easy assertions.
List<String> dump(CellBuffer b) => [
      for (var r = 0; r < b.rows; r++)
        String.fromCharCodes([
          for (var c = 0; c < b.cols; c++) b.get(r, c).rune,
        ]),
    ];

void main() {
  var star = Cell(rune: 0x2a); // '*'

  group('Painter.fillRect', () {
    test('fills the given rect, leaving the rest blank', () {
      var b = CellBuffer(3, 5);
      Painter(b).fillRect(CellRect.fromTLWH(1, 1, 2, 1), star);
      expect(dump(b), ['     ', ' ** ', '     ']);
    });

    test('fill covers the whole buffer', () {
      var b = CellBuffer(2, 3);
      Painter(b).fill(star);
      expect(dump(b), ['***', '***']);
    });
  });

  group('Painter.translate', () {
    test('shifts painted content by the offset', () {
      var b = CellBuffer(4, 4);
      Painter(b)
          .translate(CellOffset(1, 2))
          .fillRect(CellRect.fromTLWH(0, 0, 1, 1), star);
      expect(b.get(1, 2).rune, 0x2a);
      expect(b.get(0, 0).rune, 0x20);
    });

    test('translates still fill the whole buffer via fill()', () {
      var b = CellBuffer(2, 2);
      Painter(b).translate(CellOffset(1, 1)).fill(star);
      expect(dump(b), ['**', '**']);
    });
  });

  group('Painter.clip', () {
    test('drops writes outside the clip', () {
      var b = CellBuffer(4, 4);
      Painter(b)
          .clip(CellRect.fromTLWH(0, 0, 2, 2))
          .fillRect(CellRect.fromTLWH(0, 0, 10, 10), star);
      expect(dump(b), ['**  ', '**  ', '    ', '    ']);
    });

    test('clip composes with a later translate', () {
      // Clip to the top-left 2x2, then translate by (1,1): only the cell
      // that lands back inside the clip is painted.
      var b = CellBuffer(4, 4);
      Painter(b)
          .clip(CellRect.fromTLWH(0, 0, 2, 2))
          .translate(CellOffset(1, 1))
          .fillRect(CellRect.fromTLWH(0, 0, 5, 5), star);
      expect(dump(b), ['    ', ' *  ', '    ', '    ']);
    });

    test('nested clips intersect', () {
      var b = CellBuffer(4, 4);
      Painter(b)
          .clip(CellRect.fromTLWH(0, 0, 3, 3))
          .clip(CellRect.fromTLWH(1, 1, 3, 3))
          .fill(star);
      expect(dump(b), ['    ', ' ** ', ' ** ', '    ']);
    });
  });

  group('Painter lines', () {
    test('drawHLine draws a horizontal run', () {
      var b = CellBuffer(1, 5);
      Painter(b).drawHLine(CellOffset(0, 1), 3, rune: 0x2a);
      expect(dump(b), [' *** ']);
    });

    test('drawVLine draws a vertical run', () {
      var b = CellBuffer(4, 1);
      Painter(b).drawVLine(CellOffset(1, 0), 2, rune: 0x2a);
      expect(dump(b), [' ', '*', '*', ' ']);
    });

    test('non-positive length draws nothing', () {
      var b = CellBuffer(1, 3);
      Painter(b).drawHLine(CellOffset(0, 0), 0, rune: 0x2a);
      expect(dump(b), ['   ']);
    });
  });

  group('BorderChars', () {
    test('single preset has box-drawing corners', () {
      var c = BorderChars.single();
      expect(c.topLeft, '┌');
      expect(c.bottomRight, '┘');
    });

    test('ascii preset uses plain characters', () {
      var c = BorderChars.ascii();
      expect(c.topLeft, '+');
      expect(c.horizontal, '-');
      expect(c.vertical, '|');
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/tui/painter_test.dart`
Expected: FAIL — compile error, `painter.dart` does not exist.

- [ ] **Step 3: Create the implementation**

Create `app/lib/src/tui/painter.dart`:

```dart
import 'buffer.dart';
import 'cell.dart';
import 'geometry.dart';
import 'text_wrap.dart';

/// Horizontal placement of text within a rect.
enum HorizontalAlign { left, center, right }

/// Vertical placement of text within a rect.
enum VerticalAlign { top, center, bottom }

/// The six glyphs that make up a box border.
class BorderChars {
  final String topLeft;
  final String topRight;
  final String bottomLeft;
  final String bottomRight;
  final String horizontal; // top and bottom edges
  final String vertical; // left and right edges

  const BorderChars({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.horizontal,
    required this.vertical,
  });

  const BorderChars.single()
      : topLeft = '┌',
        topRight = '┐',
        bottomLeft = '└',
        bottomRight = '┘',
        horizontal = '─',
        vertical = '│';

  const BorderChars.double()
      : topLeft = '╔',
        topRight = '╗',
        bottomLeft = '╚',
        bottomRight = '╝',
        horizontal = '═',
        vertical = '║';

  const BorderChars.rounded()
      : topLeft = '╭',
        topRight = '╮',
        bottomLeft = '╰',
        bottomRight = '╯',
        horizontal = '─',
        vertical = '│';

  const BorderChars.thick()
      : topLeft = '┏',
        topRight = '┓',
        bottomLeft = '┗',
        bottomRight = '┛',
        horizontal = '━',
        vertical = '┃';

  const BorderChars.ascii()
      : topLeft = '+',
        topRight = '+',
        bottomLeft = '+',
        bottomRight = '+',
        horizontal = '-',
        vertical = '|';
}

/// A drawing surface over a [CellBuffer], carrying a translation [_origin] and
/// a [_clip] rectangle (both in buffer coordinates).
///
/// [translate] and [clip] return new [Painter]s that share the same buffer —
/// the functional "shared canvas with an offset" model. Every write routes
/// through [_put], so content outside the clip can never be painted.
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
  /// origin). Helpers that fill "everything" target this.
  CellRect get bounds =>
      _clip.shift(CellOffset(-_origin.row, -_origin.col));

  /// A painter whose local origin is shifted by [offset].
  Painter translate(CellOffset offset) =>
      Painter._(_buffer, _origin + offset, _clip);

  /// A painter clipped to [rect] (in local coordinates), intersected with the
  /// current clip.
  Painter clip(CellRect rect) =>
      Painter._(_buffer, _origin, _clip.intersect(rect.shift(_origin)));

  /// The single write chokepoint: translate local coords by the origin, drop
  /// anything outside the clip, otherwise write to the buffer.
  void _put(int row, int col, Cell cell) {
    var r = row + _origin.row;
    var c = col + _origin.col;
    if (r < _clip.top || r >= _clip.bottom) return;
    if (c < _clip.left || c >= _clip.right) return;
    _buffer.set(r, c, cell);
  }

  /// Fill the entire visible region with [cell].
  void fill(Cell cell) => fillRect(bounds, cell);

  /// Fill [rect] (local coordinates) with [cell].
  void fillRect(CellRect rect, Cell cell) {
    for (var r = rect.top; r < rect.bottom; r++) {
      for (var c = rect.left; c < rect.right; c++) {
        _put(r, c, cell);
      }
    }
  }

  /// Draw a horizontal run of [length] cells starting at [start].
  void drawHLine(
    CellOffset start,
    int length, {
    int rune = 0x2500,
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
  }) {
    var cell = Cell(rune: rune, fg: fg, bg: bg, style: style);
    for (var i = 0; i < length; i++) {
      _put(start.row, start.col + i, cell);
    }
  }

  /// Draw a vertical run of [length] cells starting at [start].
  void drawVLine(
    CellOffset start,
    int length, {
    int rune = 0x2502,
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
  }) {
    var cell = Cell(rune: rune, fg: fg, bg: bg, style: style);
    for (var i = 0; i < length; i++) {
      _put(start.row + i, start.col, cell);
    }
  }
}
```

> Note: `wrapText` is imported now because Tasks 4 and 5 add `drawBorder` and `drawText` to this same class; the import is used by the end of Task 5. If the analyzer flags an unused import at this step, that is expected and resolved in Task 5.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/tui/painter_test.dart`
Expected: PASS — all tests green.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/painter.dart app/test/tui/painter_test.dart
git commit -m "Add Painter core: translate, clip, fill, lines (TUI stage 2)"
```

---

## Task 4: `drawBorder`

Draws the perimeter of a rect using a `BorderChars` glyph set. The interior is left untouched. A rect with `width < 2` or `height < 2` degrades to a line / partial frame without crashing.

**Files:**
- Modify: `app/lib/src/tui/painter.dart`
- Test: `app/test/tui/painter_test.dart`

- [ ] **Step 1: Write the failing tests**

Add this group to `app/test/tui/painter_test.dart`, inside `main()`, before its final closing `}`:

```dart
  group('Painter.drawBorder', () {
    test('draws an ascii box around the rect', () {
      var b = CellBuffer(3, 4);
      Painter(b).drawBorder(
        CellRect.fromTLWH(0, 0, 4, 3),
        chars: BorderChars.ascii(),
      );
      expect(dump(b), ['+--+', '|  |', '+--+']);
    });

    test('leaves the interior untouched', () {
      var b = CellBuffer(3, 3);
      Painter(b).drawBorder(
        CellRect.fromTLWH(0, 0, 3, 3),
        chars: BorderChars.ascii(),
      );
      expect(b.get(1, 1).rune, 0x20); // still blank
    });

    test('a 1-wide rect does not crash and draws vertical edges', () {
      var b = CellBuffer(4, 1);
      Painter(b).drawBorder(
        CellRect.fromTLWH(0, 0, 1, 4),
        chars: BorderChars.ascii(),
      );
      // Middle rows are vertical edges; no exception thrown.
      expect(b.get(1, 0).rune, '|'.runes.first);
      expect(b.get(2, 0).rune, '|'.runes.first);
    });

    test('an empty rect draws nothing', () {
      var b = CellBuffer(3, 3);
      Painter(b).drawBorder(
        CellRect.fromTLWH(0, 0, 0, 0),
        chars: BorderChars.ascii(),
      );
      expect(dump(b), ['   ', '   ', '   ']);
    });

    test('respects the clip', () {
      var b = CellBuffer(4, 4);
      Painter(b)
          .clip(CellRect.fromTLWH(0, 0, 2, 4))
          .drawBorder(
            CellRect.fromTLWH(0, 0, 4, 4),
            chars: BorderChars.ascii(),
          );
      // Only the top two rows of the border survive the clip.
      expect(dump(b), ['+--+', '|  |', '    ', '    ']);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/tui/painter_test.dart`
Expected: FAIL — `drawBorder` is not defined on `Painter`.

- [ ] **Step 3: Add the implementation**

In `app/lib/src/tui/painter.dart`, add this method to the `Painter` class, immediately after `drawVLine`:

```dart
  /// Draw a box border around the perimeter of [rect] using [chars].
  ///
  /// The interior is left untouched. A rect narrower or shorter than 2 cells
  /// degrades gracefully — it draws what edge cells it can without crashing.
  void drawBorder(
    CellRect rect, {
    BorderChars chars = const BorderChars.single(),
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
  }) {
    if (rect.isEmpty) return;

    Cell glyph(String s) =>
        Cell(rune: s.runes.first, fg: fg, bg: bg, style: style);

    var top = rect.top;
    var bottom = rect.bottom - 1;
    var left = rect.left;
    var right = rect.right - 1;

    // Edges first; corners overwrite the ends.
    for (var c = left; c <= right; c++) {
      _put(top, c, glyph(chars.horizontal));
      _put(bottom, c, glyph(chars.horizontal));
    }
    for (var r = top; r <= bottom; r++) {
      _put(r, left, glyph(chars.vertical));
      _put(r, right, glyph(chars.vertical));
    }
    _put(top, left, glyph(chars.topLeft));
    _put(top, right, glyph(chars.topRight));
    _put(bottom, left, glyph(chars.bottomLeft));
    _put(bottom, right, glyph(chars.bottomRight));
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/tui/painter_test.dart`
Expected: PASS — all tests, including the new `drawBorder` group, green.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/painter.dart app/test/tui/painter_test.dart
git commit -m "Add Painter.drawBorder (TUI stage 2)"
```

---

## Task 5: `drawText`

Lays text out inside a rect: word-wraps (when `wrap` is true), positions the block vertically per `vAlign`, positions each line horizontally per `hAlign`, and clips to the rect's right and bottom edges. Center rounds toward top-left (floor division).

**Files:**
- Modify: `app/lib/src/tui/painter.dart`
- Test: `app/test/tui/painter_test.dart`

- [ ] **Step 1: Write the failing tests**

Add this group to `app/test/tui/painter_test.dart`, inside `main()`, before its final closing `}`:

```dart
  group('Painter.drawText', () {
    test('left/top aligned single line', () {
      var b = CellBuffer(2, 8);
      Painter(b).drawText(CellRect.fromTLWH(0, 0, 8, 2), 'hi');
      expect(dump(b), ['hi      ', '        ']);
    });

    test('horizontal center alignment', () {
      var b = CellBuffer(1, 7);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 7, 1),
        'odd',
        hAlign: HorizontalAlign.center,
      );
      // 7 - 3 = 4 spare cols, 2 each side.
      expect(dump(b), ['  odd  ']);
    });

    test('horizontal right alignment', () {
      var b = CellBuffer(1, 6);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 6, 1),
        'abc',
        hAlign: HorizontalAlign.right,
      );
      expect(dump(b), ['   abc']);
    });

    test('vertical center alignment', () {
      var b = CellBuffer(3, 3);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 3, 3),
        'x',
        vAlign: VerticalAlign.center,
      );
      expect(dump(b), ['   ', 'x  ', '   ']);
    });

    test('vertical bottom alignment', () {
      var b = CellBuffer(3, 3);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 3, 3),
        'x',
        vAlign: VerticalAlign.bottom,
      );
      expect(dump(b), ['   ', '   ', 'x  ']);
    });

    test('wraps long text across rows', () {
      var b = CellBuffer(2, 7);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 7, 2),
        'one two three',
      );
      expect(dump(b), ['one two', 'three  ']);
    });

    test('drops wrapped rows that overflow the rect height', () {
      var b = CellBuffer(3, 7);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 7, 1), // only one row tall
        'one two three',
      );
      expect(dump(b), ['one two', '       ', '       ']);
    });

    test('unwrapped long line is clipped at the rect right edge', () {
      var b = CellBuffer(1, 8);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 4, 1),
        'abcdefgh',
        wrap: false,
      );
      expect(dump(b), ['abcd    ']);
    });

    test('text is offset by the rect position', () {
      var b = CellBuffer(3, 6);
      Painter(b).drawText(CellRect.fromTLWH(1, 2, 4, 1), 'ab');
      expect(dump(b), ['      ', '  ab  ', '      ']);
    });

    test('empty rect draws nothing', () {
      var b = CellBuffer(2, 2);
      Painter(b).drawText(CellRect.fromTLWH(0, 0, 0, 0), 'x');
      expect(dump(b), ['  ', '  ']);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/tui/painter_test.dart`
Expected: FAIL — `drawText` is not defined on `Painter`.

- [ ] **Step 3: Add the implementation**

In `app/lib/src/tui/painter.dart`, add this method to the `Painter` class, immediately after `drawBorder`:

```dart
  /// Draw [text] inside [rect].
  ///
  /// When [wrap] is true, [text] is word-wrapped to the rect width; otherwise
  /// it is split only on '\n' and long lines are clipped at the right edge.
  /// The line block is positioned vertically by [vAlign] and each line
  /// horizontally by [hAlign]. Rows that overflow the rect height are dropped.
  void drawText(
    CellRect rect,
    String text, {
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
    HorizontalAlign hAlign = HorizontalAlign.left,
    VerticalAlign vAlign = VerticalAlign.top,
    bool wrap = true,
  }) {
    if (rect.isEmpty) return;

    var lines = wrap ? wrapText(text, rect.width) : text.split('\n');
    var visibleCount = lines.length < rect.height ? lines.length : rect.height;
    var extraRows = rect.height - visibleCount;
    var rowOffset = switch (vAlign) {
      VerticalAlign.top => 0,
      VerticalAlign.center => extraRows ~/ 2,
      VerticalAlign.bottom => extraRows,
    };

    for (var i = 0; i < visibleCount; i++) {
      var runes = lines[i].runes.toList();
      var extraCols = rect.width - runes.length;
      var colOffset = switch (hAlign) {
        HorizontalAlign.left => 0,
        HorizontalAlign.center => extraCols < 0 ? 0 : extraCols ~/ 2,
        HorizontalAlign.right => extraCols < 0 ? 0 : extraCols,
      };
      var row = rect.top + rowOffset + i;
      for (var j = 0; j < runes.length; j++) {
        var col = rect.left + colOffset + j;
        if (col >= rect.right) break; // clip to the rect right edge
        _put(row, col, Cell(rune: runes[j], fg: fg, bg: bg, style: style));
      }
    }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/tui/painter_test.dart`
Expected: PASS — all tests, including the new `drawText` group, green.

- [ ] **Step 5: Run the whole tui suite and the analyzer**

Run: `cd app && flutter test test/tui/`
Expected: PASS — every tui test, including the stage 1 suites, green.

Run: `flutter analyze` (from the repo root)
Expected: "No issues found!" — in particular the `text_wrap` import in `painter.dart` is now used.

- [ ] **Step 6: Commit**

```bash
git add app/lib/src/tui/painter.dart app/test/tui/painter_test.dart
git commit -m "Add Painter.drawText with wrapping and alignment (TUI stage 2)"
```

---

## Task 6: Public exports and roadmap update

Expose the new types through the `tui.dart` barrel file and mark stage 2 done in the roadmap.

**Files:**
- Modify: `app/lib/src/tui/tui.dart`
- Modify: `docs/superpowers/tui-roadmap.md`

- [ ] **Step 1: Add the exports**

Replace the entire contents of `app/lib/src/tui/tui.dart` with:

```dart
/// Public surface of the TUI engine (stage 1) and paint kit (stage 2).
library;

export 'ansi.dart' show Ansi;
export 'buffer.dart' show CellBuffer;
export 'cell.dart' show Cell, Color, TextStyle;
export 'geometry.dart' show CellOffset, CellSize, CellRect;
export 'input.dart'
    show KeyEvent, CharKey, SpecialKey, SpecialKeyCode, Modifier;
export 'painter.dart'
    show Painter, BorderChars, HorizontalAlign, VerticalAlign;
export 'terminal.dart' show Terminal, TerminalMode, FullScreenMode, InlineMode;
export 'text_wrap.dart' show wrapText;
```

- [ ] **Step 2: Update the roadmap**

In `docs/superpowers/tui-roadmap.md`, in the Stages table, change the Stage 2 row from:

```
| **2. Paint kit** | `Rect`/`CellSize` geometry + procedural paint helpers (text, border, fill) | ⬜ Not started |
```

to:

```
| **2. Paint kit** | `CellRect`/`CellSize` geometry + procedural paint helpers (text, border, fill) | ✅ Done |
```

Then, in the "Detailed docs per stage" list, add this entry after the `print_above` line:

```
- Stage 2 — [spec](specs/2026-05-15-tui-stage2-paint-kit-design.md) ·
  [plan](plans/2026-05-15-tui-stage2-paint-kit.md)
```

- [ ] **Step 3: Verify the analyzer is clean**

Run: `flutter analyze` (from the repo root)
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add app/lib/src/tui/tui.dart docs/superpowers/tui-roadmap.md
git commit -m "Export TUI paint kit; mark stage 2 done in roadmap"
```

---

## Task 7: Demo — `paint_kit_demo.dart`

A full-screen demo that exercises borders, wrapped text, alignment, and a nested `translate`+`clip` panel that visibly clips overflowing content.

**Files:**
- Create: `app/examples/tui/paint_kit_demo.dart`

- [ ] **Step 1: Create the demo**

Create `app/examples/tui/paint_kit_demo.dart`:

```dart
// Stage 2 paint-kit demo. Run in a real terminal:
//   cd app && dart run examples/tui/paint_kit_demo.dart
// Press 'q' to quit.

import 'package:flutterware_app/src/tui/tui.dart';

const _lorem = 'The paint kit draws borders, fills, lines and word-wrapped '
    'text into a shared cell buffer. Every helper routes through one clipped '
    'write path, so a panel can never bleed past its own rectangle.';

void _paint(CellBuffer buffer) {
  var painter = Painter(buffer);
  painter.fill(Cell(rune: 0x20)); // blank background

  // --- Panel 1: rounded border, centered title ---
  var panel1 = CellRect.fromTLWH(1, 2, 30, 5);
  painter.drawBorder(panel1, chars: BorderChars.rounded(), fg: Color.cyan);
  painter.drawText(
    panel1.deflate(1),
    'Paint kit',
    hAlign: HorizontalAlign.center,
    vAlign: VerticalAlign.center,
    style: TextStyle.bold,
  );

  // --- Panel 2: double border, wrapped paragraph ---
  var panel2 = CellRect.fromTLWH(1, 35, 40, 9);
  painter.drawBorder(panel2, chars: BorderChars.double(), fg: Color.yellow);
  painter.drawText(panel2.deflate(1), _lorem);

  // --- Panel 3: clipping demo. A child painter is translated into the panel
  // interior and clipped to it; the text it draws is far too wide and tall,
  // and must not escape the panel. ---
  var panel3 = CellRect.fromTLWH(8, 2, 30, 7);
  painter.drawBorder(panel3, chars: BorderChars.thick(), fg: Color.magenta);
  var interior = panel3.deflate(1);
  var clipped = painter
      .translate(interior.offset)
      .clip(CellRect.fromOffsetSize(CellOffset.zero, interior.size));
  // Draw into an oversized rect: only the part inside the clip survives.
  clipped.drawText(
    CellRect.fromTLWH(0, 0, 200, 50),
    'This sentence is deliberately much wider and taller than the panel '
        'that contains it, to prove the clip holds. ' * 3,
    fg: Color.brightGreen,
  );

  // --- Footer ---
  painter.drawText(
    CellRect.fromTLWH(buffer.rows - 1, 0, buffer.cols, 1),
    "Press 'q' to quit",
    fg: Color.brightBlack,
  );
}

Future<void> main() async {
  await Terminal.run((terminal) async {
    terminal.draw(_paint);

    unawaited(() async {
      await for (final _ in terminal.resizes) {
        terminal.draw(_paint);
      }
    }());

    await for (final event in terminal.keys) {
      if (event is CharKey && event.rune == 0x71 /* 'q' */) break;
    }
  });
}
```

> If `unawaited` is not in scope, add `import 'dart:async';` at the top. Confirm against `app/examples/tui/inline_demo.dart` / `step1_demo.dart` how they handle the resize stream and copy that pattern exactly if it differs.

- [ ] **Step 2: Verify the analyzer is clean**

Run: `flutter analyze` (from the repo root)
Expected: "No issues found!"

- [ ] **Step 3: Manual smoke test**

Run: `cd app && dart run examples/tui/paint_kit_demo.dart`

Verify in a real terminal:
- Three bordered panels render: a rounded cyan panel with a bold centered "Paint kit" title, a double-bordered yellow panel with a wrapped paragraph, and a thick magenta panel.
- The magenta panel's green text is clipped — it fills the panel interior but no green character appears outside the thick border, on any side.
- The footer "Press 'q' to quit" shows on the bottom row.
- Pressing `q` exits cleanly and the shell prompt returns with the terminal restored (no leftover escape codes, cursor visible).

- [ ] **Step 4: Format and final check**

Run: `dart tool/prepare_submit.dart` (from the repo root)
Expected: formats files; `git status` should show no unexpected diff beyond the demo file. If it reformats the demo, that is fine — stage it.

- [ ] **Step 5: Commit**

```bash
git add app/examples/tui/paint_kit_demo.dart
git commit -m "Add paint kit demo (TUI stage 2)"
```

---

## Done

After all tasks:
- `cd app && flutter test test/tui/` — all green.
- `flutter analyze` — clean.
- `dart tool/prepare_submit.dart` — no diff.
- The demo runs and clips correctly in a real terminal.

The paint kit is the surface stage 3 (render tree) will consume: a render object will receive a `Painter`, and a parent will position a child with `painter.translate(childOffset).clip(childRect)`.

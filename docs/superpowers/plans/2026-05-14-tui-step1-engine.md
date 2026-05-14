# TUI Step 1 — Engine Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the engine layer of a Flutter-style TUI framework: alt-screen lifecycle, CellBuffer + diff-to-ANSI, raw-stdin key parsing, resize handling, and crash-safe terminal restore. Deliverable is a working demo (`step1_demo.dart`) that draws a centered status box, updates on key/resize, and exits cleanly.

**Architecture:** Five small Dart files under `app/lib/src/tui/`, each with one responsibility. `Cell` and `CellBuffer` are pure data; `ansi.dart` encodes buffer diffs as escape sequences; `input.dart` parses raw stdin bytes into `KeyEvent`s; `terminal.dart` owns lifecycle and signal handling. Zero pub dependencies — `dart:io` and `dart:async` only.

**Tech Stack:** Dart 3.6+, `package:test` (already a dev dep of `flutterware_app`).

**Spec:** [`docs/superpowers/specs/2026-05-14-tui-step1-engine-design.md`](../specs/2026-05-14-tui-step1-engine-design.md)

---

## File Structure

```
app/lib/src/tui/
  cell.dart            # Cell, Color, TextStyle constants
  buffer.dart          # CellBuffer (immutable size, mutable contents)
  ansi.dart            # ANSI constants + encodeDiff(front, back)
  input.dart           # KeyEvent sealed types + parseKeyEvents()
  terminal.dart        # Terminal.run lifecycle
  tui.dart             # barrel re-export
  example/
    step1_demo.dart    # the demo program

app/test/tui/
  cell_test.dart
  buffer_test.dart
  ansi_test.dart
  input_test.dart
```

**Run commands from `app/` directory** (the package root). The plan assumes `cd app` was done once at the start of execution.

---

## Task 1: `Cell`, `Color`, `TextStyle`

**Files:**
- Create: `app/lib/src/tui/cell.dart`
- Create: `app/test/tui/cell_test.dart`

- [ ] **Step 1.1: Write the failing test**

`app/test/tui/cell_test.dart`:

```dart
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:test/test.dart';

void main() {
  group('Color', () {
    test('named ANSI colors have stable indices', () {
      expect(Color.red.ansiIndex, 1);
      expect(Color.brightWhite.ansiIndex, 15);
    });

    test('rgb colors carry rgb values', () {
      final c = Color.rgb(10, 20, 30);
      expect(c.r, 10);
      expect(c.g, 20);
      expect(c.b, 30);
    });

    test('default colors are distinct from named black', () {
      expect(Color.defaultFg, isNot(equals(Color.black)));
      expect(Color.defaultBg, isNot(equals(Color.black)));
    });

    test('value equality', () {
      expect(Color.rgb(1, 2, 3), equals(Color.rgb(1, 2, 3)));
      expect(Color.red, equals(Color.red));
      expect(Color.red, isNot(equals(Color.blue)));
    });
  });

  group('Cell', () {
    test('empty cell is a space with default colors', () {
      expect(Cell.empty.rune, 0x20);
      expect(Cell.empty.fg, Color.defaultFg);
      expect(Cell.empty.bg, Color.defaultBg);
      expect(Cell.empty.style, 0);
      expect(Cell.empty.width, 1);
    });

    test('value equality', () {
      final a = Cell(rune: 0x41, fg: Color.red, bg: Color.defaultBg, style: TextStyle.bold);
      final b = Cell(rune: 0x41, fg: Color.red, bg: Color.defaultBg, style: TextStyle.bold);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('TextStyle bitfield combines', () {
      final combined = TextStyle.bold | TextStyle.underline;
      expect(combined & TextStyle.bold, isNot(0));
      expect(combined & TextStyle.underline, isNot(0));
      expect(combined & TextStyle.italic, 0);
    });
  });
}
```

- [ ] **Step 1.2: Run test to verify it fails**

```bash
dart test test/tui/cell_test.dart
```

Expected: compilation error — `cell.dart` does not exist.

- [ ] **Step 1.3: Write the implementation**

`app/lib/src/tui/cell.dart`:

```dart
/// Text style bitfield. Combine with bitwise OR.
class TextStyle {
  static const int bold = 1 << 0;
  static const int dim = 1 << 1;
  static const int italic = 1 << 2;
  static const int underline = 1 << 3;
  static const int reverse = 1 << 4;

  // not instantiable
  TextStyle._();
}

/// Color in one of three encodings: terminal default, ANSI named (16-color),
/// or 24-bit RGB. Equality is structural.
class Color {
  final int _kind; // 0 = default, 1 = ansi, 2 = rgb
  final int ansiIndex; // valid when _kind == 1; 0..15
  final int r, g, b; // valid when _kind == 2

  const Color._(this._kind, this.ansiIndex, this.r, this.g, this.b);

  static const Color defaultFg = Color._(0, 0, 0, 0, 0);
  static const Color defaultBg = Color._(0, 1, 0, 0, 0); // sentinel distinct from defaultFg

  // 16 ANSI named colors (indices match the ANSI SGR convention).
  static const Color black = Color._(1, 0, 0, 0, 0);
  static const Color red = Color._(1, 1, 0, 0, 0);
  static const Color green = Color._(1, 2, 0, 0, 0);
  static const Color yellow = Color._(1, 3, 0, 0, 0);
  static const Color blue = Color._(1, 4, 0, 0, 0);
  static const Color magenta = Color._(1, 5, 0, 0, 0);
  static const Color cyan = Color._(1, 6, 0, 0, 0);
  static const Color white = Color._(1, 7, 0, 0, 0);
  static const Color brightBlack = Color._(1, 8, 0, 0, 0);
  static const Color brightRed = Color._(1, 9, 0, 0, 0);
  static const Color brightGreen = Color._(1, 10, 0, 0, 0);
  static const Color brightYellow = Color._(1, 11, 0, 0, 0);
  static const Color brightBlue = Color._(1, 12, 0, 0, 0);
  static const Color brightMagenta = Color._(1, 13, 0, 0, 0);
  static const Color brightCyan = Color._(1, 14, 0, 0, 0);
  static const Color brightWhite = Color._(1, 15, 0, 0, 0);

  const factory Color.rgb(int r, int g, int b) = Color._rgb;
  const Color._rgb(this.r, this.g, this.b) : _kind = 2, ansiIndex = 0;

  bool get isDefault => _kind == 0;
  bool get isAnsi => _kind == 1;
  bool get isRgb => _kind == 2;
  bool get isDefaultFg => _kind == 0 && ansiIndex == 0;
  bool get isDefaultBg => _kind == 0 && ansiIndex == 1;

  @override
  bool operator ==(Object other) =>
      other is Color &&
      _kind == other._kind &&
      ansiIndex == other.ansiIndex &&
      r == other.r &&
      g == other.g &&
      b == other.b;

  @override
  int get hashCode => Object.hash(_kind, ansiIndex, r, g, b);
}

/// A single terminal cell. Immutable.
class Cell {
  final int rune;
  final Color fg;
  final Color bg;
  final int style;
  final int width; // 1 for stage 1; reserved for wide-char support later

  const Cell({
    required this.rune,
    this.fg = Color.defaultFg,
    this.bg = Color.defaultBg,
    this.style = 0,
    this.width = 1,
  });

  static const Cell empty = Cell(rune: 0x20);

  @override
  bool operator ==(Object other) =>
      other is Cell &&
      rune == other.rune &&
      fg == other.fg &&
      bg == other.bg &&
      style == other.style &&
      width == other.width;

  @override
  int get hashCode => Object.hash(rune, fg, bg, style, width);
}
```

- [ ] **Step 1.4: Run test to verify it passes**

```bash
dart test test/tui/cell_test.dart
```

Expected: all tests pass.

- [ ] **Step 1.5: Commit**

```bash
git add app/lib/src/tui/cell.dart app/test/tui/cell_test.dart
git commit -m "Add TUI Cell, Color, TextStyle value types"
```

---

## Task 2: `CellBuffer`

**Files:**
- Create: `app/lib/src/tui/buffer.dart`
- Create: `app/test/tui/buffer_test.dart`

- [ ] **Step 2.1: Write the failing test**

`app/test/tui/buffer_test.dart`:

```dart
import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:test/test.dart';

void main() {
  group('CellBuffer', () {
    test('new buffer is filled with Cell.empty', () {
      final b = CellBuffer(3, 4);
      expect(b.rows, 3);
      expect(b.cols, 4);
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 4; c++) {
          expect(b.get(r, c), Cell.empty);
        }
      }
    });

    test('set and get round-trip', () {
      final b = CellBuffer(2, 2);
      final cell = Cell(rune: 0x41, fg: Color.red);
      b.set(0, 1, cell);
      expect(b.get(0, 1), cell);
      expect(b.get(0, 0), Cell.empty);
    });

    test('writeAt writes a string left-to-right', () {
      final b = CellBuffer(1, 10);
      b.writeAt(0, 2, 'Hi');
      expect(b.get(0, 0), Cell.empty);
      expect(b.get(0, 1), Cell.empty);
      expect(b.get(0, 2).rune, 0x48); // H
      expect(b.get(0, 3).rune, 0x69); // i
      expect(b.get(0, 4), Cell.empty);
    });

    test('writeAt applies fg/bg/style to all cells', () {
      final b = CellBuffer(1, 5);
      b.writeAt(0, 0, 'ab', fg: Color.red, style: TextStyle.bold);
      expect(b.get(0, 0).fg, Color.red);
      expect(b.get(0, 0).style, TextStyle.bold);
      expect(b.get(0, 1).fg, Color.red);
    });

    test('writeAt clips silently past right edge', () {
      final b = CellBuffer(1, 3);
      b.writeAt(0, 1, 'hello');
      expect(b.get(0, 0), Cell.empty);
      expect(b.get(0, 1).rune, 0x68); // h
      expect(b.get(0, 2).rune, 0x65); // e
      // 'llo' silently dropped
    });

    test('writeAt with negative col is partially clipped', () {
      final b = CellBuffer(1, 4);
      b.writeAt(0, -2, 'hello');
      // h,e at -2,-1 clipped; l,l,o at 0,1,2
      expect(b.get(0, 0).rune, 0x6c); // l
      expect(b.get(0, 1).rune, 0x6c); // l
      expect(b.get(0, 2).rune, 0x6f); // o
      expect(b.get(0, 3), Cell.empty);
    });

    test('set out of bounds is a no-op', () {
      final b = CellBuffer(2, 2);
      // Must not throw.
      b.set(-1, 0, Cell(rune: 0x41));
      b.set(0, 5, Cell(rune: 0x41));
      b.set(10, 10, Cell(rune: 0x41));
      expect(b.get(0, 0), Cell.empty);
    });

    test('get out of bounds returns Cell.empty', () {
      final b = CellBuffer(2, 2);
      expect(b.get(-1, 0), Cell.empty);
      expect(b.get(0, 5), Cell.empty);
    });

    test('fill replaces every cell', () {
      final b = CellBuffer(2, 2);
      final c = Cell(rune: 0x41, fg: Color.blue);
      b.fill(c);
      expect(b.get(0, 0), c);
      expect(b.get(1, 1), c);
    });

    test('fillRect fills only the given region', () {
      final b = CellBuffer(4, 4);
      final c = Cell(rune: 0x23); // #
      b.fillRect(1, 1, 2, 2, c);
      expect(b.get(0, 0), Cell.empty);
      expect(b.get(1, 1), c);
      expect(b.get(2, 2), c);
      expect(b.get(3, 3), Cell.empty);
    });

    test('fillRect clips to buffer bounds', () {
      final b = CellBuffer(2, 2);
      final c = Cell(rune: 0x23);
      b.fillRect(-1, -1, 5, 5, c); // overflows on all sides
      // Every in-bounds cell should be c.
      for (var r = 0; r < 2; r++) {
        for (var col = 0; col < 2; col++) {
          expect(b.get(r, col), c);
        }
      }
    });

    test('copyFrom copies all cells', () {
      final a = CellBuffer(2, 2);
      a.set(0, 0, Cell(rune: 0x41));
      a.set(1, 1, Cell(rune: 0x42));
      final b = CellBuffer(2, 2);
      b.copyFrom(a);
      expect(b.get(0, 0).rune, 0x41);
      expect(b.get(1, 1).rune, 0x42);
    });

    test('copyFrom throws on size mismatch', () {
      final a = CellBuffer(2, 2);
      final b = CellBuffer(3, 3);
      expect(() => b.copyFrom(a), throwsA(isA<ArgumentError>()));
    });

    test('inBounds', () {
      final b = CellBuffer(2, 3);
      expect(b.inBounds(0, 0), isTrue);
      expect(b.inBounds(1, 2), isTrue);
      expect(b.inBounds(-1, 0), isFalse);
      expect(b.inBounds(0, 3), isFalse);
      expect(b.inBounds(2, 0), isFalse);
    });
  });
}
```

- [ ] **Step 2.2: Run test to verify it fails**

```bash
dart test test/tui/buffer_test.dart
```

Expected: compilation error — `buffer.dart` does not exist.

- [ ] **Step 2.3: Write the implementation**

`app/lib/src/tui/buffer.dart`:

```dart
import 'cell.dart';

/// A grid of cells, addressed by (row, col). Size is fixed at construction.
/// All mutation methods silently clip to bounds.
class CellBuffer {
  final int rows;
  final int cols;
  final List<Cell> _cells;

  CellBuffer(this.rows, this.cols)
      : _cells = List<Cell>.filled(rows * cols, Cell.empty, growable: false);

  bool inBounds(int row, int col) =>
      row >= 0 && row < rows && col >= 0 && col < cols;

  Cell get(int row, int col) {
    if (!inBounds(row, col)) return Cell.empty;
    return _cells[row * cols + col];
  }

  void set(int row, int col, Cell cell) {
    if (!inBounds(row, col)) return;
    _cells[row * cols + col] = cell;
  }

  void writeAt(
    int row,
    int col,
    String text, {
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
  }) {
    var c = col;
    for (final rune in text.runes) {
      if (inBounds(row, c)) {
        _cells[row * cols + c] = Cell(rune: rune, fg: fg, bg: bg, style: style);
      }
      c++;
    }
  }

  void fill(Cell cell) {
    for (var i = 0; i < _cells.length; i++) {
      _cells[i] = cell;
    }
  }

  void fillRect(int row, int col, int rowCount, int colCount, Cell cell) {
    final r0 = row.clamp(0, rows);
    final r1 = (row + rowCount).clamp(0, rows);
    final c0 = col.clamp(0, cols);
    final c1 = (col + colCount).clamp(0, cols);
    for (var r = r0; r < r1; r++) {
      for (var c = c0; c < c1; c++) {
        _cells[r * cols + c] = cell;
      }
    }
  }

  void clear() => fill(Cell.empty);

  void copyFrom(CellBuffer other) {
    if (other.rows != rows || other.cols != cols) {
      throw ArgumentError('size mismatch: $rows×$cols vs ${other.rows}×${other.cols}');
    }
    for (var i = 0; i < _cells.length; i++) {
      _cells[i] = other._cells[i];
    }
  }
}
```

- [ ] **Step 2.4: Run test to verify it passes**

```bash
dart test test/tui/buffer_test.dart
```

Expected: all tests pass.

- [ ] **Step 2.5: Commit**

```bash
git add app/lib/src/tui/buffer.dart app/test/tui/buffer_test.dart
git commit -m "Add TUI CellBuffer with clipping write/fill/copy"
```

---

## Task 3: ANSI constants and color/style encoders

This task covers the simple, deterministic parts of `ansi.dart`: escape sequence constants and the helpers that turn a `Color` / style int into SGR parameters. The diff encoder is a separate task because it warrants its own test suite.

**Files:**
- Create: `app/lib/src/tui/ansi.dart`
- Create: `app/test/tui/ansi_test.dart`

- [ ] **Step 3.1: Write the failing test**

`app/test/tui/ansi_test.dart`:

```dart
import 'package:flutterware_app/src/tui/ansi.dart';
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:test/test.dart';

void main() {
  group('ansi constants', () {
    test('alt-screen sequences', () {
      expect(Ansi.enterAltScreen, '\x1b[?1049h');
      expect(Ansi.exitAltScreen, '\x1b[?1049l');
    });

    test('cursor visibility', () {
      expect(Ansi.hideCursor, '\x1b[?25l');
      expect(Ansi.showCursor, '\x1b[?25h');
    });

    test('moveTo is 1-indexed', () {
      // ANSI cursor positioning is 1-indexed; our API takes 0-indexed.
      expect(Ansi.moveTo(0, 0), '\x1b[1;1H');
      expect(Ansi.moveTo(4, 9), '\x1b[5;10H');
    });

    test('clearScreen', () {
      expect(Ansi.clearScreen, '\x1b[2J');
    });

    test('resetStyle', () {
      expect(Ansi.resetStyle, '\x1b[0m');
    });
  });

  group('sgrForeground', () {
    test('default fg', () {
      expect(Ansi.sgrForeground(Color.defaultFg), '39');
    });

    test('named ansi fg (0-7)', () {
      expect(Ansi.sgrForeground(Color.red), '31');
      expect(Ansi.sgrForeground(Color.white), '37');
    });

    test('bright named ansi fg (8-15)', () {
      expect(Ansi.sgrForeground(Color.brightRed), '91');
      expect(Ansi.sgrForeground(Color.brightWhite), '97');
    });

    test('rgb fg', () {
      expect(Ansi.sgrForeground(Color.rgb(10, 20, 30)), '38;2;10;20;30');
    });
  });

  group('sgrBackground', () {
    test('default bg', () {
      expect(Ansi.sgrBackground(Color.defaultBg), '49');
    });

    test('named ansi bg', () {
      expect(Ansi.sgrBackground(Color.blue), '44');
      expect(Ansi.sgrBackground(Color.brightCyan), '106');
    });

    test('rgb bg', () {
      expect(Ansi.sgrBackground(Color.rgb(255, 0, 128)), '48;2;255;0;128');
    });
  });

  group('sgrStyle', () {
    test('no style', () {
      expect(Ansi.sgrStyle(0), <String>[]);
    });

    test('bold', () {
      expect(Ansi.sgrStyle(TextStyle.bold), ['1']);
    });

    test('combined', () {
      final s = Ansi.sgrStyle(TextStyle.bold | TextStyle.underline | TextStyle.reverse);
      expect(s, containsAll(['1', '4', '7']));
      expect(s.length, 3);
    });
  });
}
```

- [ ] **Step 3.2: Run test to verify it fails**

```bash
dart test test/tui/ansi_test.dart
```

Expected: compilation error — `ansi.dart` does not exist.

- [ ] **Step 3.3: Write the implementation**

`app/lib/src/tui/ansi.dart`:

```dart
import 'buffer.dart';
import 'cell.dart';

/// ANSI escape sequences used by the engine.
///
/// Naming convention: constants are static strings; functions build sequences
/// from arguments. All cursor coordinates exposed by this module are 0-indexed
/// (matching CellBuffer); the CSI conversion to 1-indexed happens here.
class Ansi {
  Ansi._();

  static const String esc = '\x1b';
  static const String csi = '\x1b[';

  static const String enterAltScreen = '\x1b[?1049h';
  static const String exitAltScreen = '\x1b[?1049l';
  static const String hideCursor = '\x1b[?25l';
  static const String showCursor = '\x1b[?25h';
  static const String clearScreen = '\x1b[2J';
  static const String resetStyle = '\x1b[0m';

  /// 0-indexed row, col → CSI move sequence (1-indexed).
  static String moveTo(int row, int col) => '$csi${row + 1};${col + 1}H';

  /// SGR parameter for a foreground color. Returns the parameter string only
  /// (e.g. `'31'` or `'38;2;10;20;30'`), without the CSI prefix or final `m`.
  static String sgrForeground(Color c) {
    if (c.isDefaultFg) return '39';
    if (c.isAnsi) {
      final i = c.ansiIndex;
      return i < 8 ? '${30 + i}' : '${90 + (i - 8)}';
    }
    // rgb
    return '38;2;${c.r};${c.g};${c.b}';
  }

  /// SGR parameter for a background color.
  static String sgrBackground(Color c) {
    if (c.isDefaultBg) return '49';
    if (c.isAnsi) {
      final i = c.ansiIndex;
      return i < 8 ? '${40 + i}' : '${100 + (i - 8)}';
    }
    return '48;2;${c.r};${c.g};${c.b}';
  }

  /// SGR parameters for a style bitfield. Empty list if style == 0.
  static List<String> sgrStyle(int style) {
    final out = <String>[];
    if (style & TextStyle.bold != 0) out.add('1');
    if (style & TextStyle.dim != 0) out.add('2');
    if (style & TextStyle.italic != 0) out.add('3');
    if (style & TextStyle.underline != 0) out.add('4');
    if (style & TextStyle.reverse != 0) out.add('7');
    return out;
  }
}

/// Encode the difference between [front] (current screen state) and [back]
/// (desired state) as a string of ANSI escape sequences. Returns an empty
/// string if there are no changes.
///
/// Defined in a later task.
String encodeDiff(CellBuffer front, CellBuffer back) {
  throw UnimplementedError('see Task 4');
}
```

- [ ] **Step 3.4: Run test to verify it passes**

```bash
dart test test/tui/ansi_test.dart
```

Expected: all tests pass.

- [ ] **Step 3.5: Commit**

```bash
git add app/lib/src/tui/ansi.dart app/test/tui/ansi_test.dart
git commit -m "Add ANSI escape constants and SGR encoders"
```

---

## Task 4: `encodeDiff`

**Files:**
- Modify: `app/lib/src/tui/ansi.dart` (replace `encodeDiff` stub)
- Modify: `app/test/tui/ansi_test.dart` (add new test group)

- [ ] **Step 4.1: Add failing tests for `encodeDiff`**

Append to `app/test/tui/ansi_test.dart` (inside `void main()`):

```dart
  group('encodeDiff', () {
    test('no changes produces empty string', () {
      final front = CellBuffer(2, 2);
      final back = CellBuffer(2, 2);
      expect(encodeDiff(front, back), '');
    });

    test('single cell change emits move + SGR + rune', () {
      final front = CellBuffer(2, 4);
      final back = CellBuffer(2, 4);
      back.set(1, 2, Cell(rune: 0x41 /* A */));
      final out = encodeDiff(front, back);
      // Expected: move to (1,2) in 0-indexed = CSI 2;3H, default colors,
      // then "A".
      expect(out, contains('\x1b[2;3H'));
      expect(out, contains('A'));
    });

    test('two adjacent changes in same row skip second move', () {
      final front = CellBuffer(1, 5);
      final back = CellBuffer(1, 5);
      back.set(0, 1, Cell(rune: 0x41));
      back.set(0, 2, Cell(rune: 0x42));
      final out = encodeDiff(front, back);
      // First move to (0,1) = CSI 1;2H. After writing 'A', the cursor is at
      // (0,2), so the next 'B' should follow without another CSI move.
      final moves = '\x1b['.allMatches(out).length;
      // We expect: one CSI for move + at most SGR transitions. With both
      // cells default colored from empty state, SGR may or may not appear.
      // The number of move sequences (matching CSI <num>;<num>H) must be 1.
      final moveRegex = RegExp(r'\x1b\[\d+;\d+H');
      expect(moveRegex.allMatches(out).length, 1);
      expect(out, contains('AB'));
    });

    test('change at start of new row emits a move', () {
      final front = CellBuffer(2, 3);
      final back = CellBuffer(2, 3);
      back.set(0, 0, Cell(rune: 0x41));
      back.set(1, 0, Cell(rune: 0x42));
      final out = encodeDiff(front, back);
      final moveRegex = RegExp(r'\x1b\[\d+;\d+H');
      expect(moveRegex.allMatches(out).length, 2);
    });

    test('fg change emits SGR', () {
      final front = CellBuffer(1, 2);
      final back = CellBuffer(1, 2);
      back.set(0, 0, Cell(rune: 0x41, fg: Color.red));
      final out = encodeDiff(front, back);
      expect(out, contains('31'));
      expect(out, contains('A'));
    });

    test('consecutive cells with same color do not re-emit SGR', () {
      final front = CellBuffer(1, 3);
      final back = CellBuffer(1, 3);
      back.set(0, 0, Cell(rune: 0x41, fg: Color.red));
      back.set(0, 1, Cell(rune: 0x42, fg: Color.red));
      back.set(0, 2, Cell(rune: 0x43, fg: Color.red));
      final out = encodeDiff(front, back);
      // The red SGR (parameter "31") should appear exactly once.
      final redCount = '31'.allMatches(out).length;
      expect(redCount, 1);
      expect(out, contains('ABC'));
    });

    test('color reset emits default fg', () {
      // front: red 'A'; back: default 'A' (rune unchanged but color is)
      final front = CellBuffer(1, 1);
      front.set(0, 0, Cell(rune: 0x41, fg: Color.red));
      final back = CellBuffer(1, 1);
      back.set(0, 0, Cell(rune: 0x41 /* default */));
      // The cell is "different" (fg differs), so we emit something.
      final out = encodeDiff(front, back);
      expect(out, contains('39')); // default fg
      expect(out, contains('A'));
    });

    test('size mismatch throws', () {
      final front = CellBuffer(2, 2);
      final back = CellBuffer(3, 3);
      expect(() => encodeDiff(front, back), throwsA(isA<ArgumentError>()));
    });
  });
}
```

Also add the import at the top of `ansi_test.dart` if not already present:

```dart
import 'package:flutterware_app/src/tui/buffer.dart';
```

- [ ] **Step 4.2: Run tests to verify they fail**

```bash
dart test test/tui/ansi_test.dart
```

Expected: the new `encodeDiff` group fails (stub throws `UnimplementedError`).

- [ ] **Step 4.3: Implement `encodeDiff`**

Replace the `encodeDiff` stub at the bottom of `app/lib/src/tui/ansi.dart`:

```dart
/// Encode the difference between [front] (current screen state) and [back]
/// (desired state) as a string of ANSI escape sequences.
///
/// Optimizations:
/// - Unchanged cells are skipped.
/// - When the next changed cell is the immediate horizontal neighbor of the
///   previous one, the cursor move is omitted (the cursor advances naturally
///   after a character write).
/// - Foreground, background, and style SGR are re-emitted only when they
///   change between successive printed cells.
String encodeDiff(CellBuffer front, CellBuffer back) {
  if (front.rows != back.rows || front.cols != back.cols) {
    throw ArgumentError(
        'size mismatch: ${front.rows}×${front.cols} vs ${back.rows}×${back.cols}');
  }

  final buf = StringBuffer();

  // Track cursor position. -1 means "unknown / must emit move before next write".
  int cursorRow = -1;
  int cursorCol = -1;

  // Track the last SGR state we wrote. null means "unknown".
  Color? lastFg;
  Color? lastBg;
  int? lastStyle;

  for (var r = 0; r < back.rows; r++) {
    for (var c = 0; c < back.cols; c++) {
      final f = front.get(r, c);
      final b = back.get(r, c);
      if (f == b) continue;

      // Emit a cursor move if we are not already at this position.
      if (cursorRow != r || cursorCol != c) {
        buf.write(Ansi.moveTo(r, c));
      }

      // Emit SGR transitions only for what changed.
      final params = <String>[];
      if (lastFg == null || lastFg != b.fg) {
        params.add(Ansi.sgrForeground(b.fg));
      }
      if (lastBg == null || lastBg != b.bg) {
        params.add(Ansi.sgrBackground(b.bg));
      }
      if (lastStyle == null || lastStyle != b.style) {
        // Style transitions are simplest when we reset and re-apply, otherwise
        // we'd need to track which bits to turn off.
        if (lastStyle != null && lastStyle != 0) {
          params.insert(0, '0');
          // After reset, fg/bg also reset — re-emit them.
          if (!params.contains(Ansi.sgrForeground(b.fg))) {
            params.add(Ansi.sgrForeground(b.fg));
          }
          if (!params.contains(Ansi.sgrBackground(b.bg))) {
            params.add(Ansi.sgrBackground(b.bg));
          }
        }
        params.addAll(Ansi.sgrStyle(b.style));
      }
      if (params.isNotEmpty) {
        buf.write('${Ansi.csi}${params.join(';')}m');
      }

      buf.writeCharCode(b.rune);

      lastFg = b.fg;
      lastBg = b.bg;
      lastStyle = b.style;
      cursorRow = r;
      cursorCol = c + 1; // cursor advances after a char write
    }
  }

  return buf.toString();
}
```

- [ ] **Step 4.4: Run tests to verify they pass**

```bash
dart test test/tui/ansi_test.dart
```

Expected: all tests pass, including the new `encodeDiff` group.

- [ ] **Step 4.5: Commit**

```bash
git add app/lib/src/tui/ansi.dart app/test/tui/ansi_test.dart
git commit -m "Implement encodeDiff with cursor and SGR coalescing"
```

---

## Task 5: `KeyEvent` types

This task defines the sealed `KeyEvent` hierarchy and supporting enums. The parser comes in Task 6.

**Files:**
- Create: `app/lib/src/tui/input.dart`
- Create: `app/test/tui/input_test.dart`

- [ ] **Step 5.1: Write the failing test**

`app/test/tui/input_test.dart`:

```dart
import 'package:flutterware_app/src/tui/input.dart';
import 'package:test/test.dart';

void main() {
  group('KeyEvent types', () {
    test('CharKey holds rune and modifiers', () {
      const k = CharKey(rune: 0x41, modifiers: {});
      expect(k.rune, 0x41);
      expect(k.modifiers, isEmpty);
    });

    test('CharKey value equality', () {
      const a = CharKey(rune: 0x61, modifiers: {Modifier.ctrl});
      const b = CharKey(rune: 0x61, modifiers: {Modifier.ctrl});
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('SpecialKey for arrows', () {
      const k = SpecialKey(code: SpecialKeyCode.up, modifiers: {});
      expect(k.code, SpecialKeyCode.up);
    });

    test('SpecialKey value equality with modifier set', () {
      const a = SpecialKey(code: SpecialKeyCode.left, modifiers: {Modifier.shift});
      const b = SpecialKey(code: SpecialKeyCode.left, modifiers: {Modifier.shift});
      expect(a, equals(b));
    });

    test('different special keys are unequal', () {
      const a = SpecialKey(code: SpecialKeyCode.up, modifiers: {});
      const b = SpecialKey(code: SpecialKeyCode.down, modifiers: {});
      expect(a, isNot(equals(b)));
    });
  });
}
```

- [ ] **Step 5.2: Run test to verify it fails**

```bash
dart test test/tui/input_test.dart
```

Expected: compilation error — `input.dart` does not exist.

- [ ] **Step 5.3: Write the implementation**

`app/lib/src/tui/input.dart`:

```dart
import 'dart:async';
import 'dart:collection';

enum Modifier { shift, ctrl, alt }

enum SpecialKeyCode {
  up,
  down,
  left,
  right,
  enter,
  tab,
  backspace,
  escape,
  home,
  end,
  pageUp,
  pageDown,
  delete,
  insert,
  f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
}

sealed class KeyEvent {
  final Set<Modifier> modifiers;
  const KeyEvent(this.modifiers);
}

class CharKey extends KeyEvent {
  final int rune;
  const CharKey({required this.rune, required Set<Modifier> modifiers})
      : super(modifiers);

  @override
  bool operator ==(Object other) =>
      other is CharKey &&
      other.rune == rune &&
      _setEq(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(rune, _setHash(modifiers));

  @override
  String toString() => 'CharKey(0x${rune.toRadixString(16)}, $modifiers)';
}

class SpecialKey extends KeyEvent {
  final SpecialKeyCode code;
  const SpecialKey({required this.code, required Set<Modifier> modifiers})
      : super(modifiers);

  @override
  bool operator ==(Object other) =>
      other is SpecialKey &&
      other.code == code &&
      _setEq(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(code, _setHash(modifiers));

  @override
  String toString() => 'SpecialKey($code, $modifiers)';
}

bool _setEq(Set a, Set b) {
  if (a.length != b.length) return false;
  for (final x in a) {
    if (!b.contains(x)) return false;
  }
  return true;
}

int _setHash(Set s) {
  var h = 0;
  for (final x in s) {
    h ^= x.hashCode;
  }
  return h;
}

/// Defined in Task 6.
Stream<KeyEvent> parseKeyEvents(Stream<List<int>> bytes) {
  throw UnimplementedError('see Task 6');
}
```

- [ ] **Step 5.4: Run test to verify it passes**

```bash
dart test test/tui/input_test.dart
```

Expected: all tests pass.

- [ ] **Step 5.5: Commit**

```bash
git add app/lib/src/tui/input.dart app/test/tui/input_test.dart
git commit -m "Add KeyEvent sealed types and Modifier enum"
```

---

## Task 6: `parseKeyEvents`

**Files:**
- Modify: `app/lib/src/tui/input.dart` (replace `parseKeyEvents` stub)
- Modify: `app/test/tui/input_test.dart` (add `parseKeyEvents` group)

- [ ] **Step 6.1: Add failing tests for the parser**

Append to `app/test/tui/input_test.dart` (inside `void main()`):

```dart
  group('parseKeyEvents', () {
    Future<List<KeyEvent>> parse(List<List<int>> chunks) async {
      final stream = Stream<List<int>>.fromIterable(chunks);
      return parseKeyEvents(stream).toList();
    }

    test('ASCII printable becomes CharKey', () async {
      final events = await parse([[0x41, 0x42]]); // 'A', 'B'
      expect(events, [
        const CharKey(rune: 0x41, modifiers: {}),
        const CharKey(rune: 0x42, modifiers: {}),
      ]);
    });

    test('ctrl-A through ctrl-Z become CharKey with ctrl modifier', () async {
      final events = await parse([[0x01, 0x03, 0x1a]]); // ctrl-A, ctrl-C, ctrl-Z
      expect(events.length, 3);
      expect(events[0], CharKey(rune: 0x61, modifiers: {Modifier.ctrl})); // 'a'
      expect(events[1], CharKey(rune: 0x63, modifiers: {Modifier.ctrl})); // 'c'
      expect(events[2], CharKey(rune: 0x7a, modifiers: {Modifier.ctrl})); // 'z'
    });

    test('enter, tab, backspace', () async {
      final events = await parse([[0x0d, 0x09, 0x7f]]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.enter, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.tab, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.backspace, modifiers: {}),
      ]);
    });

    test('newline (LF) is also enter', () async {
      final events = await parse([[0x0a]]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.enter, modifiers: {}),
      ]);
    });

    test('CSI arrows', () async {
      // ESC [ A/B/C/D
      final events = await parse([
        [0x1b, 0x5b, 0x41],
        [0x1b, 0x5b, 0x42],
        [0x1b, 0x5b, 0x43],
        [0x1b, 0x5b, 0x44],
      ]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.up, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.down, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.right, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.left, modifiers: {}),
      ]);
    });

    test('SS3 arrows (ESC O A)', () async {
      final events = await parse([[0x1b, 0x4f, 0x41]]); // ESC O A
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.up, modifiers: {}),
      ]);
    });

    test('CSI with modifier (ctrl-up = ESC [1;5A)', () async {
      final events = await parse([[0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x41]]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.up, modifiers: {Modifier.ctrl}),
      ]);
    });

    test('CSI shift-arrow (ESC [1;2A)', () async {
      final events = await parse([[0x1b, 0x5b, 0x31, 0x3b, 0x32, 0x41]]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.up, modifiers: {Modifier.shift}),
      ]);
    });

    test('CSI Home/End/PgUp/PgDn (ESC [H, [F, [5~, [6~)', () async {
      final events = await parse([
        [0x1b, 0x5b, 0x48], // home
        [0x1b, 0x5b, 0x46], // end
        [0x1b, 0x5b, 0x35, 0x7e], // pgUp
        [0x1b, 0x5b, 0x36, 0x7e], // pgDn
      ]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.home, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.end, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.pageUp, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.pageDown, modifiers: {}),
      ]);
    });

    test('bare escape (no follow-up bytes) emits escape', () async {
      // A single chunk containing ONLY ESC, followed by stream end.
      final events = await parse([[0x1b]]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.escape, modifiers: {}),
      ]);
    });

    test('UTF-8 multi-byte rune', () async {
      // U+00E9 (é) in UTF-8 = C3 A9
      final events = await parse([[0xc3, 0xa9]]);
      expect(events, [
        const CharKey(rune: 0x00e9, modifiers: {}),
      ]);
    });

    test('UTF-8 split across chunks', () async {
      final events = await parse([[0xc3], [0xa9]]);
      expect(events, [
        const CharKey(rune: 0x00e9, modifiers: {}),
      ]);
    });

    test('CSI split across chunks', () async {
      final events = await parse([[0x1b], [0x5b], [0x41]]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.up, modifiers: {}),
      ]);
    });
  });
}
```

- [ ] **Step 6.2: Run tests to verify they fail**

```bash
dart test test/tui/input_test.dart
```

Expected: the `parseKeyEvents` group fails (stub throws `UnimplementedError`).

- [ ] **Step 6.3: Implement `parseKeyEvents`**

Replace the `parseKeyEvents` stub at the bottom of `app/lib/src/tui/input.dart`:

```dart
/// Parse a raw byte stream into a stream of [KeyEvent]s.
///
/// Recognized sequences:
/// - ASCII 0x20–0x7e → printable [CharKey].
/// - ASCII 0x01–0x1a (except 0x09, 0x0a, 0x0d) → ctrl-letter [CharKey].
/// - 0x09 → tab; 0x0a / 0x0d → enter; 0x7f → backspace.
/// - 0x1b alone (stream ends or no more bytes available) → escape.
/// - 0x1b 0x5b … (CSI) → arrows, home/end, page up/down, with optional
///   modifier params (`ESC [1;<mod>A`).
/// - 0x1b 0x4f X (SS3) → arrows (some terminals send these in app mode).
/// - 0xc0–0xfd start of a UTF-8 multi-byte sequence → one [CharKey] with the
///   decoded code point.
///
/// Sequences split across chunk boundaries are reassembled internally.
Stream<KeyEvent> parseKeyEvents(Stream<List<int>> bytes) async* {
  final pending = Queue<int>();
  await for (final chunk in bytes) {
    pending.addAll(chunk);
    while (pending.isNotEmpty) {
      // Attempt to consume one event from the front of [pending]. If the
      // available bytes are an incomplete prefix of a multi-byte sequence,
      // _consume returns null and we break to await more input.
      final result = _consume(pending, streamClosed: false);
      if (result == null) break;
      yield result;
    }
  }
  // Stream closed. Drain any pending bytes; treat lone ESC as escape.
  while (pending.isNotEmpty) {
    final result = _consume(pending, streamClosed: true);
    if (result == null) break;
    yield result;
  }
}

/// Try to consume one [KeyEvent] from the front of [bytes]. Returns null if
/// the bytes form an incomplete sequence and [streamClosed] is false.
/// When [streamClosed] is true, ambiguous prefixes are resolved as best-effort
/// (e.g. lone ESC → escape).
KeyEvent? _consume(Queue<int> bytes, {required bool streamClosed}) {
  final first = bytes.first;

  // --- Special single-byte cases ---
  if (first == 0x1b) {
    // ESC: could be standalone escape, or the start of CSI/SS3.
    if (bytes.length == 1) {
      if (!streamClosed) return null;
      bytes.removeFirst();
      return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
    }
    final second = bytes.elementAt(1);
    if (second == 0x5b /* [ */) {
      return _consumeCsi(bytes, streamClosed: streamClosed);
    }
    if (second == 0x4f /* O */) {
      return _consumeSs3(bytes, streamClosed: streamClosed);
    }
    // Anything else after ESC: treat ESC as standalone for stage 1.
    bytes.removeFirst();
    return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
  }

  if (first == 0x09) {
    bytes.removeFirst();
    return const SpecialKey(code: SpecialKeyCode.tab, modifiers: {});
  }
  if (first == 0x0a || first == 0x0d) {
    bytes.removeFirst();
    return const SpecialKey(code: SpecialKeyCode.enter, modifiers: {});
  }
  if (first == 0x7f) {
    bytes.removeFirst();
    return const SpecialKey(code: SpecialKeyCode.backspace, modifiers: {});
  }

  // --- ctrl-letter (0x01–0x1a, excluding the specials above) ---
  if (first >= 0x01 && first <= 0x1a) {
    bytes.removeFirst();
    // 0x01 = ctrl-A → rune 'a' (0x61). General: rune = 0x60 + first.
    return CharKey(rune: 0x60 + first, modifiers: const {Modifier.ctrl});
  }

  // --- Plain ASCII printable ---
  if (first >= 0x20 && first <= 0x7e) {
    bytes.removeFirst();
    return CharKey(rune: first, modifiers: const {});
  }

  // --- UTF-8 multi-byte ---
  if (first >= 0xc0 && first < 0xf8) {
    final byteLen = first < 0xe0 ? 2 : (first < 0xf0 ? 3 : 4);
    if (bytes.length < byteLen) {
      return streamClosed
          ? (bytes.clear(), const CharKey(rune: 0xFFFD /* replacement */, modifiers: {})).$2
          : null;
    }
    var rune = first & (0xff >> (byteLen + 1));
    final consumed = <int>[bytes.removeFirst()];
    for (var i = 1; i < byteLen; i++) {
      final next = bytes.removeFirst();
      consumed.add(next);
      rune = (rune << 6) | (next & 0x3f);
    }
    return CharKey(rune: rune, modifiers: const {});
  }

  // --- Anything else (continuation bytes appearing alone, 0xfe/0xff, etc.) ---
  // Drop the byte to avoid an infinite loop.
  bytes.removeFirst();
  return CharKey(rune: 0xFFFD, modifiers: const {});
}

/// Consume an `ESC [ ...` CSI sequence. Called with [bytes] starting at 0x1b 0x5b.
/// Returns null if more bytes are needed and the stream is still open.
KeyEvent? _consumeCsi(Queue<int> bytes, {required bool streamClosed}) {
  // We need at least ESC, [, and one final byte.
  if (bytes.length < 3 && !streamClosed) return null;

  // Snapshot the bytes so we can roll back if incomplete.
  final snapshot = bytes.toList();
  // Consume ESC and [.
  snapshot.removeAt(0);
  snapshot.removeAt(0);

  // Read parameter bytes (0x30–0x3f), intermediate bytes (0x20–0x2f),
  // and finally one final byte (0x40–0x7e).
  final paramBytes = <int>[];
  var idx = 0;
  while (idx < snapshot.length && snapshot[idx] >= 0x30 && snapshot[idx] <= 0x3f) {
    paramBytes.add(snapshot[idx]);
    idx++;
  }
  if (idx >= snapshot.length) {
    return streamClosed ? _csiUnknown(bytes) : null;
  }
  final finalByte = snapshot[idx];
  if (finalByte < 0x40 || finalByte > 0x7e) {
    return streamClosed ? _csiUnknown(bytes) : null;
  }

  // Successful parse — actually consume from [bytes].
  // Total consumed = 2 (ESC, [) + paramBytes.length + 1 (final).
  final totalConsumed = 2 + paramBytes.length + 1;
  for (var i = 0; i < totalConsumed; i++) {
    bytes.removeFirst();
  }

  return _interpretCsi(paramBytes, finalByte);
}

KeyEvent _csiUnknown(Queue<int> bytes) {
  // Stream closed mid-sequence. Drain ESC and [ at least, and emit escape.
  bytes.removeFirst(); // ESC
  if (bytes.isNotEmpty) bytes.removeFirst(); // [
  return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
}

KeyEvent _interpretCsi(List<int> paramBytes, int finalByte) {
  // Parse parameters: bytes 0x30–0x39 are digits, 0x3b is separator.
  final params = <int>[];
  var cur = 0;
  var any = false;
  for (final b in paramBytes) {
    if (b >= 0x30 && b <= 0x39) {
      cur = cur * 10 + (b - 0x30);
      any = true;
    } else if (b == 0x3b /* ; */) {
      params.add(any ? cur : 0);
      cur = 0;
      any = false;
    }
  }
  if (any) params.add(cur);

  // Modifier param (xterm convention: 1=none, 2=shift, 3=alt, 4=shift+alt,
  // 5=ctrl, 6=ctrl+shift, 7=ctrl+alt, 8=ctrl+shift+alt). Apparent in
  // sequences like `ESC [1;<mod><final>` or `ESC [<n>;<mod>~`.
  Set<Modifier> mods = const {};
  if (params.length >= 2) {
    mods = _xtermModifiers(params[1]);
  }

  switch (finalByte) {
    case 0x41: // A
      return SpecialKey(code: SpecialKeyCode.up, modifiers: mods);
    case 0x42: // B
      return SpecialKey(code: SpecialKeyCode.down, modifiers: mods);
    case 0x43: // C
      return SpecialKey(code: SpecialKeyCode.right, modifiers: mods);
    case 0x44: // D
      return SpecialKey(code: SpecialKeyCode.left, modifiers: mods);
    case 0x48: // H
      return SpecialKey(code: SpecialKeyCode.home, modifiers: mods);
    case 0x46: // F
      return SpecialKey(code: SpecialKeyCode.end, modifiers: mods);
    case 0x7e: // ~
      // First param identifies the key. Common values:
      // 2=insert, 3=delete, 5=pgUp, 6=pgDn, 15=F5, 17=F6, 18=F7, 19=F8,
      // 20=F9, 21=F10, 23=F11, 24=F12.
      final keyId = params.isNotEmpty ? params[0] : 0;
      final code = switch (keyId) {
        2 => SpecialKeyCode.insert,
        3 => SpecialKeyCode.delete,
        5 => SpecialKeyCode.pageUp,
        6 => SpecialKeyCode.pageDown,
        15 => SpecialKeyCode.f5,
        17 => SpecialKeyCode.f6,
        18 => SpecialKeyCode.f7,
        19 => SpecialKeyCode.f8,
        20 => SpecialKeyCode.f9,
        21 => SpecialKeyCode.f10,
        23 => SpecialKeyCode.f11,
        24 => SpecialKeyCode.f12,
        _ => null,
      };
      if (code != null) return SpecialKey(code: code, modifiers: mods);
      return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
    default:
      return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
  }
}

Set<Modifier> _xtermModifiers(int param) {
  // xterm encodes modifiers as (param - 1) treated as a bitfield:
  // bit 0 = shift, bit 1 = alt, bit 2 = ctrl.
  final m = (param - 1).clamp(0, 7);
  final out = <Modifier>{};
  if (m & 1 != 0) out.add(Modifier.shift);
  if (m & 2 != 0) out.add(Modifier.alt);
  if (m & 4 != 0) out.add(Modifier.ctrl);
  return out;
}

KeyEvent? _consumeSs3(Queue<int> bytes, {required bool streamClosed}) {
  // ESC O X — we need 3 bytes.
  if (bytes.length < 3) {
    return streamClosed
        ? (bytes.removeFirst(), const SpecialKey(code: SpecialKeyCode.escape, modifiers: {})).$2
        : null;
  }
  bytes.removeFirst(); // ESC
  bytes.removeFirst(); // O
  final final_ = bytes.removeFirst();
  switch (final_) {
    case 0x41:
      return const SpecialKey(code: SpecialKeyCode.up, modifiers: {});
    case 0x42:
      return const SpecialKey(code: SpecialKeyCode.down, modifiers: {});
    case 0x43:
      return const SpecialKey(code: SpecialKeyCode.right, modifiers: {});
    case 0x44:
      return const SpecialKey(code: SpecialKeyCode.left, modifiers: {});
    case 0x50:
      return const SpecialKey(code: SpecialKeyCode.f1, modifiers: {});
    case 0x51:
      return const SpecialKey(code: SpecialKeyCode.f2, modifiers: {});
    case 0x52:
      return const SpecialKey(code: SpecialKeyCode.f3, modifiers: {});
    case 0x53:
      return const SpecialKey(code: SpecialKeyCode.f4, modifiers: {});
    default:
      return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
  }
}
```

- [ ] **Step 6.4: Run tests to verify they pass**

```bash
dart test test/tui/input_test.dart
```

Expected: all tests pass, including the `parseKeyEvents` group.

- [ ] **Step 6.5: Commit**

```bash
git add app/lib/src/tui/input.dart app/test/tui/input_test.dart
git commit -m "Implement parseKeyEvents with CSI/SS3/UTF-8 support"
```

---

## Task 7: `Terminal` lifecycle

This task wires everything together: alt-screen, raw mode, signal handling, the public `Terminal.run` API. There are no unit tests here — terminal interaction is integration-level. Verification is via the demo in Task 8 and explicit manual checks.

**Files:**
- Create: `app/lib/src/tui/terminal.dart`

- [ ] **Step 7.1: Write the implementation**

`app/lib/src/tui/terminal.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'ansi.dart';
import 'buffer.dart';
import 'input.dart';

/// Owns the terminal lifecycle: alt-screen entry/exit, raw-mode stdin,
/// signal handling, double-buffered painting, and crash-safe restore.
///
/// Usage:
/// ```dart
/// await Terminal.run((terminal) async {
///   terminal.draw((buffer) { ... });
///   await for (final event in terminal.keys) { ... }
/// });
/// ```
class Terminal {
  /// Run [body] inside an active terminal session. The terminal is restored
  /// to its previous state on normal completion, on uncaught error, and on
  /// SIGINT/SIGTERM/SIGHUP.
  static Future<void> run(FutureOr<void> Function(Terminal terminal) body) async {
    final terminal = Terminal._();
    await terminal._run(body);
  }

  Terminal._();

  int _rows = 0;
  int _cols = 0;
  late CellBuffer _front;
  late CellBuffer _back;

  bool _wasEcho = false;
  bool _wasLine = false;
  bool _restored = false;

  final _resizeController = StreamController<void>.broadcast();
  final _keysController = StreamController<KeyEvent>();
  StreamSubscription<KeyEvent>? _keysSub;
  final _subs = <StreamSubscription>[];

  int get rows => _rows;
  int get cols => _cols;
  Stream<void> get resizes => _resizeController.stream;
  Stream<KeyEvent> get keys => _keysController.stream;

  Future<void> _run(FutureOr<void> Function(Terminal) body) async {
    _installSignalHandlers();
    _enter();
    try {
      await runZonedGuarded(() async {
        await body(this);
      }, (error, stack) {
        _restore();
        stderr.writeln('Unhandled error in Terminal.run: $error');
        stderr.writeln(stack);
        exitCode = 1;
      });
    } finally {
      _restore();
    }
  }

  void _enter() {
    _wasEcho = stdin.echoMode;
    _wasLine = stdin.lineMode;
    stdin.echoMode = false;
    stdin.lineMode = false;

    stdout.write(Ansi.enterAltScreen);
    stdout.write(Ansi.hideCursor);
    stdout.write(Ansi.clearScreen);
    stdout.write(Ansi.moveTo(0, 0));

    _rows = stdout.terminalLines;
    _cols = stdout.terminalColumns;
    _front = CellBuffer(_rows, _cols);
    _back = CellBuffer(_rows, _cols);

    // Pipe parsed key events into the public stream.
    _keysSub = parseKeyEvents(stdin).listen(
      _keysController.add,
      onError: _keysController.addError,
      onDone: _keysController.close,
    );

    // SIGWINCH — Unix only. Errors silently ignored on platforms without it.
    try {
      _subs.add(ProcessSignal.sigwinch.watch().listen((_) => _onResize()));
    } catch (_) {/* not supported on this platform */}
  }

  void _onResize() {
    final newRows = stdout.terminalLines;
    final newCols = stdout.terminalColumns;
    if (newRows == _rows && newCols == _cols) return;
    _rows = newRows;
    _cols = newCols;
    _front = CellBuffer(_rows, _cols);
    _back = CellBuffer(_rows, _cols);
    // Force a full repaint by clearing the screen; the caller will redraw
    // on the next resizes event and the diff will show every cell as changed.
    stdout.write(Ansi.clearScreen);
    stdout.write(Ansi.moveTo(0, 0));
    _resizeController.add(null);
  }

  void _installSignalHandlers() {
    void onTermSignal(int code) {
      _restore();
      exit(code);
    }

    try {
      _subs.add(ProcessSignal.sigint.watch().listen((_) => onTermSignal(130)));
    } catch (_) {}
    try {
      _subs.add(ProcessSignal.sigterm.watch().listen((_) => onTermSignal(143)));
    } catch (_) {}
    try {
      _subs.add(ProcessSignal.sighup.watch().listen((_) => onTermSignal(129)));
    } catch (_) {}
  }

  /// Compute and emit the diff between the current back buffer and the
  /// caller's freshly-painted back buffer. The user's [paint] function
  /// receives a cleared back buffer.
  void draw(void Function(CellBuffer buffer) paint) {
    _back.clear();
    paint(_back);
    final diff = encodeDiff(_front, _back);
    if (diff.isNotEmpty) {
      stdout.write(diff);
    }
    _front.copyFrom(_back);
  }

  void _restore() {
    if (_restored) return;
    _restored = true;

    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _keysSub?.cancel();
    if (!_keysController.isClosed) _keysController.close();
    if (!_resizeController.isClosed) _resizeController.close();

    // Write restore sequences synchronously so they reach the terminal even
    // on the way out of the process.
    try {
      stdout.write(Ansi.resetStyle);
      stdout.write(Ansi.showCursor);
      stdout.write(Ansi.exitAltScreen);
    } catch (_) {/* stdout may already be closed */}

    try {
      stdin.echoMode = _wasEcho;
      stdin.lineMode = _wasLine;
    } catch (_) {}
  }
}
```

- [ ] **Step 7.2: Verify the file compiles**

```bash
dart analyze lib/src/tui/terminal.dart
```

Expected: `No issues found!`

- [ ] **Step 7.3: Commit**

```bash
git add app/lib/src/tui/terminal.dart
git commit -m "Add Terminal lifecycle with signal-safe restore"
```

---

## Task 8: Barrel file and demo

**Files:**
- Create: `app/lib/src/tui/tui.dart`
- Create: `app/lib/src/tui/example/step1_demo.dart`

- [ ] **Step 8.1: Write the barrel file**

`app/lib/src/tui/tui.dart`:

```dart
/// Public surface of the stage 1 TUI engine.
library;

export 'ansi.dart' show Ansi, encodeDiff;
export 'buffer.dart';
export 'cell.dart';
export 'input.dart';
export 'terminal.dart';
```

- [ ] **Step 8.2: Write the demo**

`app/lib/src/tui/example/step1_demo.dart`:

```dart
import 'dart:async';

import '../buffer.dart';
import '../cell.dart';
import '../input.dart';
import '../terminal.dart';

Future<void> main() async {
  await Terminal.run((terminal) async {
    String lastKey = '(none)';
    int keyCount = 0;

    void repaint() {
      terminal.draw((b) {
        final w = terminal.cols;
        final h = terminal.rows;
        const boxW = 36;
        const boxH = 5;
        final row = ((h - boxH) ~/ 2).clamp(0, h);
        final col = ((w - boxW) ~/ 2).clamp(0, w);
        _drawBorder(b, row, col, boxH, boxW);
        b.writeAt(row + 1, col + 2, 'Size: $w × $h');
        b.writeAt(row + 2, col + 2, 'Last key: $lastKey (count: $keyCount)');
        b.writeAt(row + 3, col + 2, '(q to quit)');
      });
    }

    repaint();
    final resizeSub = terminal.resizes.listen((_) => repaint());

    try {
      await for (final event in terminal.keys) {
        keyCount++;
        lastKey = _describe(event);
        if (event is CharKey && event.rune == 0x71 /* 'q' */) break;
        if (event is CharKey &&
            event.rune == 0x63 /* 'c' */ &&
            event.modifiers.contains(Modifier.ctrl)) {
          break;
        }
        repaint();
      }
    } finally {
      await resizeSub.cancel();
    }
  });
}

void _drawBorder(CellBuffer b, int row, int col, int rows, int cols) {
  const tl = 0x250C, tr = 0x2510, bl = 0x2514, br = 0x2518;
  const h = 0x2500, v = 0x2502;
  b.set(row, col, const Cell(rune: tl));
  b.set(row, col + cols - 1, const Cell(rune: tr));
  b.set(row + rows - 1, col, const Cell(rune: bl));
  b.set(row + rows - 1, col + cols - 1, const Cell(rune: br));
  for (var c = col + 1; c < col + cols - 1; c++) {
    b.set(row, c, const Cell(rune: h));
    b.set(row + rows - 1, c, const Cell(rune: h));
  }
  for (var r = row + 1; r < row + rows - 1; r++) {
    b.set(r, col, const Cell(rune: v));
    b.set(r, col + cols - 1, const Cell(rune: v));
  }
}

String _describe(KeyEvent event) {
  final mods = event.modifiers.isEmpty
      ? ''
      : '${event.modifiers.map((m) => m.name).join('+')}+';
  return switch (event) {
    CharKey(:final rune) => '$mods${String.fromCharCode(rune)} (0x${rune.toRadixString(16)})',
    SpecialKey(:final code) => '$mods${code.name}',
  };
}
```

- [ ] **Step 8.3: Verify it compiles**

```bash
dart analyze lib/src/tui/example/step1_demo.dart
```

Expected: `No issues found!`

- [ ] **Step 8.4: Run the demo manually and verify behavior**

```bash
dart run lib/src/tui/example/step1_demo.dart
```

Verify each of the following manually:

1. **Alt-screen entry:** The terminal clears and shows the centered box. Previous terminal contents are not overwritten in the scrollback.
2. **Box content:** Shows current size, "Last key: (none) (count: 0)", and "(q to quit)".
3. **Key echo:** Press several keys (letters, arrows, enter, ctrl-A). The box updates with each one. No flicker on update.
4. **Resize:** Resize the terminal window. The box re-centers correctly. New dimensions show in the box.
5. **Quit via q:** Press q. The terminal returns to its previous state with cursor visible. Previous shell history is intact.
6. **Quit via ctrl-C:** Restart the demo, press ctrl-C. Terminal restores correctly; exit code is 130 (`echo $?`).
7. **Quit via SIGTERM:** Restart the demo, in another terminal `kill <pid>`. Terminal restores; exit code 143.
8. **Crash safety:** Temporarily edit the demo to throw at the top of `repaint()` (`throw 'oops';`). Run it. Terminal must restore even though the demo crashed. Revert the edit.

Document any failure here. If all eight pass, proceed.

- [ ] **Step 8.5: Run the full test suite to make sure nothing regressed**

```bash
dart test test/tui/
```

Expected: every test passes.

- [ ] **Step 8.6: Commit**

```bash
git add app/lib/src/tui/tui.dart app/lib/src/tui/example/step1_demo.dart
git commit -m "Add TUI stage 1 barrel and step1_demo program"
```

---

## Done criteria

- All test files pass: `dart test test/tui/` reports green.
- `dart run lib/src/tui/example/step1_demo.dart` shows the centered status box, updates on key/resize, and restores the terminal cleanly on q, ctrl-C, SIGTERM, and uncaught error.
- No new pub dependencies were added to `app/pubspec.yaml`.
- The codebase under `app/lib/src/tui/` is organized as described in the File Structure section.

## Self-review notes

- **Spec coverage:** each spec component is covered — Cell (Task 1), CellBuffer (Task 2), ansi constants (Task 3), encodeDiff (Task 4), KeyEvent (Task 5), parser (Task 6), Terminal (Task 7), demo (Task 8). The crash-safety section is implemented in Task 7 (three layers: try/finally, runZonedGuarded, signal handlers) and verified manually in Task 8 step 4.
- **Non-goals are honored:** no widgets/elements/render-objects, no mouse, no Windows special-casing (just doesn't crash on unsupported signals), no emoji width.
- **Types stay consistent across tasks:** `Cell.style` is `int`, `KeyEvent.modifiers` is `Set<Modifier>`, `Terminal.run` returns `Future<void>`. Method names (`draw`, `writeAt`, `fillRect`, `inBounds`, `copyFrom`) are used identically in spec, plan, and code.

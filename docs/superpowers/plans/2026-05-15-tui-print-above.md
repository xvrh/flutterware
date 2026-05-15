# `print_above` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `print_above` capability to the TUI engine's inline mode, letting code emit log lines that scroll into the terminal scrollback above the anchored region while the region stays intact.

**Architecture:** Natural-scroll technique — move the cursor to the inline region's top row, write the new lines each followed by `\n` (letting the terminal scroll lines into real scrollback), recompute the region's anchor row, then redraw the region by replaying the last `draw()` paint callback. A new `encodeRow` helper encodes a single buffer row; a pure `anchorRowAfterPrintAbove` helper computes the new anchor.

**Tech Stack:** Pure Dart (`dart:io`, `dart:async`), `package:test` / `flutter test`. No new dependencies.

**Spec:** [docs/superpowers/specs/2026-05-15-tui-print-above-design.md](../specs/2026-05-15-tui-print-above-design.md)

---

## File Structure

- `app/lib/src/tui/ansi.dart` — **modify**: add `encodeRow`, encodes a single `CellBuffer` row to SGR + characters.
- `app/lib/src/tui/terminal.dart` — **modify**: add top-level `anchorRowAfterPrintAbove`, the `_lastPaint` field, `printAbove`, and `printTextAbove`.
- `app/test/tui/ansi_test.dart` — **modify**: add an `encodeRow` test group.
- `app/test/tui/terminal_test.dart` — **create**: tests for the pure `anchorRowAfterPrintAbove` helper.
- `app/examples/tui/print_above_demo.dart` — **create**: streaming build-log dashboard demo.
- `docs/superpowers/tui-roadmap.md` — **modify**: mark `print_above` done.

### Testability note

`Terminal` cannot be unit-tested: `Terminal.run` sets `stdin.echoMode = false`, which throws `StdinException` outside a tty — that is why no `terminal_test.dart` exists today. So the plan unit-tests only the **pure** pieces (`encodeRow`, `anchorRowAfterPrintAbove`). The `printAbove` / `printTextAbove` methods and the full-screen `StateError` guard are verified by running the demo in a real terminal (Task 4).

---

## Task 1: `encodeRow` helper

Encodes one row of a `CellBuffer` as ANSI SGR + characters, starting at the current cursor position, with no leading cursor move and trailing blank cells dropped. `printAbove` uses it to emit each scrollback line; `encodeDiff` cannot be reused because it emits absolute cursor moves and never emits the `\n` that drives scrolling.

**Files:**
- Modify: `app/lib/src/tui/ansi.dart`
- Test: `app/test/tui/ansi_test.dart`

- [ ] **Step 1: Write the failing tests**

Add this group at the end of `main()` in `app/test/tui/ansi_test.dart`, before the final closing `}`:

```dart
  group('encodeRow', () {
    test('empty row produces empty string', () {
      final buffer = CellBuffer(1, 5);
      expect(encodeRow(buffer), '');
    });

    test('plain row emits runes with no leading cursor move', () {
      final buffer = CellBuffer(1, 5);
      buffer.writeAt(0, 0, 'Hi');
      final out = encodeRow(buffer);
      expect(out, contains('Hi'));
      expect(out, isNot(matches(RegExp(r'\x1b\[\d+;\d+H'))));
    });

    test('trailing blank cells are dropped', () {
      final buffer = CellBuffer(1, 10);
      buffer.writeAt(0, 0, 'ab');
      // Row is "ab" followed by 8 blank cells; output must not pad them.
      final out = encodeRow(buffer);
      expect(out.endsWith('b'), isTrue);
    });

    test('rowIndex selects the row', () {
      final buffer = CellBuffer(3, 5);
      buffer.writeAt(2, 0, 'Xy');
      expect(encodeRow(buffer, rowIndex: 2), contains('Xy'));
      expect(encodeRow(buffer, rowIndex: 0), '');
    });

    test('foreground color emits SGR once per run', () {
      final buffer = CellBuffer(1, 3);
      buffer.writeAt(0, 0, 'RR', fg: Color.red);
      final out = encodeRow(buffer);
      expect('31'.allMatches(out).length, 1);
      expect(out, contains('RR'));
    });

    test('style transition resets and re-applies color', () {
      final buffer = CellBuffer(1, 2);
      buffer.set(0, 0, Cell(rune: 0x41, fg: Color.red, style: TextStyle.bold));
      buffer.set(0, 1, Cell(rune: 0x42, fg: Color.red));
      final out = encodeRow(buffer);
      expect(out, matches(RegExp(r'(\x1b\[|;)0(;|m)')));
      expect(out, contains('31'));
      expect(out, contains('A'));
      expect(out, contains('B'));
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/tui/ansi_test.dart`
Expected: FAIL — `encodeRow` is undefined.

- [ ] **Step 3: Implement `encodeRow`**

Append to `app/lib/src/tui/ansi.dart` after `encodeDiff`:

```dart
/// Encode a single row of [buffer] (the row at [rowIndex]) as ANSI SGR +
/// characters, starting at the current cursor position. No leading cursor
/// move is emitted.
///
/// Trailing cells equal to [Cell.empty] are dropped — the caller is expected
/// to follow the output with an erase-to-end-of-line (`\x1b[K`) so a short
/// line leaves no stale cells behind.
///
/// SGR foreground/background/style transitions are coalesced the same way
/// [encodeDiff] coalesces them between successive cells.
String encodeRow(CellBuffer buffer, {int rowIndex = 0}) {
  // Find the last non-blank cell so trailing blanks are not emitted.
  var lastCol = -1;
  for (var c = 0; c < buffer.cols; c++) {
    if (buffer.get(rowIndex, c) != Cell.empty) lastCol = c;
  }
  if (lastCol < 0) return '';

  final buf = StringBuffer();
  Color? lastFg;
  Color? lastBg;
  int? lastStyle;

  for (var c = 0; c <= lastCol; c++) {
    final cell = buffer.get(rowIndex, c);
    final params = <String>[];
    if (lastFg == null || lastFg != cell.fg) {
      params.add(Ansi.sgrForeground(cell.fg));
    }
    if (lastBg == null || lastBg != cell.bg) {
      params.add(Ansi.sgrBackground(cell.bg));
    }
    if (lastStyle == null || lastStyle != cell.style) {
      if (lastStyle != null && lastStyle != 0) {
        params.insert(0, '0');
        if (!params.contains(Ansi.sgrForeground(cell.fg))) {
          params.add(Ansi.sgrForeground(cell.fg));
        }
        if (!params.contains(Ansi.sgrBackground(cell.bg))) {
          params.add(Ansi.sgrBackground(cell.bg));
        }
      }
      params.addAll(Ansi.sgrStyle(cell.style));
    }
    if (params.isNotEmpty) {
      buf.write('${Ansi.csi}${params.join(';')}m');
    }
    buf.writeCharCode(cell.rune);

    lastFg = cell.fg;
    lastBg = cell.bg;
    lastStyle = cell.style;
  }

  return buf.toString();
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/tui/ansi_test.dart`
Expected: PASS — all tests, including the existing `encodeDiff` group.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/ansi.dart app/test/tui/ansi_test.dart
git commit -m "Add encodeRow helper for TUI print_above"
```

---

## Task 2: `anchorRowAfterPrintAbove` helper

A pure function computing the inline region's new origin row after N lines are printed above it. The region drifts down until pinned against the bottom of the terminal, then stays. Extracted as a top-level function so it is unit-testable without a tty.

**Files:**
- Modify: `app/lib/src/tui/terminal.dart`
- Test: `app/test/tui/terminal_test.dart` (create)

- [ ] **Step 1: Write the failing tests**

Create `app/test/tui/terminal_test.dart`:

```dart
import 'package:flutterware_app/src/tui/terminal.dart';
import 'package:test/test.dart';

void main() {
  group('anchorRowAfterPrintAbove', () {
    test('region with room below just drifts down by the line count', () {
      // Region top at row 5, height 4, terminal 40 rows: plenty of room.
      expect(
        anchorRowAfterPrintAbove(
            originRow: 5, regionRows: 4, linesPrinted: 3, terminalLines: 40),
        8,
      );
    });

    test('region pins at the bottom once it reaches it', () {
      // maxOrigin = 40 - 4 = 36. originRow 35 + 10 lines would be 45.
      expect(
        anchorRowAfterPrintAbove(
            originRow: 35, regionRows: 4, linesPrinted: 10, terminalLines: 40),
        36,
      );
    });

    test('already pinned region stays pinned', () {
      expect(
        anchorRowAfterPrintAbove(
            originRow: 36, regionRows: 4, linesPrinted: 5, terminalLines: 40),
        36,
      );
    });

    test('zero lines printed leaves the anchor unchanged', () {
      expect(
        anchorRowAfterPrintAbove(
            originRow: 12, regionRows: 4, linesPrinted: 0, terminalLines: 40),
        12,
      );
    });

    test('terminal shorter than the region clamps the anchor to 0', () {
      // maxOrigin = 3 - 5 = -2; result must clamp up to 0.
      expect(
        anchorRowAfterPrintAbove(
            originRow: 0, regionRows: 5, linesPrinted: 2, terminalLines: 3),
        0,
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/tui/terminal_test.dart`
Expected: FAIL — `anchorRowAfterPrintAbove` is undefined.

- [ ] **Step 3: Implement the helper**

Add this top-level function to `app/lib/src/tui/terminal.dart`, after the `TerminalMode` classes and before `class Terminal`:

```dart
/// Compute the inline region's new origin row after [linesPrinted] lines are
/// printed into the scrollback above it.
///
/// The region drifts downward as lines are inserted above it, until it is
/// pinned against the bottom of the terminal (`terminalLines - regionRows`),
/// after which further lines scroll the screen and the anchor stays put.
/// Clamped to a minimum of 0 so a terminal shorter than the region still
/// yields a valid row.
int anchorRowAfterPrintAbove({
  required int originRow,
  required int regionRows,
  required int linesPrinted,
  required int terminalLines,
}) {
  final maxOrigin = terminalLines - regionRows;
  var next = originRow + linesPrinted;
  if (next > maxOrigin) next = maxOrigin;
  if (next < 0) next = 0;
  return next;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/tui/terminal_test.dart`
Expected: PASS — all 5 tests.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/terminal.dart app/test/tui/terminal_test.dart
git commit -m "Add anchorRowAfterPrintAbove helper for TUI print_above"
```

---

## Task 3: `printAbove` and `printTextAbove` on `Terminal`

Add the two public methods plus the `_lastPaint` field. `printAbove` is the primitive (a `CellBuffer`-paint callback, forward-compatible with a future widget layer); `printTextAbove` is the plain-text convenience. These touch `stdout` directly and cannot be unit-tested without a tty (see the Testability note) — they are exercised by the demo in Task 4.

**Files:**
- Modify: `app/lib/src/tui/terminal.dart`

- [ ] **Step 1: Add the `_lastPaint` field**

In `class Terminal`, add this field next to the other buffer state (after the `late CellBuffer _back;` line):

```dart
  /// The most recent paint callback passed to [draw]. Replayed by
  /// [printAbove] to redraw the region after it has been re-anchored.
  void Function(CellBuffer buffer)? _lastPaint;
```

- [ ] **Step 2: Store the paint callback in `draw`**

Modify `draw` in `app/lib/src/tui/terminal.dart` so its body begins by storing the callback. The method becomes:

```dart
  void draw(void Function(CellBuffer buffer) paint) {
    _lastPaint = paint;
    _back.clear();
    paint(_back);
    final diff =
        encodeDiff(_front, _back, originRow: _originRow, originCol: _originCol);
    if (diff.isNotEmpty) {
      stdout.write(diff);
    }
    _front.copyFrom(_back);
  }
```

- [ ] **Step 3: Add `printAbove` and `printTextAbove`**

Add both methods to `class Terminal`, immediately after `draw`:

```dart
  /// Insert [height] rows of content into the terminal scrollback immediately
  /// above the inline region, then redraw the region at its new anchor.
  ///
  /// [paint] receives a fresh [height]×cols [CellBuffer] addressed from
  /// (0, 0). Content wider than the terminal is clipped; lines are not
  /// wrapped. A non-positive [height] is a no-op.
  ///
  /// Only valid in inline mode. Throws [StateError] in full-screen mode,
  /// where the alt-screen buffer has no scrollback.
  void printAbove(int height, void Function(CellBuffer buffer) paint) {
    if (_mode is! InlineMode) {
      throw StateError('printAbove is only available in inline mode');
    }
    if (height <= 0) return;

    final lines = CellBuffer(height, _cols);
    paint(lines);

    final out = StringBuffer();
    // Write the new lines starting at the region's current top row. Each
    // trailing newline either drifts the region down or, once the region is
    // pinned at the bottom, scrolls a line into the terminal's scrollback.
    out.write(Ansi.moveTo(_originRow, 0));
    for (var r = 0; r < height; r++) {
      out.write(encodeRow(lines, rowIndex: r));
      out.write(Ansi.resetStyle); // so the erase below uses the default bg
      out.write('\x1b[K'); // erase to end of line
      out.write('\n');
    }

    _originRow = anchorRowAfterPrintAbove(
      originRow: _originRow,
      regionRows: _rows,
      linesPrinted: height,
      terminalLines: stdout.terminalLines,
    );

    // Wipe the now-stale region area, then redraw the region at the new
    // anchor by replaying the last paint callback against a blank front.
    out.write(Ansi.moveTo(_originRow, 0));
    out.write('\x1b[J'); // erase from cursor to end of screen

    _front = CellBuffer(_rows, _cols);
    _back.clear();
    (_lastPaint ?? (_) {})(_back);
    out.write(encodeDiff(_front, _back,
        originRow: _originRow, originCol: _originCol));
    _front.copyFrom(_back);

    stdout.write(out.toString());
  }

  /// Convenience over [printAbove] for plain text. [text] is split on '\n';
  /// each line becomes one scrollback row painted with the given style.
  ///
  /// Only valid in inline mode. Throws [StateError] in full-screen mode.
  void printTextAbove(
    String text, {
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
  }) {
    final textLines = text.split('\n');
    printAbove(textLines.length, (buffer) {
      for (var i = 0; i < textLines.length; i++) {
        buffer.writeAt(i, 0, textLines[i], fg: fg, bg: bg, style: style);
      }
    });
  }
```

- [ ] **Step 4: Add the `cell.dart` import**

`printTextAbove`'s signature references `Color` and the default style. Check the imports at the top of `app/lib/src/tui/terminal.dart`. It currently imports `ansi.dart`, `buffer.dart`, `cursor_query.dart`, `input.dart`. Add:

```dart
import 'cell.dart';
```

(Place it in alphabetical order among the existing relative imports.)

- [ ] **Step 5: Verify it analyzes cleanly**

Run: `cd app && dart analyze lib/src/tui/terminal.dart`
Expected: "No issues found!"

- [ ] **Step 6: Run the full tui test suite to confirm no regressions**

Run: `cd app && flutter test test/tui/`
Expected: PASS — all files.

- [ ] **Step 7: Commit**

```bash
git add app/lib/src/tui/terminal.dart
git commit -m "Add Terminal.printAbove and printTextAbove"
```

---

## Task 4: Streaming build-log dashboard demo

A demo that shows the feature end to end: an inline status panel pinned at the bottom while colored log lines stream into the scrollback above it via `printAbove`. This is the concrete flutterware-CLI use case (a live progress panel + scrolling build log).

**Files:**
- Create: `app/examples/tui/print_above_demo.dart`

- [ ] **Step 1: Write the demo**

Create `app/examples/tui/print_above_demo.dart`:

```dart
import 'dart:async';

import 'package:flutterware_app/src/tui/tui.dart';

/// print_above showcase: a simulated `flutter build` whose log lines stream
/// into the terminal scrollback while a status panel stays pinned below.
///
/// Exercises [Terminal.printAbove] (colored log lines into scrollback),
/// the region staying intact and re-anchored after each insert, and a
/// timer-driven animated panel rendered with [Terminal.draw].
Future<void> main() async {
  print('--- flutterware build (print_above demo) ---');
  await Terminal.run(_dashboard, mode: const InlineMode(rows: 5));
  print('--- build finished; back to normal shell output ---');
}

// Braille spinner frames.
const _spinner = [
  0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807,
  0x280F,
];

// A scripted build log: (level, message). level: 0 info, 1 warn, 2 error.
const _script = <(int, String)>[
  (0, 'Resolving dependencies...'),
  (0, 'Got dependencies.'),
  (0, 'Running Gradle task assembleDebug...'),
  (0, 'Compiling lib/main.dart'),
  (0, 'Compiling lib/src/app.dart'),
  (1, 'lib/src/app.dart:42: unused import'),
  (0, 'Compiling lib/src/widgets/home.dart'),
  (0, 'Compiling lib/src/widgets/details.dart'),
  (1, 'lib/src/widgets/details.dart:88: deprecated API'),
  (0, 'Linking native libraries'),
  (2, 'ld: duplicate symbol _kFoo (recovered)'),
  (0, 'Bundling assets'),
  (0, 'Optimizing icon tree-shaking'),
  (0, 'Signing build/app/outputs/apk/debug/app-debug.apk'),
  (0, 'Built build/app/outputs/apk/debug/app-debug.apk (24.1MB)'),
];

Future<void> _dashboard(Terminal terminal) async {
  final start = DateTime.now();
  var frames = 0;
  var emitted = 0;
  var warns = 0;
  var errors = 0;
  var done = false;

  void repaint() {
    frames++;
    terminal.draw((b) {
      final w = terminal.cols;
      _drawBorder(b, 0, 0, terminal.rows, w,
          title: ' flutterware build ');

      final progress = (emitted / _script.length * 100).round();
      final color = done ? Color.brightGreen : Color.brightCyan;

      // Row 1: spinner + phase label.
      b.set(
          1,
          2,
          Cell(
              rune: done ? 0x2714 /* heavy check */
                  : _spinner[frames % _spinner.length],
              fg: color));
      b.writeAt(1, 4, done ? 'Build complete' : 'Building...',
          style: TextStyle.bold, fg: color);

      // Row 2: progress bar + percentage.
      final barStart = 2;
      final barEnd = w - 8;
      final barWidth = (barEnd - barStart).clamp(0, w);
      final filled = (barWidth * progress / 100).round();
      for (var i = 0; i < barWidth; i++) {
        b.set(
          2,
          barStart + i,
          i < filled
              ? Cell(rune: 0x2588, fg: color)
              : const Cell(rune: 0x2591, fg: Color.brightBlack),
        );
      }
      b.writeAt(2, barEnd + 1, '${progress.toString().padLeft(3)}%', fg: color);

      // Row 3: counts + elapsed + quit hint.
      final elapsed = DateTime.now().difference(start);
      b.writeAt(3, 2,
          'warnings $warns   errors $errors   elapsed ${elapsed.inSeconds}s',
          style: TextStyle.dim);
      b.writeAt(3, w - 19, 'press q to quit', style: TextStyle.dim);
    });
  }

  // Emit one scripted log line into the scrollback above the panel.
  void emitLogLine() {
    if (emitted >= _script.length) return;
    final (level, message) = _script[emitted];
    emitted++;
    final (tag, color) = switch (level) {
      2 => ('ERROR', Color.brightRed),
      1 => (' WARN', Color.brightYellow),
      _ => (' INFO', Color.brightGreen),
    };
    if (level == 1) warns++;
    if (level == 2) errors++;
    // The tag is colored; the message is default-colored. Two printTextAbove
    // calls would be two scrollback rows, so build one styled line via the
    // printAbove primitive instead.
    terminal.printAbove(1, (b) {
      b.writeAt(0, 0, tag, fg: color, style: TextStyle.bold);
      b.writeAt(0, 6, message);
    });
    repaint();
  }

  repaint();
  final resizeSub = terminal.resizes.listen((_) => repaint());
  final ticker =
      Timer.periodic(const Duration(milliseconds: 100), (_) => repaint());
  final logTicker =
      Timer.periodic(const Duration(milliseconds: 350), (_) => emitLogLine());

  // Quit when the user presses q, or 1.5s after the build finishes.
  final quit = Completer<void>();
  void maybeFinish() {
    if (emitted >= _script.length && !done) {
      done = true;
      logTicker.cancel();
      Timer(const Duration(milliseconds: 1500), () {
        if (!quit.isCompleted) quit.complete();
      });
    }
  }

  final keySub = terminal.keys.listen((event) {
    if (event is CharKey && event.rune == 0x71 /* q */) {
      if (!quit.isCompleted) quit.complete();
    }
  });
  final finishTicker = Timer.periodic(
      const Duration(milliseconds: 100), (_) => maybeFinish());

  try {
    await quit.future;
  } finally {
    ticker.cancel();
    logTicker.cancel();
    finishTicker.cancel();
    await resizeSub.cancel();
    await keySub.cancel();
  }
}

void _drawBorder(CellBuffer b, int row, int col, int rows, int cols,
    {String? title}) {
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
  if (title != null) {
    b.writeAt(row, col + 2, title, style: TextStyle.bold);
  }
}
```

- [ ] **Step 2: Verify the demo analyzes cleanly**

Run: `cd app && dart analyze examples/tui/print_above_demo.dart`
Expected: "No issues found!"

- [ ] **Step 3: Run the demo in a real terminal**

Run: `cd app && dart run examples/tui/print_above_demo.dart`

Expected, verify by eye:
- A 5-row bordered status panel appears, with an animated spinner and progress bar.
- Colored log lines (`INFO`/`WARN`/`ERROR` tags) stream into the scrollback **above** the panel, roughly 3 per second.
- The panel is never corrupted or duplicated as lines stream in; it stays pinned.
- After the last log line, the panel shows "Build complete" with a check mark, then the program exits ~1.5s later.
- Pressing `q` quits early and cleanly; the next shell prompt starts on a fresh line below where the panel was.
- Scrolling the terminal back shows all the emitted log lines preserved in scrollback.

- [ ] **Step 4: Commit**

```bash
git add app/examples/tui/print_above_demo.dart
git commit -m "Add print_above streaming build-log demo"
```

---

## Task 5: Mark `print_above` done in the roadmap

**Files:**
- Modify: `docs/superpowers/tui-roadmap.md`

- [ ] **Step 1: Update the stages table**

In `docs/superpowers/tui-roadmap.md`, change the `print_above` row of the Stages table from:

```markdown
| **`print_above`** | Print log lines into scrollback above an inline region | ⏳ Next |
```

to:

```markdown
| **`print_above`** | Print log lines into scrollback above an inline region | ✅ Done |
```

- [ ] **Step 2: Update the detailed-docs list**

In the "Detailed docs per stage" list, add a line after the Stage 1.5 inline-mode entry:

```markdown
- `print_above` — [spec](specs/2026-05-15-tui-print-above-design.md) ·
  [plan](plans/2026-05-15-tui-print-above.md)
```

- [ ] **Step 3: Replace the "`print_above` — the next step" section**

The section titled `## `print_above` — the next step` describes the feature as upcoming. Replace its body (keep the heading text as `## `print_above`` without "the next step") with a past-tense summary:

```markdown
## `print_above`

Inline mode renders a fixed region anchored at the cursor. `print_above` (the
ratatui `insert_before` capability) lets inline-mode code emit log/output
lines that scroll into the terminal scrollback **above** the region, without
disturbing the region itself.

`Terminal.printAbove` writes the new lines at the region's top row and lets
the terminal scroll them into real scrollback, recomputes the region's anchor
row (`_originRow`), then redraws the region by replaying the last `draw()`
paint callback. `printTextAbove` is the plain-text convenience over it. See
the [design spec](specs/2026-05-15-tui-print-above-design.md).
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/tui-roadmap.md
git commit -m "Mark print_above done in TUI roadmap"
```

---

## Final Verification

- [ ] Run the full tui test suite: `cd app && flutter test test/tui/` — all PASS.
- [ ] Run workspace analysis: `flutter analyze` from the repo root — no new issues.
- [ ] Run the formatter: `dart tool/prepare_submit.dart` from the repo root, then `git status` — commit any formatting diff it produces.
- [ ] Confirm the demo behaves as described in Task 4, Step 3.

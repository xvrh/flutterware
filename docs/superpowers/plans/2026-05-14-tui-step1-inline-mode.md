# TUI Step 1 — Inline Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add inline rendering mode to the existing stage 1 TUI engine — a fixed-height region anchored at the cursor's startup position, complementing the existing full-screen alt-screen mode.

**Architecture:** Five small, focused changes: extend `encodeDiff` with an optional coordinate-origin offset; introduce a `TerminalMode` sealed class; add a cursor-position query helper for capturing the inline anchor row; branch `Terminal`'s lifecycle on mode; ship an `inline_demo.dart`. Engine modules below `Terminal` (Cell, CellBuffer, parser, Ansi) are unchanged — they were already mode-agnostic.

**Tech Stack:** Same as before — Dart 3.6+, `package:test`, zero pub dependencies.

**Spec:** [`docs/superpowers/specs/2026-05-14-tui-step1-inline-mode-design.md`](../specs/2026-05-14-tui-step1-inline-mode-design.md)

---

## File Structure

```
app/lib/src/tui/
  ansi.dart            # MODIFY — encodeDiff gains originRow/originCol
  terminal.dart        # MODIFY — TerminalMode types, mode-aware lifecycle
  cursor_query.dart    # NEW    — cursor-position query helper (testable)
  tui.dart             # MODIFY — export TerminalMode, FullScreenMode, InlineMode
  example/
    inline_demo.dart   # NEW    — demonstrates inline mode

app/test/tui/
  ansi_test.dart       # MODIFY — add origin-offset tests
  cursor_query_test.dart # NEW  — unit tests for the query parser
```

**Run commands** assume `cd app` from the worktree root before running `dart test` / `dart analyze`.

---

## Task 1: Extend `encodeDiff` with origin offset

**Files:**
- Modify: `app/lib/src/tui/ansi.dart` (encodeDiff signature + body)
- Modify: `app/test/tui/ansi_test.dart` (add 2 new tests)

- [ ] **Step 1.1: Add failing tests**

Append these tests to the existing `group('encodeDiff', () { ... })` block in `app/test/tui/ansi_test.dart`, before its closing `});`:

```dart
test('originRow shifts all cursor moves down', () {
  final front = CellBuffer(1, 2);
  final back = CellBuffer(1, 2);
  back.set(0, 0, Cell(rune: 0x41));
  back.set(0, 1, Cell(rune: 0x42));
  final out = encodeDiff(front, back, originRow: 5);
  // The single cursor move for the first cell should target row 5+0=5
  // (1-indexed: 6), col 0 (1-indexed: 1).
  expect(out, contains('\x1b[6;1H'));
  expect(out, contains('AB'));
});

test('originCol shifts all cursor moves right', () {
  final front = CellBuffer(1, 1);
  final back = CellBuffer(1, 1);
  back.set(0, 0, Cell(rune: 0x41));
  final out = encodeDiff(front, back, originCol: 10);
  // Move target: row 0+0=0 (1-indexed: 1), col 0+10=10 (1-indexed: 11).
  expect(out, contains('\x1b[1;11H'));
});

test('default origin (0, 0) preserves existing behavior', () {
  // Regression guard: omitting the new params must produce identical output
  // to the pre-extension version.
  final front = CellBuffer(1, 1);
  final back = CellBuffer(1, 1);
  back.set(0, 0, Cell(rune: 0x41));
  final withDefault = encodeDiff(front, back);
  final withExplicit = encodeDiff(front, back, originRow: 0, originCol: 0);
  expect(withDefault, withExplicit);
  expect(withDefault, contains('\x1b[1;1H'));
});
```

- [ ] **Step 1.2: Run to verify they fail**

```bash
cd app && dart test test/tui/ansi_test.dart
```

Expected: the 3 new tests fail (compilation error because `encodeDiff` doesn't accept those named params).

- [ ] **Step 1.3: Update `encodeDiff` signature and body**

In `app/lib/src/tui/ansi.dart`, find the existing `encodeDiff` function and change its signature and the one line that emits cursor moves:

```dart
String encodeDiff(
  CellBuffer front,
  CellBuffer back, {
  int originRow = 0,
  int originCol = 0,
}) {
  if (front.rows != back.rows || front.cols != back.cols) {
    throw ArgumentError(
        'size mismatch: ${front.rows}×${front.cols} vs ${back.rows}×${back.cols}');
  }

  final buf = StringBuffer();

  var cursorRow = -1;
  var cursorCol = -1;

  Color? lastFg;
  Color? lastBg;
  int? lastStyle;

  for (var r = 0; r < back.rows; r++) {
    for (var c = 0; c < back.cols; c++) {
      final f = front.get(r, c);
      final b = back.get(r, c);
      if (f == b) continue;

      if (cursorRow != r || cursorCol != c) {
        buf.write(Ansi.moveTo(r + originRow, c + originCol));
      }

      // ... rest of the function body unchanged
```

Everything below the `buf.write(Ansi.moveTo(...))` line stays exactly the same. The only edit beyond the signature is `r + originRow, c + originCol` (was `r, c`).

Also update the docstring at the top of `encodeDiff` to add one paragraph:

```
/// The optional [originRow] and [originCol] are added to every absolute
/// cursor move emitted. Pass them when rendering into a sub-region of the
/// terminal (e.g. inline mode); the back buffer is still addressed from
/// (0, 0) on the caller's side.
```

- [ ] **Step 1.4: Run to verify all tests pass**

```bash
cd app && dart test test/tui/ansi_test.dart
```

Expected: 28 tests pass (25 pre-existing + 3 new).

- [ ] **Step 1.5: Commit**

```bash
git add app/lib/src/tui/ansi.dart app/test/tui/ansi_test.dart
git commit -m "Extend encodeDiff with originRow/originCol offset for sub-region rendering"
```

---

## Task 2: `TerminalMode` types

**Files:**
- Modify: `app/lib/src/tui/terminal.dart` (add `TerminalMode` types, add `mode` parameter; no behavior change yet)
- Modify: `app/lib/src/tui/tui.dart` (export the new types)

This task introduces the API surface for mode selection. It does NOT yet change the lifecycle — `Terminal` accepts the parameter, stores it, but `_enter`/`_restore` still behave as before. Behavior change is Task 4.

- [ ] **Step 2.1: Add the `TerminalMode` sealed hierarchy**

At the top of `app/lib/src/tui/terminal.dart`, after the existing imports and before `class Terminal`, add:

```dart
/// Rendering mode for a [Terminal] session.
sealed class TerminalMode {
  const TerminalMode();
}

/// Take over the whole terminal via the alt-screen buffer. The default.
final class FullScreenMode extends TerminalMode {
  const FullScreenMode();
}

/// Render into a fixed-height region anchored at the cursor's position
/// when [Terminal.run] starts. Normal scrollback above the region is
/// preserved. Suitable for status panels and dashboards that coexist with
/// regular CLI output.
final class InlineMode extends TerminalMode {
  /// Height of the region in rows. Must be > 0.
  final int rows;
  const InlineMode({required this.rows}) : assert(rows > 0);
}
```

- [ ] **Step 2.2: Thread the `mode` parameter through `Terminal`**

Find `Terminal.run` and update its signature:

```dart
static Future<void> run(
  FutureOr<void> Function(Terminal terminal) body, {
  TerminalMode mode = const FullScreenMode(),
}) async {
  final terminal = Terminal._(mode);
  await terminal._run(body);
}
```

Update the constructor and add the field:

```dart
Terminal._(this._mode);

final TerminalMode _mode;
```

(Place `final TerminalMode _mode;` near the other private fields, around the same area as `_rows`, `_cols`.)

The rest of the class is unchanged for Task 2 — `_enter`, `_onResize`, `_restore`, `draw` continue to behave as full-screen regardless of `_mode`. That's intentional; Task 4 wires up the inline branches.

- [ ] **Step 2.3: Export the new types from the barrel**

In `app/lib/src/tui/tui.dart`, update the `terminal.dart` export line:

```dart
export 'terminal.dart' show Terminal, TerminalMode, FullScreenMode, InlineMode;
```

(The rest of the barrel stays the same.)

- [ ] **Step 2.4: Verify everything still compiles and existing tests pass**

```bash
cd app && dart analyze lib/src/tui/
cd app && dart test test/tui/
```

Expected: `No issues found!`, and 70 tests pass (67 pre-existing + 3 from Task 1). No new tests in this task — `TerminalMode` is just a data class, and the absent behavior change means no observable difference yet.

- [ ] **Step 2.5: Commit**

```bash
git add app/lib/src/tui/terminal.dart app/lib/src/tui/tui.dart
git commit -m "Add TerminalMode sealed class and thread it through Terminal.run"
```

---

## Task 3: Cursor-position query helper

**Files:**
- Create: `app/lib/src/tui/cursor_query.dart` (new)
- Create: `app/test/tui/cursor_query_test.dart` (new)

This is the hardest piece. The helper queries the terminal for its cursor position by writing `\x1b[6n` and parsing the response `\x1b[<row>;<col>R` out of an incoming byte stream, while preserving any non-response bytes (which are real input from the user typing during the query) for later delivery to the parser. Designed for unit-testing without a real terminal: it takes the byte source and the byte sink as parameters.

- [ ] **Step 3.1: Write the failing tests**

`app/test/tui/cursor_query_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutterware_app/src/tui/cursor_query.dart';
import 'package:test/test.dart';

void main() {
  group('queryCursorPosition', () {
    test('parses a clean response and returns 0-indexed row', () async {
      final input = StreamController<List<int>>();
      final outputBuf = <int>[];

      final future = queryCursorPosition(
        bytes: input.stream,
        write: outputBuf.addAll,
        fallbackRow: -1,
      );

      // Simulate terminal response: CSI 5;12R (row 5, col 12, 1-indexed).
      input.add('\x1b[5;12R'.codeUnits);

      final result = await future;
      expect(result.row, 4); // 0-indexed
      expect(result.col, 11);
      expect(result.leftoverBytes, isEmpty);
      // The query helper should have written CSI 6n.
      expect(utf8.decode(outputBuf), '\x1b[6n');

      await input.close();
    });

    test('response split across chunks', () async {
      final input = StreamController<List<int>>();
      final future = queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: -1,
      );

      input.add([0x1b, 0x5b]);
      input.add('5'.codeUnits);
      input.add(';12R'.codeUnits);

      final result = await future;
      expect(result.row, 4);
      expect(result.col, 11);
      expect(result.leftoverBytes, isEmpty);
      await input.close();
    });

    test('non-response bytes before the response are forwarded as leftover', () async {
      // The user typed 'A' before the response arrived.
      final input = StreamController<List<int>>();
      final future = queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: -1,
      );

      input.add([0x41]); // 'A'
      input.add('\x1b[3;7R'.codeUnits);

      final result = await future;
      expect(result.row, 2);
      expect(result.col, 6);
      expect(result.leftoverBytes, [0x41]);
      await input.close();
    });

    test('non-response bytes after the response are forwarded as leftover', () async {
      // The user typed 'B' right after the response.
      final input = StreamController<List<int>>();
      final future = queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: -1,
      );

      input.add('\x1b[3;7R'.codeUnits);
      input.add([0x42]); // 'B' — arrives in the same async tick

      final result = await future;
      expect(result.row, 2);
      // 'B' arrived in a separate chunk after the helper had completed; it is
      // NOT captured in leftoverBytes (the helper has already resolved).
      expect(result.leftoverBytes, isEmpty);
      await input.close();
    });

    test('interleaved escape-prefixed non-response bytes survive', () async {
      // An up-arrow key '\x1b[A' interleaves: ESC, [, A. The parser must
      // recognize that this isn't a position response (A isn't a digit after
      // ESC [), discard its partial-parse state, and forward those 3 bytes
      // to leftoverBytes. Then the real response comes through.
      final input = StreamController<List<int>>();
      final future = queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: -1,
      );

      input.add('\x1b[A'.codeUnits);     // arrow up — must NOT be consumed as response
      input.add('\x1b[10;20R'.codeUnits); // real response

      final result = await future;
      expect(result.row, 9);
      expect(result.col, 19);
      expect(result.leftoverBytes, '\x1b[A'.codeUnits);
      await input.close();
    });

    test('timeout returns fallback row and empty leftover', () async {
      final input = StreamController<List<int>>();
      final result = await queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: 42,
        timeout: const Duration(milliseconds: 50),
      );
      expect(result.row, 42);
      expect(result.col, 0);
      expect(result.leftoverBytes, isEmpty);
      await input.close();
    });

    test('timeout forwards any bytes received before timeout as leftover', () async {
      final input = StreamController<List<int>>();
      final future = queryCursorPosition(
        bytes: input.stream,
        write: (_) {},
        fallbackRow: 42,
        timeout: const Duration(milliseconds: 50),
      );

      input.add([0x58, 0x59]); // 'X', 'Y' — random non-response bytes
      // No response ever comes.

      final result = await future;
      expect(result.row, 42);
      expect(result.leftoverBytes, [0x58, 0x59]);
      await input.close();
    });
  });
}
```

- [ ] **Step 3.2: Run to verify they fail**

```bash
cd app && dart test test/tui/cursor_query_test.dart
```

Expected: compilation error — `cursor_query.dart` doesn't exist.

- [ ] **Step 3.3: Implement `cursor_query.dart`**

`app/lib/src/tui/cursor_query.dart`:

```dart
import 'dart:async';

/// Result of a [queryCursorPosition] call.
///
/// [row] and [col] are 0-indexed.
/// [leftoverBytes] are any bytes received during the query that were NOT
/// part of the position response (typically keystrokes the user typed
/// while the query was in flight). Callers should forward these to their
/// regular input pipeline.
class CursorPositionResult {
  final int row;
  final int col;
  final List<int> leftoverBytes;
  const CursorPositionResult({
    required this.row,
    required this.col,
    required this.leftoverBytes,
  });
}

/// Query the terminal for the current cursor position.
///
/// Writes `CSI 6n` via [write], then consumes bytes from [bytes] until a
/// `CSI <row>;<col> R` response arrives. Returns 0-indexed coordinates.
///
/// If the terminal does not respond within [timeout], returns a result with
/// [CursorPositionResult.row] equal to [fallbackRow] and any bytes received
/// during the wait forwarded as `leftoverBytes`.
///
/// The query writes its own bytes and reads from the provided stream — it
/// does not touch `stdin` or `stdout` directly, which makes it unit-testable
/// without a real terminal.
Future<CursorPositionResult> queryCursorPosition({
  required Stream<List<int>> bytes,
  required void Function(List<int>) write,
  required int fallbackRow,
  Duration timeout = const Duration(milliseconds: 200),
}) async {
  final completer = Completer<CursorPositionResult>();
  final leftover = <int>[];

  // Parser state: looking for ESC [ <digits> ; <digits> R
  // _State values:
  //   0 = scanning for ESC
  //   1 = saw ESC, expect [
  //   2 = saw ESC[, expect first digit of row
  //   3 = in row digits (>=1 already consumed), expect more digits or ;
  //   4 = saw ;, expect first digit of col
  //   5 = in col digits, expect more digits or R
  var state = 0;
  var row = 0;
  var col = 0;
  // Bytes that we tentatively consumed as part of a possible response.
  // If parsing bails out, these are flushed back to [leftover].
  final pending = <int>[];

  void rollback(int trailingByte) {
    leftover.addAll(pending);
    leftover.add(trailingByte);
    pending.clear();
    state = 0;
    row = 0;
    col = 0;
  }

  late StreamSubscription<List<int>> sub;
  sub = bytes.listen(
    (chunk) {
      if (completer.isCompleted) {
        leftover.addAll(chunk);
        return;
      }
      for (final byte in chunk) {
        if (completer.isCompleted) {
          leftover.add(byte);
          continue;
        }
        switch (state) {
          case 0:
            if (byte == 0x1b /* ESC */) {
              pending.add(byte);
              state = 1;
            } else {
              leftover.add(byte);
            }
            break;
          case 1:
            if (byte == 0x5b /* [ */) {
              pending.add(byte);
              state = 2;
            } else {
              rollback(byte);
            }
            break;
          case 2:
            if (byte >= 0x30 && byte <= 0x39) {
              pending.add(byte);
              row = byte - 0x30;
              state = 3;
            } else {
              rollback(byte);
            }
            break;
          case 3:
            if (byte >= 0x30 && byte <= 0x39) {
              pending.add(byte);
              row = row * 10 + (byte - 0x30);
            } else if (byte == 0x3b /* ; */) {
              pending.add(byte);
              state = 4;
            } else {
              rollback(byte);
            }
            break;
          case 4:
            if (byte >= 0x30 && byte <= 0x39) {
              pending.add(byte);
              col = byte - 0x30;
              state = 5;
            } else {
              rollback(byte);
            }
            break;
          case 5:
            if (byte >= 0x30 && byte <= 0x39) {
              pending.add(byte);
              col = col * 10 + (byte - 0x30);
            } else if (byte == 0x52 /* R */) {
              // Response complete.
              completer.complete(CursorPositionResult(
                row: row - 1,
                col: col - 1,
                leftoverBytes: List.unmodifiable(leftover),
              ));
            } else {
              rollback(byte);
            }
            break;
        }
      }
    },
    onError: (error, stack) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        // Stream closed before a response arrived. Treat as timeout-like.
        completer.complete(CursorPositionResult(
          row: fallbackRow,
          col: 0,
          leftoverBytes: List.unmodifiable(leftover),
        ));
      }
    },
  );

  write('\x1b[6n'.codeUnits);

  try {
    final result = await completer.future.timeout(
      timeout,
      onTimeout: () => CursorPositionResult(
        row: fallbackRow,
        col: 0,
        leftoverBytes: List.unmodifiable(leftover),
      ),
    );
    return result;
  } finally {
    await sub.cancel();
  }
}
```

- [ ] **Step 3.4: Run tests to verify they pass**

```bash
cd app && dart test test/tui/cursor_query_test.dart
```

Expected: all 7 tests pass.

- [ ] **Step 3.5: Commit**

```bash
git add app/lib/src/tui/cursor_query.dart app/test/tui/cursor_query_test.dart
git commit -m "Add cursor-position query helper for inline-mode anchor capture"
```

---

## Task 4: Inline-mode lifecycle in `Terminal`

**Files:**
- Modify: `app/lib/src/tui/terminal.dart` (mode-aware `_enter`, `_onResize`, `_restore`, `draw`; stdin routing for cursor query)

This task makes `Terminal` actually behave differently based on `_mode`. It introduces a small stdin-routing layer so the cursor-position query can intercept bytes from stdin without losing them, and threads the captured `_originRow` into every `encodeDiff` call.

Read the entire current `terminal.dart` before starting — this is a refactor of an existing file, not a greenfield write.

- [ ] **Step 4.1: Add stdin routing**

The current `Terminal._enter()` does `parseKeyEvents(stdin)` directly. The cursor-position query needs to consume bytes from stdin before the parser does. We introduce a single subscription to stdin and route bytes either to the parser's controller (normal mode) or to the cursor-query helper (briefly, only during inline-mode entry).

Add these fields to `Terminal`, near the other private state:

```dart
final _stdinController = StreamController<List<int>>();
StreamSubscription<List<int>>? _stdinSub;
int _originRow = 0;
int _originCol = 0;
bool _anchored = false;
```

Strategy for the stdin routing:

- `_stdinController` is a regular (single-subscription) `StreamController<List<int>>`. Single-sub controllers buffer events added before a listener attaches, which is what we need to bridge the gap between the cursor-query helper cancelling its subscription and the key parser subscribing.
- `_stdinSub` is a single subscription to actual `stdin`, forwarding all bytes into `_stdinController` for the whole session.
- During inline-mode entry, `queryCursorPosition` is the sole subscriber to `_stdinController.stream`. After it resolves, it cancels its subscription in its own `finally` block. The key parser then subscribes; bytes received in the gap are queued by the controller and delivered when the parser attaches.

Replace `_enter()` entirely with:

```dart
Future<void> _enter() async {
  _wasEcho = stdin.echoMode;
  _wasLine = stdin.lineMode;
  stdin.echoMode = false;
  stdin.lineMode = false;

  // Pipe stdin into our internal controller. Both the cursor-position query
  // (briefly, during inline-mode entry) and the key parser (for the rest of
  // the session) consume from _stdinController.stream.
  _stdinSub = stdin.listen(
    _stdinController.add,
    onError: _stdinController.addError,
    onDone: _stdinController.close,
  );

  final mode = _mode;
  if (mode is InlineMode) {
    stdout.write(Ansi.hideCursor);
    stdout.write('\n' * mode.rows);
    stdout.write('\x1b[${mode.rows}F'); // CPL: cursor previous line × rows

    final result = await queryCursorPosition(
      bytes: _stdinController.stream,
      write: stdout.add,
      fallbackRow: stdout.terminalLines - mode.rows,
    );
    _originRow = result.row;
    _originCol = 0;
    _anchored = true;
    // Replay leftover bytes so the key parser sees them next.
    if (result.leftoverBytes.isNotEmpty) {
      _stdinController.add(result.leftoverBytes);
    }

    _rows = mode.rows;
    _cols = stdout.terminalColumns;
  } else {
    stdout.write(Ansi.enterAltScreen);
    stdout.write(Ansi.hideCursor);
    stdout.write(Ansi.clearScreen);
    stdout.write(Ansi.moveTo(0, 0));
    _originRow = 0;
    _originCol = 0;
    _anchored = true;
    _rows = stdout.terminalLines;
    _cols = stdout.terminalColumns;
  }

  _front = CellBuffer(_rows, _cols);
  _back = CellBuffer(_rows, _cols);

  // Hook up the key parser to the (now free) _stdinController.stream.
  _keysSub = parseKeyEvents(_stdinController.stream).listen(
    _keysController.add,
    onError: _keysController.addError,
    onDone: _keysController.close,
  );

  // SIGWINCH — Unix only.
  try {
    _subs.add(ProcessSignal.sigwinch.watch().listen((_) => _onResize()));
  } catch (_) {/* not supported on this platform */}
}
```

`_enter()` now returns `Future<void>` (was `void`). Update `_run()` to await it:

```dart
Future<void> _run(FutureOr<void> Function(Terminal) body) async {
  _installSignalHandlers();
  await _enter();
  // ... rest of _run body unchanged
}
```

- [ ] **Step 4.2: Update `draw()` to use the origin**

Find `Terminal.draw` and change the `encodeDiff` call to pass the origin:

```dart
void draw(void Function(CellBuffer buffer) paint) {
  _back.clear();
  paint(_back);
  final diff = encodeDiff(_front, _back, originRow: _originRow, originCol: _originCol);
  if (diff.isNotEmpty) {
    stdout.write(diff);
  }
  _front.copyFrom(_back);
}
```

- [ ] **Step 4.3: Update `_onResize()` for inline mode**

Replace the existing `_onResize` with a mode-aware version:

```dart
void _onResize() {
  final newCols = stdout.terminalColumns;
  final mode = _mode;
  if (mode is InlineMode) {
    if (newCols == _cols) return; // height is fixed; only columns can change
    _cols = newCols;
    _front = CellBuffer(_rows, _cols);
    _back = CellBuffer(_rows, _cols);
    // Do NOT clearScreen — that would wipe scrollback content above the
    // inline region. Callers should repaint in response to the resizes
    // event; the new (empty) _front means every cell will appear changed
    // and be repainted.
  } else {
    final newRows = stdout.terminalLines;
    if (newRows == _rows && newCols == _cols) return;
    _rows = newRows;
    _cols = newCols;
    _front = CellBuffer(_rows, _cols);
    _back = CellBuffer(_rows, _cols);
    stdout.write(Ansi.clearScreen);
    stdout.write(Ansi.moveTo(0, 0));
  }
  _resizeController.add(null);
}
```

- [ ] **Step 4.4: Update `_restore()` for inline mode**

Modify `_restore` to branch on mode (just the ANSI sequence section; the subscription cancellation is unchanged):

```dart
void _restore() {
  if (_restored) return;
  _restored = true;

  for (final sub in _subs) {
    sub.cancel();
  }
  _subs.clear();
  _keysSub?.cancel();
  _stdinSub?.cancel();
  if (!_keysController.isClosed) _keysController.close();
  if (!_resizeController.isClosed) _resizeController.close();
  if (!_stdinController.isClosed) _stdinController.close();

  try {
    stdout.write(Ansi.resetStyle);
    if (_mode is InlineMode) {
      if (_anchored) {
        stdout.write(Ansi.moveTo(_originRow, 0));
        stdout.write('\x1b[J'); // clear to end of screen
      }
      stdout.write(Ansi.showCursor);
      stdout.write('\n'); // next prompt on a fresh line
    } else {
      stdout.write(Ansi.showCursor);
      stdout.write(Ansi.exitAltScreen);
    }
  } catch (_) {/* stdout may already be closed */}

  try {
    stdin.echoMode = _wasEcho;
    stdin.lineMode = _wasLine;
  } catch (_) {}
}
```

- [ ] **Step 4.5: Add the import for cursor_query.dart**

At the top of `terminal.dart`, add:

```dart
import 'cursor_query.dart';
```

- [ ] **Step 4.6: Run analyze and tests**

```bash
cd app && dart analyze lib/src/tui/
cd app && dart test test/tui/
```

Expected: clean analyze, all 77 tests pass (no new tests in this task — Task 1 added 3 encodeDiff tests, Task 3 added 7 cursor_query tests, both contributing to the running total).

- [ ] **Step 4.7: Commit**

```bash
git add app/lib/src/tui/terminal.dart
git commit -m "Wire inline-mode lifecycle into Terminal with cursor-position anchoring"
```

---

## Task 5: Inline demo and final verification

**Files:**
- Create: `app/lib/src/tui/example/inline_demo.dart` (new)

The inline demo serves the same purpose as `step1_demo.dart` does for full-screen mode: a small program that exercises every part of the new code path. Manual interactive verification by the human follows.

- [ ] **Step 5.1: Write the demo**

`app/lib/src/tui/example/inline_demo.dart`:

```dart
import 'dart:async';

import '../tui.dart';

Future<void> main() async {
  // Print some normal CLI output above the inline region first, so we can
  // visually confirm the scrollback is preserved.
  print('--- preceding shell output (this should remain visible above) ---');
  print('flutterware status:');

  await Terminal.run((terminal) async {
    var lastKey = '(none)';
    var keyCount = 0;

    void repaint() {
      terminal.draw((b) {
        final w = terminal.cols;
        _drawBorder(b, 0, 0, terminal.rows, w);
        b.writeAt(1, 2, 'Inline region: $w cols × ${terminal.rows} rows');
        b.writeAt(2, 2, 'Last key: $lastKey (count: $keyCount)');
        b.writeAt(3, 2, '(q to quit)');
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
  }, mode: const InlineMode(rows: 5));

  print('--- inline region exited; back to normal shell output ---');
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

- [ ] **Step 5.2: Verify analyze and tests**

```bash
cd app && dart analyze lib/src/tui/
cd app && dart test test/tui/
```

Expected: clean analyze and 77 tests pass.

- [ ] **Step 5.3: Manual verification (SKIP for subagent run)**

This step requires interactive testing in a real terminal and is for the human reviewer to run AFTER the implementation lands. The subagent should NOT attempt it.

Items the human will verify:

1. **Scrollback preserved.** The "preceding shell output" lines remain visible above the inline region after entry.
2. **Inline rendering.** The bordered status panel appears below the preceding output, 5 rows tall.
3. **Key updates.** Pressing keys updates the panel (`Last key:` field changes, count increments).
4. **Resize width.** Resizing the terminal width reflows the panel border to the new width.
5. **Resize height shrink (acceptable degradation).** Shrinking the terminal height to below the region's start row results in the region painting offscreen until the terminal is grown back. No crash.
6. **Clean exit.** Pressing 'q' (or ctrl-C) clears the inline region; the cursor lands on a fresh line below; the next shell prompt appears there. The "preceding shell output" remains visible in scrollback. The final "back to normal shell output" line prints.
7. **No regression in full-screen.** Run `dart run lib/src/tui/example/step1_demo.dart` to confirm the existing demo still works identically.

- [ ] **Step 5.4: Commit**

```bash
git add app/lib/src/tui/example/inline_demo.dart
git commit -m "Add inline-mode demo program"
```

---

## Done criteria

- All test files pass: `dart test test/tui/` reports green with 77 tests (67 original + 3 from Task 1 encodeDiff offset + 7 from Task 3 cursor_query).
- `dart analyze lib/src/tui/` reports `No issues found!`.
- `dart run lib/src/tui/example/step1_demo.dart` continues to work as before (full-screen).
- `dart run lib/src/tui/example/inline_demo.dart` runs in a real terminal with the behavior described in Task 5.3.
- No new pub dependencies in `app/pubspec.yaml`.
- `Terminal.run(...)` still works with no `mode` argument (default is `FullScreenMode`).

## Self-review notes

- **Spec coverage:** Cursor-query mechanism (Task 3), `TerminalMode` types (Task 2), `encodeDiff` offset (Task 1), mode-aware lifecycle (Task 4), inline demo (Task 5), barrel exports (Task 2). The `_anchored` flag in the crash-safe restore is part of Task 4 step 4.4.
- **Backwards compatibility:** Every existing test, demo, and call site continues to work unchanged. `encodeDiff`'s new params default to 0; `Terminal.run`'s `mode` parameter defaults to `const FullScreenMode()`.
- **Type consistency:** `_originRow` / `_originCol` are `int`; the cursor-query helper returns 0-indexed values; `encodeDiff` adds them to the 0-indexed buffer coords before passing to `Ansi.moveTo` (which 1-indexes for CSI output). The cursor-query helper subtracts 1 from the parsed CSI response (which was 1-indexed) so the stored origin is 0-indexed. No off-by-one across the chain.

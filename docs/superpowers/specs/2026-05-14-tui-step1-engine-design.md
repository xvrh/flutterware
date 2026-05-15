# TUI Step 1 — Engine foundation

**Status:** Draft
**Date:** 2026-05-14
**Scope:** Step 1 of a multi-step initiative to build a Flutter-style TUI framework in Dart for the flutterware CLI.

---

## Context

The flutterware CLI (`app/bin/flutterware.dart`) currently uses a line-oriented logger (vendored AnsiTerminal + StdoutLogger) for its output. The long-term goal is to give it a real full-screen TUI: dashboards, navigation, live state. We're getting there in stages — each stage delivering something demonstrable on its own — and this spec covers stage 1 only.

The end-state architecture mirrors Flutter's three-tree pipeline (Widget → Element → RenderObject), but the render and engine layers are terminal-shaped instead of Skia-shaped. Stages 2–4 build the paint kit, render tree, and widget layer on top of stage 1.

**Stage 1 builds the engine layer in isolation, with a direct procedural paint API.** No layout, no render objects, no widgets. The deliverable is something a stage-2 paint kit, and eventually a stage-4 widget tree, can sit on top of without modification.

## Goals

1. A clean, restartable, crash-safe terminal session: alt-screen entry/exit, raw-mode stdin, restore-on-panic.
2. A `CellBuffer` abstraction (rows × cols of `Cell`) that can be painted into procedurally.
3. Efficient output: diff the back-buffer against the front-buffer, emit ANSI escape sequences only for changed cells.
4. A `KeyEvent` stream from stdin with the common keys (printable chars, arrows, enter, tab, backspace, escape, ctrl-modifiers).
5. Resize-aware: a SIGWINCH handler triggers a redraw with the new dimensions.
6. A demo program that exercises all of the above.

## Non-goals (for stage 1)

- **No layout.** No constraints, no flex, no padding. Painting is by absolute `(row, col)`.
- **No widgets, elements, or render objects.** Those are stages 3 and 4.
- **No mouse input.** Defer to a later stage (Unix mouse escape parsing has its own rabbit holes).
- **No Windows polish.** Mac/Linux first. Code should compile on Windows but quirks (no SIGWINCH, alternative raw-mode dance) are out of scope. Windows handling is a follow-up.
- **No emoji or CJK width handling.** Basic Latin only. The `Cell` struct will carry a `width` field so we can extend later, but the parser/painter treats every rune as 1 cell for now.
- **No animations or ticker.** The engine repaints on demand (input event, resize, explicit caller-driven `markDirty`), not on a frame clock.
- **No theming, colors-by-name, or color profiles.** A `Color` is an explicit 24-bit RGB or one of the 16 ANSI named colors. Terminal capability detection is a follow-up.

## Location

`app/lib/src/tui/` inside the `flutterware_app` package. Reasoning: the consuming CLI lives there, and `flutterware_app` (`publish_to: 'none'`) is the more permissive package for adding dependencies if we ever need them. Promotable later if we want to share.

Source layout:

```
app/lib/src/tui/
  cell.dart          # Cell, Color, TextStyle, CellWidth
  buffer.dart        # CellBuffer + paint helpers
  ansi.dart          # ANSI escape constants + buffer-diff encoder
  input.dart         # raw-stdin → KeyEvent parser
  terminal.dart      # Terminal lifecycle (enter/exit alt-screen, frame loop, signals)
  tui.dart           # barrel file (public exports for stage 1)
app/lib/src/tui/example/
  step1_demo.dart    # the demo described below
```

## Dependencies

**Zero pub dependencies.** Stage 1 uses only `dart:io`, `dart:async`, `dart:convert` (for `utf8`), and `dart:typed_data` (for `Uint8List` in the buffer).

## Components

### `Cell`

```dart
class Cell {
  final int rune;         // Unicode code point; 0x20 = space (the "empty" cell)
  final Color fg;
  final Color bg;
  final int style;        // bitfield: bold, italic, underline, reverse, dim
  final int width;        // 1 for stage 1; reserved for future wide-char support
  const Cell({...});
  static const empty = Cell(rune: 0x20, fg: Color.defaultFg, bg: Color.defaultBg, style: 0, width: 1);
}
```

`Cell` is immutable and value-comparable (override `==` / `hashCode`). Value equality drives the diff in `ansi.dart`.

**Why a fixed `rune: int` and not a `String`:** keeps `Cell` cheap to compare and store. Multi-codepoint sequences (combining marks, emoji families) are out of scope for stage 1.

`Color` is a small sealed-style class: named ANSI (16 colors), 256-color indexed, or 24-bit RGB. `Color.defaultFg`/`Color.defaultBg` map to "reset to terminal default" (ANSI `39` / `49`), distinct from explicit colors.

`TextStyle` is a bitfield constant container: `TextStyle.bold | TextStyle.underline`. Lives in `cell.dart`.

### `CellBuffer`

```dart
class CellBuffer {
  final int rows;
  final int cols;
  CellBuffer(this.rows, this.cols);

  Cell get(int row, int col);
  void set(int row, int col, Cell cell);
  void writeAt(int row, int col, String text, {Color fg, Color bg, int style});
  void fill(Cell cell);
  void fillRect(int row, int col, int rows, int cols, Cell cell);
  void clear();  // fill(Cell.empty)
  void copyFrom(CellBuffer other);  // for back→front after flush

  bool inBounds(int row, int col);  // returns false instead of throwing — callers can clip freely
}
```

**Storage:** a flat `List<Cell>` of length `rows * cols`. Index = `row * cols + col`. Cells are immutable, so storing them directly is fine.

**Out-of-bounds policy:** `set` / `writeAt` silently clip. Painting past the right edge truncates; painting at a negative row/col is a no-op for those cells. This is important: stage 2's paint helpers will routinely paint shapes that extend past the buffer (e.g. a centered box bigger than the terminal) and we want that to degrade gracefully, not throw.

**Resize:** buffers are immutable in size. On SIGWINCH, `Terminal` allocates new back and front buffers at the new dimensions and re-invokes the caller's paint function. No in-place resize.

### `ansi.dart`

Two things live here:

**(1) Escape sequence constants:** `enterAltScreen`, `exitAltScreen`, `hideCursor`, `showCursor`, `clearScreen`, `moveTo(row, col)`, `setForeground(Color)`, `setBackground(Color)`, `setStyle(int)`, `resetStyle`.

**(2) `String encodeDiff(CellBuffer front, CellBuffer back)`:** the heart of the engine's output. Walks both buffers, emits ANSI for each changed cell. Optimizations:

- Skip unchanged cells.
- When the next changed cell is the immediate neighbor of the previous one, omit the cursor-move (the cursor advances naturally after a character write).
- Track current fg/bg/style and only emit `setForeground` / `setBackground` / `setStyle` when they change.
- Group consecutive changed cells in the same row to minimize cursor moves.

**Output is a single `String` built with a `StringBuffer`**, returned to `Terminal` which writes it to `stdout` in one call. Atomic-ish writes minimize tearing.

### `KeyEvent` and `input.dart`

```dart
sealed class KeyEvent { final Set<Modifier> modifiers; ... }
class CharKey extends KeyEvent { final int rune; }
class SpecialKey extends KeyEvent { final SpecialKeyCode code; }
enum SpecialKeyCode { up, down, left, right, enter, tab, backspace, escape, home, end, pageUp, pageDown, delete, ... }
enum Modifier { ctrl, alt, shift }
```

`Stream<KeyEvent> readKeys(Stdin stdin)` consumes raw bytes and emits events.

**Parsing approach:** a small state machine that handles:

- Single byte 0x20–0x7e → `CharKey` (ASCII printable).
- Single byte < 0x20 → ctrl-modifier `CharKey` (0x01 = ctrl-A, 0x03 = ctrl-C, etc.). Special handling for `\r` / `\n` → `SpecialKey(enter)`, `\t` → `tab`, `\x7f` → `backspace`, `\x1b` standalone → `escape`.
- ESC `[` … → CSI sequences (arrow keys `\x1b[A` etc., modifier-prefixed forms like `\x1b[1;5A` for ctrl-up).
- ESC `O` … → SS3 sequences (some terminals send `\x1bOA` for arrows in app mode).
- UTF-8 multi-byte → decode to a single `CharKey` with the full code point.

**Ambiguity handled:** a bare `\x1b` could be the escape key or the start of an unfinished sequence. Resolution: short timer (e.g. 50ms with no further bytes → emit `SpecialKey(escape)`). For stage 1, simpler approach: if no bytes follow within one event-loop tick, treat as escape. Refine later if needed.

**ctrl-C handling:** the input parser emits a `CharKey(rune: 0x03, modifiers: {ctrl})`. SIGINT handling is the `Terminal`'s job, not the input layer's — when raw mode is on, ctrl-C arrives as a byte, not a signal. `Terminal` may translate that byte into a clean shutdown if no listener handles it.

### `Terminal`

The lifecycle owner. Public surface:

```dart
class Terminal {
  static Future<void> run(FutureOr<void> Function(Terminal terminal) body);

  int get rows;
  int get cols;
  Stream<KeyEvent> get keys;
  Stream<void> get resizes;  // emits whenever rows/cols change

  void draw(void Function(CellBuffer buffer) paint);
  Future<void> exit([int code = 0]);
}
```

**`Terminal.run` is the only entry point.** It:

1. Saves the current terminal state (`stdin.echoMode`, `lineMode`).
2. Enters alt-screen (`\x1b[?1049h`), hides cursor (`\x1b[?25l`), enables raw mode.
3. Allocates `front` and `back` buffers at current size.
4. Sets up signal handlers: SIGWINCH (resize), SIGINT/SIGTERM (clean exit), and a top-level `runZonedGuarded` for uncaught errors.
5. Starts the stdin parser, exposed via the `keys` stream.
6. Calls `body(terminal)`, which is expected to subscribe to events and call `draw` as needed. Most stage-1 programs will be a loop reading keys.
7. On any exit path (normal completion, error, signal): restore cursor, exit alt-screen, restore stdin modes, write any pending error to stderr, and exit with the appropriate code.

**`draw(paint)`:**

- Calls `back.clear()` (cheap — single fill).
- Calls user's `paint(back)`.
- Computes `encodeDiff(front, back)` and writes the result to stdout.
- `front.copyFrom(back)`.

This is a pull model: nothing redraws unless the caller asks for it. Stage 1 doesn't impose a frame clock; that comes later when the widget layer needs `setState` → schedule frame.

### Crash safety (the load-bearing piece)

A failed restore leaves the user in alt-screen with no echo and no cursor — they have to `reset(1)` blind. Three layers of defense:

1. **Normal path:** `Terminal.run` uses `try { … } finally { _restore() }`.
2. **Async errors:** the whole body runs inside `runZonedGuarded`; uncaught zone errors trigger `_restore()` before rethrowing.
3. **Signals:** SIGINT, SIGTERM, SIGHUP handlers each call `_restore()` and then `exit(130)` / `exit(143)` / `exit(129)`. These handlers are installed before alt-screen entry.

`_restore()` is idempotent and writes the exit sequences directly to `stdout` (no async, no Dart-side state assumptions — the process may be on its way out).

**Known residual risk:** a `SIGKILL` or a hard crash of the Dart VM still leaves a broken terminal. There's no defense for that on Unix; it's accepted. (Some TUI libs install a shell-level trap via parent process; out of scope.)

## The demo (`step1_demo.dart`)

```dart
import 'dart:async';
import '../tui.dart';

Future<void> main() async {
  await Terminal.run((terminal) async {
    String lastKey = '(none)';
    int keyCount = 0;

    void repaint() {
      terminal.draw((b) {
        b.fill(Cell.empty);
        final w = terminal.cols, h = terminal.rows;
        final boxW = 30, boxH = 5;
        final row = (h - boxH) ~/ 2;
        final col = (w - boxW) ~/ 2;
        _drawBorder(b, row, col, boxH, boxW);
        b.writeAt(row + 1, col + 2, 'Size: $w × $h');
        b.writeAt(row + 2, col + 2, 'Last key: $lastKey ($keyCount)');
        b.writeAt(row + 3, col + 2, '(q to quit)');
      });
    }

    repaint();
    terminal.resizes.listen((_) => repaint());

    await for (final event in terminal.keys) {
      keyCount++;
      lastKey = _describe(event);
      if (event is CharKey && event.rune == 0x71 /* q */) break;
      repaint();
    }
  });
}
```

(Helper `_drawBorder` and `_describe` are inline in the demo file.)

**What this proves:**

- Alt-screen entry/exit and terminal restore (kill the process or press q, terminal should look untouched).
- CellBuffer painting and diff output (no flicker, no full-screen repaints on every key).
- Key event parsing (arrows show up as ↑ ↓ ← →, q quits, ctrl-C exits cleanly).
- Resize handling (resize terminal during run, box re-centers).
- Crash safety (replace `b.writeAt(...)` with `throw 'oops'` — terminal still restores).

## Testing strategy

Unit tests for the parts that don't touch a real terminal:

- **`CellBuffer`** — write/read round-trip, bounds clipping, fill/fillRect.
- **`encodeDiff`** — given two synthetic buffers, assert exact escape sequence output. Several cases: no changes, single cell change, run of changes in one row, changes across rows, fg/bg/style transitions, default-color reset.
- **`input.dart` parser** — feed canned byte sequences (as `Stream<List<int>>`), assert emitted `KeyEvent`s. Cover: ASCII, ctrl-letters, all arrow forms (CSI and SS3), CSI with modifier params, multi-byte UTF-8, the escape-vs-prefix ambiguity.

Integration test for `Terminal` is harder (needs a pty). For stage 1, the demo program serves as manual integration test. Automated pty-driven testing is a follow-up stage if it earns its keep.

## Open questions deferred to later stages

- Mouse input parsing (stage 2 or 3).
- Wide-character / emoji width (stage 4, when `Text` widget arrives).
- Windows terminal quirks (lack of SIGWINCH, ConPTY raw-mode setup).
- Capability detection (does this terminal support 24-bit color? Does it understand a particular CSI sequence?).
- A frame scheduler for animations (stage 4 alongside `Ticker`).

## Success criteria for stage 1

The demo runs, behaves as described, and the codebase is structured such that stage 2 can build a paint kit on top of `CellBuffer` without touching anything in `terminal.dart`, `input.dart`, or `ansi.dart`. If we have to refactor those for stage 2, the boundary was wrong.

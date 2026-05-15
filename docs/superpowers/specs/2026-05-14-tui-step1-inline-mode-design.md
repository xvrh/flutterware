# TUI Step 1 — Inline Mode (extension)

**Status:** Draft
**Date:** 2026-05-14
**Scope:** Add an inline rendering mode to the existing stage 1 engine, so the framework supports both full-screen (alt-screen) and inline (fixed-height region at the cursor) use cases. This is a stage-1 extension, not a separate stage — it ships in the same branch.

**Extends:** [`2026-05-14-tui-step1-engine-design.md`](./2026-05-14-tui-step1-engine-design.md)

---

## Context

The original stage 1 design assumed full-screen, alt-screen rendering. Reviewing it against ratatui's inline mode (`ratatui::Terminal::with_options(Viewport::Inline(N))`), inline mode is a strictly more useful default for many CLI scenarios — including the immediate flutterware use case where the long-running CLI in `app/bin/flutterware.dart` wants a "dashboard at the bottom of the terminal while normal output continues to scroll above" UX rather than full-screen takeover.

The engine layer is already mode-agnostic. `CellBuffer`, `encodeDiff`, and `parseKeyEvents` don't care whether their output covers the whole screen or a small region. The full-screen assumption lives entirely inside `Terminal`. This extension makes the mode an explicit parameter.

## Goals

1. A `TerminalMode` API on `Terminal.run` that supports both `fullScreen()` (current behavior, default) and `inline({required int rows})`.
2. Inline mode renders an N-row region anchored at the cursor's position when `Terminal.run` started. Normal terminal scrollback above is preserved on exit.
3. `encodeDiff` becomes coordinate-origin-aware so the same diff pipeline drives both modes.
4. A working inline demo (`inline_demo.dart`) demonstrating the mode.

## Non-goals (for this round)

- **No `print_above` / `insert_before`** — i.e. no API for "scroll log lines into the scrollback above the inline region while the region stays put". This is the natural next feature after inline-mode lands, but it's out of scope here. The architecture must not preclude it.
- **No relative-move rendering.** Inline mode still uses absolute `\x1b[r;cH` positioning, just offset by the region's anchor row. This is simpler and works for stage 1.5; if `print_above` lands later and needs relative anchoring, we'll revisit at that time.
- **No height-on-resize.** If the terminal shrinks below the inline region's reserved height, the buffer keeps its declared height and painting clips naturally (CellBuffer already handles OOB writes). Width does adjust on SIGWINCH.
- **No "anchor moves with output above".** Once the inline region is anchored at startup, its absolute row stays put. If the user prints to stdout from outside the TUI in a way that scrolls the terminal, the region will drift. This is acceptable for stage 1.5 because the inline TUI body owns the output channel. `print_above` (deferred) is what would fix this.
- **No automatic "follow the cursor" mode.** Inline starts at the cursor's current position at `Terminal.run` entry, and that position is captured once. There's no support for repositioning.

## Architecture

### `TerminalMode` sealed class

```dart
sealed class TerminalMode {
  const TerminalMode();
  factory TerminalMode.fullScreen() = FullScreenMode;
  factory TerminalMode.inline({required int rows}) = InlineMode;
}
final class FullScreenMode extends TerminalMode {
  const FullScreenMode();
}
final class InlineMode extends TerminalMode {
  final int rows;
  const InlineMode({required this.rows}) : assert(rows > 0);
}
```

Public surface stays minimal: callers pass `TerminalMode.fullScreen()` (or omit for the default) or `TerminalMode.inline(rows: 8)`. The sealed hierarchy keeps the door open if we ever need polymorphism, but stage 1.5 just switches on `mode` directly in `Terminal`.

### `Terminal.run` signature change

```dart
static Future<void> run(
  FutureOr<void> Function(Terminal terminal) body, {
  TerminalMode mode = const FullScreenMode(),
});
```

Default value is `const FullScreenMode()` so all existing call sites keep working unchanged. The `step1_demo.dart` doesn't change.

### `encodeDiff` signature change

```dart
String encodeDiff(
  CellBuffer front,
  CellBuffer back, {
  int originRow = 0,
  int originCol = 0,
});
```

Adds two named parameters defaulting to 0. Inside the function, each `Ansi.moveTo(r, c)` call becomes `Ansi.moveTo(r + originRow, c + originCol)`. That's the only line that changes; everything else (cursor-advance tracking, SGR coalescing) is unchanged.

### `Terminal` internal state additions

```dart
class Terminal {
  final TerminalMode _mode;
  int _originRow = 0;     // absolute row of buffer (0, 0)
  int _originCol = 0;     // absolute col of buffer (0, 0)
  // existing _front, _back, _rows, _cols, ...
}
```

For full-screen mode, `_originRow`/`_originCol` stay 0 and the buffer covers the whole viewport (existing behavior). For inline mode, `_originRow` is captured at entry from where the cursor was, and `_cols` mirrors `stdout.terminalColumns` while `_rows` is fixed to `InlineMode.rows`.

### Computing the inline region's anchor row

`encodeDiff` emits absolute `\x1b[<r>;<c>H` moves with the `originRow`/`originCol` offset added. So `Terminal` needs to know the absolute row of the inline region's top-left corner. We capture that row once at entry, via a cursor-position query:

1. Reserve vertical space: print `'\n' * rows` (the terminal scrolls the viewport up if there's no room below the cursor — exactly what we want).
2. Move cursor back: `\x1b[<rows>F` (CPL — cursor previous line) brings the cursor to column 0 of what will become the region's top row.
3. Briefly pause the key parser's stdin listener (or attach an intercepting filter).
4. Write `\x1b[6n` (DSR — device status report). The terminal responds on stdin with `\x1b[<r>;<c>R`.
5. Read bytes from stdin until we get the response. Parse `<r>` as the 1-indexed absolute row; store `_originRow = r - 1` (0-indexed) and `_originCol = 0`.
6. Resume / un-filter the key parser. Any non-DSR bytes received during step 5 (e.g. keystrokes the user happened to type during entry) are forwarded to the parser as if they'd arrived normally.

If the terminal doesn't respond within ~200ms (rare — basically only headless test terminals), we fall back to `_originRow = stdout.terminalLines - rows` (best-guess). The fallback is documented as imperfect; an inline TUI in a non-responsive terminal will paint at the bottom of the viewport and may behave oddly if the viewport doesn't auto-scroll.

**Why not use DECSC/DECRC (cursor save/restore)?** They'd avoid needing the absolute row — the terminal remembers the anchor for us. But `encodeDiff` emits absolute `CSI r;cH` positioning, so the cursor's "current" position doesn't help. We'd have to either rewrite the encoder to use relative moves (out of scope; see Non-goals) or query the absolute row anyway. Querying once at entry and offsetting all moves is the simpler path.

Implementation: the query/parse logic lives in a new private helper inside `terminal.dart` (estimate ~40 lines including the parser-pause/intercept dance). It runs exactly once, during `_enter()` in inline mode, and isn't needed for full-screen mode.

### Lifecycle differences

```
                       FullScreenMode              InlineMode
─────────────────────────────────────────────────────────────
_enter() writes        enterAltScreen              hideCursor
                       hideCursor                  '\n' * rows  (reserve space)
                       clearScreen                 CSI <rows> F (back to top)
                       moveTo(0, 0)                (then query cursor pos for
                                                    _originRow — see above)

buffer size            cols × terminalLines        cols × InlineMode.rows
_originRow             0                           captured at entry
_originCol             0                           0
draw() origin          (0, 0) passed to            (_originRow, 0) passed to
                       encodeDiff                  encodeDiff

_onResize()            reallocate cols × lines     reallocate cols × InlineMode.rows
                       full clearScreen            do NOT re-anchor; just resize
                                                   buffers and signal the user

_restore() writes      resetStyle                  resetStyle
                       showCursor                  Ansi.moveTo(_originRow, 0)
                       exitAltScreen               CSI J  (clear to end of screen)
                                                   showCursor
                                                   '\n'  (move cursor below region
                                                   so next shell prompt starts on
                                                   a fresh line)
```

### SIGWINCH in inline mode

When the terminal is resized:

- `terminalColumns` may change → reallocate `_front` and `_back` at `(InlineMode.rows, newCols)`.
- `terminalLines` may change → could push the inline region off-screen if the terminal shrinks below `_originRow + rows`. In stage 1.5, we accept this: the region stays at the captured `_originRow`, and if it's now off-screen, paint output writes to invisible cells. The next time the terminal grows back, the region reappears.

A more robust approach (re-anchoring on resize) is deferred. It's doable but adds complexity around "the cursor isn't at the anchor anymore after a resize-induced scroll".

### Crash-safe restore in inline mode

The three-layer safety from full-screen mode (try/finally, runZonedGuarded, signal handlers) carries over unchanged. The `_restore()` sequence for inline mode:

1. `\x1b[0m` — reset style.
2. `Ansi.moveTo(_originRow, 0)` — position cursor at the anchor (absolute).
3. `\x1b[J` — clear from cursor to end of screen (wipes the region and any output below it within the viewport).
4. `\x1b[?25h` — show cursor.
5. `\n` — move cursor one line below so the next shell prompt starts fresh.
6. Restore stdin echo/line modes.

If the process crashes hard before `_originRow` was captured (e.g. uncaught error inside the cursor-position query helper), `_originRow` defaults to 0 and step 2 would move the cursor to absolute row 0. To avoid trashing the user's shell scrollback in that early-crash case, `_restore()` guards on a separate `_anchored` flag set only after the cursor query succeeds (or its fallback runs). If `!_anchored`, the inline-mode restore skips steps 2 and 3 entirely and just writes the style reset, cursor show, and a newline.

## Coordinate translation summary

The mental model:

- The user's `draw((buf) => ...)` paints into `buf`, whose coordinate origin `(0, 0)` is the top-left of the inline region.
- The `Terminal` adds `(_originRow, _originCol)` to every absolute move emitted by `encodeDiff`.
- For full-screen mode, `(_originRow, _originCol)` is `(0, 0)` and the behavior is identical to today.

## Public API summary

```dart
// Existing, unchanged behavior:
await Terminal.run((t) async { ... });
await Terminal.run((t) async { ... }, mode: TerminalMode.fullScreen());

// New:
await Terminal.run((t) async {
  t.draw((b) {
    b.writeAt(0, 0, 'Status: running');
    b.writeAt(1, 0, 'Tests: 42 passing');
  });
  await for (final key in t.keys) { /* ... */ }
}, mode: TerminalMode.inline(rows: 5));
```

## Files touched

- **Modify** `app/lib/src/tui/ansi.dart` — add `originRow`/`originCol` to `encodeDiff`. Existing tests still pass (default 0/0 = unchanged behavior). Add 1-2 new tests for the offset case.
- **Modify** `app/lib/src/tui/terminal.dart` — `TerminalMode` sealed class, optional `mode` parameter on `Terminal.run`, mode-aware `_enter` / `_onResize` / `_restore` / `draw`. Add cursor-position query helper. The `_keysController` and `parseKeyEvents` wiring needs a "pause/resume + intercept" capability for the position query.
- **Modify** `app/lib/src/tui/tui.dart` — export the new `TerminalMode` types.
- **Create** `app/lib/src/tui/example/inline_demo.dart` — demonstrates inline mode.
- **Modify** `app/test/tui/ansi_test.dart` — 1-2 tests for the `originRow`/`originCol` offset behavior.

Estimated total: ~250-350 lines of additions (largely in terminal.dart) plus ~50 lines of tests.

## Success criteria

1. All existing tests still pass without modification (default `mode` keeps behavior identical).
2. New offset tests for `encodeDiff` pass.
3. `inline_demo.dart` runs in a real terminal:
   - Shows a small status panel at the cursor.
   - Normal shell output is preserved above on entry.
   - Pressing keys updates the panel.
   - Pressing `q` exits, the region is cleared, and the next shell prompt appears below where the region was.
   - Resizing the terminal width reflows the panel; resizing the height doesn't shift the anchor (acceptable for stage 1.5).
4. The full-screen demo (`step1_demo.dart`) still works identically.

## Open questions deferred

- `print_above`/`insert_before` capability.
- Re-anchoring on terminal-height shrink.
- Headless test mode (a `Terminal` variant that paints into an in-memory sink for golden-file testing).
- Multiplexer (tmux/screen) quirks around `\x1b[6n` cursor-position queries.

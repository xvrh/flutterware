# TUI Step 1 — `print_above` (extension)

**Status:** Draft
**Date:** 2026-05-15
**Scope:** Add a `print_above` capability to the inline rendering mode: emit
log/output lines that scroll into the terminal scrollback **above** the inline
region while the region itself stays anchored and intact. This is the feature
deliberately deferred from the inline-mode work.

**Extends:** [`2026-05-14-tui-step1-inline-mode-design.md`](./2026-05-14-tui-step1-inline-mode-design.md)

---

## Context

Inline mode renders a fixed-height region anchored at the cursor's position
when `Terminal.run` starts. The inline-mode spec explicitly scoped out
`print_above` (the ratatui `insert_before` capability) and listed it as the
natural next feature.

Without it, an inline TUI owns the terminal output channel exclusively: any
`print` to stdout from outside the TUI scrolls the terminal and the region's
absolute anchor (`_originRow`) drifts out of sync. `print_above` gives the TUI
a sanctioned way to emit scrollback content — log lines, build output, command
results — so that a status panel and a streaming log can coexist. This is the
concrete flutterware-CLI use case: a live status/progress panel pinned at the
bottom, with normal build log flowing into scrollback above it.

## Goals

1. A `Terminal.printAbove` primitive that inserts N painted rows into the
   scrollback above the inline region.
2. A `Terminal.printTextAbove` convenience for the common plain-text log-line
   case.
3. The inline region stays visually intact and correctly anchored after a
   `printAbove` call — `_originRow` is recomputed and the region is redrawn.
4. A demo (`print_above_demo.dart`) showing a streaming build-log dashboard.

## Non-goals (for this round)

- **No line wrapping.** Lines wider than the terminal are clipped, consistent
  with `CellBuffer`'s existing out-of-bounds clipping. Wrapping is deferred.
- **No full-screen support.** `print_above` is meaningless in full-screen mode
  (the alt-screen buffer has no scrollback). Calling it in full-screen mode
  throws `StateError`.
- **No widget rendering.** The primitive takes a `CellBuffer`-paint callback —
  the same model as `draw()` — which is forward-compatible with a future
  widget layer (a widget renders into a buffer), but no widget machinery is
  built here.
- **No scroll-region (`DECSTBM`) approach.** See "Mechanism" below for why.
- **No batching/coalescing.** Each `printAbove` call is one self-contained
  scroll-and-redraw. Callers that want to emit many lines at once pass them in
  a single call.

## Mechanism

### Why natural-scroll, not scroll-region

Two ways to get lines into the scrollback above a fixed region:

- **Scroll-region (`DECSTBM`, `\x1b[t;br`)** — define a scrolling region above
  the inline region and scroll within it. **Rejected:** on most terminals,
  lines that scroll *out* of a `DECSTBM` region are discarded rather than
  pushed to scrollback — even when the region's top is screen row 1. That
  defeats the purpose of `print_above`.
- **Natural-scroll** — move the cursor to the region's top row, write the new
  lines each followed by `\n`, and let the terminal scroll on its own. A `\n`
  emitted on the last row of the screen performs a real scroll: the top line
  enters the terminal's scrollback. This is the ratatui `insert_before`
  technique and the approach used here.

### Anchor drift

The inline region occupies absolute rows `_originRow .. _originRow + _rows - 1`.
When `printAbove` writes N new lines starting at `_originRow`, the region is
pushed downward. Two sub-cases, unified by one formula:

- If there is room below the region, the region simply moves down within the
  viewport; nothing enters scrollback.
- Once the region reaches the bottom of the screen, further `\n`s scroll the
  screen — old top lines enter scrollback and the region stays pinned at the
  bottom.

Unified recomputation, evaluated against a freshly-read terminal height:

```
_originRow = min(_originRow + N, terminalLines - _rows)
```

`terminalLines` is read fresh inside `printAbove` so a resize that happened
since the last frame is accounted for. If `terminalLines < _rows` (terminal
shorter than the region) the result clamps via `max(0, ...)`; the region
paints clipped, consistent with the inline-mode height non-goal.

### Algorithm

`printAbove(int height, void Function(CellBuffer) paint)`:

1. If the mode is not `InlineMode`, throw `StateError`.
2. Allocate a temporary `CellBuffer(height, _cols)`; run `paint` on it.
3. Emit the cursor move to absolute `(_originRow, 0)`.
4. For each of the `height` rows of the temp buffer: emit that row's encoded
   SGR + characters via `encodeRow`, then `\x1b[K` (erase to end of line, so a
   short line leaves no stale cells), then `\n`. The `\n`s drive the scroll.
5. Recompute `_originRow` with the formula above.
6. Emit a move to the new `(_originRow, 0)` followed by `\x1b[J` (erase from
   cursor to end of screen), wiping the now-stale region area.
7. Reset `_front` to a blank buffer of the current size, replay the stored
   last-paint callback into `_back`, compute `encodeDiff` at the new origin,
   write it, and copy `_back` into `_front`. The region reappears intact at its
   new anchor.

If no `draw()` has happened yet (`_lastPaint == null`), step 7 still runs with
a no-op paint: the region area is left blank, which is correct.

### Why `encodeDiff` cannot be reused for step 4

`encodeDiff` emits absolute `\x1b[r;cH` cursor moves and never emits `\n`.
Absolute positioning does not scroll the terminal, so it cannot push anything
into scrollback. Step 4 needs explicit `\n`s. A small dedicated `encodeRow`
helper encodes a single buffer row (left-to-right SGR-coalesced run of cells,
trailing blank cells dropped since `\x1b[K` clears them).

## API

Both methods are added to the existing `Terminal` class; no new exported
types.

```dart
/// Insert [height] rows of content into the terminal scrollback immediately
/// above the inline region, then redraw the region at its new anchor.
///
/// [paint] receives a fresh [height]×cols [CellBuffer] addressed from (0, 0).
/// Content wider than the terminal is clipped; lines are not wrapped.
///
/// Only valid in inline mode. Throws [StateError] in full-screen mode.
void printAbove(int height, void Function(CellBuffer buffer) paint);

/// Convenience over [printAbove] for plain text. [text] is split on '\n';
/// each line becomes one scrollback row painted with the given style.
///
/// Only valid in inline mode. Throws [StateError] in full-screen mode.
void printTextAbove(
  String text, {
  Color fg = Color.defaultFg,
  Color bg = Color.defaultBg,
  int style = 0,
});
```

`printTextAbove` computes `height` from the split line count and delegates to
`printAbove`.

## `Terminal` internal state additions

```dart
class Terminal {
  // existing fields ...
  void Function(CellBuffer)? _lastPaint; // most recent draw() callback
}
```

`draw()` stores its callback into `_lastPaint` before painting, so `printAbove`
can replay it to redraw the region. This is the only new state.

## `encodeRow` helper

Lives in `ansi.dart` next to `encodeDiff`.

```dart
/// Encode a single [CellBuffer] row as SGR + characters, starting at the
/// current cursor position (no leading cursor move). Trailing default/blank
/// cells are omitted — the caller is expected to follow with `\x1b[K`.
String encodeRow(CellBuffer row, {int rowIndex = 0});
```

It walks one row, coalescing foreground/background/style SGR transitions the
same way `encodeDiff` does, and trims trailing blank cells.

## Files touched

- **Modify** `app/lib/src/tui/terminal.dart` — `printAbove`, `printTextAbove`,
  `_lastPaint` field, `_lastPaint` assignment in `draw()`.
- **Modify** `app/lib/src/tui/ansi.dart` — add `encodeRow`.
- **Create** `app/examples/tui/print_above_demo.dart` — streaming build-log
  dashboard demo.
- **Modify** `app/test/tui/ansi_test.dart` — tests for `encodeRow` (SGR
  coalescing, trailing-blank trimming, styled cells).
- **Modify** `app/test/tui/terminal_test.dart` (or create) — anchor-drift
  arithmetic and the full-screen `StateError`. If `Terminal` is not unit-
  testable without a tty, cover the drift formula via an extracted pure
  helper.
- **Modify** `docs/superpowers/tui-roadmap.md` — mark `print_above` done.

## Success criteria

1. All existing tests still pass.
2. `encodeRow` tests pass (plain row, styled row, trailing-blank trimming).
3. The anchor-drift formula is covered by a test.
4. `printAbove` / `printTextAbove` throw `StateError` in full-screen mode.
5. `print_above_demo.dart` runs in a real terminal:
   - A status panel stays pinned as an inline region.
   - Log lines stream into the scrollback above it and remain visible in
     scrollback when scrolled back.
   - The status panel is never corrupted by the streaming output.
   - Pressing `q` exits cleanly; the next shell prompt starts below the
     region.

## Open questions deferred

- Line wrapping for content wider than the terminal.
- Re-anchoring `print_above` interaction with terminal-height shrink mid-run.
- A headless/in-memory `Terminal` for golden-file testing of `printAbove`.
- Widget-layer integration (a `printAbove(Widget)` overload) — arrives with
  the widget layer in stage 4.

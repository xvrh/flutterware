# TUI framework — roadmap

This document tracks the staged plan for building a Flutter-style terminal UI
framework in `app/lib/src/tui/`, and records the design decisions made along
the way. It is the index over the per-stage specs and plans in
`docs/superpowers/specs/` and `docs/superpowers/plans/`.

## The idea

Flutter's genius is its reactive pipeline — the Widget tree (immutable config),
the Element tree (mounted instances + state), and the RenderObject tree (layout
+ paint). That machinery is **rendering-backend agnostic**: it doesn't care
whether the final output is pixels via Skia or characters via ANSI escape
codes. The plan is to keep that upper architecture and replace the
pixel-shaped render/engine layers with terminal-shaped ones.

The end goal is a full-screen TUI; the immediate, concrete consumer is the
flutterware CLI in `app/`, which today uses line-oriented logger output and
could use a richer status/dashboard UI.

## Stages

| Stage | What it delivers | Status |
|-------|------------------|--------|
| **1. Engine** | Terminal lifecycle, `CellBuffer`, diff-to-ANSI, key parsing, crash-safe restore | ✅ Done |
| **1.5 Inline mode** | A fixed-height region anchored at the cursor, alongside full-screen | ✅ Done |
| **`print_above`** | Print log lines into scrollback above an inline region | ✅ Done |
| **2. Paint kit** | `CellRect`/`CellSize` geometry + procedural paint helpers (text, border, fill) | ✅ Done |
| **3. Render tree** | `RenderObject`/`RenderBox`, `BoxConstraints`, `Row`/`Column`/`Padding` | ✅ Done |
| **4. Widget layer** | `Widget`/`Element`, `StatelessWidget`/`StatefulWidget`, `setState` | ⬜ Not started |
| **5. Integration** | Replace the flutterware CLI startup UX with a real TUI screen | ⬜ Not started |

Each stage is independently useful: after stage 1 you have a working terminal
library; after stage 3 you have a layout engine; after stage 4 you have the
framework.

### Detailed docs per stage

- Stage 1 — [spec](specs/2026-05-14-tui-step1-engine-design.md) ·
  [plan](plans/2026-05-14-tui-step1-engine.md)
- Stage 1.5 inline mode — [spec](specs/2026-05-14-tui-step1-inline-mode-design.md) ·
  [plan](plans/2026-05-14-tui-step1-inline-mode.md)
- `print_above` — [spec](specs/2026-05-15-tui-print-above-design.md) ·
  [plan](plans/2026-05-15-tui-print-above.md)
- Stage 2 — [spec](specs/2026-05-15-tui-stage2-paint-kit-design.md) ·
  [plan](plans/2026-05-15-tui-stage2-paint-kit.md)
- Stage 3 — [spec](specs/2026-05-15-tui-stage3-render-tree-design.md) ·
  [plan](plans/2026-05-15-tui-stage3-render-tree.md)

## Key design decisions

Recorded so future work doesn't re-litigate them:

- **Cells, not pixels.** Layout reuses Flutter's box protocol (`BoxConstraints`,
  parent passes constraints down, child returns a size) — the only change is
  the unit: terminal cells instead of logical pixels. Text layout becomes
  trivial because a monospace cell is one grapheme.
- **Shared-buffer painting.** Render objects paint into one shared `CellBuffer`
  with an offset, like Skia's `Canvas` — not by each returning its own buffer.
  Avoids per-frame allocation.
- **Always double-buffer + diff.** `encodeDiff` compares the just-painted back
  buffer to the on-screen front buffer and emits ANSI only for changed cells.
  Skipping this would mean visible flicker and ~2 KB of escapes per frame.
- **Reimplement the engine; transcribe the framework.** Stages 1–3 are written
  from scratch — Flutter's render layer is pixel/Skia-shaped, there's nothing
  to copy. Stage 4 is where transcribing `package:flutter`'s
  `framework.dart` pays off: the Widget/Element machinery (rebuild scheduling,
  `GlobalKey`, `InheritedWidget`) is backend-agnostic and full of hard-won edge
  cases.
- **Location: `app/lib/src/tui/`.** Inside the `flutterware_app` package
  (`publish_to: none`), because the consuming CLI lives there and that package
  tolerates new dependencies if ever needed. Promotable to a standalone package
  later if it earns it.
- **Zero pub dependencies.** The whole engine is `dart:io` + `dart:async`. A
  goal worth preserving through later stages where practical.
- **Two terminal modes.** Full-screen (alt-screen takeover) and inline (a
  fixed-height region at the cursor). `TerminalMode` is a sealed class so the
  set is closed and exhaustively switchable.

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

## Known limitations carried forward

These are accepted in stage 1 and should be revisited as later stages land:

- Non-tty stdin throws `StdinException` on startup (before alt-screen entry —
  no terminal damage). A try/catch with a fallback would fix it.
- A microsecond-wide window during inline-mode entry where a keystroke could be
  dropped, between the cursor-query subscription cancelling and the key parser
  subscribing.
- No re-anchoring when the terminal height shrinks below the inline region.
- No wide-character / emoji width handling — deferred to stage 4, when the
  `Text` widget arrives. The `Cell.width` field is reserved for it.
- Windows: signal-driven features (resize via SIGWINCH) are Unix-only.

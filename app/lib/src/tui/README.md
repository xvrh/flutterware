# TUI engine

A terminal UI engine in pure Dart — the foundation for a Flutter-style
declarative UI that renders to a character grid instead of pixels.

The long-term goal mirrors Flutter's three-tree pipeline
(Widget → Element → RenderObject), but the render and engine layers are
terminal-shaped rather than Skia-shaped. **This package is currently stage 1:
the engine layer only.** There are no widgets, layout, or render objects yet —
see [the roadmap](../../../../docs/superpowers/tui-roadmap.md) for the staged
plan.

## What's here

| File | Responsibility |
|------|----------------|
| `cell.dart` | `Cell`, `Color` (default / 16 ANSI / 24-bit RGB), `TextStyle` bitfield |
| `buffer.dart` | `CellBuffer` — a fixed-size, clipping, row-major grid of cells |
| `ansi.dart` | ANSI escape constants, SGR encoders, and `encodeDiff` |
| `input.dart` | `parseKeyEvents` — raw stdin bytes → `KeyEvent` stream |
| `cursor_query.dart` | Cursor-position query (`ESC[6n`) used to anchor inline mode |
| `terminal.dart` | `Terminal` — lifecycle, signal handling, double-buffered painting |
| `tui.dart` | Barrel file: the public API surface |

Examples live in `app/examples/tui/`.

## Quick start

```dart
import 'package:flutterware_app/src/tui/tui.dart';

Future<void> main() async {
  await Terminal.run((terminal) async {
    terminal.draw((buffer) {
      buffer.writeAt(0, 0, 'Hello, terminal!', style: TextStyle.bold);
      buffer.writeAt(1, 0, 'Press q to quit.', fg: Color.brightBlack);
    });

    await for (final event in terminal.keys) {
      if (event is CharKey && event.rune == 0x71 /* 'q' */) break;
    }
  });
}
```

`Terminal.run` enters a terminal session, runs your body, and restores the
terminal on exit — including on uncaught errors and on SIGINT/SIGTERM/SIGHUP.

- **`terminal.draw((buffer) { ... })`** — paint a frame. You always paint the
  whole frame; the engine diffs it against the previous frame and emits only
  the ANSI escapes needed for the changed cells.
- **`terminal.keys`** — a broadcast stream of parsed `KeyEvent`s.
- **`terminal.resizes`** — emits when the terminal is resized. You are
  responsible for calling `draw` again in response.

## Rendering modes

```dart
// Full-screen (default): takes over the terminal via the alt-screen buffer.
await Terminal.run(body);
await Terminal.run(body, mode: TerminalMode.fullScreen());

// Inline: a fixed-height region anchored at the cursor's start position.
// Normal scrollback above the region is preserved — good for status panels
// and progress UIs that coexist with regular CLI output.
await Terminal.run(body, mode: TerminalMode.inline(rows: 5));
```

## How painting works

`CellBuffer` is a grid of immutable `Cell`s addressed by `(row, col)`. Writes
that fall outside the buffer are silently clipped, so painting code never has
to bounds-check.

`Terminal` keeps two buffers — `front` (what is on screen) and `back` (what you
just painted). `encodeDiff` walks both and emits ANSI escape sequences only for
cells that changed, coalescing cursor moves and SGR (color/style) changes. This
keeps redraws cheap and flicker-free even when only a few cells change between
frames.

## Current limitations

Stage 1 is intentionally scoped. Not yet supported:

- No layout, widgets, or render objects (stages 2–4).
- No mouse input.
- No wide-character / emoji width handling — every cell is one column.
- Windows: compiles and runs, but signal-driven features (resize) are
  Unix-only for now.
- Non-tty stdin (e.g. piped input) throws on startup, before the alt-screen is
  entered — no terminal damage, but not graceful.

See [the roadmap](../../../../docs/superpowers/tui-roadmap.md) for what comes
next and the detailed design specs in `docs/superpowers/specs/`.

# TUI engine

A terminal UI engine in pure Dart — the foundation for a Flutter-style
declarative UI that renders to a character grid instead of pixels.

The long-term goal mirrors Flutter's three-tree pipeline
(Widget → Element → RenderObject), but the render and engine layers are
terminal-shaped rather than Skia-shaped. **This package is currently at
stage 4.5a: engine, paint kit, render tree, widget layer, and focus system.** See
[the roadmap](../../../../docs/superpowers/tui-roadmap.md) for the staged
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
| `geometry.dart` | `CellOffset`, `CellSize`, `CellRect` — integer-cell geometry |
| `painter.dart` | `Painter` — offset+clip drawing surface; `BorderChars`, text helpers |
| `text_wrap.dart` | `wrapText` — pure word-wrapping |
| `render/` | The render tree: `RenderObject`/`RenderBox`, `BoxConstraints`, `RenderFlex`/`RenderPadding`/`RenderText`/`RenderDecoratedBox`/`RenderConstrainedBox`, `RenderTuiView` |
| `widgets/` | The widget layer: `Widget`/`Element`/`State`, `BuildOwner`, `InheritedWidget`, concrete widgets (`Text`, `Row`, `Column`, …), `TuiBinding`, and `runApp` |
| `widgets/focus_manager.dart` | `FocusNode`, `FocusScopeNode`, `FocusManager`, `KeyEventResult` — the focus tree and key-event routing |
| `widgets/focus_scope.dart` | `Focus` and `FocusScope` widgets — declarative wrappers around focus nodes |
| `widgets/focus_traversal.dart` | `FocusTraversalPolicy`, `ReadingOrderTraversalPolicy`, `DirectionalFocusTraversalPolicy`, `FocusTraversalGroup` — Tab/Shift-Tab and arrow-key traversal |

Examples live in `app/examples/tui/`. The richest is `widget_showcase.dart`, an animated five-scene showcase reel (plasma, starfield, charts, layout lab, typography) with keyboard navigation — run it with `cd app && dart run examples/tui/widget_showcase.dart`.

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

## Widgets quick start

```dart
import 'dart:async';
import 'package:flutterware_app/src/tui/tui.dart';

class Counter extends StatefulWidget {
  const Counter({super.key});
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  var _count = 0;
  StreamSubscription<KeyEvent>? _keySub;
  var _subscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_subscribed) {
      _subscribed = true;
      _keySub = TerminalApp.of(context).keys.listen((event) {
        if (event is CharKey && event.rune == 0x71 /* 'q' */) {
          TerminalApp.of(context).exit();
        } else {
          setState(() => _count++);
        }
      });
    }
  }

  @override
  void dispose() {
    _keySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('Count: $_count'),
        Text("(press any key to increment, 'q' to quit)"),
      ]);
}

Future<void> main() => runApp(const Counter());
```

`runApp` opens a full-screen terminal session, mounts the widget tree, and
drives frames. Each call to `setState` schedules a microtask-coalesced rebuild.
`TerminalApp.of(context)` gives any descendant access to the key stream, the
current terminal size, and an `exit` hook.

## Current limitations

Stage 4.5a is intentionally scoped. Not yet supported:

- Repaint is whole-tree: with no layer model, `markNeedsPaint` repaints
  everything. Re-layout *is* localized to relayout boundaries.
- No GlobalKey or animation/tickers — deferred to later stages.
- The focus system (focus tree, traversal, key routing) is implemented as of
  Stage 4.5a. The declarative `Actions`/`Intents`/`Shortcuts` key-binding layer
  is deferred to Stage 4.5b.
- No render object clips its children. A child larger than its slot (e.g. a
  `FlexFit.loose` child, or content overflowing a panel) will bleed; a parent
  must opt into `Painter.clip` itself. A `RenderClipRect` is left for a later
  stage.
- No mouse input.
- No wide-character / emoji width handling — every cell is one column.
- Windows: compiles and runs, but signal-driven features (resize) are
  Unix-only for now.
- Non-tty stdin (e.g. piped input) throws on startup, before the alt-screen is
  entered — no terminal damage, but not graceful.

See [the roadmap](../../../../docs/superpowers/tui-roadmap.md) for what comes
next and the detailed design specs in `docs/superpowers/specs/`.

# Embedder

Experimental Flutter engine embedder, part of `flutterware_app`.

**Step 3b (current):** an out-of-process Flutter-engine guest renders an
animated, interactive scene with the **Metal renderer**, directly into shared
`IOSurface`-backed Metal textures — a zero-copy path with no per-frame copy.
The flutterware desktop GUI displays it live in an external `Texture`. The
panel is resizable and forwards pointer, keyboard, scroll-wheel and trackpad
pan/zoom input (`input_region.dart`).

## Run the GUI harness

```sh
cd app && flutter run -t lib/main_embedder_dev.dart -d macos \
  --dart-define=FLUTTERWARE_APP_ROOT="$(pwd)" \
  --dart-define=FLUTTER_SDK_ROOT="$(cd "$(dirname "$(which flutter)")/.." && pwd)"
```

This builds and spawns the guest, then shows its live output. A macOS app
launched by `flutter run` has no usable environment or working directory, so
the `app/` package root and Flutter SDK root are passed via `--dart-define`.

## Capturing a panel that shows a guest

`EmbeddedEngine.capture` asks the live guest for its next composited frame, as
a raw BGRA file `decodeRawFrame` reads. It exists because **the guest is not in
the host's layer tree**: `Texture(textureId:)` is resolved by the platform
compositor at raster time, so `RenderRepaintBoundary.toImage()` of the window
returns a fully transparent rectangle where the panel is. A picture of the
window *and* its guest is two captures composited — measured, see decision 5 of
`docs/superpowers/specs/2026-07-27-gui-cli-mcp-architecture.md`.

## Run the headless smoke

```sh
dart run app/tool/embedder/run.dart
```

Spawns the guest and writes its first frame to `app/build/embedder/scene.png`.

## How it works

Two processes, a Unix-domain-socket control channel, and shared `IOSurface`s:

- **Guest** (`native/`) — the long-lived C/Objective-C host embedding
  `FlutterEmbedder`. `host.c` runs the engine with the Metal renderer;
  `surface.{m,h}` owns the `MTLDevice`/`MTLCommandQueue` and the ring of
  `IOSurface`-backed Metal textures; `ipc.{c,h}` is the framed socket protocol;
  `input.{c,h}` translates pointer/key events.
- **GUI runtime** (`lib/src/embedder/`) — `embedded_engine.dart` builds and
  spawns the guest, owns the socket, and bridges frames to the texture;
  `embedder_harness_screen.dart` is the dev screen; `protocol.dart` is the wire
  codec; `embedder_build.dart` / `tool/embedder/build_guest.dart` orchestrate
  the build.
- **Native plugin** (`macos/Runner/EmbedderTexturePlugin.swift`) — registers
  the external `FlutterTexture` and wraps each `IOSurface` as a `CVPixelBuffer`.

The guest announces surfaces by `IOSurfaceID`, signals each frame with
`FrameReady`, and accepts `Resize`/`PointerEvent`/`KeyEvent`/`Shutdown`.

## Tests

- `app/test/embedder/` — fast unit tests (`raw_frame_test`, `protocol_test`).
- `app/integration_test/embedder/` — heavy tests (`compiler_test`,
  `flutter_cache_test`, `live_bridge_test`):

  ```sh
  cd app && dart test integration_test/embedder
  ```

The GUI texture path is verified manually via the harness.

## Keyboard and text input

Two guest-side replacements for platform plumbing this embedder does not have,
both installed by the generated catalog entrypoint and both in
`package:flutterware/ui_catalog_guest.dart`:

- **`GuestKeyboard`** — delivery. `FlutterEngineSendKeyEvent` alone reaches
  nothing: `KeyEventManager` infers a `keyDataThenRawKeyData` embedder from the
  first event and then queues every key, waiting for the legacy
  `flutter/keyevent` platform message that normally follows and flushes the
  queue. With no platform channels there is no flush, so **no key reached a
  demo at all** — not a shortcut, not an arrow. This replaces `onKeyData` and
  dispatches to both destinations itself.
- **`GuestTextInput`** — insertion *and the editing commands*. A `TextField`
  gets its text from the platform IME, and there is none; this is a
  `TextInputControl` that builds editing state from the character each key
  carries. It also names the commands: on Apple platforms the framework
  refuses backspace, delete, the arrows, home, end and page while a field is
  focused and waits for the IME to send `deleteBackward:`, `moveLeft:` and
  friends, so the control maps key plus modifiers to those selectors.

The panel decides what a demo is allowed to hear — `isReservedAppChord`
(`catalog/app_chords.dart`). It keeps only the chords the host actually binds;
everything else, modifier keys included, goes to the guest, which is what makes
⌘A and ⌘Z work inside a demo.

`tool/embedder/input_probe.dart` is what proves the chain end to end: it types
into a real guest and scrolls one, then reads back what the demo shows.
`input_smoke.dart` only proves the guest survives the messages — which is
exactly how keyboard input looked fine while every key sat queued.

## Not yet implemented

Hot reload (step 4), IME composition (dead keys, CJK), guest clipboard,
multiple embedded engines, non-macOS platforms.

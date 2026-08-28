# Embedder

Experimental Flutter engine embedder, part of `flutterware_app`.

**Step 3b (current):** an out-of-process Flutter-engine guest renders an
animated, interactive scene and the flutterware desktop GUI displays it live in
an external `Texture`. The panel is resizable and forwards pointer, keyboard,
scroll-wheel and trackpad pan/zoom input (`input_region.dart`).

How the frame crosses the process boundary is the one thing that is not the
same on every host, and it is confined to `native/surface.{m,c}` plus one
`#ifdef` in `host.c`:

- **macOS** renders with the **Metal renderer** directly into shared
  `IOSurface`-backed Metal textures — zero-copy, no per-frame copy at all.
- **Linux** renders with the **OpenGL renderer** on a surfaceless EGL context
  and reads each frame back into a ring of `/dev/shm` mappings the GUI uploads
  from — one copy each way, ~2ms at 800×600. Zero-copy there means a dmabuf and
  is future work.

**Linux is not finished.** The guest is: the headless pipeline below produces a
correct `scene.png`, and the live panel comes up in the studio. But widening the
panel segfaults the *host* application inside the engine's compositor, and the
fault is reached with an external texture of any kind registered — see
`docs/superpowers/specs/2026-08-28-linux-embedder-guest-findings.md` § "Phase 1,
as built" for the seven things that were ruled out and where to pick it up.

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
a raw file `decodeRawFrame` reads (the header says which byte order). It exists because **the guest is not in
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

Two processes, a Unix-domain-socket control channel, and a ring of surfaces
both can reach:

- **Guest** (`native/`) — the long-lived C/Objective-C host embedding the
  engine. `host.c` runs it and owns the socket loop; `surface.h` is the ring
  contract, implemented by `surface.m` (Metal + IOSurface) and `surface_gl.c`
  (EGL + shared memory); `ipc.{c,h}` is the framed socket protocol;
  `input.{c,h}` translates pointer/key events. Only the renderer config differs
  per host — resize, capture, window metrics and input are written once.
- **GUI runtime** (`lib/src/embedder/`) — `embedded_engine.dart` builds and
  spawns the guest, owns the socket, and bridges frames to the texture;
  `embedder_harness_screen.dart` is the dev screen; `protocol.dart` is the wire
  codec; `embedder_build.dart` / `tool/embedder/build_guest.dart` orchestrate
  the build.
- **Native plugin** — `macos/Runner/EmbedderTexturePlugin.swift` registers the
  external `FlutterTexture` and wraps each `IOSurface` as a `CVPixelBuffer`;
  `linux/runner/embedder_texture_plugin.cc` answers the same four methods on
  the same channel with an `FlTextureGL` over the shared-memory ring.

The guest announces each ring slot by an opaque handle — an `IOSurfaceID` in
decimal, or a shared-memory name — signals each frame with `FrameReady`, and
accepts `Resize`/`PointerEvent`/`KeyEvent`/`Shutdown`. The raw frame a capture
writes carries its pixel order in the header, because the Metal ring is BGRA
and the GL one is RGBA.

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
`package:flutterware/previews_guest.dart`:

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
multiple embedded engines, Windows, dmabuf zero-copy on Linux — and the Linux
resize crash above.

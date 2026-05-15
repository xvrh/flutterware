# Embedder

Experimental Flutter engine embedder, part of `flutterware_app`.

**Step 3b (current):** an out-of-process Flutter-engine guest renders an
animated, interactive scene with the **Metal renderer**, directly into shared
`IOSurface`-backed Metal textures — a zero-copy path with no per-frame copy.
The flutterware desktop GUI displays it live in an external `Texture`. The
panel is resizable and forwards pointer/keyboard input.

## Run the GUI harness

```sh
cd app && flutter run -t lib/main_embedder_dev.dart -d macos \
  --dart-define=FLUTTERWARE_APP_ROOT="$(pwd)" \
  --dart-define=FLUTTER_SDK_ROOT="$(cd "$(dirname "$(which flutter)")/.." && pwd)"
```

This builds and spawns the guest, then shows its live output. A macOS app
launched by `flutter run` has no usable environment or working directory, so
the `app/` package root and Flutter SDK root are passed via `--dart-define`.

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

## Not yet implemented

Hot reload (step 4), text input/IME, multiple embedded engines, non-macOS
platforms.

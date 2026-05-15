# Embedder

Experimental Flutter engine embedder, part of `flutterware_app`.

**Step 2 (current):** compile a static `runApp` Flutter UI to kernel with the
Flutter `frontend_server`, render it headless inside a C host that embeds the
prebuilt Flutter engine, and capture the rendered frame to a PNG. No window, no
GUI integration, no hot reload.

## Run it

```sh
dart run app/tool/embedder/run.dart
```

Run with the Dart SDK bundled in your Flutter checkout
(`<flutter>/bin/cache/dart-sdk/bin/dart`). The first run downloads
`FlutterEmbedder.framework` (~31 MB); later runs reuse the cached copy. The
output PNG is written to `app/build/embedder/scene.png`.

## How it works

`tool/embedder/run.dart` chains these steps:

1. **Fetch the engine.** The C embedder API (`FlutterEngineRun`, …) is not
   exported by the `FlutterMacOS.framework` in the local Flutter cache — that is
   the high-level Obj-C desktop framework. The C API ships in a separate
   artifact, `FlutterEmbedder.framework`, downloaded from Flutter's artifact
   storage keyed by the engine revision in `<flutter>/bin/cache/engine.stamp`
   and cached under `app/.engine/` (gitignored).
2. **Compile.** `frontend_server` compiles `tool/embedder/scene.dart` against
   the Flutter patched SDK into `build/embedder/assets/kernel_blob.bin`.
3. **Build the host.** CMake builds `native/host.c` against
   `FlutterEmbedder.framework`.
4. **Render.** The host starts the engine headless (software renderer, no
   window), sends a window-metrics event, lets the UI settle, and writes the
   composited frame to a raw file (`build/embedder/scene.rawframe`).
5. **Encode.** The orchestrator decodes the raw frame and encodes
   `build/embedder/scene.png`.

## Layout (paths relative to `app/`)

- `lib/src/embedder/compiler.dart` — drives `frontend_server` to produce
  `kernel_blob.bin`.
- `lib/src/embedder/flutter_cache.dart` — locates Flutter cache artifacts and
  the engine revision.
- `lib/src/embedder/raw_frame.dart` — decodes the host's raw frame file into a
  `package:image` `Image`.
- `tool/embedder/compile.dart` — CLI wrapper around the compiler.
- `tool/embedder/run.dart` — orchestrator: fetch engine → compile → build host
  → render → encode PNG.
- `tool/embedder/scene.dart` — the Flutter app that gets rendered.
- `native/host.c` — C host embedding the Flutter engine (software renderer,
  headless) that renders and captures a frame.
- `native/flutter_embedder.h` — vendored engine embedder header. **Must match
  the engine revision in your Flutter cache.** Re-download it (see the
  implementation plan) after upgrading Flutter.
- `native/CMakeLists.txt` — builds the host.

## Tests

The embedder tests live in two places:

- `app/test/embedder/raw_frame_test.dart` — a fast unit test; runs in the
  default `flutter test`.
- `app/integration_test/embedder/` — tests that touch the real Flutter
  toolchain (one builds the C host and renders); kept out of the default
  `flutter test`. Run them explicitly:

  ```sh
  cd app && dart test integration_test/embedder
  ```

## Not yet implemented

Live display in the flutterware desktop GUI, GPU/Metal rendering and external
textures, hot reload, animation, non-macOS platforms.

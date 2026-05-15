# Embedder

Experimental Flutter engine embedder, part of `flutterware_app`.

**Step 3a — guest (current):** the C host is a long-lived, out-of-process
Flutter-engine *guest*. It compiles an animated `runApp` scene to kernel, runs
it with the software renderer, and `memcpy`s every frame into shared
`IOSurface`s. It speaks a framed wire protocol over a Unix domain socket:
`SurfacesAllocated`, `FrameReady`, `Resize`, `PointerEvent`, `KeyEvent`,
`Shutdown`. The GUI-side display (an external `Texture`) is Plan 2 / a later
step.

## Run it (headless smoke)

```sh
dart run app/tool/embedder/run.dart
```

Run with the Dart SDK bundled in your Flutter checkout. `run.dart` spawns the
guest, captures its first frame, and writes `app/build/embedder/scene.png`.

## How it works

- `lib/src/embedder/compiler.dart` — drives `frontend_server` to produce
  `kernel_blob.bin`.
- `lib/src/embedder/flutter_cache.dart` — locates Flutter cache artifacts and
  the engine revision.
- `lib/src/embedder/embedder_build.dart` — ensures `FlutterEmbedder.framework`,
  compiles the scene, builds the C host.
- `lib/src/embedder/protocol.dart` — the wire-protocol message types and codec.
- `lib/src/embedder/raw_frame.dart` — decodes a raw frame file (used by the
  guest's `--capture-raw` smoke path).
- `tool/embedder/scene.dart` — the animated, interactive scene.
- `tool/embedder/run.dart` — protocol client: spawn guest, capture one frame
  → PNG.
- `native/host.c` — long-lived guest main loop.
- `native/surface.{c,h}` — `IOSurface` triple-buffer ring.
- `native/ipc.{c,h}` — Unix-socket framed IPC.
- `native/input.{c,h}` — pointer/key event translation.
- `native/flutter_embedder.h` — vendored engine embedder header. **Must match
  the engine revision in your Flutter cache.**
- `native/CMakeLists.txt` — builds the host.

## Tests

- `app/test/embedder/` — fast unit tests (`raw_frame_test`, `protocol_test`);
  run in the default `flutter test`.
- `app/integration_test/embedder/` — heavy tests that touch the real toolchain
  (`compiler_test`, `flutter_cache_test`, `live_bridge_test`):

  ```sh
  cd app && dart test integration_test/embedder
  ```

## Not yet implemented

Live display in the flutterware desktop GUI (Plan 2), GPU/Metal rendering and a
zero-copy path (step 3b), hot reload (step 4), text input/IME, non-macOS
platforms.

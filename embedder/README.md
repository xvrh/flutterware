# flutterware_embedder

Experimental Flutter engine embedder.

**Step 1 (current):** compile a hello-world Dart program to kernel with the
Flutter `frontend_server` and run it headless inside a C host that embeds the
prebuilt Flutter engine. The program's `print()` output is echoed to stdout.
No window, no rendering.

## Run it

```sh
dart run embedder/tool/run.dart
```

Run with the Dart SDK bundled in your Flutter checkout
(`<flutter>/bin/cache/dart-sdk/bin/dart`). The first run downloads
`FlutterEmbedder.framework` (~31 MB); later runs reuse the cached copy.

## How it works

`tool/run.dart` chains four steps:

1. **Fetch the engine.** The C embedder API (`FlutterEngineRun`, …) is not
   exported by the `FlutterMacOS.framework` in the local Flutter cache — that is
   the high-level Obj-C desktop framework. The C API ships in a separate
   artifact, `FlutterEmbedder.framework`, downloaded from Flutter's artifact
   storage keyed by the engine revision in `<flutter>/bin/cache/engine.stamp`
   and cached under `embedder/.engine/` (gitignored).
2. **Compile.** `frontend_server` compiles `example/hello.dart` against the
   Flutter patched SDK into `build/assets/kernel_blob.bin`.
3. **Build the host.** CMake builds `native/host.c` against
   `FlutterEmbedder.framework`.
4. **Run.** The host starts the engine headless (software renderer, no window),
   the engine runs the kernel's `main()`, and Dart `print()` output arrives via
   the embedder API's `log_message_callback` and is echoed to stdout.

## Layout

- `lib/compiler.dart` — drives `frontend_server` to produce `kernel_blob.bin`.
- `lib/src/flutter_cache.dart` — locates Flutter cache artifacts and the engine
  revision.
- `bin/compile.dart` — CLI wrapper around the compiler.
- `native/host.c` — C host embedding the Flutter engine (software renderer,
  headless).
- `native/flutter_embedder.h` — vendored engine embedder header. **Must match
  the engine revision in your Flutter cache.** Re-download it (see the
  implementation plan) after upgrading Flutter.
- `native/CMakeLists.txt` — builds the host.
- `tool/run.dart` — orchestrator: fetch engine → compile → build host → run.

## Not yet implemented

Window/surface, external textures, hot reload, GUI integration, non-macOS
platforms.

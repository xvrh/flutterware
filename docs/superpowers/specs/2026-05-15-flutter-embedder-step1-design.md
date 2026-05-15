# Flutter embedder — Step 1: "Hello World" through a Flutter-engine embedder

**Date:** 2026-05-15
**Status:** Approved design

## Long-term vision

A fast way to run Dart/Flutter code and display the result inside a desktop app, via
an external texture composited by a host application. The host embeds the Flutter
engine directly, controls the renderer, and supports rapid iteration (hot reload).

This spec covers **only step 1**: proving the compile-and-run backbone end to end,
headless, with no rendering. Later steps add a real surface/texture, a window, and
hot reload.

## Goal of step 1

Prove the pipeline works end to end:

```
hello.dart  --(CFE / frontend_server)-->  kernel_blob.bin  --(Flutter engine)-->  execution
```

A native C host embeds the prebuilt Flutter engine, runs a hello-world Dart program
compiled to kernel, and surfaces the program's `print()` output on the host's own
stdout. Fully headless: no window, no texture, no widgets.

## Key decisions

- **Engine source:** the prebuilt `FlutterEmbedder.framework` engine artifact. No
  Dart SDK or engine build from source. This framework embeds a Dart VM *and*
  exports the public C embedder API symbols (`FlutterEngineRun`, …). Note: the
  `FlutterMacOS.framework` shipped in the local cache is the high-level Obj-C
  desktop framework and does **not** export the C embedder API — hence the separate
  artifact. `FlutterEmbedder.framework` is not in the local cache by default; it is
  downloaded once from Flutter's official artifact storage
  (`storage.googleapis.com/flutter_infra_release/flutter/<engine-revision>/darwin-x64/FlutterEmbedder.framework.zip`,
  ~31 MB) and cached, gitignored, under `embedder/.engine/`. The engine revision is
  read from `<flutter>/bin/cache/engine.stamp`.
- **Embedder API:** `flutter_embedder.h` — a single stable, versioned header copied
  from the Flutter engine repo at the cache's pinned engine revision. (It is also
  bundled inside `FlutterEmbedder.framework`; the vendored copy keeps the build
  self-contained.)
- **Compiler:** the Flutter cache's `frontend_server` snapshot, driven via
  `package:frontend_server_client`. `frontend_server` *is* `package:front_end`'s
  `IncrementalKernelGenerator` wrapped as a server — the same compiler `flutter run`
  uses. Chosen over a one-shot `kernelForProgram` call because hot reload (a near-term
  step) needs the incremental `compile`/`recompile`/`accept`/`reject` protocol, and
  the cached snapshot is version-matched to the engine (no dependency pinning).
- **Renderer:** the engine's software renderer in headless mode. The
  `surface_present_callback` returns `true` and discards pixels. The engine still
  starts the root isolate and runs `main()` — no window metrics event is sent.
- **Scope intent:** foundation for a real flutterware feature (a fast Flutter
  preview/runner), built to be kept and extended — not a throwaway spike.

## Components & boundaries

A new pub workspace member `embedder/` (package `flutterware_embedder`,
`publish_to: none`), added to the root `pubspec.yaml` workspace list.

Two cleanly separable units that meet at exactly one interface — **an `assets/`
directory containing `kernel_blob.bin`**:

| Unit | Language | Responsibility | Depends on |
|---|---|---|---|
| **Compiler** | Dart | `hello.dart` → `assets/kernel_blob.bin` | `frontend_server` snapshot, `frontend_server_client` |
| **Host** | C | Links `FlutterEmbedder.framework`, runs the engine headless on the assets dir, echoes Dart `print()` to stdout | `flutter_embedder.h`, `FlutterEmbedder.framework`, `icudtl.dat` |

Either unit can be tested or replaced independently of the other.

### Compiler (`embedder/lib/compiler.dart` + `embedder/bin/compile.dart`)

- Resolves the Flutter SDK (via `flutter` on `PATH`) to locate the cached
  `frontend_server` snapshot and the `flutter_patched_sdk`.
- Drives `frontend_server` through `package:frontend_server_client`.
- Step 1 issues a single `compile()` call and writes the resulting kernel to
  `embedder/build/assets/kernel_blob.bin`.
- The incremental machinery (`recompile`/`accept`/`reject`, partial dills) is
  inherited from `frontend_server` and left unused in step 1; it is the foundation
  for step-2 hot reload.

### Host (`embedder/native/host.c` + `embedder/native/CMakeLists.txt`)

- Vendors `flutter_embedder.h` (single header, copied from the engine repo at the
  cache's pinned engine revision).
- `FlutterRendererConfig` type `kSoftware`; `surface_present_callback` returns
  `true` and discards the pixel buffer. No window, no
  `FlutterEngineSendWindowMetricsEvent`.
- `FlutterProjectArgs`: `assets_path` → the assets dir, `icu_data_path` → the cached
  `icudtl.dat`, `log_message_callback` → writes to the host's stdout (Dart `print()`
  is routed through this callback).
- Lifecycle: `FlutterEngineRun` → wait until the log callback observes the expected
  line *or* a bounded timeout (~10 s) → `FlutterEngineShutdown`. Exit code 0 on match,
  non-zero on timeout, giving a clear pass/fail signal.
- Links the framework via `-F <embedder>/.engine -framework FlutterEmbedder`, with
  an install rpath pointing at the same directory.
- No VM service in step 1.

## Layout

```
embedder/
  pubspec.yaml              # flutterware_embedder; added to root workspace list
  lib/compiler.dart         # frontend_server client wrapper
  lib/src/flutter_cache.dart # locates Flutter SDK cache artifacts
  bin/compile.dart          # CLI: hello.dart -> assets/kernel_blob.bin
  example/hello.dart        # void main() => print('Hello, World!');
  native/
    flutter_embedder.h      # vendored, version-matched to the cached engine
    host.c
    CMakeLists.txt
  tool/run.dart             # orchestrator: fetch engine -> compile -> build -> run
  test/pipeline_test.dart   # integration test
  .engine/                  # gitignored: downloaded FlutterEmbedder.framework
  README.md                 # records the engine-revision matching constraint
```

`tool/run.dart` is the single entry point: ensure `FlutterEmbedder.framework` is
downloaded, compile the kernel, configure and build the CMake host, run it, and
surface its exit code.

## Data flow

0. `tool/run.dart` ensures `FlutterEmbedder.framework` is present under
   `embedder/.engine/`, downloading it from Flutter's artifact storage (keyed by the
   engine revision in `bin/cache/engine.stamp`) on first run.
1. `tool/run.dart` invokes the compiler → `frontend_server` compiles
   `example/hello.dart` against the Flutter patched SDK → `build/assets/kernel_blob.bin`.
2. `tool/run.dart` configures and builds the CMake host → `build/host`.
3. The host starts the Flutter engine with `assets_path = build/assets`.
4. The engine starts its root isolate and runs `main()`; `print('Hello, World!')`
   reaches the host via `log_message_callback`.
5. The host echoes the line to its stdout, shuts the engine down, exits 0.

## Error handling

- **Flutter SDK / cache artifacts not found:** the compiler and `tool/run.dart` fail
  fast with a message naming the missing path.
- **`FlutterEmbedder.framework` download fails:** `tool/run.dart` reports the failed
  URL / HTTP status and exits non-zero before attempting to build.
- **Compilation failure:** `frontend_server` reports diagnostics; the compiler
  surfaces them and exits non-zero without producing `kernel_blob.bin`.
- **Engine fails to start or `main()` never prints:** the host's bounded timeout
  fires; it shuts the engine down and exits non-zero.
- **Engine-revision / `flutter_embedder.h` mismatch:** `FlutterEngineRun` reports a
  version error via the embedder API; the host surfaces it. The README documents
  that the vendored header must match the cached engine revision.

## Testing

- `embedder/test/pipeline_test.dart`: runs `tool/run.dart` as a subprocess, asserts
  exit code 0 and stdout contains `Hello, World!`. This single integration test
  covers the whole pipeline; the C host is not unit-testable in isolation.
- Manual: `dart run embedder/tool/run.dart`.

## Out of scope for step 1 (deferred)

- Any window, surface, or `runApp`/widgets.
- Metal/OpenGL/Vulkan rendering and external textures.
- Hot reload — requires enabling the engine's VM service and a VM-service client in
  the host to push `frontend_server`'s incremental dills via the `reloadSources`
  RPC. The host's structure should leave room for this but step 1 does not implement
  it.
- Integration into the flutterware desktop GUI.
- Platforms other than macOS.

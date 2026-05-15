# Flutter embedder — Step 2: render a Flutter app to a PNG, headless

**Date:** 2026-05-15
**Status:** Approved design

## Long-term vision

A fast way to run Dart/Flutter code and display the result inside the flutterware
desktop app, with hot reload. The host embeds the Flutter engine directly and
controls the renderer.

The staircase toward that goal:

- **Step 1 (done):** compile a hello-world to kernel and run it headless in the
  embedded engine; `print()` reaches stdout. Proved compile → kernel → engine.
- **Step 2 (this spec):** render a real `runApp` Flutter UI and capture it to a
  PNG, headless. Proves the rendering path — framework build, layout, the
  compositor, frame scheduling.
- **Step 3 (future):** display the rendered surface live in the flutterware
  desktop GUI via an external texture (likely a Metal surface for zero-copy).
- **Step 4 (future):** hot reload — the engine's VM service plus incremental
  `frontend_server` recompiles.

## Goal of step 2

Prove the rendering path end to end:

```
scene.dart --(frontend_server)--> kernel_blob.bin --(engine + software renderer)--> RGBA frame --> PNG
```

A static `runApp` Flutter UI is compiled to kernel, run in the embedded engine,
composited by the engine's software renderer, captured as a raw pixel buffer by
the C host, and encoded to a PNG by the Dart orchestrator. The deliverable is a
saved image proving the pixels are a real Flutter render.

Still headless: no OS window, no GUI integration, no hot reload, no animation.

## Key decisions

- **Renderer:** the engine's software renderer (`kSoftware`), reusing step 1's
  `FlutterRendererConfig`. The `surface_present_callback` — a no-op in step 1 —
  now captures the composited buffer. Chosen over the compositor/backing-store
  API and Metal render-to-texture: those belong to step 3 (live GUI display) and
  would front-load GPU work. Software capture is a one-callback delta from
  working step-1 code and isolates "does the engine render correctly".
- **Pipeline evolved in place.** Step 1's headless *print* pipeline is replaced,
  not duplicated: the host, sample, orchestrator and integration test all become
  render-oriented. The host keeps the `log_message_callback`, so `print()` from
  the rendered app still surfaces for debugging. Rendering subsumes the "engine
  ran" proof.
- **PNG encoding in Dart.** The C host writes a raw pixel buffer; the Dart
  orchestrator encodes the PNG with `package:image` (already an `app`
  dependency). Keeps the C host free of an image library.
- **Frame capture: last frame after a settle window.** The host keeps the latest
  presented buffer; once no new present arrives for ~500 ms (or a ~10 s hard
  timeout fires) it writes that buffer. Robust if the UI takes a few frames to
  finalise; a static UI naturally yields one frame then idles.
- **Render target: `MaterialApp` + centred `Text`.** Exercises the real
  framework (Material theming, layout, font rendering) while staying static and
  deterministic.

## Components & boundaries

All paths are under `app/` (the embedder lives in `flutterware_app` — see
`app/lib/src/embedder/`). Units and their interfaces:

| Unit | Language | Responsibility | Interface |
|---|---|---|---|
| **Scene** | Dart | The static Flutter app under test | `tool/embedder/scene.dart`, a `runApp` entrypoint |
| **Host** | C | Run the engine, render, capture one settled frame | CLI args in → raw frame file out |
| **Raw-frame decoder** | Dart | Parse the raw frame file into an image | `decodeRawFrame(Uint8List) -> Image` |
| **Orchestrator** | Dart | Fetch engine, compile, build host, run, encode PNG | `tool/embedder/run.dart` |

The host ↔ Dart interface is the **raw frame file**: a 12-byte little-endian
header (`width`, `height`, `row_bytes` as `uint32`) followed by the raw pixel
bytes.

### Scene — `app/tool/embedder/scene.dart` (replaces `hello.dart`)

```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Color(0xFF1565C0),
      body: Center(
        child: Text('Flutterware embedder',
            style: TextStyle(color: Colors.white, fontSize: 48)),
      ),
    ),
  ));
}
```

Static and deterministic. The existing `compileToKernel` already targets the
Flutter SDK, and the workspace `package_config.json` resolves `package:flutter`,
so this compiles with no compiler changes.

### Host — `app/native/host.c` (evolved render host)

- Renderer config stays `kSoftware`. `surface_present_callback` now captures:
  under a mutex, `memcpy` the buffer (`row_bytes × height`), record `row_bytes`
  and `height` from the callback, timestamp the frame, signal a condition
  variable. The logical `width` is the compile-time window constant (800), not
  derived from `row_bytes` — `row_bytes` is a stride and may exceed `width × 4`.
- After `FlutterEngineRun`, send `FlutterEngineSendWindowMetricsEvent`
  (width 800, height 600, pixel ratio 1.0) so the framework builds and the
  engine schedules a frame. No custom vsync — the engine free-runs.
- **Settle capture:** the main thread waits on the condition variable; once no
  new present has arrived for ~500 ms, or a ~10 s hard timeout fires, it writes
  the latest captured buffer to the output file (header + pixels). Exit code 0
  if a frame was captured, non-zero if none was.
- Keeps `log_message_callback` → host stdout.
- CLI: `host <assets_dir> <icu_data_path> <output_raw_file>`. Window size is a
  compile-time constant (800×600) in `host.c`.
- **Pixel format** (RGBA vs BGRA, premultiplied or not) follows the embedder
  header's software-renderer contract. The host writes the bytes verbatim; the
  exact channel order is pinned during implementation by inspecting the first
  PNG and swapping channels if the colours are wrong.

### Raw-frame decoder — `app/lib/src/embedder/raw_frame.dart`

`Image decodeRawFrame(Uint8List fileBytes)` parses the 12-byte header, copies the
pixels row by row to drop any `row_bytes` stride padding, and returns a
`package:image` `Image`. Pure logic — no engine or SDK dependency — so it is
unit-testable with a hand-built byte buffer.

### Orchestrator — `app/tool/embedder/run.dart`

Same flow as step 1 (ensure `FlutterEmbedder.framework`, compile, build the C
host, run it) with two changes:

- Compiles `scene.dart` instead of `hello.dart`.
- After the host exits 0, reads the raw frame file, calls `decodeRawFrame`,
  `encodePng`, writes `build/embedder/scene.png`, and prints its absolute path.

## Data flow

1. `run.dart` ensures `FlutterEmbedder.framework` is present (step-1 logic).
2. `frontend_server` compiles `scene.dart` → `build/embedder/assets/kernel_blob.bin`.
3. CMake builds the C host.
4. The host starts the engine, sends window metrics; the framework builds the
   UI and the engine composites a frame via the software renderer.
5. The host captures the settled frame and writes the raw frame file.
6. `run.dart` decodes the raw file and encodes `build/embedder/scene.png`.

## Error handling

- **Compilation failure:** `frontend_server` diagnostics surface; the orchestrator
  exits non-zero (unchanged from step 1).
- **Engine produces no frame:** the host's hard timeout fires; it exits non-zero
  and the orchestrator stops before encoding.
- **Malformed raw frame file** (truncated, header/​payload size mismatch):
  `decodeRawFrame` throws with a descriptive message; the orchestrator exits
  non-zero.
- **`FlutterEmbedder.framework` download / engine-start failures:** as step 1.

## Testing

- `app/test/embedder/raw_frame_test.dart` — **fast unit test**: hand-built header
  + pixel bytes (including a stride-padded case) → `decodeRawFrame` → assert the
  resulting `Image` dimensions and pixels. Runs in the default `flutter test`.
- `app/integration_test/embedder/render_test.dart` — replaces `pipeline_test.dart`:
  runs `run.dart`, asserts exit 0, the PNG exists and is 800×600, a corner pixel
  is the expected background blue, and the centre region is not all-background
  (text was rendered).
- `app/integration_test/embedder/compiler_test.dart` — unchanged except it
  compiles `scene.dart`.
- `app/integration_test/embedder/flutter_cache_test.dart` — unchanged.

Integration tests stay out of the default `flutter test`; run them with
`cd app && dart test integration_test/embedder`.

## Out of scope for step 2 (deferred)

- An OS window or on-screen surface.
- Metal/OpenGL/Vulkan/GPU rendering and external textures.
- Live display in the flutterware desktop GUI.
- Hot reload.
- Animation, and multi-frame or video capture.

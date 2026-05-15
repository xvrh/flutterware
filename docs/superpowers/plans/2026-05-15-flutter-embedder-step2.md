# Flutter Embedder — Step 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a static `runApp` Flutter UI in the embedded engine and capture it to a PNG, headless.

**Architecture:** The step-1 headless *print* pipeline is evolved in place into a *render* pipeline. The C host (`app/native/host.c`) sends a window-metrics event so the framework builds, captures the composited buffer from the software renderer's `surface_present_callback` once the UI settles, and writes a raw frame file (a 12-byte header + pixels). A Dart unit `raw_frame.dart` decodes that file into a `package:image` `Image`; the `run.dart` orchestrator encodes it to `scene.png`.

**Tech Stack:** Dart (`package:image` 4.8.0, `path`, `test`), C11, CMake, the prebuilt Flutter engine (`FlutterEmbedder.framework`).

**Reference spec:** `docs/superpowers/specs/2026-05-15-flutter-embedder-step2-design.md`

**Environment assumptions (verified):**
- Run all Dart commands with the Flutter-bundled SDK: `/Users/xavier/flutter/bin/dart` (and `/Users/xavier/flutter/bin/flutter`).
- The embedder already lives in `flutterware_app` under `app/` (folded from a former standalone package). Existing files: `app/lib/src/embedder/{compiler.dart,flutter_cache.dart}`, `app/native/{host.c,CMakeLists.txt,flutter_embedder.h}`, `app/tool/embedder/{run.dart,compile.dart,hello.dart}`, tests under `app/integration_test/embedder/`.
- `FlutterEmbedder.framework` is already downloaded at `app/.engine/FlutterEmbedder.framework` (gitignored; step 1 fetched it). CMake builds against it via `-DFLUTTER_FRAMEWORK_DIR`.
- `package:image` 4.8.0 is a transitive dep of `app`; `Image.fromBytes({width, height, bytes (ByteBuffer), bytesOffset, numChannels, rowStride, order})`, `encodePng(Image)`, `decodePng(Uint8List)`, and `ChannelOrder.{rgba,bgra}` are available.
- `app/native/flutter_embedder.h` (vendored) defines `FlutterWindowMetricsEvent` (fields `struct_size, width, height, pixel_ratio, …`) and `FlutterEngineSendWindowMetricsEvent(engine, &event)`.
- macOS arm64. CMake ≥ 3.15, `curl`, `unzip` on PATH.

---

## Task 1: Raw-frame decoder

**Files:**
- Create: `app/lib/src/embedder/raw_frame.dart`
- Test: `app/test/embedder/raw_frame_test.dart`

This is a pure-logic unit — no engine or SDK dependency — so it is a fast unit
test that runs in the default `flutter test`.

- [ ] **Step 1: Write the failing test**

`app/test/embedder/raw_frame_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutterware_app/src/embedder/raw_frame.dart';
import 'package:test/test.dart';

/// Builds a raw frame file: 12-byte LE header + [pixels].
Uint8List _rawFrame(int width, int height, int rowBytes, List<int> pixels) {
  var header = ByteData(12)
    ..setUint32(0, width, Endian.little)
    ..setUint32(4, height, Endian.little)
    ..setUint32(8, rowBytes, Endian.little);
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(pixels))
      .toBytes();
}

void main() {
  test('decodes a tight 2x1 BGRA buffer', () {
    // Pixel 0 = blue (B=255), pixel 1 = red (R=255), BGRA byte order.
    var pixels = [255, 0, 0, 255, 0, 0, 255, 255];
    var image = decodeRawFrame(_rawFrame(2, 1, 8, pixels));

    expect(image.width, 2);
    expect(image.height, 1);
    var p0 = image.getPixel(0, 0);
    expect(p0.r.toInt(), 0);
    expect(p0.g.toInt(), 0);
    expect(p0.b.toInt(), 255);
    var p1 = image.getPixel(1, 0);
    expect(p1.r.toInt(), 255);
    expect(p1.g.toInt(), 0);
    expect(p1.b.toInt(), 0);
  });

  test('honours row-stride padding', () {
    // 1x2 image, rowBytes 8 = 4 pixel bytes + 4 padding bytes per row.
    var row0 = [255, 0, 0, 255, 9, 9, 9, 9]; // blue + padding
    var row1 = [0, 0, 255, 255, 9, 9, 9, 9]; // red + padding
    var image = decodeRawFrame(_rawFrame(1, 2, 8, [...row0, ...row1]));

    expect(image.width, 1);
    expect(image.height, 2);
    var top = image.getPixel(0, 0);
    expect(top.b.toInt(), 255);
    var bottom = image.getPixel(0, 1);
    expect(bottom.r.toInt(), 255);
  });

  test('rejects a truncated file (shorter than the header)', () {
    expect(() => decodeRawFrame(Uint8List(6)), throwsFormatException);
  });

  test('rejects a payload size mismatch', () {
    // Header declares 2x1 with rowBytes 8 (16 payload bytes); supply 4.
    expect(() => decodeRawFrame(_rawFrame(2, 1, 8, [0, 0, 0, 0])),
        throwsFormatException);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && /Users/xavier/flutter/bin/dart test test/embedder/raw_frame_test.dart`
Expected: FAIL — `raw_frame.dart` does not exist / `decodeRawFrame` undefined.

- [ ] **Step 3: Implement the decoder**

`app/lib/src/embedder/raw_frame.dart`:

```dart
import 'dart:typed_data';

import 'package:image/image.dart';

/// Decodes a raw frame file written by the embedder C host into an [Image].
///
/// File layout: a 12-byte little-endian header (`width`, `height`, `rowBytes`
/// as `uint32`) followed by `rowBytes * height` pixel bytes in BGRA order.
/// `rowBytes` is a stride and may exceed `width * 4`.
Image decodeRawFrame(Uint8List fileBytes) {
  if (fileBytes.length < 12) {
    throw FormatException(
        'Raw frame file too short: ${fileBytes.length} bytes');
  }
  var header = ByteData.sublistView(fileBytes, 0, 12);
  var width = header.getUint32(0, Endian.little);
  var height = header.getUint32(4, Endian.little);
  var rowBytes = header.getUint32(8, Endian.little);

  if (rowBytes < width * 4) {
    throw FormatException(
        'Raw frame rowBytes ($rowBytes) is smaller than width*4 '
        '(${width * 4})');
  }
  var expectedLength = 12 + rowBytes * height;
  if (fileBytes.length != expectedLength) {
    throw FormatException(
        'Raw frame size mismatch: header implies $expectedLength bytes, '
        'file has ${fileBytes.length}');
  }

  return Image.fromBytes(
    width: width,
    height: height,
    bytes: fileBytes.buffer,
    bytesOffset: fileBytes.offsetInBytes + 12,
    numChannels: 4,
    rowStride: rowBytes,
    order: ChannelOrder.bgra,
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && /Users/xavier/flutter/bin/dart test test/embedder/raw_frame_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/embedder/raw_frame.dart app/test/embedder/raw_frame_test.dart
git commit -m "Add raw-frame decoder for the embedder render pipeline"
```

---

## Task 2: Render scene, replacing the hello-world sample

**Files:**
- Create: `app/tool/embedder/scene.dart`
- Delete: `app/tool/embedder/hello.dart`
- Modify: `app/integration_test/embedder/compiler_test.dart`

- [ ] **Step 1: Create the render scene**

`app/tool/embedder/scene.dart`:

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

- [ ] **Step 2: Delete the old hello-world sample**

```bash
git rm app/tool/embedder/hello.dart
```

- [ ] **Step 3: Point the compiler integration test at the new scene**

In `app/integration_test/embedder/compiler_test.dart`, change the test name and
the entrypoint path. Replace:

```dart
  test('compiles hello.dart to a non-empty kernel blob', () async {
```

with:

```dart
  test('compiles scene.dart to a non-empty kernel blob', () async {
```

and replace:

```dart
      entrypoint: p.join(packageRoot, 'tool', 'embedder', 'hello.dart'),
```

with:

```dart
      entrypoint: p.join(packageRoot, 'tool', 'embedder', 'scene.dart'),
```

- [ ] **Step 4: Verify the scene compiles**

Run: `cd app && /Users/xavier/flutter/bin/dart test integration_test/embedder/compiler_test.dart`
Expected: PASS — `frontend_server` compiles `scene.dart` (which imports
`package:flutter/material.dart`) to a non-empty kernel blob.

- [ ] **Step 5: Commit**

```bash
git add app/tool/embedder/scene.dart app/tool/embedder/hello.dart app/integration_test/embedder/compiler_test.dart
git commit -m "Replace hello-world sample with a render scene"
```

---

## Task 3: Rewrite the C host to render and capture a frame

**Files:**
- Modify (full rewrite): `app/native/host.c`

The host gains: a capturing `surface_present_callback`, a window-metrics event,
a settle-then-capture wait loop, and raw-frame file output. `CMakeLists.txt`
needs no change (no new libraries).

- [ ] **Step 1: Replace `app/native/host.c` entirely with:**

```c
// Headless Flutter-engine host: runs a kernel blob, renders one settled frame
// with the software renderer, and writes the raw pixel buffer to a file.
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "flutter_embedder.h"

// Logical window size; the engine renders the UI at this size.
enum { kWidth = 800, kHeight = 600 };
// Quiet period with no new frame after which the UI is treated as settled.
enum { kSettleMs = 500 };
// Hard cap on the whole render.
enum { kHardTimeoutSec = 10 };

static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_cond = PTHREAD_COND_INITIALIZER;

static unsigned char* g_frame = NULL;  // latest captured pixel buffer
static size_t g_frame_capacity = 0;
static size_t g_row_bytes = 0;
static size_t g_height = 0;
static uint64_t g_frame_count = 0;  // bumped on every present

// Software renderer present callback: copy the composited buffer so the main
// thread can write it out once the UI settles.
static bool PresentSoftware(void* user_data, const void* allocation,
                            size_t row_bytes, size_t height) {
  (void)user_data;
  size_t size = row_bytes * height;
  pthread_mutex_lock(&g_mutex);
  if (size > g_frame_capacity) {
    g_frame = realloc(g_frame, size);
    g_frame_capacity = size;
  }
  memcpy(g_frame, allocation, size);
  g_row_bytes = row_bytes;
  g_height = height;
  g_frame_count++;
  pthread_cond_signal(&g_cond);
  pthread_mutex_unlock(&g_mutex);
  return true;
}

// Receives engine log output, including Dart print() statements.
static void OnLogMessage(const char* tag, const char* message,
                         void* user_data) {
  (void)user_data;
  if (tag && tag[0]) {
    printf("[%s] %s\n", tag, message);
  } else {
    printf("%s\n", message ? message : "");
  }
  fflush(stdout);
}

// Absolute CLOCK_REALTIME deadline `ms` milliseconds from now.
static struct timespec DeadlineIn(long ms) {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  ts.tv_sec += ms / 1000;
  ts.tv_nsec += (ms % 1000) * 1000000L;
  if (ts.tv_nsec >= 1000000000L) {
    ts.tv_sec += 1;
    ts.tv_nsec -= 1000000000L;
  }
  return ts;
}

static bool Before(const struct timespec* a, const struct timespec* b) {
  if (a->tv_sec != b->tv_sec) return a->tv_sec < b->tv_sec;
  return a->tv_nsec < b->tv_nsec;
}

// Writes the captured frame: a 12-byte little-endian header
// (width, height, row_bytes) followed by the raw pixels. Caller holds g_mutex.
static bool WriteFrame(const char* path) {
  FILE* f = fopen(path, "wb");
  if (!f) {
    fprintf(stderr, "Cannot open output file: %s\n", path);
    return false;
  }
  uint32_t header[3] = {(uint32_t)kWidth, (uint32_t)g_height,
                        (uint32_t)g_row_bytes};
  size_t payload = g_row_bytes * g_height;
  bool ok = fwrite(header, sizeof(uint32_t), 3, f) == 3 &&
            fwrite(g_frame, 1, payload, f) == payload;
  fclose(f);
  return ok;
}

int main(int argc, char** argv) {
  if (argc != 4) {
    fprintf(stderr,
            "usage: %s <assets_dir> <icu_data_path> <output_raw_file>\n",
            argv[0]);
    return 2;
  }
  const char* assets_path = argv[1];
  const char* icu_data_path = argv[2];
  const char* output_path = argv[3];

  FlutterRendererConfig renderer = {0};
  renderer.type = kSoftware;
  renderer.software.struct_size = sizeof(FlutterSoftwareRendererConfig);
  renderer.software.surface_present_callback = PresentSoftware;

  FlutterProjectArgs args = {0};
  args.struct_size = sizeof(FlutterProjectArgs);
  args.assets_path = assets_path;
  args.icu_data_path = icu_data_path;
  args.log_message_callback = OnLogMessage;
  args.log_tag = "embedder";

  FlutterEngine engine = NULL;
  FlutterEngineResult result = FlutterEngineRun(
      FLUTTER_ENGINE_VERSION, &renderer, &args, NULL, &engine);
  if (result != kSuccess || engine == NULL) {
    fprintf(stderr, "FlutterEngineRun failed: %d\n", (int)result);
    return 1;
  }

  // Tell the framework the window size so it builds and the engine renders.
  FlutterWindowMetricsEvent metrics = {0};
  metrics.struct_size = sizeof(FlutterWindowMetricsEvent);
  metrics.width = kWidth;
  metrics.height = kHeight;
  metrics.pixel_ratio = 1.0;
  FlutterEngineSendWindowMetricsEvent(engine, &metrics);

  struct timespec hard_deadline = DeadlineIn(kHardTimeoutSec * 1000);
  pthread_mutex_lock(&g_mutex);

  // Wait for the first frame, bounded by the hard deadline.
  while (g_frame_count == 0) {
    if (pthread_cond_timedwait(&g_cond, &g_mutex, &hard_deadline) != 0) {
      break;
    }
  }
  bool have_frame = g_frame_count > 0;

  // Wait for the UI to settle: no new frame for kSettleMs (clamped to the
  // hard deadline so a misbehaving scene cannot loop forever).
  while (have_frame) {
    uint64_t seen = g_frame_count;
    struct timespec settle = DeadlineIn(kSettleMs);
    if (Before(&hard_deadline, &settle)) settle = hard_deadline;
    int rc = pthread_cond_timedwait(&g_cond, &g_mutex, &settle);
    if (rc != 0) break;               // settle window elapsed -> settled
    if (g_frame_count == seen) break; // spurious wakeup -> settled
    // a new frame arrived -> re-arm the settle wait
  }

  bool ok = have_frame && WriteFrame(output_path);
  pthread_mutex_unlock(&g_mutex);

  FlutterEngineShutdown(engine);

  if (!have_frame) {
    fprintf(stderr, "Timed out waiting for a rendered frame.\n");
    return 1;
  }
  if (!ok) {
    fprintf(stderr, "Failed to write %s\n", output_path);
    return 1;
  }
  return 0;
}
```

- [ ] **Step 2: Verify the host compiles and links**

Run:
```bash
cmake -S app/native -B /tmp/embedder_host_build \
  -DFLUTTER_FRAMEWORK_DIR="$(pwd)/app/.engine"
cmake --build /tmp/embedder_host_build
```
Expected: configures and builds `/tmp/embedder_host_build/host` with no errors.
(If `app/.engine/FlutterEmbedder.framework` is missing, run
`dart run app/tool/embedder/run.dart` once first — but with the old `run.dart`
this is unlikely; the framework persists from step 1.)

- [ ] **Step 3: Commit**

```bash
git add app/native/host.c
git commit -m "Rewrite C host to render and capture a frame"
```

---

## Task 4: Update the orchestrator to render and encode a PNG

**Files:**
- Modify (full rewrite): `app/tool/embedder/run.dart`

- [ ] **Step 1: Replace `app/tool/embedder/run.dart` entirely with:**

```dart
import 'dart:io';

import 'package:flutterware_app/src/embedder/compiler.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/raw_frame.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Downloads FlutterEmbedder.framework if needed, compiles scene.dart, builds
/// the C host, renders one frame, and encodes it to a PNG.
Future<void> main() async {
  // <app>/tool/embedder/run.dart -> <app>
  var packageRoot =
      p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  // This is a pub workspace: package_config.json lives at the repo root.
  var repoRoot = p.dirname(packageRoot);
  var cache = FlutterCache.fromRunningSdk();

  var buildDir = p.join(packageRoot, 'build', 'embedder');
  var assetsDir = p.join(buildDir, 'assets');
  var kernelBlob = p.join(assetsDir, 'kernel_blob.bin');
  var nativeBuildDir = p.join(buildDir, 'native');
  var engineDir = p.join(packageRoot, '.engine');
  var rawFrame = p.join(buildDir, 'scene.rawframe');
  var pngPath = p.join(buildDir, 'scene.png');

  await _ensureEmbedderFramework(cache, engineDir);

  stdout.writeln('[run] compiling scene.dart -> kernel_blob.bin');
  await compileToKernel(
    entrypoint: p.join(packageRoot, 'tool', 'embedder', 'scene.dart'),
    outputDill: kernelBlob,
    packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
    cache: cache,
  );

  stdout.writeln('[run] configuring + building the C host');
  await _run('cmake', [
    '-S', p.join(packageRoot, 'native'),
    '-B', nativeBuildDir,
    '-DFLUTTER_FRAMEWORK_DIR=$engineDir',
  ]);
  await _run('cmake', ['--build', nativeBuildDir]);

  stdout.writeln('[run] rendering the scene');
  var host = await Process.start(
    p.join(nativeBuildDir, 'host'),
    [assetsDir, cache.icuData, rawFrame],
    mode: ProcessStartMode.inheritStdio,
  );
  var hostExit = await host.exitCode;
  if (hostExit != 0) {
    stderr.writeln('[run] host failed ($hostExit)');
    exit(hostExit);
  }

  stdout.writeln('[run] encoding PNG');
  var image = decodeRawFrame(File(rawFrame).readAsBytesSync());
  File(pngPath).writeAsBytesSync(img.encodePng(image));
  stdout.writeln('[run] wrote $pngPath');
}

/// Ensures `FlutterEmbedder.framework` (the C embedder API, not part of the
/// local Flutter cache) is present under [engineDir], downloading it from
/// Flutter's artifact storage if it is missing or built for a different engine
/// revision.
Future<void> _ensureEmbedderFramework(
    FlutterCache cache, String engineDir) async {
  var revision = cache.engineRevision;
  var frameworkDir = p.join(engineDir, 'FlutterEmbedder.framework');
  var stamp = File(p.join(engineDir, 'engine.revision'));
  if (Directory(frameworkDir).existsSync() &&
      stamp.existsSync() &&
      stamp.readAsStringSync().trim() == revision) {
    return;
  }

  stdout.writeln('[run] downloading FlutterEmbedder.framework ($revision)');
  if (Directory(frameworkDir).existsSync()) {
    Directory(frameworkDir).deleteSync(recursive: true);
  }
  Directory(engineDir).createSync(recursive: true);

  var url = 'https://storage.googleapis.com/flutter_infra_release/flutter/'
      '$revision/darwin-x64/FlutterEmbedder.framework.zip';
  var zip = p.join(engineDir, 'FlutterEmbedder.framework.zip');
  await _run('curl', ['-fSL', url, '-o', zip]);
  // The zip's root entries are the framework's contents, so extract straight
  // into the `FlutterEmbedder.framework` directory.
  await _run('unzip', ['-q', '-o', zip, '-d', frameworkDir]);
  File(zip).deleteSync();
  stamp.writeAsStringSync(revision);
}

Future<void> _run(String executable, List<String> args) async {
  var process = await Process.start(executable, args,
      mode: ProcessStartMode.inheritStdio);
  var code = await process.exitCode;
  if (code != 0) {
    stderr.writeln('[run] `$executable ${args.join(' ')}` failed ($code)');
    exit(code);
  }
}
```

- [ ] **Step 2: Verify analysis is clean**

Run: `cd app && /Users/xavier/flutter/bin/dart analyze tool/embedder/run.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add app/tool/embedder/run.dart
git commit -m "Render the scene to a PNG in the embedder orchestrator"
```

---

## Task 5: End-to-end render integration test

**Files:**
- Create: `app/integration_test/embedder/render_test.dart`
- Delete: `app/integration_test/embedder/pipeline_test.dart`

- [ ] **Step 1: Create the render integration test**

`app/integration_test/embedder/render_test.dart`:

```dart
import 'dart:io';

import 'package:image/image.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('renders scene.dart to an 800x600 PNG', () async {
    // `dart test` runs with the package root (<app>) as the current directory.
    var runScript =
        p.join(Directory.current.path, 'tool', 'embedder', 'run.dart');

    var result =
        await Process.run(Platform.resolvedExecutable, ['run', runScript]);

    printOnFailure('exit code: ${result.exitCode}');
    printOnFailure('stdout:\n${result.stdout}');
    printOnFailure('stderr:\n${result.stderr}');
    expect(result.exitCode, 0);

    var pngFile = File(
        p.join(Directory.current.path, 'build', 'embedder', 'scene.png'));
    expect(pngFile.existsSync(), isTrue, reason: 'scene.png should exist');

    var image = decodePng(pngFile.readAsBytesSync())!;
    expect(image.width, 800);
    expect(image.height, 600);

    // The Scaffold background is Color(0xFF1565C0): R=21 G=101 B=192.
    // A wrong channel order (RGBA vs BGRA) makes this fail loudly.
    var corner = image.getPixel(2, 2);
    expect(corner.r.toInt(), closeTo(21, 4));
    expect(corner.g.toInt(), closeTo(101, 4));
    expect(corner.b.toInt(), closeTo(192, 4));

    // The centred white text means the central scanline is not all background.
    var sawText = false;
    for (var x = 100; x < 700 && !sawText; x += 3) {
      var px = image.getPixel(x, 300);
      if (px.r.toInt() > 200 && px.g.toInt() > 200 && px.b.toInt() > 200) {
        sawText = true;
      }
    }
    expect(sawText, isTrue,
        reason: 'expected white text pixels along the centre scanline');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
```

- [ ] **Step 2: Delete the old step-1 pipeline test**

```bash
git rm app/integration_test/embedder/pipeline_test.dart
```

- [ ] **Step 3: Run the render test**

Run: `cd app && /Users/xavier/flutter/bin/dart test integration_test/embedder/render_test.dart`
Expected: PASS — the orchestrator compiles `scene.dart`, builds the host, renders, writes `scene.png`; the test confirms 800×600, a blue corner, and white text pixels.

If the corner assertion fails with red/blue swapped (e.g. `corner.r ≈ 192`),
the software renderer's pixel order is RGBA, not BGRA: change `ChannelOrder.bgra`
to `ChannelOrder.rgba` in `app/lib/src/embedder/raw_frame.dart`, re-run the
`raw_frame_test.dart` unit test (update its BGRA byte comments accordingly), and
re-run this test. Report this if it happens.

- [ ] **Step 4: Run the full embedder test suite**

Run: `cd app && /Users/xavier/flutter/bin/dart test test/embedder integration_test/embedder`
Expected: all PASS — `raw_frame_test`, `flutter_cache_test`, `compiler_test`, `render_test`.

- [ ] **Step 5: Commit**

```bash
git add app/integration_test/embedder/render_test.dart app/integration_test/embedder/pipeline_test.dart
git commit -m "Add end-to-end render integration test for the embedder"
```

---

## Task 6: Update the README and final analysis

**Files:**
- Modify: `app/lib/src/embedder/README.md`

- [ ] **Step 1: Replace `app/lib/src/embedder/README.md` entirely with:**

```markdown
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
```

- [ ] **Step 2: Verify workspace-wide analysis is clean**

Run (from repo root): `/Users/xavier/flutter/bin/flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add app/lib/src/embedder/README.md
git commit -m "Update embedder README for step 2 (headless render)"
```

---

## Self-Review notes

- **Spec coverage:** software-renderer capture in `host.c` (Task 3); scene =
  MaterialApp + centred Text (Task 2); raw frame file interface — 12-byte LE
  header + pixels (Tasks 1, 3); PNG encoded in Dart via `package:image`
  (Tasks 1, 4); settle-window frame capture (Task 3); pipeline evolved in place,
  print path replaced (Tasks 2–5 delete `hello.dart`/`pipeline_test.dart`);
  fast unit test in `test/`, heavy tests in `integration_test/` (Tasks 1, 5);
  README (Task 6).
- **Pixel-format risk:** the spec flags RGBA-vs-BGRA as implementation-pinned.
  The plan defaults to `ChannelOrder.bgra` (Skia N32 on macOS) and Task 5 Step 3
  gives the exact remedy if the corner-pixel assertion shows a swap.
- **Type consistency:** `decodeRawFrame(Uint8List) -> Image` is defined in Task 1
  and consumed identically in Task 4. The host CLI contract
  `host <assets_dir> <icu_data_path> <output_raw_file>` matches between Task 3
  and Task 4. The raw frame header (`width`, `height`, `rowBytes`, uint32 LE) is
  written in Task 3 and parsed in Task 1.
- **Deferred items** (window, GPU/Metal, GUI display, hot reload, animation) are
  intentionally absent.

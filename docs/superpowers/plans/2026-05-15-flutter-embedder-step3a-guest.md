# Flutter Embedder — Step 3a (Plan 1): Guest process & wire protocol

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the step-2 one-shot C host into a long-lived, out-of-process Flutter-engine *guest* that renders an animated, interactive scene into shared `IOSurface`s and exchanges frames/input with a controlling process over a Unix-domain-socket wire protocol.

**Architecture:** The guest connects to a Unix socket, runs the engine with the software renderer, and `memcpy`s every composited RGBA frame into one of three ring-buffered `IOSurface`s (swapping to BGRA). It announces surfaces by `IOSurfaceID`, signals each frame with a `FrameReady` message, and accepts `Resize`/`PointerEvent`/`KeyEvent`/`Shutdown` messages. A pure-Dart codec (`protocol.dart`) encodes/decodes the same wire format. `run.dart` becomes a thin protocol client that captures one frame to a PNG; an integration test drives the guest end to end.

**Tech Stack:** Dart (`package:image`, `package:path`, `package:test`), C11, CMake, the prebuilt Flutter engine (`FlutterEmbedder.framework`), macOS `IOSurface`/`CoreFoundation`.

**Reference spec:** `docs/superpowers/specs/2026-05-15-flutter-embedder-step3a-design.md`

**Environment assumptions (verified):**
- Run all Dart commands with the Flutter-bundled SDK: `/Users/xavier/flutter/bin/dart`.
- The embedder lives in `flutterware_app` under `app/`. Existing files: `app/lib/src/embedder/{compiler.dart,flutter_cache.dart,raw_frame.dart,README.md}`, `app/native/{host.c,CMakeLists.txt,flutter_embedder.h}`, `app/tool/embedder/{run.dart,compile.dart,scene.dart}`, tests under `app/test/embedder/raw_frame_test.dart` and `app/integration_test/embedder/{compiler_test.dart,flutter_cache_test.dart,render_test.dart}`.
- `FlutterEmbedder.framework` is at `app/.engine/FlutterEmbedder.framework` (gitignored; step 1 fetched it). CMake builds against it via `-DFLUTTER_FRAMEWORK_DIR`.
- `app/native/flutter_embedder.h` defines `FlutterSoftwareRendererConfig` (`surface_present_callback`), `FlutterWindowMetricsEvent` / `FlutterEngineSendWindowMetricsEvent`, `FlutterPointerEvent` / `FlutterEngineSendPointerEvent`, `FlutterKeyEvent` / `FlutterEngineSendKeyEvent`, and the enums `FlutterPointerPhase { kCancel, kUp, kDown, kMove, kAdd, kRemove, kHover, ... }`, `FlutterPointerSignalKind`, `FlutterPointerDeviceKind`, `FlutterKeyEventType { kFlutterKeyEventTypeUp, kFlutterKeyEventTypeDown, kFlutterKeyEventTypeRepeat }`.
- macOS arm64. CMake ≥ 3.15, `curl`, `unzip` on PATH.
- The host is little-endian (arm64/x64), so the C side writes integers with `memcpy` and the Dart side reads them little-endian.

**Lint notes (from `analysis_options.yaml`):** `prefer_single_quotes`, `omit_local_variable_types` (prefer `var`), `avoid_final_parameters`, `unawaited_futures` (wrap fire-and-forget in `unawaited(...)`). `prefer_const_*` Flutter lints are **off**.

---

## File structure

| File | Responsibility |
|---|---|
| `app/lib/src/embedder/protocol.dart` (new) | Pure-Dart wire-protocol message types + codec + `FrameReader`. |
| `app/test/embedder/protocol_test.dart` (new) | Fast unit tests for the codec. |
| `app/lib/src/embedder/embedder_build.dart` (new) | Reusable orchestration: ensure `FlutterEmbedder.framework`, compile a scene, build the C host. |
| `app/tool/embedder/scene.dart` (modify) | Animated, interactive `runApp` scene. |
| `app/native/surface.h` / `surface.c` (new) | `IOSurface` triple-buffer ring. |
| `app/native/ipc.h` / `ipc.c` (new) | Unix socket connect + framed read/write. |
| `app/native/input.h` / `input.c` (new) | Decode pointer/key messages → engine calls. |
| `app/native/host.c` (rewrite) | Long-lived guest main loop. |
| `app/native/CMakeLists.txt` (modify) | Compile the new sources, link `IOSurface`/`CoreFoundation`. |
| `app/tool/embedder/run.dart` (rewrite) | Thin protocol client: spawn guest, capture one frame → PNG. |
| `app/integration_test/embedder/live_bridge_test.dart` (new) | End-to-end guest + protocol test. |
| `app/integration_test/embedder/render_test.dart` (delete) | Superseded by `live_bridge_test.dart`. |
| `app/lib/src/embedder/README.md` (modify) | Document the step-3a guest. |

---

## Task 1: Wire-protocol codec

**Files:**
- Create: `app/lib/src/embedder/protocol.dart`
- Test: `app/test/embedder/protocol_test.dart`

Pure logic, no I/O — a fast unit test that runs in the default `flutter test`.

Wire frame: `[uint32 LE length][uint8 type][payload]`, where `length` counts the
type byte plus the payload. All integers little-endian; doubles IEEE-754 LE.

- [ ] **Step 1: Write the failing test**

`app/test/embedder/protocol_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:test/test.dart';

void main() {
  T roundTrip<T extends EmbedderMessage>(T message) {
    var reader = FrameReader();
    var decoded = reader.addBytes(encodeMessage(message)).toList();
    expect(decoded, hasLength(1));
    return decoded.single as T;
  }

  test('round-trips Ready', () {
    expect(roundTrip(const ReadyMessage()), isA<ReadyMessage>());
  });

  test('round-trips Shutdown', () {
    expect(roundTrip(const ShutdownMessage()), isA<ShutdownMessage>());
  });

  test('round-trips SurfacesAllocated', () {
    var msg = roundTrip(const SurfacesAllocatedMessage(
      generation: 7,
      width: 800,
      height: 600,
      rowBytes: 3200,
      surfaceIds: [11, 22, 33],
    ));
    expect(msg.generation, 7);
    expect(msg.width, 800);
    expect(msg.height, 600);
    expect(msg.rowBytes, 3200);
    expect(msg.surfaceIds, [11, 22, 33]);
  });

  test('round-trips FrameReady with a large frameId', () {
    var msg = roundTrip(const FrameReadyMessage(
        ringIndex: 2, frameId: 0x1_0000_0001));
    expect(msg.ringIndex, 2);
    expect(msg.frameId, 0x1_0000_0001);
  });

  test('round-trips Error', () {
    var msg = roundTrip(const ErrorMessage('engine failed: 42'));
    expect(msg.message, 'engine failed: 42');
  });

  test('round-trips Resize', () {
    var msg = roundTrip(const ResizeMessage(
        width: 1024, height: 768, pixelRatio: 2.0));
    expect(msg.width, 1024);
    expect(msg.height, 768);
    expect(msg.pixelRatio, 2.0);
  });

  test('round-trips PointerEvent', () {
    var msg = roundTrip(const PointerEventMessage(
      phase: PointerPhase.down,
      x: 12.5,
      y: 64.25,
      buttons: 1,
      scrollDeltaX: 0.0,
      scrollDeltaY: -3.5,
      timestampMicros: 123456,
    ));
    expect(msg.phase, PointerPhase.down);
    expect(msg.x, 12.5);
    expect(msg.y, 64.25);
    expect(msg.buttons, 1);
    expect(msg.scrollDeltaY, -3.5);
    expect(msg.timestampMicros, 123456);
  });

  test('round-trips KeyEvent', () {
    var msg = roundTrip(const KeyEventMessage(
      kind: KeyEventKind.down,
      physicalKey: 0x00070004,
      logicalKey: 0x00000061,
      modifiers: 0,
      timestampMicros: 999,
    ));
    expect(msg.kind, KeyEventKind.down);
    expect(msg.physicalKey, 0x00070004);
    expect(msg.logicalKey, 0x00000061);
    expect(msg.timestampMicros, 999);
  });

  test('FrameReader splits two concatenated frames', () {
    var bytes = BytesBuilder()
      ..add(encodeMessage(const ReadyMessage()))
      ..add(encodeMessage(const FrameReadyMessage(ringIndex: 0, frameId: 1)));
    var decoded = FrameReader().addBytes(bytes.toBytes()).toList();
    expect(decoded, hasLength(2));
    expect(decoded[0], isA<ReadyMessage>());
    expect(decoded[1], isA<FrameReadyMessage>());
  });

  test('FrameReader reassembles a frame delivered byte by byte', () {
    var frame = encodeMessage(const FrameReadyMessage(ringIndex: 1, frameId: 9));
    var reader = FrameReader();
    var decoded = <EmbedderMessage>[];
    for (var b in frame) {
      decoded.addAll(reader.addBytes([b]));
    }
    expect(decoded, hasLength(1));
    expect((decoded.single as FrameReadyMessage).frameId, 9);
  });

  test('decodeMessageBody rejects an unknown type tag', () {
    expect(() => decodeMessageBody(Uint8List.fromList([0xFF])),
        throwsFormatException);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && /Users/xavier/flutter/bin/dart test test/embedder/protocol_test.dart`
Expected: FAIL — `protocol.dart` does not exist.

- [ ] **Step 3: Implement the protocol**

`app/lib/src/embedder/protocol.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

/// Wire protocol shared with the embedder guest process (`app/native/`).
///
/// Each frame on the socket is `[uint32 LE length][uint8 type][payload]`,
/// where `length` counts the type byte plus the payload. Integers are
/// little-endian; doubles are IEEE-754 little-endian.

/// Message type tags. Must match the `kMsg*` enum in `app/native/ipc.h`.
enum MessageType {
  ready(1),
  surfacesAllocated(2),
  frameReady(3),
  error(4),
  resize(5),
  pointerEvent(6),
  keyEvent(7),
  shutdown(8);

  const MessageType(this.tag);
  final int tag;

  static MessageType fromTag(int tag) => values.firstWhere(
        (t) => t.tag == tag,
        orElse: () => throw FormatException('Unknown message tag: $tag'),
      );
}

/// Pointer phases; the index order matches `FlutterPointerPhase` in
/// `flutter_embedder.h` so the guest can cast the index directly.
enum PointerPhase { cancel, up, down, move, add, remove, hover }

enum KeyEventKind { down, up, repeat }

sealed class EmbedderMessage {
  const EmbedderMessage();
}

class ReadyMessage extends EmbedderMessage {
  const ReadyMessage();
}

class SurfacesAllocatedMessage extends EmbedderMessage {
  const SurfacesAllocatedMessage({
    required this.generation,
    required this.width,
    required this.height,
    required this.rowBytes,
    required this.surfaceIds,
  });

  final int generation;
  final int width;
  final int height;
  final int rowBytes;
  final List<int> surfaceIds;
}

class FrameReadyMessage extends EmbedderMessage {
  const FrameReadyMessage({required this.ringIndex, required this.frameId});

  final int ringIndex;
  final int frameId;
}

class ErrorMessage extends EmbedderMessage {
  const ErrorMessage(this.message);

  final String message;
}

class ResizeMessage extends EmbedderMessage {
  const ResizeMessage({
    required this.width,
    required this.height,
    required this.pixelRatio,
  });

  final int width;
  final int height;
  final double pixelRatio;
}

class PointerEventMessage extends EmbedderMessage {
  const PointerEventMessage({
    required this.phase,
    required this.x,
    required this.y,
    required this.buttons,
    required this.scrollDeltaX,
    required this.scrollDeltaY,
    required this.timestampMicros,
  });

  final PointerPhase phase;
  final double x;
  final double y;
  final int buttons;
  final double scrollDeltaX;
  final double scrollDeltaY;
  final int timestampMicros;
}

class KeyEventMessage extends EmbedderMessage {
  const KeyEventMessage({
    required this.kind,
    required this.physicalKey,
    required this.logicalKey,
    required this.modifiers,
    required this.timestampMicros,
  });

  final KeyEventKind kind;
  final int physicalKey;
  final int logicalKey;
  final int modifiers;
  final int timestampMicros;
}

class ShutdownMessage extends EmbedderMessage {
  const ShutdownMessage();
}

void _u32(BytesBuilder b, int value) {
  var d = ByteData(4)..setUint32(0, value, Endian.little);
  b.add(d.buffer.asUint8List());
}

void _u64(BytesBuilder b, int value) {
  var d = ByteData(8)..setUint64(0, value, Endian.little);
  b.add(d.buffer.asUint8List());
}

void _f64(BytesBuilder b, double value) {
  var d = ByteData(8)..setFloat64(0, value, Endian.little);
  b.add(d.buffer.asUint8List());
}

/// Encodes [message] into a complete wire frame (length prefix included).
Uint8List encodeMessage(EmbedderMessage message) {
  var body = BytesBuilder();
  switch (message) {
    case ReadyMessage():
      body.addByte(MessageType.ready.tag);
    case SurfacesAllocatedMessage():
      body.addByte(MessageType.surfacesAllocated.tag);
      _u32(body, message.generation);
      _u32(body, message.surfaceIds.length);
      _u32(body, message.width);
      _u32(body, message.height);
      _u32(body, message.rowBytes);
      for (var id in message.surfaceIds) {
        _u32(body, id);
      }
    case FrameReadyMessage():
      body.addByte(MessageType.frameReady.tag);
      _u32(body, message.ringIndex);
      _u64(body, message.frameId);
    case ErrorMessage():
      body.addByte(MessageType.error.tag);
      var bytes = utf8.encode(message.message);
      _u32(body, bytes.length);
      body.add(bytes);
    case ResizeMessage():
      body.addByte(MessageType.resize.tag);
      _u32(body, message.width);
      _u32(body, message.height);
      _f64(body, message.pixelRatio);
    case PointerEventMessage():
      body.addByte(MessageType.pointerEvent.tag);
      _u32(body, message.phase.index);
      _f64(body, message.x);
      _f64(body, message.y);
      _u32(body, message.buttons);
      _f64(body, message.scrollDeltaX);
      _f64(body, message.scrollDeltaY);
      _u64(body, message.timestampMicros);
    case KeyEventMessage():
      body.addByte(MessageType.keyEvent.tag);
      _u32(body, message.kind.index);
      _u64(body, message.physicalKey);
      _u64(body, message.logicalKey);
      _u32(body, message.modifiers);
      _u64(body, message.timestampMicros);
    case ShutdownMessage():
      body.addByte(MessageType.shutdown.tag);
  }
  var bodyBytes = body.toBytes();
  var frame = BytesBuilder();
  _u32(frame, bodyBytes.length);
  frame.add(bodyBytes);
  return frame.toBytes();
}

/// Decodes one frame body (`[uint8 type][payload]`, no length prefix).
EmbedderMessage decodeMessageBody(Uint8List body) {
  if (body.isEmpty) {
    throw FormatException('Empty message body');
  }
  var type = MessageType.fromTag(body[0]);
  var data = ByteData.sublistView(body, 1);
  switch (type) {
    case MessageType.ready:
      return const ReadyMessage();
    case MessageType.shutdown:
      return const ShutdownMessage();
    case MessageType.surfacesAllocated:
      var generation = data.getUint32(0, Endian.little);
      var count = data.getUint32(4, Endian.little);
      var width = data.getUint32(8, Endian.little);
      var height = data.getUint32(12, Endian.little);
      var rowBytes = data.getUint32(16, Endian.little);
      var ids = [
        for (var i = 0; i < count; i++)
          data.getUint32(20 + i * 4, Endian.little),
      ];
      return SurfacesAllocatedMessage(
        generation: generation,
        width: width,
        height: height,
        rowBytes: rowBytes,
        surfaceIds: ids,
      );
    case MessageType.frameReady:
      return FrameReadyMessage(
        ringIndex: data.getUint32(0, Endian.little),
        frameId: data.getUint64(4, Endian.little),
      );
    case MessageType.error:
      var len = data.getUint32(0, Endian.little);
      var text = utf8.decode(
          body.sublist(1 + 4, 1 + 4 + len));
      return ErrorMessage(text);
    case MessageType.resize:
      return ResizeMessage(
        width: data.getUint32(0, Endian.little),
        height: data.getUint32(4, Endian.little),
        pixelRatio: data.getFloat64(8, Endian.little),
      );
    case MessageType.pointerEvent:
      return PointerEventMessage(
        phase: PointerPhase.values[data.getUint32(0, Endian.little)],
        x: data.getFloat64(4, Endian.little),
        y: data.getFloat64(12, Endian.little),
        buttons: data.getUint32(20, Endian.little),
        scrollDeltaX: data.getFloat64(24, Endian.little),
        scrollDeltaY: data.getFloat64(32, Endian.little),
        timestampMicros: data.getUint64(40, Endian.little),
      );
    case MessageType.keyEvent:
      return KeyEventMessage(
        kind: KeyEventKind.values[data.getUint32(0, Endian.little)],
        physicalKey: data.getUint64(4, Endian.little),
        logicalKey: data.getUint64(12, Endian.little),
        modifiers: data.getUint32(20, Endian.little),
        timestampMicros: data.getUint64(24, Endian.little),
      );
  }
}

/// Accumulates socket bytes and yields complete messages as frames arrive.
class FrameReader {
  final BytesBuilder _buffer = BytesBuilder();

  Iterable<EmbedderMessage> addBytes(List<int> chunk) sync* {
    _buffer.add(chunk);
    var data = _buffer.toBytes();
    var offset = 0;
    while (data.length - offset >= 4) {
      var len = ByteData.sublistView(data, offset, offset + 4)
          .getUint32(0, Endian.little);
      if (data.length - offset - 4 < len) break;
      var bodyStart = offset + 4;
      yield decodeMessageBody(
          Uint8List.sublistView(data, bodyStart, bodyStart + len));
      offset = bodyStart + len;
    }
    _buffer.clear();
    if (offset < data.length) {
      _buffer.add(data.sublist(offset));
    }
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && /Users/xavier/flutter/bin/dart test test/embedder/protocol_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/embedder/protocol.dart app/test/embedder/protocol_test.dart
git commit -m "Add embedder wire-protocol codec"
```

---

## Task 2: Animated, interactive scene

**Files:**
- Modify: `app/tool/embedder/scene.dart`

The scene must animate continuously (so frames flow) and respond to a tap (so
input forwarding can be verified). `compiler_test.dart` already compiles
`scene.dart`, so no test change is needed.

- [ ] **Step 1: Replace `app/tool/embedder/scene.dart` entirely with:**

```dart
import 'package:flutter/material.dart';

void main() => runApp(const _EmbedderScene());

class _EmbedderScene extends StatelessWidget {
  const _EmbedderScene();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const _SceneBody(),
    );
  }
}

class _SceneBody extends StatefulWidget {
  const _SceneBody();

  @override
  State<_SceneBody> createState() => _SceneBodyState();
}

class _SceneBodyState extends State<_SceneBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  int _taps = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1565C0),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RotationTransition(
              turns: _controller,
              child: Container(width: 120, height: 120, color: Colors.white),
            ),
            const SizedBox(height: 32),
            Text('Taps: $_taps',
                style: const TextStyle(color: Colors.white, fontSize: 32)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() => _taps++),
              child: const Text('Tap me'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify the scene still compiles**

Run: `cd app && /Users/xavier/flutter/bin/dart test integration_test/embedder/compiler_test.dart`
Expected: PASS — `frontend_server` compiles `scene.dart` to a non-empty kernel blob.

- [ ] **Step 3: Commit**

```bash
git add app/tool/embedder/scene.dart
git commit -m "Make the embedder scene animated and interactive"
```

---

## Task 3: Reusable build orchestration

**Files:**
- Create: `app/lib/src/embedder/embedder_build.dart`

Extracts the framework-download and host-build logic so both `run.dart` and the
Plan-2 `EmbeddedEngine` can reuse it. No new behaviour — this is the step-2
`run.dart` orchestration lifted into a library, minus the render step.

- [ ] **Step 1: Create `app/lib/src/embedder/embedder_build.dart`:**

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import 'compiler.dart';
import 'flutter_cache.dart';

/// Ensures `FlutterEmbedder.framework` (the C embedder API, not part of the
/// local Flutter cache) is present under [engineDir], downloading it from
/// Flutter's artifact storage if it is missing or built for a different
/// engine revision.
Future<void> ensureEmbedderFramework(
    FlutterCache cache, String engineDir) async {
  var revision = cache.engineRevision;
  var frameworkDir = p.join(engineDir, 'FlutterEmbedder.framework');
  var stamp = File(p.join(engineDir, 'engine.revision'));
  if (Directory(frameworkDir).existsSync() &&
      stamp.existsSync() &&
      stamp.readAsStringSync().trim() == revision) {
    return;
  }

  stdout.writeln('[embedder] downloading FlutterEmbedder.framework ($revision)');
  if (Directory(frameworkDir).existsSync()) {
    Directory(frameworkDir).deleteSync(recursive: true);
  }
  Directory(engineDir).createSync(recursive: true);

  var url = 'https://storage.googleapis.com/flutter_infra_release/flutter/'
      '$revision/darwin-x64/FlutterEmbedder.framework.zip';
  var zip = p.join(engineDir, 'FlutterEmbedder.framework.zip');
  await _run('curl', ['-fSL', url, '-o', zip]);
  await _run('unzip', ['-q', '-o', zip, '-d', frameworkDir]);
  File(zip).deleteSync();
  stamp.writeAsStringSync(revision);
}

/// Compiles the embedder scene at [scenePath] to a kernel blob at [kernelBlob].
Future<void> compileScene({
  required String scenePath,
  required String kernelBlob,
  required String packageConfig,
  required FlutterCache cache,
}) async {
  stdout.writeln('[embedder] compiling ${p.basename(scenePath)} -> kernel');
  await compileToKernel(
    entrypoint: scenePath,
    outputDill: kernelBlob,
    packageConfig: packageConfig,
    cache: cache,
  );
}

/// Configures and builds the C host with CMake into [nativeBuildDir].
/// Returns the path to the built `host` executable.
Future<String> buildHost({
  required String nativeSourceDir,
  required String nativeBuildDir,
  required String engineDir,
}) async {
  stdout.writeln('[embedder] configuring + building the C host');
  await _run('cmake', [
    '-S', nativeSourceDir,
    '-B', nativeBuildDir,
    '-DFLUTTER_FRAMEWORK_DIR=$engineDir',
  ]);
  await _run('cmake', ['--build', nativeBuildDir]);
  return p.join(nativeBuildDir, 'host');
}

Future<void> _run(String executable, List<String> args) async {
  var process = await Process.start(executable, args,
      mode: ProcessStartMode.inheritStdio);
  var code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(
        executable, args, 'exited with $code', code);
  }
}
```

- [ ] **Step 2: Verify analysis is clean**

Run: `cd app && /Users/xavier/flutter/bin/dart analyze lib/src/embedder/embedder_build.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add app/lib/src/embedder/embedder_build.dart
git commit -m "Extract reusable embedder build orchestration"
```

---

## Task 4: C guest — IOSurface ring

**Files:**
- Create: `app/native/surface.h`
- Create: `app/native/surface.c`

Three BGRA `IOSurface`s in a ring. The guest renders into one slot per frame.
The software renderer hands the present callback an **RGBA** buffer (step 2
confirmed RGBA byte order); this code swaps to BGRA while copying, because the
GUI side wraps the surface as a `kCVPixelFormatType_32BGRA` `CVPixelBuffer`.

- [ ] **Step 1: Create `app/native/surface.h`:**

```c
#ifndef EMBEDDER_SURFACE_H
#define EMBEDDER_SURFACE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// A ring of three IOSurfaces shared with the GUI process. The guest renders
// into one slot at a time; the GUI reads whichever slot FrameReady names.
#define SURFACE_RING_COUNT 3

// Allocates a fresh ring of BGRA IOSurfaces sized width x height, releasing
// any previous ring. Returns false on allocation failure.
bool surface_ring_init(int width, int height);

// Releases the ring.
void surface_ring_destroy(void);

// Copies an RGBA frame from the software renderer into the next ring slot,
// swapping channels to BGRA. Returns the slot index written, or -1 if no ring
// exists.
int surface_ring_present(const void* rgba, size_t row_bytes, size_t height);

// Fills out[SURFACE_RING_COUNT] with the global IOSurfaceIDs of the ring.
void surface_ring_ids(uint32_t out[SURFACE_RING_COUNT]);

int surface_ring_width(void);
int surface_ring_height(void);
size_t surface_ring_row_bytes(void);

#endif  // EMBEDDER_SURFACE_H
```

- [ ] **Step 2: Create `app/native/surface.c`:**

```c
#include "surface.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOSurface/IOSurface.h>

static IOSurfaceRef g_ring[SURFACE_RING_COUNT];
static int g_width;
static int g_height;
static int g_next;

static IOSurfaceRef CreateSurface(int width, int height) {
  int bpe = 4;
  int bpr = width * 4;
  int pixel_format = 0x42475241;  // 'BGRA'
  CFMutableDictionaryRef props = CFDictionaryCreateMutable(
      kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
      &kCFTypeDictionaryValueCallBacks);
  CFNumberRef w = CFNumberCreate(NULL, kCFNumberIntType, &width);
  CFNumberRef h = CFNumberCreate(NULL, kCFNumberIntType, &height);
  CFNumberRef e = CFNumberCreate(NULL, kCFNumberIntType, &bpe);
  CFNumberRef r = CFNumberCreate(NULL, kCFNumberIntType, &bpr);
  CFNumberRef f = CFNumberCreate(NULL, kCFNumberIntType, &pixel_format);
  CFDictionarySetValue(props, kIOSurfaceWidth, w);
  CFDictionarySetValue(props, kIOSurfaceHeight, h);
  CFDictionarySetValue(props, kIOSurfaceBytesPerElement, e);
  CFDictionarySetValue(props, kIOSurfaceBytesPerRow, r);
  CFDictionarySetValue(props, kIOSurfacePixelFormat, f);
  IOSurfaceRef surface = IOSurfaceCreate(props);
  CFRelease(w);
  CFRelease(h);
  CFRelease(e);
  CFRelease(r);
  CFRelease(f);
  CFRelease(props);
  return surface;
}

bool surface_ring_init(int width, int height) {
  surface_ring_destroy();
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    g_ring[i] = CreateSurface(width, height);
    if (!g_ring[i]) {
      surface_ring_destroy();
      return false;
    }
  }
  g_width = width;
  g_height = height;
  g_next = 0;
  return true;
}

void surface_ring_destroy(void) {
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    if (g_ring[i]) {
      CFRelease(g_ring[i]);
      g_ring[i] = NULL;
    }
  }
  g_width = 0;
  g_height = 0;
  g_next = 0;
}

int surface_ring_present(const void* rgba, size_t row_bytes, size_t height) {
  if (!g_ring[0]) return -1;
  int slot = g_next;
  IOSurfaceRef surface = g_ring[slot];
  IOSurfaceLock(surface, 0, NULL);
  uint8_t* dst = (uint8_t*)IOSurfaceGetBaseAddress(surface);
  size_t dst_stride = IOSurfaceGetBytesPerRow(surface);
  const uint8_t* src = (const uint8_t*)rgba;
  size_t rows = height < (size_t)g_height ? height : (size_t)g_height;
  size_t cols = (size_t)g_width;
  for (size_t y = 0; y < rows; y++) {
    const uint8_t* s = src + y * row_bytes;
    uint8_t* d = dst + y * dst_stride;
    for (size_t x = 0; x < cols; x++) {
      d[x * 4 + 0] = s[x * 4 + 2];  // B <- R
      d[x * 4 + 1] = s[x * 4 + 1];  // G
      d[x * 4 + 2] = s[x * 4 + 0];  // R <- B
      d[x * 4 + 3] = s[x * 4 + 3];  // A
    }
  }
  IOSurfaceUnlock(surface, 0, NULL);
  g_next = (g_next + 1) % SURFACE_RING_COUNT;
  return slot;
}

void surface_ring_ids(uint32_t out[SURFACE_RING_COUNT]) {
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    out[i] = g_ring[i] ? IOSurfaceGetID(g_ring[i]) : 0;
  }
}

int surface_ring_width(void) { return g_width; }
int surface_ring_height(void) { return g_height; }

size_t surface_ring_row_bytes(void) {
  return g_ring[0] ? IOSurfaceGetBytesPerRow(g_ring[0]) : 0;
}
```

- [ ] **Step 3: Commit**

```bash
git add app/native/surface.h app/native/surface.c
git commit -m "Add IOSurface triple-buffer ring for the embedder guest"
```

(Compilation is verified together with the rest of the host in Task 7.)

---

## Task 5: C guest — IPC socket

**Files:**
- Create: `app/native/ipc.h`
- Create: `app/native/ipc.c`

Unix-domain-socket connect plus framed read/write matching `protocol.dart`.
`ipc_send` is mutex-guarded so the raster thread (FrameReady) and the main
thread (SurfacesAllocated, Error) can both write.

- [ ] **Step 1: Create `app/native/ipc.h`:**

```c
#ifndef EMBEDDER_IPC_H
#define EMBEDDER_IPC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Wire message type tags. Must match MessageType in protocol.dart.
enum {
  kMsgReady = 1,
  kMsgSurfacesAllocated = 2,
  kMsgFrameReady = 3,
  kMsgError = 4,
  kMsgResize = 5,
  kMsgPointerEvent = 6,
  kMsgKeyEvent = 7,
  kMsgShutdown = 8,
};

// Connects to the GUI's Unix domain socket. Returns the fd, or -1 on failure.
int ipc_connect(const char* socket_path);

// Sends one framed message: [uint32 len][uint8 type][payload]. Thread-safe.
bool ipc_send(int fd, uint8_t type, const uint8_t* payload, size_t len);

// Reads exactly one framed message. On success returns the type tag and sets
// *payload (malloc'd, caller frees; NULL if empty) and *len. Returns -1 on
// EOF or error.
int ipc_read(int fd, uint8_t** payload, size_t* len);

#endif  // EMBEDDER_IPC_H
```

- [ ] **Step 2: Create `app/native/ipc.c`:**

```c
#include "ipc.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static pthread_mutex_t g_write_mutex = PTHREAD_MUTEX_INITIALIZER;

int ipc_connect(const char* socket_path) {
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) return -1;
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);
  if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
    close(fd);
    return -1;
  }
  return fd;
}

static bool write_all(int fd, const uint8_t* data, size_t len) {
  size_t off = 0;
  while (off < len) {
    ssize_t n = write(fd, data + off, len - off);
    if (n <= 0) return false;
    off += (size_t)n;
  }
  return true;
}

static bool read_all(int fd, uint8_t* data, size_t len) {
  size_t off = 0;
  while (off < len) {
    ssize_t n = read(fd, data + off, len - off);
    if (n <= 0) return false;
    off += (size_t)n;
  }
  return true;
}

bool ipc_send(int fd, uint8_t type, const uint8_t* payload, size_t len) {
  uint32_t frame_len = (uint32_t)(1 + len);
  uint8_t header[5];
  memcpy(header, &frame_len, 4);  // host is little-endian
  header[4] = type;
  pthread_mutex_lock(&g_write_mutex);
  bool ok = write_all(fd, header, 5) &&
            (len == 0 || write_all(fd, payload, len));
  pthread_mutex_unlock(&g_write_mutex);
  return ok;
}

int ipc_read(int fd, uint8_t** payload, size_t* len) {
  uint8_t header[5];
  if (!read_all(fd, header, 5)) return -1;
  uint32_t frame_len;
  memcpy(&frame_len, header, 4);
  if (frame_len < 1) return -1;
  size_t payload_len = frame_len - 1;
  uint8_t* buf = payload_len ? (uint8_t*)malloc(payload_len) : NULL;
  if (payload_len && !read_all(fd, buf, payload_len)) {
    free(buf);
    return -1;
  }
  *payload = buf;
  *len = payload_len;
  return header[4];
}
```

- [ ] **Step 3: Commit**

```bash
git add app/native/ipc.h app/native/ipc.c
git commit -m "Add Unix-socket IPC for the embedder guest"
```

---

## Task 6: C guest — input translation

**Files:**
- Create: `app/native/input.h`
- Create: `app/native/input.c`

Decodes `PointerEvent` / `KeyEvent` payloads (the exact byte layout produced by
`encodeMessage` in `protocol.dart`) into embedder API calls.

`PointerEvent` payload: `u32 phase, f64 x, f64 y, u32 buttons, f64 scrollDX,
f64 scrollDY, u64 timestamp` — 48 bytes. `KeyEvent` payload: `u32 kind, u64
physical, u64 logical, u32 modifiers, u64 timestamp` — 32 bytes.

- [ ] **Step 1: Create `app/native/input.h`:**

```c
#ifndef EMBEDDER_INPUT_H
#define EMBEDDER_INPUT_H

#include <stddef.h>
#include <stdint.h>

#include "flutter_embedder.h"

// Decodes a PointerEvent payload and forwards it to the engine.
void input_handle_pointer(FlutterEngine engine, const uint8_t* payload,
                          size_t len);

// Decodes a KeyEvent payload and forwards it to the engine.
void input_handle_key(FlutterEngine engine, const uint8_t* payload,
                      size_t len);

#endif  // EMBEDDER_INPUT_H
```

- [ ] **Step 2: Create `app/native/input.c`:**

```c
#include "input.h"

#include <string.h>

static uint32_t rd_u32(const uint8_t* p, size_t off) {
  uint32_t v;
  memcpy(&v, p + off, 4);
  return v;
}

static uint64_t rd_u64(const uint8_t* p, size_t off) {
  uint64_t v;
  memcpy(&v, p + off, 8);
  return v;
}

static double rd_f64(const uint8_t* p, size_t off) {
  double v;
  memcpy(&v, p + off, 8);
  return v;
}

void input_handle_pointer(FlutterEngine engine, const uint8_t* p, size_t len) {
  if (len < 48) return;
  FlutterPointerEvent ev = {0};
  ev.struct_size = sizeof(FlutterPointerEvent);
  // protocol PointerPhase order matches FlutterPointerPhase.
  ev.phase = (FlutterPointerPhase)rd_u32(p, 0);
  ev.x = rd_f64(p, 4);
  ev.y = rd_f64(p, 12);
  ev.buttons = (int64_t)rd_u32(p, 20);
  double scroll_dx = rd_f64(p, 24);
  double scroll_dy = rd_f64(p, 32);
  ev.timestamp = (size_t)rd_u64(p, 40);
  ev.device_kind = kFlutterPointerDeviceKindMouse;
  if (scroll_dx != 0.0 || scroll_dy != 0.0) {
    ev.signal_kind = kFlutterPointerSignalKindScroll;
    ev.scroll_delta_x = scroll_dx;
    ev.scroll_delta_y = scroll_dy;
  }
  FlutterEngineSendPointerEvent(engine, &ev, 1);
}

void input_handle_key(FlutterEngine engine, const uint8_t* p, size_t len) {
  if (len < 32) return;
  FlutterKeyEvent ev = {0};
  ev.struct_size = sizeof(FlutterKeyEvent);
  uint32_t kind = rd_u32(p, 0);  // 0 down, 1 up, 2 repeat
  ev.type = kind == 1   ? kFlutterKeyEventTypeUp
            : kind == 2 ? kFlutterKeyEventTypeRepeat
                        : kFlutterKeyEventTypeDown;
  ev.physical = rd_u64(p, 4);
  ev.logical = rd_u64(p, 12);
  // modifiers (offset 20, u32) are not part of FlutterKeyEvent; ignored in 3a.
  ev.timestamp = (double)rd_u64(p, 24);
  ev.character = NULL;
  ev.synthesized = false;
  FlutterEngineSendKeyEvent(engine, &ev, NULL, NULL);
}
```

- [ ] **Step 3: Commit**

```bash
git add app/native/input.h app/native/input.c
git commit -m "Add input-event translation for the embedder guest"
```

---

## Task 7: C guest — long-lived main loop

**Files:**
- Rewrite: `app/native/host.c`
- Modify: `app/native/CMakeLists.txt`

The host stops being a one-shot render-and-exit program. It connects to the
socket, runs the engine, presents into the ring, and serves the socket read
loop on the main thread until `Shutdown` or EOF.

**Ordering guarantee:** `surface_present_callback` sends `FrameReady` while
holding `g_ring_mutex`, and the resize handler sends `SurfacesAllocated` while
holding the same mutex. This guarantees the GUI never sees a `FrameReady` for a
ring generation before the matching `SurfacesAllocated`.

- [ ] **Step 1: Replace `app/native/host.c` entirely with:**

```c
// Long-lived Flutter-engine guest: runs a kernel blob, renders with the
// software renderer into shared IOSurfaces, and exchanges frames + input with
// a controlling process over a Unix domain socket.
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "flutter_embedder.h"
#include "input.h"
#include "ipc.h"
#include "surface.h"

static int g_socket = -1;
static FlutterEngine g_engine = NULL;
static pthread_mutex_t g_ring_mutex = PTHREAD_MUTEX_INITIALIZER;
static uint32_t g_generation = 0;
static uint64_t g_frame_id = 0;
static double g_pixel_ratio = 1.0;

// Optional headless smoke: dump the first frame as a step-2 raw file.
static const char* g_capture_path = NULL;
static bool g_captured = false;

// Receives engine log output, including Dart print(). Kept on stdout so the
// control socket carries only protocol traffic.
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

// Writes a step-2 raw frame file: 12-byte LE header (width, height, row_bytes)
// then the raw RGBA pixels straight from the software renderer.
static void WriteRawCapture(const char* path, const void* rgba,
                            size_t row_bytes, size_t height) {
  FILE* f = fopen(path, "wb");
  if (!f) return;
  uint32_t header[3] = {(uint32_t)surface_ring_width(), (uint32_t)height,
                        (uint32_t)row_bytes};
  fwrite(header, sizeof(uint32_t), 3, f);
  fwrite(rgba, 1, row_bytes * height, f);
  fclose(f);
}

static void SendSurfacesAllocated(void) {
  uint32_t ids[SURFACE_RING_COUNT];
  surface_ring_ids(ids);
  uint8_t payload[5 * 4 + SURFACE_RING_COUNT * 4];
  uint32_t generation = g_generation;
  uint32_t count = SURFACE_RING_COUNT;
  uint32_t width = (uint32_t)surface_ring_width();
  uint32_t height = (uint32_t)surface_ring_height();
  uint32_t row_bytes = (uint32_t)surface_ring_row_bytes();
  memcpy(payload + 0, &generation, 4);
  memcpy(payload + 4, &count, 4);
  memcpy(payload + 8, &width, 4);
  memcpy(payload + 12, &height, 4);
  memcpy(payload + 16, &row_bytes, 4);
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    memcpy(payload + 20 + i * 4, &ids[i], 4);
  }
  ipc_send(g_socket, kMsgSurfacesAllocated, payload, sizeof(payload));
}

static void SendWindowMetrics(int width, int height, double pixel_ratio) {
  FlutterWindowMetricsEvent metrics = {0};
  metrics.struct_size = sizeof(FlutterWindowMetricsEvent);
  metrics.width = (size_t)width;
  metrics.height = (size_t)height;
  metrics.pixel_ratio = pixel_ratio;
  FlutterEngineSendWindowMetricsEvent(g_engine, &metrics);
}

// Software renderer present callback (engine raster thread). Copies the frame
// into the ring and notifies the GUI. FrameReady is sent under g_ring_mutex so
// it is always ordered after the matching SurfacesAllocated.
static bool PresentSoftware(void* user_data, const void* allocation,
                            size_t row_bytes, size_t height) {
  (void)user_data;
  pthread_mutex_lock(&g_ring_mutex);
  int slot = surface_ring_present(allocation, row_bytes, height);
  if (slot >= 0) {
    g_frame_id++;
    uint64_t frame_id = g_frame_id;
    if (g_capture_path && !g_captured) {
      WriteRawCapture(g_capture_path, allocation, row_bytes, height);
      g_captured = true;
    }
    uint8_t payload[12];
    uint32_t ring_index = (uint32_t)slot;
    memcpy(payload + 0, &ring_index, 4);
    memcpy(payload + 4, &frame_id, 8);
    ipc_send(g_socket, kMsgFrameReady, payload, sizeof(payload));
  }
  pthread_mutex_unlock(&g_ring_mutex);
  return true;
}

int main(int argc, char** argv) {
  if (argc < 6) {
    fprintf(stderr,
            "usage: %s <assets_dir> <icu_data_path> <socket_path> "
            "<width> <height> [--capture-raw <path>]\n",
            argv[0]);
    return 2;
  }
  const char* assets_path = argv[1];
  const char* icu_data_path = argv[2];
  const char* socket_path = argv[3];
  int width = atoi(argv[4]);
  int height = atoi(argv[5]);
  for (int i = 6; i + 1 < argc; i += 2) {
    if (strcmp(argv[i], "--capture-raw") == 0) {
      g_capture_path = argv[i + 1];
    }
  }

  g_socket = ipc_connect(socket_path);
  if (g_socket < 0) {
    fprintf(stderr, "Cannot connect to socket: %s\n", socket_path);
    return 1;
  }

  if (!surface_ring_init(width, height)) {
    const char* msg = "IOSurface allocation failed";
    ipc_send(g_socket, kMsgError, (const uint8_t*)msg, strlen(msg));
    return 1;
  }

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

  FlutterEngineResult result = FlutterEngineRun(
      FLUTTER_ENGINE_VERSION, &renderer, &args, NULL, &g_engine);
  if (result != kSuccess || g_engine == NULL) {
    char msg[64];
    snprintf(msg, sizeof(msg), "FlutterEngineRun failed: %d", (int)result);
    ipc_send(g_socket, kMsgError, (const uint8_t*)msg, strlen(msg));
    return 1;
  }

  ipc_send(g_socket, kMsgReady, NULL, 0);
  SendSurfacesAllocated();
  SendWindowMetrics(width, height, g_pixel_ratio);

  // Socket read loop on the main thread.
  for (;;) {
    uint8_t* payload = NULL;
    size_t len = 0;
    int type = ipc_read(g_socket, &payload, &len);
    if (type < 0) break;  // GUI closed the socket.
    if (type == kMsgResize && len >= 16) {
      uint32_t new_width;
      uint32_t new_height;
      double pixel_ratio;
      memcpy(&new_width, payload + 0, 4);
      memcpy(&new_height, payload + 4, 4);
      memcpy(&pixel_ratio, payload + 8, 8);
      pthread_mutex_lock(&g_ring_mutex);
      g_pixel_ratio = pixel_ratio;
      if (surface_ring_init((int)new_width, (int)new_height)) {
        g_generation++;
        SendSurfacesAllocated();
      }
      pthread_mutex_unlock(&g_ring_mutex);
      SendWindowMetrics((int)new_width, (int)new_height, pixel_ratio);
    } else if (type == kMsgPointerEvent) {
      input_handle_pointer(g_engine, payload, len);
    } else if (type == kMsgKeyEvent) {
      input_handle_key(g_engine, payload, len);
    } else if (type == kMsgShutdown) {
      free(payload);
      break;
    }
    free(payload);
  }

  // FlutterEngineShutdown blocks with the software renderer; just release the
  // surfaces and let the OS reclaim the rest.
  surface_ring_destroy();
  return 0;
}
```

- [ ] **Step 2: Replace `app/native/CMakeLists.txt` entirely with:**

```cmake
cmake_minimum_required(VERSION 3.15)
project(flutterware_embedder_host C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

if(NOT FLUTTER_FRAMEWORK_DIR)
  message(FATAL_ERROR
    "Pass -DFLUTTER_FRAMEWORK_DIR=<dir containing FlutterEmbedder.framework>")
endif()

add_executable(host host.c surface.c ipc.c input.c)
target_include_directories(host PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_options(host PRIVATE "-F${FLUTTER_FRAMEWORK_DIR}")
target_link_libraries(host PRIVATE
  "-framework FlutterEmbedder"
  "-framework IOSurface"
  "-framework CoreFoundation")
set_target_properties(host PROPERTIES
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "${FLUTTER_FRAMEWORK_DIR}")
```

- [ ] **Step 3: Verify the guest compiles and links**

Run:
```bash
cmake -S app/native -B /tmp/embedder_host_build \
  -DFLUTTER_FRAMEWORK_DIR="$(pwd)/app/.engine"
cmake --build /tmp/embedder_host_build
```
Expected: configures and builds `/tmp/embedder_host_build/host` with no errors.
(If `app/.engine/FlutterEmbedder.framework` is missing, it persists from step 1;
otherwise run the Task-8 `run.dart` once — it downloads the framework.)

- [ ] **Step 4: Commit**

```bash
git add app/native/host.c app/native/CMakeLists.txt
git commit -m "Rewrite the C host as a long-lived embedder guest"
```

---

## Task 8: `run.dart` as a thin protocol client

**Files:**
- Rewrite: `app/tool/embedder/run.dart`

`run.dart` now spawns the guest with `--capture-raw`, waits for the first
`FrameReady` over the socket, then encodes the dumped raw file to a PNG. The
guest writes the raw file *before* sending `FrameReady` (both under
`g_ring_mutex`), so the file is ready when the message arrives.

- [ ] **Step 1: Replace `app/tool/embedder/run.dart` entirely with:**

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:flutterware_app/src/embedder/raw_frame.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Spawns the embedder guest, captures its first rendered frame, and encodes
/// it to a PNG at `build/embedder/scene.png`.
Future<void> main() async {
  // <app>/tool/embedder/run.dart -> <app>
  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var repoRoot = p.dirname(packageRoot);
  var cache = FlutterCache.fromRunningSdk();

  var buildDir = p.join(packageRoot, 'build', 'embedder');
  var assetsDir = p.join(buildDir, 'assets');
  var kernelBlob = p.join(assetsDir, 'kernel_blob.bin');
  var nativeBuildDir = p.join(buildDir, 'native');
  var engineDir = p.join(packageRoot, '.engine');
  var rawFrame = p.join(buildDir, 'scene.rawframe');
  var pngPath = p.join(buildDir, 'scene.png');
  var socketPath = p.join(buildDir, 'embedder.sock');

  Directory(buildDir).createSync(recursive: true);

  await ensureEmbedderFramework(cache, engineDir);
  await compileScene(
    scenePath: p.join(packageRoot, 'tool', 'embedder', 'scene.dart'),
    kernelBlob: kernelBlob,
    packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
    cache: cache,
  );
  var hostPath = await buildHost(
    nativeSourceDir: p.join(packageRoot, 'native'),
    nativeBuildDir: nativeBuildDir,
    engineDir: engineDir,
  );

  var socketFile = File(socketPath);
  if (socketFile.existsSync()) socketFile.deleteSync();
  var server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix), 0);

  stdout.writeln('[run] spawning guest');
  var guest = await Process.start(
    hostPath,
    [assetsDir, cache.icuData, socketPath, '800', '600',
     '--capture-raw', rawFrame],
    mode: ProcessStartMode.inheritStdio,
  );

  var conn = await server.first;
  var reader = FrameReader();
  var gotFrame = false;
  loop:
  await for (var chunk in conn) {
    for (var message in reader.addBytes(chunk)) {
      if (message is FrameReadyMessage) {
        gotFrame = true;
        break loop;
      }
      if (message is ErrorMessage) {
        stderr.writeln('[run] guest error: ${message.message}');
        guest.kill();
        await server.close();
        exit(1);
      }
    }
  }

  conn.add(encodeMessage(const ShutdownMessage()));
  await conn.flush();
  await conn.close();
  await guest.exitCode;
  await server.close();
  if (socketFile.existsSync()) socketFile.deleteSync();

  if (!gotFrame) {
    stderr.writeln('[run] guest closed the socket before rendering a frame');
    exit(1);
  }

  stdout.writeln('[run] encoding PNG');
  var image = decodeRawFrame(File(rawFrame).readAsBytesSync());
  File(pngPath).writeAsBytesSync(img.encodePng(image));
  stdout.writeln('[run] wrote $pngPath');
}
```

- [ ] **Step 2: Verify analysis is clean**

Run: `cd app && /Users/xavier/flutter/bin/dart analyze tool/embedder/run.dart`
Expected: "No issues found!"

- [ ] **Step 3: Run it end to end**

Run: `cd app && /Users/xavier/flutter/bin/dart run tool/embedder/run.dart`
Expected: compiles the scene, builds the guest, spawns it, and writes
`app/build/embedder/scene.png`. Open the PNG — it should show the blue
background with a white square and the "Tap me" button.

If the colours are swapped (the background looks orange/red instead of blue),
the software renderer's byte order is BGRA, not RGBA: remove the channel swap
in `surface.c`'s `surface_ring_present` (copy `s[x*4+k]` straight to
`d[x*4+k]`) and re-run. Report it if this happens.

- [ ] **Step 4: Commit**

```bash
git add app/tool/embedder/run.dart
git commit -m "Rebuild run.dart as an embedder protocol client"
```

---

## Task 9: End-to-end guest integration test

**Files:**
- Create: `app/integration_test/embedder/live_bridge_test.dart`
- Delete: `app/integration_test/embedder/render_test.dart`

This heavy test builds and spawns the guest directly, then drives the protocol:
it asserts continuous frames flow and that a resize re-allocates surfaces.

- [ ] **Step 1: Write the test**

`app/integration_test/embedder/live_bridge_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('guest streams live frames and re-allocates surfaces on resize',
      () async {
    // `dart test` runs with the package root (<app>) as the current directory.
    var packageRoot = Directory.current.path;
    var repoRoot = p.dirname(packageRoot);
    var cache = FlutterCache.fromRunningSdk();

    var buildDir = p.join(packageRoot, 'build', 'embedder');
    var assetsDir = p.join(buildDir, 'assets');
    var engineDir = p.join(packageRoot, '.engine');
    var socketPath = p.join(buildDir, 'embedder_test.sock');
    Directory(buildDir).createSync(recursive: true);

    await ensureEmbedderFramework(cache, engineDir);
    await compileScene(
      scenePath: p.join(packageRoot, 'tool', 'embedder', 'scene.dart'),
      kernelBlob: p.join(assetsDir, 'kernel_blob.bin'),
      packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
      cache: cache,
    );
    var hostPath = await buildHost(
      nativeSourceDir: p.join(packageRoot, 'native'),
      nativeBuildDir: p.join(buildDir, 'native'),
      engineDir: engineDir,
    );

    var socketFile = File(socketPath);
    if (socketFile.existsSync()) socketFile.deleteSync();
    var server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix), 0);

    var guest = await Process.start(
      hostPath,
      [assetsDir, cache.icuData, socketPath, '800', '600'],
      mode: ProcessStartMode.inheritStdio,
    );
    addTearDown(() async {
      guest.kill();
      await server.close();
      if (socketFile.existsSync()) socketFile.deleteSync();
    });

    var conn = await server.first;
    var reader = FrameReader();
    var incoming = StreamController<EmbedderMessage>();
    conn.listen((chunk) {
      for (var message in reader.addBytes(chunk)) {
        incoming.add(message);
      }
    }, onDone: incoming.close);
    var messages = StreamQueue<EmbedderMessage>(incoming.stream);

    Future<T> next<T extends EmbedderMessage>() async {
      while (true) {
        var message = await messages.next
            .timeout(const Duration(seconds: 30));
        if (message is ErrorMessage) {
          fail('guest error: ${message.message}');
        }
        if (message is T) return message;
      }
    }

    // Startup: Ready then SurfacesAllocated for an 800x600 ring of 3.
    await next<ReadyMessage>();
    var first = await next<SurfacesAllocatedMessage>();
    expect(first.width, 800);
    expect(first.height, 600);
    expect(first.surfaceIds, hasLength(3));
    expect(first.surfaceIds.every((id) => id != 0), isTrue);

    // Continuous frames: collect several with strictly increasing frameIds.
    var frameIds = <int>[];
    while (frameIds.length < 5) {
      frameIds.add((await next<FrameReadyMessage>()).frameId);
    }
    for (var i = 1; i < frameIds.length; i++) {
      expect(frameIds[i], greaterThan(frameIds[i - 1]),
          reason: 'frameId must increase: $frameIds');
    }

    // Resize: the guest re-allocates surfaces at the new size.
    conn.add(encodeMessage(
        const ResizeMessage(width: 1024, height: 768, pixelRatio: 1.0)));
    await conn.flush();
    var resized = await next<SurfacesAllocatedMessage>();
    expect(resized.width, 1024);
    expect(resized.height, 768);
    expect(resized.generation, greaterThan(first.generation));

    // Frames keep flowing after the resize.
    await next<FrameReadyMessage>();

    conn.add(encodeMessage(const ShutdownMessage()));
    await conn.flush();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
```

Note: `StreamQueue` comes from `package:async`, already an `app` dependency.
Add `import 'package:async/async.dart';` at the top if the analyzer reports
`StreamQueue` undefined.

- [ ] **Step 2: Delete the superseded step-2 render test**

```bash
git rm app/integration_test/embedder/render_test.dart
```

- [ ] **Step 3: Run the test**

Run: `cd app && /Users/xavier/flutter/bin/dart test integration_test/embedder/live_bridge_test.dart`
Expected: PASS — the guest builds, streams 5+ frames with increasing ids, and
re-allocates a 1024×768 surface ring on resize.

- [ ] **Step 4: Run the full embedder test suite**

Run: `cd app && /Users/xavier/flutter/bin/dart test test/embedder integration_test/embedder`
Expected: all PASS — `raw_frame_test`, `protocol_test`, `flutter_cache_test`,
`compiler_test`, `live_bridge_test`.

- [ ] **Step 5: Commit**

```bash
git add app/integration_test/embedder/live_bridge_test.dart app/integration_test/embedder/render_test.dart
git commit -m "Add end-to-end embedder guest integration test"
```

---

## Task 10: Update the README and final analysis

**Files:**
- Modify: `app/lib/src/embedder/README.md`

- [ ] **Step 1: Replace `app/lib/src/embedder/README.md` entirely with:**

```markdown
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
```

- [ ] **Step 2: Verify workspace-wide analysis is clean**

Run (from repo root): `/Users/xavier/flutter/bin/flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add app/lib/src/embedder/README.md
git commit -m "Update embedder README for step 3a (guest process)"
```

---

## Self-Review notes

- **Spec coverage:** out-of-process guest (Tasks 4–7); software renderer + CPU
  copy into `IOSurface` (Task 4); `IOSurface` triple-buffer ring (Task 4);
  Unix-socket framed protocol (Tasks 1, 5); `Ready`/`SurfacesAllocated`/
  `FrameReady`/`Error`/`Resize`/`PointerEvent`/`KeyEvent`/`Shutdown` (Task 1
  codec, Task 7 guest); animated + interactive scene (Task 2); resize
  re-allocation (Task 7); input forwarding (Task 6); headless PNG smoke via
  `--capture-raw` (Tasks 7, 8); protocol unit test + guest integration test
  (Tasks 1, 9); README (Task 10). The GUI texture display, `EmbeddedEngine`,
  and the native macOS plugin are intentionally deferred to Plan 2.
- **Pixel-format risk:** `surface.c` swaps RGBA→BGRA; step 2 confirmed the
  software renderer outputs RGBA. Task 8 Step 3 gives the exact remedy if the
  swap is wrong.
- **Type consistency:** the wire layout is defined once in `protocol.dart`
  (Task 1) and mirrored byte-for-byte in `host.c`/`input.c` (Tasks 6–7): tags
  `kMsg*` = `MessageType.tag`; `SurfacesAllocated` =
  `generation,count,width,height,rowBytes,ids[]`; `FrameReady` =
  `ringIndex(u32),frameId(u64)`; `Resize` = `width(u32),height(u32),
  pixelRatio(f64)`; `PointerEvent` 48 bytes; `KeyEvent` 32 bytes. The guest CLI
  `host <assets> <icu> <socket> <width> <height> [--capture-raw <path>]` is
  used identically in Tasks 7, 8, 9.
- **Deferred items** (Metal/zero-copy, hot reload, IME, multi-engine,
  non-macOS) are intentionally absent.
```

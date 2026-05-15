# Flutter embedder Step 3b — Metal zero-copy renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch the out-of-process Flutter-engine guest from the software renderer to the Metal renderer, rendering directly into shared IOSurface-backed Metal textures — a true zero-copy path with no per-frame `memcpy` or RGBA→BGRA swap.

**Architecture:** The guest's `FlutterRendererConfig` becomes `kMetal`. Each ring `IOSurface` also backs an `id<MTLTexture>` the engine renders into. `present_drawable_callback` commits an empty command buffer on the shared `present_command_queue` and sends `FrameReady` from its completion handler, so the GUI never reads a half-rendered surface. The ring is reallocated inside `get_next_drawable_callback` on the raster thread when the requested size changes, so a resize never races an in-flight texture. The GUI side (`embedded_engine.dart`, `protocol.dart`, `EmbedderTexturePlugin.swift`) is unchanged — it already wraps the IOSurfaces as Metal-compatible `CVPixelBuffer`s.

**Tech Stack:** C + Objective-C (ARC), Metal, IOSurface, CMake; Dart/Flutter for the GUI runtime and the headless smoke; the Flutter C embedder API (`FlutterEmbedder.framework`).

**Reference spec:** `docs/superpowers/specs/2026-05-15-flutter-embedder-step3b-design.md`

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `app/lib/src/embedder/raw_frame.dart` | Decode the guest's raw capture file into an `Image`. | Pixel order RGBA → BGRA. |
| `app/test/embedder/raw_frame_test.dart` | Unit test for `decodeRawFrame`. | Fixtures rewritten for BGRA. |
| `app/native/surface.h` | Interface of the shared-surface unit. | Metal device/queue/texture/fence API replaces the software-copy API. |
| `app/native/surface.m` | The shared `MTLDevice`/`MTLCommandQueue`, the ring of *(IOSurface, MTLTexture)* pairs, the present fence, CPU readback. | New file; replaces `surface.c`. Objective-C, ARC. |
| `app/native/surface.c` | (deleted) | Removed — replaced by `surface.m`. |
| `app/native/host.c` | Engine lifecycle, socket loop. | `kMetal` renderer config + `get_next_drawable`/`present_drawable` callbacks; `PresentSoftware` removed; `Resize` handler simplified. |
| `app/native/CMakeLists.txt` | Build the `host` executable. | Compile `surface.m` (ARC, OBJC language); link Metal + Foundation. |
| `app/lib/src/embedder/README.md` | Embedder overview. | Step 3a → 3b wording. |

Unchanged: `app/native/ipc.{c,h}`, `app/native/input.{c,h}`, `app/lib/src/embedder/protocol.dart`, `app/lib/src/embedder/embedded_engine.dart`, `app/macos/Runner/EmbedderTexturePlugin.swift`, `app/tool/embedder/run.dart`, `app/tool/embedder/build_guest.dart` — the wire protocol and the GUI side do not change.

---

## Task 1: Switch the raw-frame decoder to BGRA

The guest's Metal renderer writes BGRA pixels straight into the IOSurfaces (no channel swap). The headless capture file therefore changes from RGBA to BGRA byte order. `decodeRawFrame` already has a unit test, so this is done test-first.

**Files:**
- Modify: `app/lib/src/embedder/raw_frame.dart`
- Test: `app/test/embedder/raw_frame_test.dart`

- [ ] **Step 1: Update the test fixtures to BGRA**

Replace the entire contents of `app/test/embedder/raw_frame_test.dart` with:

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
    var row0 = [255, 0, 0, 255, 9, 9, 9, 9]; // blue + padding (BGRA)
    var row1 = [0, 0, 255, 255, 9, 9, 9, 9]; // red + padding (BGRA)
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

Run: `cd app && flutter test test/embedder/raw_frame_test.dart`
Expected: FAIL — the first two tests fail because `raw_frame.dart` still decodes the bytes as RGBA, so `p0.r` is 255 (not 0) and `p0.b` is 0 (not 255).

- [ ] **Step 3: Switch the decoder to BGRA**

In `app/lib/src/embedder/raw_frame.dart`, update the doc comment and the `ChannelOrder`. Change the comment line:

```dart
/// followed by `rowBytes * height` pixel bytes in RGBA order.
```

to:

```dart
/// followed by `rowBytes * height` pixel bytes in BGRA order.
```

and change the last argument of `Image.fromBytes`:

```dart
    order: ChannelOrder.rgba,
```

to:

```dart
    order: ChannelOrder.bgra,
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && flutter test test/embedder/raw_frame_test.dart`
Expected: PASS — all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/embedder/raw_frame.dart app/test/embedder/raw_frame_test.dart
git commit -m "Decode embedder raw capture frames as BGRA"
```

---

## Task 2: Swap the guest to the Metal renderer

This is one atomic native change: `surface.h`, `surface.m`, `CMakeLists.txt`, and `host.c` must all land together for the guest to compile. It is verified by building the guest, running the headless PNG smoke, and running the live-bridge integration test.

**Files:**
- Modify: `app/native/surface.h`
- Create: `app/native/surface.m`
- Delete: `app/native/surface.c`
- Modify: `app/native/CMakeLists.txt`
- Modify: `app/native/host.c`

- [ ] **Step 1: Replace `surface.h`**

Replace the entire contents of `app/native/surface.h` with:

```c
#ifndef EMBEDDER_SURFACE_H
#define EMBEDDER_SURFACE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// A ring of three IOSurfaces shared with the GUI process. Each IOSurface also
// backs a Metal texture the engine renders into directly (zero-copy). The
// guest renders into one slot at a time; the GUI reads whichever slot
// FrameReady names.
#define SURFACE_RING_COUNT 3

// Creates the shared MTLDevice/MTLCommandQueue on the first call, then a fresh
// ring of (IOSurface, MTLTexture) pairs sized width x height, releasing any
// previous ring. Returns false on device or allocation failure.
bool surface_ring_init(int width, int height);

// Releases the ring.
void surface_ring_destroy(void);

// The MTLDevice handle (id<MTLDevice>) for FlutterMetalRendererConfig.device.
// NULL before the first successful surface_ring_init.
const void* surface_metal_device(void);

// The MTLCommandQueue handle (id<MTLCommandQueue>) for
// FlutterMetalRendererConfig.present_command_queue.
const void* surface_metal_queue(void);

// The MTLTexture handle (id<MTLTexture>) backing ring slot `slot`, handed to
// the engine from get_next_drawable_callback. NULL if slot is out of range.
const void* surface_ring_texture(int slot);

// The slot index the engine should render into next. Does not advance.
int surface_ring_acquire(void);

// Advances to the next ring slot. Called from present_drawable_callback.
void surface_ring_advance(void);

// Commits an empty command buffer on the present command queue and invokes
// `on_complete(user_data)` from its completion handler. Because the engine
// submits its render on the same in-order queue, the handler runs only after
// the GPU has finished writing the frame.
void surface_present_fence(void (*on_complete)(void* user_data),
                           void* user_data);

// IOSurfaceLock / IOSurfaceUnlock a ring slot for CPU readback (used under
// --capture-raw). surface_lock returns the slot's base address, or NULL.
const void* surface_lock(int slot);
void surface_unlock(int slot);

// Fills out[SURFACE_RING_COUNT] with the global IOSurfaceIDs of the ring.
void surface_ring_ids(uint32_t out[SURFACE_RING_COUNT]);

int surface_ring_width(void);
int surface_ring_height(void);
size_t surface_ring_row_bytes(void);

#endif  // EMBEDDER_SURFACE_H
```

- [ ] **Step 2: Create `surface.m` and delete `surface.c`**

Create `app/native/surface.m` with:

```objc
#include "surface.h"

#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>

// The shared device and command queue, created lazily on the first
// surface_ring_init. The engine submits its render commands on g_queue (passed
// as present_command_queue), so the fence command buffer is correctly ordered.
static id<MTLDevice> g_device;
static id<MTLCommandQueue> g_queue;

// The current ring. Owned entirely by the engine raster thread: surface_ring_init
// is only ever called from get_next_drawable_callback (and once at startup,
// before the engine runs), so no cross-thread locking is needed.
static IOSurfaceRef g_ios[SURFACE_RING_COUNT];
static id<MTLTexture> g_tex[SURFACE_RING_COUNT];
static int g_width;
static int g_height;
static int g_next;

static IOSurfaceRef CreateSurface(int width, int height) {
  int bpe = 4;
  int pixel_format = 0x42475241;  // 'BGRA'
  CFMutableDictionaryRef props = CFDictionaryCreateMutable(
      kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
      &kCFTypeDictionaryValueCallBacks);
  CFNumberRef w = CFNumberCreate(NULL, kCFNumberIntType, &width);
  CFNumberRef h = CFNumberCreate(NULL, kCFNumberIntType, &height);
  CFNumberRef e = CFNumberCreate(NULL, kCFNumberIntType, &bpe);
  CFNumberRef f = CFNumberCreate(NULL, kCFNumberIntType, &pixel_format);
  CFDictionarySetValue(props, kIOSurfaceWidth, w);
  CFDictionarySetValue(props, kIOSurfaceHeight, h);
  CFDictionarySetValue(props, kIOSurfaceBytesPerElement, e);
  CFDictionarySetValue(props, kIOSurfacePixelFormat, f);
  // Deliberately do NOT set kIOSurfaceBytesPerRow: width*4 is not necessarily
  // a valid (aligned) row stride, and an unaligned value makes IOSurfaceCreate
  // fail outright for some widths. Letting IOSurface pick the stride keeps
  // creation reliable at every window size.
  // The GUI process resolves these surfaces with IOSurfaceLookup(id); that
  // only works for surfaces flagged global.
  CFDictionarySetValue(props, kIOSurfaceIsGlobal, kCFBooleanTrue);
  IOSurfaceRef surface = IOSurfaceCreate(props);
  CFRelease(w);
  CFRelease(h);
  CFRelease(e);
  CFRelease(f);
  CFRelease(props);
  return surface;
}

static id<MTLTexture> CreateTexture(IOSurfaceRef ios, int width, int height) {
  MTLTextureDescriptor* desc = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                   width:(NSUInteger)width
                                  height:(NSUInteger)height
                               mipmapped:NO];
  desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  desc.storageMode = MTLStorageModeShared;
  return [g_device newTextureWithDescriptor:desc iosurface:ios plane:0];
}

bool surface_ring_init(int width, int height) {
  if (width <= 0 || height <= 0) return false;
  if (g_device == nil) {
    g_device = MTLCreateSystemDefaultDevice();
    if (g_device == nil) return false;
    g_queue = [g_device newCommandQueue];
    if (g_queue == nil) return false;
  }
  // Build the new ring into temporaries; only swap in (and release the old
  // ring) once every pair is allocated. A failed re-allocation then leaves the
  // existing ring intact and still presentable.
  IOSurfaceRef fresh_ios[SURFACE_RING_COUNT] = {0};
  id<MTLTexture> fresh_tex[SURFACE_RING_COUNT] = {nil, nil, nil};
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    fresh_ios[i] = CreateSurface(width, height);
    fresh_tex[i] =
        fresh_ios[i] ? CreateTexture(fresh_ios[i], width, height) : nil;
    if (!fresh_ios[i] || fresh_tex[i] == nil) {
      for (int j = 0; j <= i; j++) {
        if (fresh_ios[j]) CFRelease(fresh_ios[j]);
        fresh_tex[j] = nil;
      }
      return false;
    }
  }
  surface_ring_destroy();
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    g_ios[i] = fresh_ios[i];
    g_tex[i] = fresh_tex[i];
  }
  g_width = width;
  g_height = height;
  g_next = 0;
  return true;
}

void surface_ring_destroy(void) {
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    if (g_ios[i]) {
      CFRelease(g_ios[i]);
      g_ios[i] = NULL;
    }
    g_tex[i] = nil;
  }
  g_width = 0;
  g_height = 0;
  g_next = 0;
}

const void* surface_metal_device(void) {
  return (__bridge const void*)g_device;
}

const void* surface_metal_queue(void) {
  return (__bridge const void*)g_queue;
}

const void* surface_ring_texture(int slot) {
  if (slot < 0 || slot >= SURFACE_RING_COUNT) return NULL;
  return (__bridge const void*)g_tex[slot];
}

int surface_ring_acquire(void) { return g_next; }

void surface_ring_advance(void) {
  g_next = (g_next + 1) % SURFACE_RING_COUNT;
}

void surface_present_fence(void (*on_complete)(void*), void* user_data) {
  id<MTLCommandBuffer> cb = [g_queue commandBuffer];
  [cb addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    (void)buffer;
    on_complete(user_data);
  }];
  [cb commit];
}

const void* surface_lock(int slot) {
  if (slot < 0 || slot >= SURFACE_RING_COUNT || !g_ios[slot]) return NULL;
  IOSurfaceLock(g_ios[slot], kIOSurfaceLockReadOnly, NULL);
  return IOSurfaceGetBaseAddress(g_ios[slot]);
}

void surface_unlock(int slot) {
  if (slot < 0 || slot >= SURFACE_RING_COUNT || !g_ios[slot]) return;
  IOSurfaceUnlock(g_ios[slot], kIOSurfaceLockReadOnly, NULL);
}

void surface_ring_ids(uint32_t out[SURFACE_RING_COUNT]) {
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    out[i] = g_ios[i] ? IOSurfaceGetID(g_ios[i]) : 0;
  }
}

int surface_ring_width(void) { return g_width; }
int surface_ring_height(void) { return g_height; }

size_t surface_ring_row_bytes(void) {
  return g_ios[0] ? IOSurfaceGetBytesPerRow(g_ios[0]) : 0;
}
```

Then delete the old software-renderer file:

```bash
git rm app/native/surface.c
```

- [ ] **Step 3: Update `CMakeLists.txt`**

Replace the entire contents of `app/native/CMakeLists.txt` with:

```cmake
cmake_minimum_required(VERSION 3.16)
project(flutterware_embedder_host C OBJC)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

if(NOT FLUTTER_FRAMEWORK_DIR)
  message(FATAL_ERROR
    "Pass -DFLUTTER_FRAMEWORK_DIR=<dir containing FlutterEmbedder.framework>")
endif()

add_executable(host host.c surface.m ipc.c input.c)
# surface.m is Objective-C and uses ARC for its Metal object lifetimes.
set_source_files_properties(surface.m PROPERTIES COMPILE_FLAGS "-fobjc-arc")
target_include_directories(host PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_options(host PRIVATE "-F${FLUTTER_FRAMEWORK_DIR}")
target_link_libraries(host PRIVATE
  "-framework FlutterEmbedder"
  "-framework IOSurface"
  "-framework CoreFoundation"
  "-framework Foundation"
  "-framework Metal")
set_target_properties(host PROPERTIES
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "${FLUTTER_FRAMEWORK_DIR}")
```

(`OBJC` is added to the `project()` languages so CMake compiles `surface.m`; `Foundation` and `Metal` are the new frameworks.)

- [ ] **Step 4: Rewrite `host.c` for the Metal renderer**

Replace the entire contents of `app/native/host.c` with:

```c
// Long-lived Flutter-engine guest: runs a kernel blob, renders with the Metal
// renderer directly into shared IOSurface-backed Metal textures (zero-copy),
// and exchanges frames + input with a controlling process over a Unix domain
// socket.
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
// generation and frame_id are only touched on the engine raster thread (inside
// the drawable callbacks), and once at startup before the engine runs.
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
// then the raw BGRA pixels read back from ring slot `slot`.
static void WriteRawCapture(const char* path, int slot) {
  const void* base = surface_lock(slot);
  if (!base) return;
  size_t row_bytes = surface_ring_row_bytes();
  size_t height = (size_t)surface_ring_height();
  FILE* f = fopen(path, "wb");
  if (f) {
    uint32_t header[3] = {(uint32_t)surface_ring_width(), (uint32_t)height,
                          (uint32_t)row_bytes};
    fwrite(header, sizeof(uint32_t), 3, f);
    fwrite(base, 1, row_bytes * height, f);
    fclose(f);
  }
  surface_unlock(slot);
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

// Carries the identity of a presented frame to the GPU completion handler.
typedef struct {
  uint32_t ring_index;
  uint64_t frame_id;
  uint32_t generation;
} PresentedFrame;

// Runs on a Metal-internal thread once the engine's render for this frame has
// finished on the GPU. The surface is fully written by now, so it is safe to
// read it back and to tell the GUI the frame is ready.
static void OnFramePresented(void* user_data) {
  PresentedFrame* frame = (PresentedFrame*)user_data;
  if (g_capture_path && !g_captured) {
    WriteRawCapture(g_capture_path, (int)frame->ring_index);
    g_captured = true;
  }
  uint8_t payload[16];
  memcpy(payload + 0, &frame->ring_index, 4);
  memcpy(payload + 4, &frame->frame_id, 8);
  memcpy(payload + 12, &frame->generation, 4);
  ipc_send(g_socket, kMsgFrameReady, payload, sizeof(payload));
  free(frame);
}

// Engine raster thread: hands the engine the next ring slot's Metal texture.
// If the engine asks for a size different from the current ring (a resize),
// the ring is reallocated here — at this point the engine holds no texture, so
// freeing the old ring is safe and no cross-thread locking is needed.
static FlutterMetalTexture GetNextDrawable(
    void* user_data, const FlutterFrameInfo* frame_info) {
  (void)user_data;
  int width = (int)frame_info->size.width;
  int height = (int)frame_info->size.height;
  if (width != surface_ring_width() || height != surface_ring_height()) {
    if (surface_ring_init(width, height)) {
      g_generation++;
      SendSurfacesAllocated();
    }
  }
  int slot = surface_ring_acquire();
  FlutterMetalTexture texture = {0};
  texture.struct_size = sizeof(FlutterMetalTexture);
  texture.texture_id = slot;
  texture.texture = surface_ring_texture(slot);
  texture.user_data = NULL;
  texture.destruction_callback = NULL;  // the guest owns the ring.
  return texture;
}

// Engine raster thread: the engine has submitted its render into this slot's
// texture. Advance the ring and fence the GPU; FrameReady is sent from the
// fence's completion handler so the GUI never reads a half-rendered surface.
static bool PresentDrawable(void* user_data,
                            const FlutterMetalTexture* texture) {
  (void)user_data;
  PresentedFrame* frame = (PresentedFrame*)malloc(sizeof(PresentedFrame));
  frame->ring_index = (uint32_t)texture->texture_id;
  frame->frame_id = ++g_frame_id;
  frame->generation = g_generation;
  surface_ring_advance();
  surface_present_fence(OnFramePresented, frame);
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
    const char* msg = "Metal surface allocation failed";
    ipc_send(g_socket, kMsgError, (const uint8_t*)msg, strlen(msg));
    return 1;
  }

  FlutterRendererConfig renderer = {0};
  renderer.type = kMetal;
  renderer.metal.struct_size = sizeof(FlutterMetalRendererConfig);
  renderer.metal.device = surface_metal_device();
  renderer.metal.present_command_queue = surface_metal_queue();
  renderer.metal.get_next_drawable_callback = GetNextDrawable;
  renderer.metal.present_drawable_callback = PresentDrawable;

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
      g_pixel_ratio = pixel_ratio;
      // The ring is reallocated inside GetNextDrawable on the raster thread;
      // here we only nudge the engine to render at the new size.
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

  // Just release the surfaces and let the OS reclaim the rest.
  surface_ring_destroy();
  return 0;
}
```

- [ ] **Step 5: Build the guest**

Run: `cd app && dart run tool/embedder/build_guest.dart`
Expected: the script downloads/uses `FlutterEmbedder.framework`, compiles the scene, and CMake builds the host. The last three printed lines are `ASSETS_DIR=…`, `ICU_DATA=…`, `HOST_PATH=…`. No compiler or linker errors. If CMake reports a stale cache after the `CMakeLists.txt` change, delete `app/build/embedder/native` and re-run.

- [ ] **Step 6: Run the headless PNG smoke**

Run: `dart run app/tool/embedder/run.dart`
Expected: prints `[run] spawning guest`, `[run] encoding PNG`, and `[run] wrote …/app/build/embedder/scene.png`. No `[run] guest error:` line. Open `app/build/embedder/scene.png` and confirm it shows the scene (the same animated scene as 3a, captured at one instant) with correct colors — proving the Metal render reached the IOSurface and the BGRA readback decoded correctly.

- [ ] **Step 7: Run the live-bridge integration test**

Run: `cd app && dart test integration_test/embedder/live_bridge_test.dart`
Expected: PASS — the guest streams `Ready`, `SurfacesAllocated`, five `FrameReady` messages with strictly increasing `frameId`, and re-allocates surfaces with a higher `generation` on resize. This exercises the Metal path end to end (Metal device creation works headlessly on macOS).

- [ ] **Step 8: Analyze and commit**

Run: `flutter analyze`
Expected: no new issues.

```bash
git add app/native/surface.h app/native/surface.m app/native/host.c app/native/CMakeLists.txt
git rm app/native/surface.c
git commit -m "Render the embedder guest with the Metal renderer (zero-copy)"
```

---

## Task 3: Update the embedder README

The README still describes step 3a and the software renderer. Bring it in line with the Metal path.

**Files:**
- Modify: `app/lib/src/embedder/README.md`

- [ ] **Step 1: Update the "current" description**

In `app/lib/src/embedder/README.md`, replace the paragraph that begins `**Step 3a (current):**`:

```markdown
**Step 3a (current):** an out-of-process Flutter-engine guest renders an
animated, interactive scene with the software renderer into shared
`IOSurface`s; the flutterware desktop GUI displays it live in an external
`Texture`. The panel is resizable and forwards pointer/keyboard input.
```

with:

```markdown
**Step 3b (current):** an out-of-process Flutter-engine guest renders an
animated, interactive scene with the **Metal renderer**, directly into shared
`IOSurface`-backed Metal textures — a zero-copy path with no per-frame copy.
The flutterware desktop GUI displays it live in an external `Texture`. The
panel is resizable and forwards pointer/keyboard input.
```

- [ ] **Step 2: Update the guest bullet under "How it works"**

Replace the `**Guest** (`native/`)` bullet:

```markdown
- **Guest** (`native/`) — the long-lived C host embedding `FlutterEmbedder`.
  `host.c` runs the engine; `surface.{c,h}` is the `IOSurface` triple-buffer
  ring; `ipc.{c,h}` is the framed socket protocol; `input.{c,h}` translates
  pointer/key events.
```

with:

```markdown
- **Guest** (`native/`) — the long-lived C/Objective-C host embedding
  `FlutterEmbedder`. `host.c` runs the engine with the Metal renderer;
  `surface.{m,h}` owns the `MTLDevice`/`MTLCommandQueue` and the ring of
  `IOSurface`-backed Metal textures; `ipc.{c,h}` is the framed socket protocol;
  `input.{c,h}` translates pointer/key events.
```

- [ ] **Step 3: Update the "Not yet implemented" line**

Replace:

```markdown
GPU/Metal rendering and a zero-copy path (step 3b), hot reload (step 4), text
input/IME, multiple embedded engines, non-macOS platforms.
```

with:

```markdown
Hot reload (step 4), text input/IME, multiple embedded engines, non-macOS
platforms.
```

- [ ] **Step 4: Commit**

```bash
git add app/lib/src/embedder/README.md
git commit -m "Update embedder README for the step 3b Metal renderer"
```

---

## Manual verification (after all tasks)

Run the GUI harness and confirm the live Metal path visually — this is the part the automated tests cannot cover:

```sh
cd app && flutter run -t lib/main_embedder_dev.dart -d macos \
  --dart-define=FLUTTERWARE_APP_ROOT="$(pwd)" \
  --dart-define=FLUTTER_SDK_ROOT="$(cd "$(dirname "$(which flutter)")/.." && pwd)"
```

Confirm: the animated scene renders live in the texture panel, resizing the panel reflows the guest UI, clicking and typing into the texture region reaches the embedded app, and the macOS console shows no Metal or `IOSurface` errors and no visible tearing. (Screenshots cannot be captured in the agent environment — ask the user to eyeball this.)

---

## Self-Review Notes

- **Spec coverage:** Metal renderer config (Task 2 host.c), IOSurface-backed MTLTextures (Task 2 surface.m), completion-handler fence (Task 2 `surface_present_fence` + `OnFramePresented`), resize-in-`get_next_drawable` (Task 2 `GetNextDrawable`), BGRA pixel format (Task 1 + surface.m `MTLPixelFormatBGRA8Unorm`), headless capture via IOSurface readback (Task 2 `WriteRawCapture`/`surface_lock`), error handling for nil device (Task 2 `surface_ring_init` returns false → `host.c` sends `Error`), unchanged wire protocol and GUI side (no task — verified by the unchanged integration test), README (Task 3). All spec sections map to a task.
- **Key risk (from the spec):** the fence assumes the engine submits its render command buffer on the `present_command_queue` the guest provides. The macOS Metal embedder does. If a half-rendered frame ever appeared, this assumption would be the place to check.
- **Type consistency:** `surface_ring_acquire`/`surface_ring_advance`/`surface_ring_texture`/`surface_present_fence`/`surface_lock`/`surface_unlock` are declared in `surface.h` (Task 2 Step 1) and defined identically in `surface.m` (Step 2); `host.c` (Step 4) calls them with matching signatures. `PresentedFrame` is defined and used only within `host.c`.

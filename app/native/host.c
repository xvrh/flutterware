// Long-lived Flutter-engine guest: runs a kernel blob, renders into a ring of
// surfaces shared with a controlling process, and exchanges frames + input with
// it over a Unix domain socket.
//
// The renderer is the one thing that is not the same on every host — Metal
// into IOSurface-backed textures on macOS, GL into a framebuffer read back
// into shared memory elsewhere — and it is confined to the two blocks marked
// `__APPLE__` below plus `surface.m` / `surface_gl.c`. Everything else here —
// the socket loop, resize, capture, window metrics, input — is written once.
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef __APPLE__
#include <EGL/egl.h>
#endif

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

// A pending capture request. `--capture-raw` arms one at startup; a kMsgCapture
// message arms another at any time, which is what lets one warm guest be
// screenshotted repeatedly instead of being respawned per frame wanted.
//
// Written on the main thread (argv, socket loop), read and cleared on a
// Metal completion thread, so it is guarded.
static pthread_mutex_t g_capture_lock = PTHREAD_MUTEX_INITIALIZER;
static char* g_capture_path = NULL;

// A *sequence* of captures: every frame presented while this is armed is
// written, named `<prefix><n>.rawframe`, and acked like a single capture.
//
// It exists because a video is not N screenshots. Driving one capture per
// frame from the GUI costs two cross-process round trips a frame — one to move
// the playhead and one to ask for the picture — and measured at phone
// resolution those were 18 of the 22ms a frame cost, against 4ms of actual
// drawing. Armed once, the loop that remains is entirely inside the guest:
// Dart moves the playhead and awaits a frame, and every frame that lands is
// written here with no one asked anything.
//
// Frames map onto the caller's stops by *position*, which is exactly true for
// as long as nothing but that loop schedules a frame. The caller is what
// enforces that: it settles first, and refuses the result unless it was acked
// the number of frames it asked for.
static char* g_sequence_prefix = NULL;
static uint32_t g_sequence_remaining = 0;
static uint32_t g_sequence_index = 0;

// How many presented frames make one written one. A screen that applies its
// playhead from a post-frame callback needs two — the frame that moved the
// playhead shows the previous position — and writing both would shift every
// file after it rather than fix anything. So the guest draws `stride` frames a
// stop and only the last is kept.
static uint32_t g_sequence_stride = 1;
static uint32_t g_sequence_tick = 0;

// The engine asks the platform to wait for a vsync, and the platform hands the
// baton back when the next one lands. With no callback registered the engine
// uses its own waiter, which on a desktop is the real display link — so a
// headless render that draws as fast as it can was still paced at 60Hz, one
// frame every 16.6ms whatever it was drawing. Measured: 31 frames took 515ms
// at 900x700, at iPhone SE and at iPhone 13 alike, a 4.6x range of pixels for
// the same wall clock. The display was the only thing being measured.
//
// So the wait is ours, and it is skipped exactly while a capture sequence is
// armed. Nothing else changes: an interactive guest is still paced to a
// display, because a preview panel rendering flat out would burn a core to
// produce frames the panel drops.
static const uint64_t kFrameIntervalNanos = 16600000;

// Whether this guest paces itself to a display at all. Off unless
// `--free-vsync` says so, and only a headless render says so.
static bool g_free_vsync = false;

// The engine asks the platform to wait for a vsync and hands over a baton to
// return when the next one lands. With no callback registered it uses its own
// waiter, which on a desktop is the real display link — so a headless render
// drawing as fast as it could was still paced at one frame every 16.6ms.
// Measured: 31 frames took 515ms at 900x700, at iPhone SE and at iPhone 13
// alike — a 4.6x range of pixels for identical wall clock, because the display
// was the only thing being timed. Returning the baton immediately took the
// same render to 118ms.
//
// Registered only for a guest launched to render, and never for one behind a
// preview panel: a panel's guest paced by nothing would burn a core producing
// frames the panel drops, and the engine's own waiter is already right for it.
static void OnVsyncRequest(void* user_data, intptr_t baton) {
  uint64_t now = FlutterEngineGetCurrentTime();
  FlutterEngineOnVsync(g_engine, baton, now, now + kFrameIntervalNanos);
}

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

// Writes a raw frame file: a 16-byte LE header (width, height, row_bytes,
// pixel order) then the pixels read back from ring slot `slot`.
//
// The order is in the header rather than agreed in advance because it differs
// per host — see `surface_ring_pixel_order`.
static void WriteRawCapture(const char* path, int slot) {
  const void* base = surface_lock(slot);
  if (!base) return;
  size_t row_bytes = surface_ring_row_bytes();
  size_t height = (size_t)surface_ring_height();
  FILE* f = fopen(path, "wb");
  if (f) {
    uint32_t header[4] = {(uint32_t)surface_ring_width(), (uint32_t)height,
                          (uint32_t)row_bytes, surface_ring_pixel_order()};
    fwrite(header, sizeof(uint32_t), 4, f);
    fwrite(base, 1, row_bytes * height, f);
    fclose(f);
  }
  surface_unlock(slot);
}

// Announces the ring: its size, and how the GUI is to find each slot.
//
// The handles are length-prefixed strings rather than the fixed-width ids this
// used to send, because what a slot *is* differs per host — an IOSurfaceID
// there, a shared-memory name here — and one shape both can say is worth more
// than four bytes.
static void SendSurfacesAllocated(void) {
  // 5 header words, then a length and a name per slot. 256 is well past the
  // longest handle either host produces (an IOSurfaceID in decimal, or
  // "/flutterware-<pid>-<serial>-<slot>").
  uint8_t payload[5 * 4 + SURFACE_RING_COUNT * (4 + 256)];
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
  size_t at = 20;
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    const char* handle = surface_ring_handle(i);
    if (handle == NULL) handle = "";
    uint32_t len = (uint32_t)strlen(handle);
    if (len > 256) len = 256;
    memcpy(payload + at, &len, 4);
    memcpy(payload + at + 4, handle, len);
    at += 4 + len;
  }
  ipc_send(g_socket, kMsgSurfacesAllocated, payload, at);
}

// `insets` is top, right, bottom, left in physical pixels — a device's safe
// areas, which only the GUI knows because it is the one that picked the
// device. The frame around the screen is drawn in that other process, so
// without this the guest has no way to learn that it is behind a notch.
static void SendWindowMetrics(int width, int height, double pixel_ratio,
                              const double insets[4]) {
  FlutterWindowMetricsEvent metrics = {0};
  metrics.struct_size = sizeof(FlutterWindowMetricsEvent);
  metrics.width = (size_t)width;
  metrics.height = (size_t)height;
  metrics.pixel_ratio = pixel_ratio;
  metrics.physical_view_inset_top = insets[0];
  metrics.physical_view_inset_right = insets[1];
  metrics.physical_view_inset_bottom = insets[2];
  metrics.physical_view_inset_left = insets[3];
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

  // Take the pending request, if any, and clear it under the lock so a second
  // request cannot be lost or double-written.
  pthread_mutex_lock(&g_capture_lock);
  char* capture_path = g_capture_path;
  g_capture_path = NULL;
  pthread_mutex_unlock(&g_capture_lock);

  if (capture_path) {
    WriteRawCapture(capture_path, (int)frame->ring_index);
    // Tell the caller the file is complete; without this it can only guess
    // when the bytes have landed.
    ipc_send(g_socket, kMsgCaptured, (const uint8_t*)capture_path,
             strlen(capture_path));
    free(capture_path);
  }

  // The sequence, taken under the same lock and for the same reason.
  pthread_mutex_lock(&g_capture_lock);
  char* sequence_path = NULL;
  if (g_sequence_remaining > 0 && g_sequence_prefix) {
    g_sequence_tick++;
    if (g_sequence_tick % g_sequence_stride == 0) {
      size_t size = strlen(g_sequence_prefix) + 32;
      sequence_path = (char*)malloc(size);
      snprintf(sequence_path, size, "%s%u.rawframe", g_sequence_prefix,
               g_sequence_index);
      g_sequence_index++;
      g_sequence_remaining--;
      if (g_sequence_remaining == 0) {
        free(g_sequence_prefix);
        g_sequence_prefix = NULL;
      }
    }
  }
  pthread_mutex_unlock(&g_capture_lock);

  if (sequence_path) {
    WriteRawCapture(sequence_path, (int)frame->ring_index);
    ipc_send(g_socket, kMsgCaptured, (const uint8_t*)sequence_path,
             strlen(sequence_path));
    free(sequence_path);
  }
  uint8_t payload[16];
  memcpy(payload + 0, &frame->ring_index, 4);
  memcpy(payload + 4, &frame->frame_id, 8);
  memcpy(payload + 12, &frame->generation, 4);
  ipc_send(g_socket, kMsgFrameReady, payload, sizeof(payload));
  free(frame);
}

// Reallocates the ring when the engine asks for a size it is not, and tells the
// GUI when it did. Called from the engine's raster thread on every frame, on
// both hosts — at that point the engine holds no drawable, so freeing the old
// ring is safe and no cross-thread locking is needed.
static void ResizeRingIfNeeded(const FlutterFrameInfo* frame_info) {
  int width = (int)frame_info->size.width;
  int height = (int)frame_info->size.height;
  if (width == surface_ring_width() && height == surface_ring_height()) return;
  if (surface_ring_init(width, height)) {
    g_generation++;
    SendSurfacesAllocated();
  }
}

#ifdef __APPLE__

// Engine raster thread: hands the engine the next ring slot's Metal texture.
// If the engine asks for a size different from the current ring (a resize),
// the ring is reallocated here — at this point the engine holds no texture, so
// freeing the old ring is safe and no cross-thread locking is needed.
static FlutterMetalTexture GetNextDrawable(
    void* user_data, const FlutterFrameInfo* frame_info) {
  (void)user_data;
  ResizeRingIfNeeded(frame_info);
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

#else  // __APPLE__

// The engine's OpenGL renderer, in four callbacks it invokes on its own
// threads. Everything they do lives in `surface_gl.c`; these exist because the
// engine's signatures carry a user_data the surface unit has no use for.
static bool GlMakeCurrent(void* user_data) {
  (void)user_data;
  return surface_gl_make_current();
}

static bool GlClearCurrent(void* user_data) {
  (void)user_data;
  return surface_gl_clear_current();
}

static bool GlMakeResourceCurrent(void* user_data) {
  (void)user_data;
  return surface_gl_make_resource_current();
}

// Engine raster thread, once per frame — `fbo_reset_after_present` is what
// makes it once per frame rather than once per run, and that is what gives the
// GL host the resize hook `get_next_drawable` is on Metal.
static uint32_t GlFbo(void* user_data, const FlutterFrameInfo* frame_info) {
  (void)user_data;
  ResizeRingIfNeeded(frame_info);
  return surface_gl_fbo();
}

// Engine raster thread: the frame is in the framebuffer, so copy it into the
// ring and say so.
//
// There is no fence here and nothing to wait for. `surface_gl_readback` ends in
// a `glReadPixels`, which is synchronous by definition — it cannot return
// before the GPU has finished writing what it reads — so by the time this
// line is reached the frame is in the slot and OnFramePresented can be called
// outright, where the Metal path has to wait for a command buffer to complete.
// Note for whoever profiles this: on the Metal path `OnFramePresented` runs
// from a command-buffer completion handler, off the raster thread. Here it runs
// inline, so an armed capture does its `fwrite` — 7.7MB at 1600x1200 — and its
// blocking `ipc_send` inside the engine's present callback, stalling the
// guest's raster thread for the length of a disk write. Only a capture pays it,
// and a capture is already a stop-and-photograph, but a guest that captured
// every frame would be paced by the filesystem.
static bool GlPresent(void* user_data) {
  (void)user_data;
  int slot = surface_ring_acquire();
  surface_gl_readback(slot);
  PresentedFrame* frame = (PresentedFrame*)malloc(sizeof(PresentedFrame));
  frame->ring_index = (uint32_t)slot;
  frame->frame_id = ++g_frame_id;
  frame->generation = g_generation;
  surface_ring_advance();
  OnFramePresented(frame);
  return true;
}

static void* GlProcResolver(void* user_data, const char* name) {
  (void)user_data;
  return (void*)eglGetProcAddress(name);
}

#endif  // __APPLE__

int main(int argc, char** argv) {
  if (argc < 6) {
    fprintf(stderr,
            "usage: %s <assets_dir> <icu_data_path> <socket_path> "
            "<width> <height> [--capture-raw <path>] [--free-vsync]\n",
            argv[0]);
    return 2;
  }
  const char* assets_path = argv[1];
  const char* icu_data_path = argv[2];
  const char* socket_path = argv[3];
  int width = atoi(argv[4]);
  int height = atoi(argv[5]);
  // One argument at a time, and the ones that take a value say so. The
  // previous loop stepped in pairs, which silently swallowed any flag that
  // stands alone: `--free-vsync` as the last argument left `i + 1 < argc`
  // false and the loop never ran at all.
  for (int i = 6; i < argc; i++) {
    if (strcmp(argv[i], "--free-vsync") == 0) {
      g_free_vsync = true;
    } else if (strcmp(argv[i], "--capture-raw") == 0 && i + 1 < argc) {
      g_capture_path = strdup(argv[++i]);
    }
  }

  g_socket = ipc_connect(socket_path);
  if (g_socket < 0) {
    fprintf(stderr, "Cannot connect to socket: %s\n", socket_path);
    return 1;
  }

  if (!surface_ring_init(width, height)) {
    const char* msg = "surface allocation failed";
    ipc_send(g_socket, kMsgError, (const uint8_t*)msg, strlen(msg));
    return 1;
  }

  FlutterRendererConfig renderer = {0};
#ifdef __APPLE__
  renderer.type = kMetal;
  renderer.metal.struct_size = sizeof(FlutterMetalRendererConfig);
  renderer.metal.device = surface_metal_device();
  renderer.metal.present_command_queue = surface_metal_queue();
  renderer.metal.get_next_drawable_callback = GetNextDrawable;
  renderer.metal.present_drawable_callback = PresentDrawable;
#else
  renderer.type = kOpenGL;
  renderer.open_gl.struct_size = sizeof(FlutterOpenGLRendererConfig);
  renderer.open_gl.make_current = GlMakeCurrent;
  renderer.open_gl.clear_current = GlClearCurrent;
  renderer.open_gl.make_resource_current = GlMakeResourceCurrent;
  renderer.open_gl.present = GlPresent;
  renderer.open_gl.fbo_with_frame_info_callback = GlFbo;
  renderer.open_gl.fbo_reset_after_present = true;
  renderer.open_gl.gl_proc_resolver = GlProcResolver;
#endif

  FlutterProjectArgs args = {0};
  args.struct_size = sizeof(FlutterProjectArgs);
  args.assets_path = assets_path;
  args.icu_data_path = icu_data_path;
  args.log_message_callback = OnLogMessage;
  args.log_tag = "embedder";
  if (g_free_vsync) args.vsync_callback = OnVsyncRequest;

  // Impeller, unless the escape hatch says otherwise. Two reasons it is not
  // optional: Flutter GPU needs it and refuses without it, and the tester the
  // audit runs on now draws with it — a guest still on Skia would mean a
  // `screenshot` and an `audit` of one entry were rasterized differently.
  //
  // `Settings::enable_impeller` defaults to true only on Android and iOS, so
  // every desktop embedder has to ask. The name below is
  // `softwareRenderingKey` in `app/lib/src/constants.dart`; the two halves
  // have to agree.
  //
  // The GL host names its backend and the Metal one does not, which is not an
  // inconsistency: an unqualified `--enable-impeller` falls through to the
  // engine's Vulkan branch, and on Linux there is a Vulkan driver for it to
  // fall through *to* — a renderer config saying `kOpenGL` and a rasterizer
  // that came up on Vulkan. Naming `opengles` is what holds the two together.
  // Nothing is named on macOS because nothing has needed to be; the Metal
  // config has always been enough there, and a flag added on a host this
  // cannot be run on is a change made blind.
  const char* engine_argv[] = {"flutterware_guest", "--enable-impeller",
#ifndef __APPLE__
                               "--impeller-backend=opengles",
#endif
                               "--enable-flutter-gpu"};
  const char* software = getenv("FW_SOFTWARE_RENDERING");
  if (software == NULL || strcmp(software, "1") != 0) {
    args.command_line_argc =
        (int)(sizeof(engine_argv) / sizeof(engine_argv[0]));
    args.command_line_argv = engine_argv;
  }

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
  const double no_insets[4] = {0, 0, 0, 0};
  SendWindowMetrics(width, height, g_pixel_ratio, no_insets);

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
      double insets[4] = {0, 0, 0, 0};
      memcpy(&new_width, payload + 0, 4);
      memcpy(&new_height, payload + 4, 4);
      memcpy(&pixel_ratio, payload + 8, 8);
      // Optional, so a client built before the insets existed still resizes.
      if (len >= 48) memcpy(insets, payload + 16, 32);
      g_pixel_ratio = pixel_ratio;
      // The ring is reallocated inside GetNextDrawable on the raster thread;
      // here we only nudge the engine to render at the new size.
      SendWindowMetrics((int)new_width, (int)new_height, pixel_ratio, insets);
    } else if (type == kMsgPointerEvent) {
      input_handle_pointer(g_engine, payload, len);
    } else if (type == kMsgKeyEvent) {
      input_handle_key(g_engine, payload, len);
    } else if (type == kMsgCapture) {
      // Arm a capture and force a frame: the engine renders nothing when
      // nothing changed, so without this a request on a static scene would
      // wait forever.
      char* path = (char*)malloc(len + 1);
      memcpy(path, payload, len);
      path[len] = '\0';
      pthread_mutex_lock(&g_capture_lock);
      free(g_capture_path);
      g_capture_path = path;
      pthread_mutex_unlock(&g_capture_lock);
      FlutterEngineScheduleFrame(g_engine);
    } else if (type == kMsgCaptureSequence) {
      // `<count u32 LE><stride u32 LE><prefix>`. No frame is scheduled: the point of a
      // sequence is that the guest's own loop schedules them, and one forced
      // here would be written as somebody's stop before that loop had set it.
      if (len >= 8) {
        uint32_t count;
        uint32_t stride;
        memcpy(&count, payload, 4);
        memcpy(&stride, payload + 4, 4);
        if (stride == 0) stride = 1;
        char* prefix = (char*)malloc(len - 8 + 1);
        memcpy(prefix, payload + 8, len - 8);
        prefix[len - 8] = '\0';
        pthread_mutex_lock(&g_capture_lock);
        free(g_sequence_prefix);
        g_sequence_prefix = count > 0 ? prefix : NULL;
        if (count == 0) free(prefix);
        g_sequence_remaining = count;
        g_sequence_stride = stride;
        g_sequence_index = 0;
        g_sequence_tick = 0;
        pthread_mutex_unlock(&g_capture_lock);
      }
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

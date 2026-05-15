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

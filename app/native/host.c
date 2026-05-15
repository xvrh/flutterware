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
    uint8_t payload[16];
    uint32_t ring_index = (uint32_t)slot;
    uint32_t generation = g_generation;
    memcpy(payload + 0, &ring_index, 4);
    memcpy(payload + 4, &frame_id, 8);
    memcpy(payload + 12, &generation, 4);
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

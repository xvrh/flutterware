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

  // FlutterEngineShutdown blocks indefinitely with the software renderer
  // (the engine's internal threads have no vsync source to drain). Since this
  // process only needs to write the PNG and exit, skip graceful shutdown and
  // let the OS reclaim resources.
  if (!have_frame) {
    fprintf(stderr, "Timed out waiting for a rendered frame.\n");
    exit(1);
  }
  if (!ok) {
    fprintf(stderr, "Failed to write %s\n", output_path);
    exit(1);
  }
  exit(0);
}

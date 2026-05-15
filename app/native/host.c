// Headless Flutter-engine host: runs a kernel blob and echoes Dart print()
// output (delivered via the embedder log callback) to stdout.
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include "flutter_embedder.h"

static const char* kExpected = "Hello, World!";

static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_cond = PTHREAD_COND_INITIALIZER;
static bool g_found = false;

// Software renderer present callback: there is no surface in headless mode,
// so discard the pixels and report success.
static bool PresentSoftware(void* user_data, const void* allocation,
                            size_t row_bytes, size_t height) {
  (void)user_data;
  (void)allocation;
  (void)row_bytes;
  (void)height;
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
  if (message && strstr(message, kExpected)) {
    pthread_mutex_lock(&g_mutex);
    g_found = true;
    pthread_cond_signal(&g_cond);
    pthread_mutex_unlock(&g_mutex);
  }
}

int main(int argc, char** argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: %s <assets_dir> <icu_data_path>\n", argv[0]);
    return 2;
  }
  const char* assets_path = argv[1];
  const char* icu_data_path = argv[2];

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

  // Wait up to 10s for hello.dart's print() to arrive via OnLogMessage.
  struct timespec deadline;
  clock_gettime(CLOCK_REALTIME, &deadline);
  deadline.tv_sec += 10;
  pthread_mutex_lock(&g_mutex);
  while (!g_found) {
    if (pthread_cond_timedwait(&g_cond, &g_mutex, &deadline) != 0) {
      break;  // timed out
    }
  }
  bool found = g_found;
  pthread_mutex_unlock(&g_mutex);

  FlutterEngineShutdown(engine);

  if (!found) {
    fprintf(stderr, "Timed out waiting for \"%s\".\n", kExpected);
    return 1;
  }
  return 0;
}

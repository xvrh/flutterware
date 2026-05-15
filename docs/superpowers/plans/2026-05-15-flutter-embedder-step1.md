# Flutter Embedder — Step 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compile a hello-world Dart program to kernel with the Flutter `frontend_server` and run it headless inside a C host that embeds the prebuilt Flutter engine, surfacing the program's `print()` output on the host's stdout.

**Architecture:** A new pub-workspace member `embedder/` with two units that meet at one interface — an `assets/` directory containing `kernel_blob.bin`. A Dart **compiler** drives the Flutter cache's `frontend_server` (via `package:frontend_server_client`) to produce that kernel. A C **host** links `FlutterEmbedder.framework` (the prebuilt engine artifact that exports the C embedder API), runs the engine with the engine's software renderer in headless mode (no window), and echoes Dart `print()` — delivered through the embedder API's `log_message_callback` — to its own stdout. A `tool/run.dart` orchestrator downloads the framework, then chains compile → CMake build → run.

**Tech Stack:** Dart (`frontend_server_client`, `path`, `test`), C11, CMake, the prebuilt Flutter engine (`FlutterEmbedder.framework`) and `flutter_embedder.h`.

**Reference spec:** `docs/superpowers/specs/2026-05-15-flutter-embedder-step1-design.md`

**Environment assumptions (verified on the dev machine):**
- The compiler and orchestrator are run with the Dart SDK bundled in the Flutter checkout (`<flutter>/bin/cache/dart-sdk/bin/dart`). `frontend_server_client` auto-discovers `<dart-sdk>/bin/snapshots/frontend_server_aot.dart.snapshot` and runs it with `dartaotruntime` when `frontendServerPath` is omitted.
- Flutter cache layout (relative to `<flutter>/bin/cache`):
  - `artifacts/engine/common/flutter_patched_sdk/platform_strong.dill`
  - `artifacts/engine/darwin-x64/icudtl.dat`
  - `engine.stamp` — the 40-char engine revision.
- The C embedder API (`FlutterEngineRun`, …) is NOT exported by the cache's
  `FlutterMacOS.framework`. It ships in `FlutterEmbedder.framework`, downloaded at
  run time from `storage.googleapis.com/flutter_infra_release/flutter/<engine-revision>/darwin-x64/FlutterEmbedder.framework.zip`
  (~31 MB) and cached, gitignored, under `embedder/.engine/`.
- macOS host, CMake ≥ 3.15 and `curl`/`unzip` on PATH.

---

## Task 1: Scaffold the `embedder` workspace package

**Files:**
- Create: `embedder/pubspec.yaml`
- Create: `embedder/.gitignore`
- Create: `embedder/example/hello.dart`
- Modify: `pubspec.yaml` (root, the `workspace:` list)

- [ ] **Step 1: Add the member to the root workspace**

In the root `pubspec.yaml`, change the `workspace:` block from:

```yaml
workspace:
  - app
  - examples/example
```

to:

```yaml
workspace:
  - app
  - examples/example
  - embedder
```

- [ ] **Step 2: Create `embedder/pubspec.yaml`**

```yaml
name: flutterware_embedder
description: Experimental Flutter engine embedder (step 1 — headless hello world).
publish_to: 'none'
resolution: workspace

environment:
  sdk: ^3.6.0

dependencies:
  frontend_server_client: ^4.0.0
  path: ^1.9.0

dev_dependencies:
  test: ^1.25.0
```

- [ ] **Step 3: Create `embedder/.gitignore`**

```
build/
.dart_tool/
.engine/
```

- [ ] **Step 4: Create `embedder/example/hello.dart`**

```dart
void main() {
  print('Hello, World!');
}
```

- [ ] **Step 5: Resolve dependencies**

Run from the repo root: `flutter pub get`
Expected: completes without error; `embedder/.dart_tool/package_config.json` is created.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml embedder/pubspec.yaml embedder/.gitignore embedder/example/hello.dart pubspec.lock
git commit -m "Scaffold flutterware_embedder workspace package"
```

---

## Task 2: Flutter cache path resolver

**Files:**
- Create: `embedder/lib/src/flutter_cache.dart`
- Test: `embedder/test/flutter_cache_test.dart`

- [ ] **Step 1: Write the failing test**

`embedder/test/flutter_cache_test.dart`:

```dart
import 'dart:io';

import 'package:flutterware_embedder/src/flutter_cache.dart';
import 'package:test/test.dart';

void main() {
  test('resolves existing Flutter cache artifacts from the running SDK', () {
    var cache = FlutterCache.fromRunningSdk();

    expect(File(cache.platformDill).existsSync(), isTrue,
        reason: 'platform_strong.dill should exist at ${cache.platformDill}');
    expect(File(cache.icuData).existsSync(), isTrue,
        reason: 'icudtl.dat should exist at ${cache.icuData}');
    expect(cache.engineRevision, matches(RegExp(r'^[0-9a-f]{40}$')),
        reason: 'engine.stamp should hold a 40-char git revision');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd embedder && dart test test/flutter_cache_test.dart`
Expected: FAIL — `flutter_cache.dart` does not exist / `FlutterCache` undefined.

- [ ] **Step 3: Implement the resolver**

`embedder/lib/src/flutter_cache.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates artifacts inside a Flutter checkout's `bin/cache` directory.
class FlutterCache {
  FlutterCache(this.cacheDir);

  /// Path to `<flutter>/bin/cache`.
  final String cacheDir;

  /// Derives the cache directory from the running Dart executable, which must
  /// be the Dart SDK bundled in a Flutter checkout
  /// (`<flutter>/bin/cache/dart-sdk/bin/dart`).
  factory FlutterCache.fromRunningSdk() {
    var dart = Platform.resolvedExecutable;
    // <cache>/dart-sdk/bin/dart -> <cache>
    var cache = p.dirname(p.dirname(p.dirname(dart)));
    if (!Directory(p.join(cache, 'artifacts', 'engine')).existsSync()) {
      throw StateError(
          'Could not locate the Flutter cache from "$dart". Run this tool '
          'with the Dart SDK bundled in your Flutter checkout.');
    }
    return FlutterCache(cache);
  }

  String get _engine => p.join(cacheDir, 'artifacts', 'engine');

  /// The Flutter patched SDK directory, used as `--sdk-root` for the compiler.
  String get flutterPatchedSdkDir =>
      p.join(_engine, 'common', 'flutter_patched_sdk');

  /// The platform kernel passed as `--platform` to the compiler.
  String get platformDill =>
      p.join(flutterPatchedSdkDir, 'platform_strong.dill');

  /// ICU data the engine needs at startup.
  String get icuData => p.join(_engine, 'darwin-x64', 'icudtl.dat');

  /// The engine revision the cached artifacts were built at. Used to fetch the
  /// matching `FlutterEmbedder.framework` from Flutter's artifact storage.
  String get engineRevision =>
      File(p.join(cacheDir, 'engine.stamp')).readAsStringSync().trim();
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd embedder && dart test test/flutter_cache_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add embedder/lib/src/flutter_cache.dart embedder/test/flutter_cache_test.dart
git commit -m "Add Flutter cache path resolver to embedder"
```

---

## Task 3: Kernel compiler

**Files:**
- Create: `embedder/lib/compiler.dart`
- Test: `embedder/test/compiler_test.dart`

- [ ] **Step 1: Write the failing test**

`embedder/test/compiler_test.dart`:

```dart
import 'dart:io';

import 'package:flutterware_embedder/compiler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('compiles example/hello.dart to a non-empty kernel blob', () async {
    var packageRoot = Directory.current.path; // `dart test` runs from here
    var outDir = Directory.systemTemp.createTempSync('embedder_compile_test');
    addTearDown(() => outDir.deleteSync(recursive: true));
    var outputDill = p.join(outDir.path, 'kernel_blob.bin');

    // This is a pub workspace: the single package_config.json lives at the
    // repo root (the parent of the embedder package), not per-member.
    var repoRoot = p.dirname(packageRoot);
    var dill = await compileToKernel(
      entrypoint: p.join(packageRoot, 'example', 'hello.dart'),
      outputDill: outputDill,
      packageConfig:
          p.join(repoRoot, '.dart_tool', 'package_config.json'),
    );

    expect(dill.existsSync(), isTrue);
    expect(dill.lengthSync(), greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd embedder && dart test test/compiler_test.dart`
Expected: FAIL — `compiler.dart` does not exist / `compileToKernel` undefined.

- [ ] **Step 3: Implement the compiler**

`embedder/lib/compiler.dart`:

```dart
import 'dart:io';

import 'package:frontend_server_client/frontend_server_client.dart';

import 'src/flutter_cache.dart';

/// Compiles [entrypoint] to a Flutter-target kernel blob at [outputDill] using
/// the Flutter cache's `frontend_server`.
///
/// [cache] defaults to the cache of the running Dart SDK. Returns the written
/// kernel file. Throws [StateError] on compilation errors.
Future<File> compileToKernel({
  required String entrypoint,
  required String outputDill,
  required String packageConfig,
  FlutterCache? cache,
}) async {
  cache ??= FlutterCache.fromRunningSdk();
  File(outputDill).parent.createSync(recursive: true);

  var client = await FrontendServerClient.start(
    entrypoint,
    outputDill,
    cache.platformDill,
    sdkRoot: cache.flutterPatchedSdkDir,
    target: 'flutter',
    packagesJson: packageConfig,
  );
  try {
    var result = await client.compile();
    if (result == null || result.dillOutput == null) {
      throw StateError('frontend_server produced no kernel output.');
    }
    if (result.errorCount > 0) {
      throw StateError('Compilation failed:\n'
          '${result.compilerOutputLines.join('\n')}');
    }
    client.accept();
    return File(result.dillOutput!);
  } finally {
    await client.shutdown();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd embedder && dart test test/compiler_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add embedder/lib/compiler.dart embedder/test/compiler_test.dart
git commit -m "Add frontend_server-based kernel compiler to embedder"
```

---

## Task 4: `bin/compile.dart` CLI

**Files:**
- Create: `embedder/bin/compile.dart`

- [ ] **Step 1: Implement the CLI**

A thin wrapper for manual use; covered end-to-end by the Task 8 integration test.

`embedder/bin/compile.dart`:

```dart
import 'dart:io';

import 'package:flutterware_embedder/compiler.dart';
import 'package:path/path.dart' as p;

/// Usage: dart run flutterware_embedder:compile <entrypoint.dart> <output.dill>
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: compile <entrypoint.dart> <output_dill>');
    exit(2);
  }
  var entrypoint = p.absolute(args[0]);
  var outputDill = p.absolute(args[1]);
  // This is a pub workspace: package_config.json lives at the repo root.
  // Platform.script -> <repo>/embedder/bin/compile.dart, so go up three dirs.
  var packageConfig = p.join(
      p.dirname(p.dirname(p.dirname(Platform.script.toFilePath()))),
      '.dart_tool',
      'package_config.json');

  var dill = await compileToKernel(
    entrypoint: entrypoint,
    outputDill: outputDill,
    packageConfig: packageConfig,
  );
  stdout.writeln('Wrote ${dill.lengthSync()} bytes to ${dill.path}');
}
```

- [ ] **Step 2: Verify it analyzes cleanly**

Run: `cd embedder && dart analyze bin/compile.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add embedder/bin/compile.dart
git commit -m "Add compile CLI to embedder"
```

---

## Task 5: Vendor `flutter_embedder.h`

**Files:**
- Create: `embedder/native/flutter_embedder.h`

- [ ] **Step 1: Download the embedder header at the cached engine revision**

The engine revision matches the Flutter framework revision. Get it:

Run: `git -C "$(dirname "$(dirname "$(which flutter)")")" rev-parse HEAD`
This prints the Flutter/engine commit SHA — call it `<SHA>`.

Download the embedder header from the Flutter monorepo at that revision:

```bash
mkdir -p embedder/native
curl -fsSL \
  "https://raw.githubusercontent.com/flutter/flutter/<SHA>/engine/src/flutter/shell/platform/embedder/embedder.h" \
  -o embedder/native/flutter_embedder.h
```

- [ ] **Step 2: Verify the header is the embedder API**

Run: `grep -c 'FlutterEngineRun\|FlutterProjectArgs\|log_message_callback' embedder/native/flutter_embedder.h`
Expected: a non-zero count (the header declares `FlutterEngineRun`, the `FlutterProjectArgs` struct, and the `log_message_callback` field).

If the count is 0 the path or SHA is wrong — the header is a single self-contained file; do not proceed until it contains these symbols.

- [ ] **Step 3: Commit**

```bash
git add embedder/native/flutter_embedder.h
git commit -m "Vendor flutter_embedder.h for the embedder host"
```

---

## Task 6: The C host

**Files:**
- Create: `embedder/native/host.c`
- Create: `embedder/native/CMakeLists.txt`

- [ ] **Step 1: Write `embedder/native/host.c`**

```c
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
```

- [ ] **Step 2: Write `embedder/native/CMakeLists.txt`**

```cmake
cmake_minimum_required(VERSION 3.15)
project(flutterware_embedder_host C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

if(NOT FLUTTER_FRAMEWORK_DIR)
  message(FATAL_ERROR
    "Pass -DFLUTTER_FRAMEWORK_DIR=<dir containing FlutterEmbedder.framework>")
endif()

add_executable(host host.c)
target_include_directories(host PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_options(host PRIVATE "-F${FLUTTER_FRAMEWORK_DIR}")
target_link_libraries(host PRIVATE "-framework FlutterEmbedder")
set_target_properties(host PROPERTIES
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "${FLUTTER_FRAMEWORK_DIR}")
```

> Note: the C embedder API (`FlutterEngineRun`, …) is exported by
> `FlutterEmbedder.framework`, **not** by the `FlutterMacOS.framework` in the local
> cache (that one is the high-level Obj-C desktop framework). `FlutterEmbedder.framework`
> is downloaded by the Task 7 orchestrator into `embedder/.engine/`.

- [ ] **Step 3: Commit**

The C host cannot be built standalone here — it links `FlutterEmbedder.framework`,
which the Task 7 orchestrator downloads. Compile + link + run are verified
end-to-end when `tool/run.dart` runs (Tasks 7 and 8). Commit the source now:

```bash
git add embedder/native/host.c embedder/native/CMakeLists.txt
git commit -m "Add C host that embeds the Flutter engine headless"
```

---

## Task 7: `tool/run.dart` orchestrator

**Files:**
- Create: `embedder/tool/run.dart`

- [ ] **Step 1: Implement the orchestrator**

`embedder/tool/run.dart`:

```dart
import 'dart:io';

import 'package:flutterware_embedder/compiler.dart';
import 'package:flutterware_embedder/src/flutter_cache.dart';
import 'package:path/path.dart' as p;

/// Downloads FlutterEmbedder.framework if needed, compiles example/hello.dart,
/// builds the C host, runs it. Exits with the host's exit code.
Future<void> main() async {
  // <embedder>/tool/run.dart -> <embedder>
  var packageRoot = p.dirname(p.dirname(p.fromUri(Platform.script)));
  // This is a pub workspace: package_config.json lives at the repo root.
  var repoRoot = p.dirname(packageRoot);
  var cache = FlutterCache.fromRunningSdk();

  var assetsDir = p.join(packageRoot, 'build', 'assets');
  var kernelBlob = p.join(assetsDir, 'kernel_blob.bin');
  var nativeBuildDir = p.join(packageRoot, 'build', 'native');
  var engineDir = p.join(packageRoot, '.engine');

  await _ensureEmbedderFramework(cache, engineDir);

  stdout.writeln('[run] compiling hello.dart -> kernel_blob.bin');
  await compileToKernel(
    entrypoint: p.join(packageRoot, 'example', 'hello.dart'),
    outputDill: kernelBlob,
    packageConfig:
        p.join(repoRoot, '.dart_tool', 'package_config.json'),
    cache: cache,
  );

  stdout.writeln('[run] configuring + building the C host');
  await _run('cmake', [
    '-S', p.join(packageRoot, 'native'),
    '-B', nativeBuildDir,
    '-DFLUTTER_FRAMEWORK_DIR=$engineDir',
  ]);
  await _run('cmake', ['--build', nativeBuildDir]);

  stdout.writeln('[run] starting the engine host');
  var host = await Process.start(
    p.join(nativeBuildDir, 'host'),
    [assetsDir, cache.icuData],
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await host.exitCode);
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

- [ ] **Step 2: Verify it runs end to end**

Run: `dart run embedder/tool/run.dart`
Expected: prints the `[run]` progress lines, then `Hello, World!` (from the engine host), and exits 0.

- [ ] **Step 3: Commit**

```bash
git add embedder/tool/run.dart
git commit -m "Add run orchestrator: compile, build host, run"
```

---

## Task 8: Pipeline integration test

**Files:**
- Test: `embedder/test/pipeline_test.dart`

- [ ] **Step 1: Write the integration test**

`embedder/test/pipeline_test.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('hello world runs end to end through the engine embedder', () async {
    // `dart test` runs with the package root as the current directory.
    var runScript = p.join(Directory.current.path, 'tool', 'run.dart');

    var result =
        await Process.run(Platform.resolvedExecutable, ['run', runScript]);

    printOnFailure('exit code: ${result.exitCode}');
    printOnFailure('stdout:\n${result.stdout}');
    printOnFailure('stderr:\n${result.stderr}');

    expect(result.stdout, contains('Hello, World!'));
    expect(result.exitCode, 0);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
```

- [ ] **Step 2: Run the test**

Run: `cd embedder && dart test test/pipeline_test.dart`
Expected: PASS — the orchestrator compiles, builds the host, runs the engine, and `Hello, World!` appears in stdout with exit code 0.

- [ ] **Step 3: Run the full embedder test suite**

Run: `cd embedder && dart test`
Expected: all three test files (`flutter_cache_test`, `compiler_test`, `pipeline_test`) PASS.

- [ ] **Step 4: Commit**

```bash
git add embedder/test/pipeline_test.dart
git commit -m "Add end-to-end pipeline integration test for embedder"
```

---

## Task 9: README and final analysis

**Files:**
- Create: `embedder/README.md`

- [ ] **Step 1: Write `embedder/README.md`**

```markdown
# flutterware_embedder

Experimental Flutter engine embedder.

**Step 1 (current):** compile a hello-world Dart program to kernel with the
Flutter `frontend_server` and run it headless inside a C host that embeds the
prebuilt Flutter engine. The program's `print()` output is echoed to stdout.
No window, no rendering.

## Run it

```sh
dart run embedder/tool/run.dart
```

Run with the Dart SDK bundled in your Flutter checkout
(`<flutter>/bin/cache/dart-sdk/bin/dart`).

## Layout

- `lib/compiler.dart` — drives `frontend_server` to produce `kernel_blob.bin`.
- `lib/src/flutter_cache.dart` — locates Flutter cache artifacts.
- `native/host.c` — C host embedding the Flutter engine (software renderer,
  headless).
- `native/flutter_embedder.h` — vendored engine embedder header. **Must match
  the engine revision in your Flutter cache.** Re-download it (see the
  implementation plan) after upgrading Flutter.
- `tool/run.dart` — orchestrator: compile → build host → run.

## Not yet implemented

Window/surface, external textures, hot reload, GUI integration, non-macOS
platforms.
```

- [ ] **Step 2: Verify workspace-wide analysis is clean**

Run (from repo root): `flutter analyze`
Expected: "No issues found!" (the embedder package included).

- [ ] **Step 3: Commit**

```bash
git add embedder/README.md
git commit -m "Add embedder README"
```

---

## Self-Review notes

- **Spec coverage:** package scaffold + workspace member (Task 1); compiler unit via `frontend_server_client` (Tasks 3–4); `flutter_embedder.h` vendoring (Task 5); headless software-renderer C host with `log_message_callback` → stdout (Task 6); `assets/kernel_blob.bin` interface (Tasks 3, 6, 7); `tool/run.dart` orchestrator (Task 7); single integration test (Task 8); README recording the engine-revision constraint (Task 9). Cache path resolution (Task 2) is an implied dependency of the compiler and host.
- **Deferred items** (window, textures, hot reload, VM service, non-macOS) are intentionally absent — out of scope per the spec.
- **Type consistency:** `FlutterCache` (`platformDill`, `icuData`, `engineRevision`, `flutterPatchedSdkDir`) and `compileToKernel({entrypoint, outputDill, packageConfig, cache})` are used identically across Tasks 2, 3, 4, 7. The host CLI contract `host <assets_dir> <icu_data_path>` matches between Task 6 and Task 7.

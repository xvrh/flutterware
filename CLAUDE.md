# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This is a pub workspace (`workspace:` in root `pubspec.yaml`) with two member packages:

- `/` — the published `flutterware` package. Contains the runtime libraries that Flutter apps depend on (`lib/devbar.dart`, `lib/flutter_test.dart`, `lib/feature_flag.dart`, `lib/ui_catalog.dart`, `lib/router_outlet.dart`, `lib/drawing.dart`) plus the user-facing CLI entry point `bin/flutterware.dart`.
- `app/` — `flutterware_app`, the Flutter desktop GUI (`publish_to: none`). Implements the actual tools the user sees: test runner, dependency manager, launcher icon editor, etc.
- `examples/example` — workspace member used as a sample project.

Versions in `pubspec.yaml` (`flutterware`) and `app/pubspec.yaml` (`flutterware_app`) must stay in sync — see the comment in the root pubspec.

## How the CLI/GUI launch flow works

`dart run flutterware` from a user's Flutter project executes `bin/flutterware.dart` — the launcher. It resolves its own package via `Isolate.resolvePackageUri`, works out everything that has to exist before `fw` can run, and narrates the lot as a `LaunchPlan` (`lib/src/launch_plan.dart`):

1. **Unpack**, for a hosted dependency only: copy the package + `app/` into `~/.flutterware/<sha1(packageRoot)>/` (Windows: `%APPDATA%`). A path dependency — i.e. this checkout — runs in place, so there is no copy and no flag to remember.
2. **Resolve**, for a fresh copy only (`dart pub get` in `app/`).
3. **Build the CLI** (`dart build cli -t bin/fw.dart -o app/build/cli`) **and build the GUI** (`flutter build <os> --release`), *concurrently*. The GUI build does not consume the CLI binary, and overlapping them is ~10s off a ~44s first run. `DesktopGui` (`lib/src/desktop_gui.dart`) is the one place that knows where the binary lands and which command produces it; the launcher and `GuiLauncher` both call it.
4. Spawn the CLI with `ProcessStartMode.inheritStdio`, passing context in env vars: `DART_EXECUTABLE_PATH`, `APP_TOOL_PATH`, `FW_EDITABLE_SOURCES`, and `FW_GUI_BUILD_RESULT` when it did the GUI build (see `lib/src/constants.dart` and `lib/src/desktop_gui.dart`).

The CLI (`app/bin/fw.dart` → `FwCli`) treats the GUI as one command among `status`, `actions`, `run`, `init`. `fw app` locates the Flutter SDK from the dart executable, builds the GUI if the launcher did not, and spawns it with `FW_PROJECT_PATH`, `FW_APP_TOOL_PATH`, `FW_FLUTTER_SDK_PATH` (see `app/lib/src/constants.dart`).

**Nothing forwards logs.** Every stage inherits or pipes stdio directly, so output arrives in the terminal that ran `dart run flutterware` without a transport. `RemoteLogServer`/`RemoteLogClient` and the 2800-line `lib/src/logs/` tree they lived in are deleted; `lib/src/log_client.dart` is what remains, and it is a `Logger.root` listener that calls `print`. In release mode `fw app` pipes the GUI's stdio so it can keep a `LiveRegion` (`lib/src/live_region.dart`) pinned below it; under `flutter run` (path dependency) stdio is inherited so `r`/`R`/`q` keep working.

When changing CLI behavior, remember a *hosted* install is cached under `~/.flutterware/`. Pass `--force-compile` to rebuild it, or delete that directory. Working on this checkout needs neither.

## Developing the GUI without the CLI bootstrap

Use `app/lib/main_dev.dart` as the entry point in your IDE. It bypasses the env-var wiring and runs the worktree shell against flutterware's own workspace, with a default Flutter SDK discovered via `FlutterSdkPath.findSdks()`. The catalog panel needs the app root passed in (`flutter run -t lib/main_dev.dart -d macos --dart-define=FLUTTERWARE_APP_ROOT="$(pwd)"` from `app/`). This is the normal inner-loop entry for GUI work.

`app/lib/main.dart` is the production entry point and **requires** the env vars above; it is not runnable standalone.

## Test runner architecture (legacy)

The pre-overhaul "test visualizer" still exists in-tree but is unreachable from the shell (`main.dart`); it is slated for a rewrite (master-plan M4, `docs/superpowers/specs/2026-07-30-scenarios-design.md`). Until then:

- `lib/src/test_runner/runtime/` — code that runs inside the user's Flutter test process, exported to consumers via `lib/flutter_test.dart`. This half is published API.
- `lib/src/test_runner/protocol/` and `app/lib/src/test_runner/` — the old wire format and GUI side, reachable only from dev entry points.

## Common commands

All commands run from the repo root unless noted.

```sh
# Static analysis (workspace-wide; CI uses the beta channel)
flutter analyze

# Tests for the GUI app
cd app && flutter test
# Run a single test file
cd app && flutter test test/dependencies_test.dart

# Pure-Dart tests for the root package
dart test test/router_outlet/path_test.dart

# Format the whole workspace (this is what CI checks)
dart tool/prepare_submit.dart

# Refresh pubspecs across all workspace members
dart tool/pub_get_all_projects.dart
dart tool/pub_upgrade_all_projects.dart

# Regenerate built_value / json_serializable code
cd app && dart run build_runner build --delete-conflicting-outputs
# (run from the package whose .g.dart files you're regenerating)

# Run the CLI end-to-end against examples/example, forcing a fresh compile
cd examples/example && dart run flutterware --force-compile -v
```

## CI expectations

`.github/workflows/analyze-and-test.yaml` runs on the Flutter `beta` channel and will fail if `dart tool/prepare_submit.dart` produces any diff (excluding `pubspec.lock`). Always run that formatter before committing.

## Lint rules worth knowing

`analysis_options.yaml` enables `strict-casts` and a stricter-than-default lint set. A few rules differ from typical Flutter projects:

- `prefer_single_quotes`, `use_raw_strings`, `prefer_interpolation_to_compose_strings` are on.
- `omit_local_variable_types` — prefer `var` over explicit types for locals.
- `avoid_final_parameters` — do not mark function parameters `final`.
- `unawaited_futures` — wrap intentional fire-and-forget calls in `unawaited(...)`.
- `prefer_const_*` Flutter lints are explicitly **off**; do not litter the code with `const`.
- `avoid_print` is off (the CLI uses `print`).

## Vendored packages

`lib/src/third_party/` holds copies of `device_frame`, `highlight`, and `flutter_highlight` driven by `vendor.yaml`. Edit those files in-place; they are not pulled from pub.

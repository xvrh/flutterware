# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This is a pub workspace (`workspace:` in root `pubspec.yaml`) with two member packages:

- `/` — the published `flutterware` package. Contains the runtime libraries that Flutter apps depend on (`lib/devbar.dart`, `lib/flutter_test.dart`, `lib/feature_flag.dart`, `lib/previews.dart`, `lib/ui_catalog.dart`, `lib/router_outlet.dart`, `lib/drawing.dart`) plus the user-facing CLI entry point `bin/flutterware.dart`.
- `app/` — `flutterware_app`, the Flutter desktop GUI (`publish_to: none`). Implements the actual tools the user sees: test runner, dependency manager, launcher icon editor, etc.
- `examples/example` — workspace member used as a sample project.

Versions in `pubspec.yaml` (`flutterware`) and `app/pubspec.yaml` (`flutterware_app`) must stay in sync — see the comment in the root pubspec.

## Toolchain: fvm-pinned Flutter SDK

The SDK is pinned in `.fvmrc` and managed by [fvm](https://fvm.app). The `flutter`/`dart` on PATH are typically older than the pin (the workspace requires a recent beta) and **fail the SDK constraint check** — always use `fvm flutter ...` / `fvm dart ...`, or equivalently `.fvm/flutter_sdk/bin/flutter` / `.fvm/flutter_sdk/bin/dart`.

One-time setup in a fresh clone or worktree (`.fvm/` is gitignored, so it starts absent):

```sh
fvm use --skip-pub-get   # reads .fvmrc, no prompt; creates .fvm/flutter_sdk (fvm install first if the SDK isn't cached)
fvm flutter pub get
```

Note: `.gitignore` starts with `.*`, so dot-directories like `.claude/` are silently unaddable — `git add` no-ops on them.

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

## Driving the running GUI (the agent inner loop)

For GUI work, the fastest loop is not restart-and-look — it is *drive*: launch the GUI through the run plugin (which wraps the entry point in the run guest), then alternate code edits with `act`/`observe` transactions against the live window. Design: `docs/superpowers/specs/2026-08-11-run-drive-design.md`.

- **The MCP server.** `.mcp.json` registers `fvm dart run flutterware_app:mcp`, so the server is always built from this checkout — the globally installed `fw` binary can be weeks stale. Tools: `flutterware_status`, `flutterware_actions`, `flutterware_invoke`, `flutterware_act`. Everything they can do is documented in `docs/capabilities.md` (generated). In a fresh worktree the server cannot start until the one-time fvm setup above has run (`.fvm/` starts absent) — an MCP connection failure at session start means that, not a broken server. Without MCP, the same actions are reachable in-process from a `Session` — `app/tool/drive_spike/dogfood.dart` is a working example.
- **The loop.** Open with `flutterware_act {verb: observe}` — the human may already have the window running, and launching again spawns a second instance that steals the run's handle. Only if the reply says nothing is running: `flutterware_invoke run/launch {package: app, entrypoint: lib/main_dev.dart, device: macos, wait: true}` — the "Studio (dev)" entry point declared in `tool/flutterware.dart`. Then per iteration: edit → `flutterware_invoke run/reload` → `flutterware_act {verb: observe}`. Measured: **~2s per edit-reload-observe round trip**, screenshot plus visible texts in every reply. A hidden window is fully drivable (the settle loop forces frames), so the human minimizing the app changes nothing.
- **Refusals are instructions.** `multiple` → retry with `{"nth": {"target": …, "index": 0}}`; `notFound` reports the texts of the screen it searched. A wrong-target tap cannot succeed silently. `tree: true` costs thousands of tokens on the real GUI — the texts ride along free; ask for the tree only when you need structure.
- **`navigate` jumps.** The shell registers the drive navigate handler (`app/lib/src/shell/drive_navigator.dart`), so one call — `flutterware_act {verb: navigate, route: "fw:///worktrees/<worktree>/<plugin>/<segments…>"}` — replaces a tap path through the rail. The grammar is the address bar's own `fw://`; refusals teach it and list the worktrees git knows, and every act reply carries `worktree`, so the route builds from what the last reply already told you.
- **You are co-driving one app with the human.** Every step lands in the run's journal (`~/.flutterware/run/<key>.journal.jsonl`) and shows in the GUI's Run → Steps tab; the human may have moved the app since your last step, so open with `observe`, never assume the screen is where you left it.
- **Scenarios vs drive.** Scenarios stay the tool for deterministic, headless flows (milliseconds, FakeAsync). Reach for drive when it must be the real thing: real data, real backend, a real device, or this GUI itself.

## Test runner architecture (legacy)

The pre-overhaul "test visualizer" still exists in-tree but is unreachable from the shell (`main.dart`); it is slated for a rewrite (master-plan M4, `docs/superpowers/specs/2026-07-30-scenarios-design.md`). Until then:

- `lib/src/test_runner/runtime/` — code that runs inside the user's Flutter test process, exported to consumers via `lib/flutter_test.dart`. This half is published API.
- `lib/src/test_runner/protocol/` and `app/lib/src/test_runner/` — the old wire format and GUI side, reachable only from dev entry points.

## Common commands

All commands run from the repo root unless noted. Always via fvm — see the toolchain section above.

```sh
# Static analysis (workspace-wide; CI uses the beta channel)
fvm flutter analyze

# Tests for the GUI app
cd app && fvm flutter test
# Run a single test file
cd app && fvm flutter test test/dependencies_test.dart

# Pure-Dart tests for the root package
fvm dart test test/router_outlet/path_test.dart

# Format the whole workspace (this is what CI checks)
fvm dart tool/prepare_submit.dart

# Refresh pubspecs across all workspace members (workspace resolves from the root)
fvm flutter pub get

# Regenerate built_value / json_serializable code
cd app && fvm dart run build_runner build --delete-conflicting-outputs
# (run from the package whose .g.dart files you're regenerating)

# Run the CLI end-to-end against examples/example, forcing a fresh compile
cd examples/example && fvm dart run flutterware --force-compile -v
```

## Formatting

The only sanctioned formatter is `fvm dart tool/prepare_submit.dart` (or letting the pre-commit hook format staged files). **Never run bare `dart format`** — it uses whatever dart_style ships with the invoking SDK and infers language versions per file, both of which diverge from what CI checks and produce spurious diffs.

## CI expectations

`.github/workflows/analyze-and-test.yaml` runs on the Flutter `beta` channel and will fail if `tool/prepare_submit.dart` produces any diff (excluding `pubspec.lock`). Always run that formatter before committing.

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

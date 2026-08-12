# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This is a pub workspace (`workspace:` in root `pubspec.yaml`) with two member packages:

- `/` — the published `flutterware` package. Contains the runtime libraries that Flutter apps depend on (`lib/devbar.dart`, `lib/flutter_test.dart`, `lib/feature_flag.dart`, `lib/previews.dart`, `lib/ui_catalog.dart`, `lib/router_outlet.dart`) plus the user-facing CLI entry point `bin/flutterware.dart`.
- `app/` — `flutterware_app`, the Flutter desktop GUI (`publish_to: none`). Implements the actual tools the user sees: test runner, dependency manager, launcher icon editor, etc.
- `examples/example` — workspace member used as a sample project.

Versions in `pubspec.yaml` (`flutterware`) and `app/pubspec.yaml` (`flutterware_app`) must stay in sync — see the comment in the root pubspec.

## Toolchain: the committed `./fw` wrapper

The SDK is pinned in `flutter_version` and fetched by the committed `./fw` wrapper script (macOS-only for now) — no fvm, no global tool. The `flutter`/`dart` on PATH are typically older than the pin (the workspace requires a recent beta) and **fail the SDK constraint check** — always go through the wrapper: `./fw flutter ...` / `./fw dart ...` (from a subdirectory, `../fw` and so on). The first run downloads the pinned SDK to `~/.flutterware/sdks/<version>/` (checksummed, ~4 min cold); after that the wrapper adds ~0.1s. `FW_FLUTTER_SDK=<path>` bypasses the pin.

One-time setup in a fresh clone or worktree:

```sh
./fw flutter pub get     # first run also downloads the pinned SDK
```

`./fw flutter upgrade`/`downgrade`/`channel <x>` are refused: bump the pin by editing `flutter_version`.

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

- **The MCP server.** `.mcp.json` runs `tool/mcp_server.sh`, which self-heals a fresh worktree (`./fw` SDK install + pub get, ~8s when the SDK is already in `~/.flutterware/sdks`) and then serves from this checkout's source — the globally installed `fw` binary can be weeks stale. Tools: `flutterware_status`, `flutterware_actions`, `flutterware_invoke`, `flutterware_act`. Everything they can do is documented in `docs/capabilities.md` (generated).
- **If the flutterware MCP tools are unavailable, STOP. Do not start the task.** Report it loudly in your first message — not as an aside, not in the final summary — then diagnose and fix the cause: run `printf '' | sh tool/mcp_server.sh` and read its stderr; usually the fix is the one-time setup above. The client cannot reconnect mid-session, so once the cause is fixed, tell the user the MCP will be back on the next session and ask them to restart. **Never silently work around a dead MCP.** The one sanctioned fallback — `cd app && ../fw dart run tool/drive_spike/step.dart <action> '<json>'`, one run-plugin action per process — may be used only after the user has explicitly agreed to continue without the MCP.
- **The loop.** Open with `flutterware_act {verb: observe}` — the human may already have the window running, and launching again spawns a second instance that steals the run's handle. Only if the reply says nothing is running: `flutterware_invoke run/launch {package: app, entrypoint: lib/main_dev.dart, device: macos, wait: true}` — the "Studio (dev)" entry point declared in `tool/flutterware.dart`. Then per iteration: edit → `flutterware_invoke run/reload` → `flutterware_act {verb: observe}`. Measured: **~2s per edit-reload-observe round trip**, screenshot plus visible texts in every reply. A hidden window is fully drivable (the settle loop forces frames), so the human minimizing the app changes nothing.
- **Refusals are instructions.** `multiple` → retry with `{"nth": {"target": …, "index": 0}}`; `notFound` reports the texts of the screen it searched. A wrong-target tap cannot succeed silently. `tree: true` costs thousands of tokens on the real GUI — the texts ride along free; ask for the tree only when you need structure.
- **When Flutter cannot see it, `layer: native` can.** The verbs above address the app's widget tree, which ends at the platform's edge. Pass `layer: native` to the same `act`/`observe` and you address the platform's own accessibility tree instead: permission dialogs and other native popups, a webview's DOM, another app the flow jumped to, and a screenshot of the *real device screen* rather than a raster of the Flutter layer. It is slower (Android ~4s a step; the iOS simulator ~0.6s) so it stays the fallback, and it is never taken for you — a drive refusal that could be a native thing says so. It does `observe`, `tap`, `enterText` (Android only) and `foreground`; targets are the same grammar minus `key`/`tooltip`/`within`, plus `{"role": …}` and `{"at": {"x": …, "y": …}}` for a point no element covers. Two rules worth knowing before they bite: on Android the tree is the **focused window**, so a dialog is fully there but the soft keyboard is not; on macOS it sees native chrome only, because a Flutter app publishes nothing of its own UI to macOS accessibility.
- **A suspended iOS app is recoverable now.** `act {verb: foreground, layer: native}` brings a backgrounded simulator app back — Home, then its icon, because `simctl launch` would restart it and lose the state. The timeout that reports the problem says this too.
- **`navigate` jumps.** The shell registers the drive navigate handler (`app/lib/src/shell/drive_navigator.dart`), so one call — `flutterware_act {verb: navigate, route: "fw:///worktrees/<worktree>/<plugin>/<segments…>"}` — replaces a tap path through the rail. The grammar is the address bar's own `fw://`; refusals teach it and list the worktrees git knows, and every act reply carries `worktree`, so the route builds from what the last reply already told you.
- **You are co-driving one app with the human.** Every step lands in the run's journal (`~/.flutterware/run/<key>.journal.jsonl`) and shows in the GUI's Run → Steps tab; the human may have moved the app since your last step, so open with `observe`, never assume the screen is where you left it. What they did is not a guess: the reply's `human` field lists their taps since your last step (`tap "Pay"`), and the same entries precede your step in the journal as `actor: human`.
- **Phones drive the same way, foregrounded.** An Android emulator and an iOS simulator run the identical loop at desktop speed (measured 2026-08-11 — `docs/superpowers/specs/2026-08-11-run-drive-design.md` § Mobile), so `run/launch` on a device id is all it takes. Two differences to know: **iOS suspends a backgrounded app**, so an act against one comes back as a timeout telling you to bring it forward — a hidden desktop window and a backgrounded Android app both drive fine — and the screenshot is the Flutter layer tree only, so the soft keyboard and platform views are blank bands in it. Physical iOS additionally needs the project's Xcode signing to be set up.
- **Scenarios vs drive.** Scenarios stay the tool for deterministic, headless flows (milliseconds, FakeAsync). Reach for drive when it must be the real thing: real data, real backend, a real device, or this GUI itself.

## Common commands

All commands run from the repo root unless noted. Always via the `./fw` wrapper — see the toolchain section above.

```sh
# Static analysis (workspace-wide; CI runs the same pinned SDK via ./fw)
./fw flutter analyze

# Tests for the GUI app
cd app && ../fw flutter test
# Run a single test file
cd app && ../fw flutter test test/dependencies_test.dart

# Pure-Dart tests for the root package
./fw dart test test/router_outlet/path_test.dart

# Format the whole workspace (this is what CI checks)
./fw dart tool/prepare_submit.dart

# Refresh pubspecs across all workspace members (workspace resolves from the root)
./fw flutter pub get

# Regenerate built_value / json_serializable code
cd app && ../fw dart run build_runner build --delete-conflicting-outputs
# (run from the package whose .g.dart files you're regenerating)

# Run the CLI end-to-end against examples/example, forcing a fresh compile
cd examples/example && ../../fw dart run flutterware --force-compile -v
```

## Formatting

The only sanctioned formatter is `./fw dart tool/prepare_submit.dart` (or letting the pre-commit hook format staged files). **Never run bare `dart format`** — it uses whatever dart_style ships with the invoking SDK and infers language versions per file, both of which diverge from what CI checks and produce spurious diffs.

## CI expectations

`.github/workflows/analyze-and-test.yaml` runs on the pinned SDK via `./fw` and will fail if `tool/prepare_submit.dart` produces any diff (excluding `pubspec.lock`). Always run that formatter before committing.

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

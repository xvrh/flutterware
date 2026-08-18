# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Never name another project

**Nothing written here may name a client, their repository, their people or their product.** Not code, comments, doc comments, docs, tests, fixtures, test data, commit messages, branch names, PR titles and bodies, changelog entries, or issue text. This repository is public; they are not.

Work with a real consumer is where most of the good findings come from, and those findings are still worth writing down — write them without the identity. *"A consumer migrating from v1"*, *"measured on a real 46-scenario suite"*, *"an app that loads its translations at boot"* carry the whole of the evidence. The name carries none of it.

This applies to everything that leaves the machine, including a PR opened on your behalf — check before pushing, not after.

## Repository layout

This is a pub workspace (`workspace:` in root `pubspec.yaml`) with two member packages:

- `/` — the published `flutterware` package. Contains the runtime libraries that Flutter apps depend on (`lib/devbar.dart`, `lib/flutter_test.dart`, `lib/feature_flag.dart`, `lib/previews.dart`, `lib/ui_catalog.dart`, `lib/router_outlet.dart`) plus the user-facing CLI entry point `bin/flutterware.dart`.
- `app/` — `flutterware_app`, the Flutter desktop GUI (`publish_to: none`). Implements the actual tools the user sees: test runner, dependency manager, launcher icon editor, etc.
- `examples/example` — workspace member used as a sample project.

Versions in `pubspec.yaml` (`flutterware`) and `app/pubspec.yaml` (`flutterware_app`) must stay in sync — see the comment in the root pubspec.

## Toolchain: fvm

The SDK is pinned in `.fvmrc` and installed by [fvm](https://fvm.app). Every Flutter or Dart command in this repo goes through it: `fvm flutter …` / `fvm dart …`, from any directory.

### Setting yourself up

```sh
fvm install && fvm flutter pub get
```

`fvm install` is a no-op (~0.2s) when the version is already in `~/fvm/versions`; on a new machine it downloads it, which takes minutes.

**The one rule: the SDK is whichever one the invocation names.** `fvm dart run flutterware` says which SDK to use by choosing the `dart` that runs it. Nothing in this repo discovers an SDK from a pin file, a cache or `FLUTTER_HOME` — `test/ambient_sdk_test.dart` fails the build if any source spawns a bare `dart` or `flutter`. So do not reach for the `flutter`/`dart` on PATH: measured 2026-08-14 on this machine, PATH Dart is **3.12.1 stable** against a `^3.13.0-0` floor, and `dart run flutterware` there fails with *"The language version 3.13 … is too high"*.

If the MCP server is what you need up, `tool/mcp_server.sh` performs this setup itself on first connect — measured **5s** on a worktree with a stale resolution and the SDK already cached. See the drive section below.

One thing worth knowing before you point anything else at fvm: **on a version it has not cached, `fvm` auto-installs and narrates the download onto stdout** — a banner, a spinner and a curl progress meter, with no flag to quiet it. Harmless in a terminal, fatal where stdout is a protocol. That is why `tool/mcp_server.sh` installs first, redirected, before it execs the server.

Note: `.gitignore` starts with `.*`, so dot-files need an explicit `!` line to be committable — `.fvmrc` has one. Dot-directories like `.claude/` are otherwise silently unaddable (`git add` no-ops on them).

### Which Flutter we support: two numbers, not one

`.fvmrc` and the `environment:` floors in the pubspecs answer different questions, and keeping them apart is the whole policy.

- **`.fvmrc` is the pin** — the SDK development happens on. It tracks whatever beta is worth having; fvm installs exactly it and CI runs exactly it.
- **The `environment:` floors are a promise** — the oldest Flutter the package claims to work on. They move *only* when something below them actually breaks.

Let the floor track the pin and it promises the beta of the week. That is how `flutter: '>=3.47.0-0'` came to sit in a package whose last published floor was `>=3.21.0`: a floor naming an unreleased beta is a package nobody on stable can install. Held apart, stable catches up on its own — the floor stays put, stable rises past it, and the package becomes installable there with nobody republishing.

Only the pubspecs that ship carry the promise: the root package and `app/`, which `.pubignore` keeps in the archive. `examples/example` is excluded and records its own real requirement (dot shorthands, Dart 3.10).

```sh
fvm dart tool/bump_flutter.dart beta        # or stable, or 3.48.0-0.1.pre — moves the pin
fvm dart tool/bump_flutter.dart --floor     # promise the pin, after a break below it
fvm dart tool/bump_flutter.dart --check     # what CI runs; offline
```

A bump writes `.fvmrc` only; run `fvm install` after it. `--check` reads the SDK it is *running under* and refuses if that is not the pin, so it works the same on a laptop and in CI.

Each command moves one number, never both. `--check` catches only the half that breaks *us* — a floor risen above the pin. A floor that is lower than what the code needs is a claim nothing here disproves, because nothing runs an older SDK.

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

Use `app/lib/main_dev.dart` as the entry point in your IDE. It bypasses the env-var wiring and runs the worktree shell against flutterware's own workspace. This is the normal inner-loop entry for GUI work. It discovers **no** SDK of its own and throws if it is not given one — see below.

`main`'s optional named parameters are its **knobs**, so launched through flutterware (*Studio (dev)*) they are editable on the run's Knobs tab and a change costs a hot restart rather than a rebuild. Launched by hand each falls back to a define, so an old run configuration still works.

The Flutter SDK is the one that bites: a `flutter run` GUI has a stripped environment, so nothing inside the process can see which `flutter` launched it — and flutterware never guesses an SDK. **Through flutterware you no longer pass it**: `tool/flutterware.dart` declares the knob `from: ValueSource.flutterSdk`, so the launcher hands over the SDK it is building with, and `required: true` refuses the launch *before the build* if it ever cannot. By hand, say it out loud:

```sh
cd app && fvm flutter run -t lib/main_dev.dart -d macos \
  --dart-define=FLUTTERWARE_APP_ROOT="$(pwd)" \
  --dart-define=FLUTTER_SDK_ROOT="$(cd "$(dirname "$(which flutter)")/.." && pwd)"
```

`app/lib/main.dart` is the production entry point and **requires** the env vars above; it is not runnable standalone.

## Driving the running GUI (the agent inner loop)

For GUI work, the fastest loop is not restart-and-look — it is *drive*: launch the GUI through the run plugin (which wraps the entry point in the run guest), then alternate code edits with `act`/`observe` transactions against the live window. Design: `docs/superpowers/specs/2026-08-11-run-drive-design.md`.

- **The MCP server.** `.mcp.json` runs `tool/mcp_server.sh`, which self-heals a fresh worktree (`fvm install` + pub get, ~5s when the SDK is already in `~/fvm/versions`) and then serves from this checkout's source rather than from anything installed. Tools: `flutterware_status`, `flutterware_actions`, `flutterware_invoke`, `flutterware_act`. Everything they can do is documented in `docs/capabilities.md` (generated).
- **If the flutterware MCP tools are unavailable, STOP. Do not start the task.** Report it loudly in your first message — not as an aside, not in the final summary — then diagnose and fix the cause: run `printf '' | sh tool/mcp_server.sh` and read its stderr; usually the fix is the one-time setup above. The client cannot reconnect mid-session, so once the cause is fixed, tell the user the MCP will be back on the next session and ask them to restart. **Never silently work around a dead MCP.** The one sanctioned fallback — `cd app && fvm dart run tool/drive_spike/step.dart <action> '<json>'`, one plugin action per process (`<plugin>/<action>` for anything but run) — may be used only after the user has explicitly agreed to continue without the MCP. The same script is also the way to exercise an action the *connected* server is too old to know about: it is frozen at the session's start, so a plugin action you just wrote is not on it.
- **The loop.** Open with `flutterware_act {verb: observe}` — the human may already have the window running, and launching again spawns a second instance that steals the run's handle. Only if the reply says nothing is running: `flutterware_invoke run/launch {package: app, entrypoint: lib/main_dev.dart, device: macos, wait: true}` — the "Studio (dev)" entry point declared in `tool/flutterware.dart`. Then per iteration: edit → `flutterware_invoke run/reload` → `flutterware_act {verb: observe}`. **What an entry point has to be launched with is on `run/entrypoints`, not here** — each knob with its kind, its default and whether it is `required`; a required one with nothing to fall back on reports no default at all, and `launch` refuses it before it builds anything rather than after. Measured: **~2s per edit-reload-observe round trip**, screenshot plus visible texts in every reply. A hidden window is fully drivable (the settle loop forces frames), so the human minimizing the app changes nothing.
- **Refusals are instructions.** `multiple` → retry with `{"nth": {"target": …, "index": 0}}`; `notFound` reports the texts of the screen it searched. A wrong-target tap cannot succeed silently. `tree: true` costs thousands of tokens on the real GUI — the texts ride along free; ask for the tree only when you need structure.
- **When Flutter cannot see it, `layer: native` can.** The verbs above address the app's widget tree, which ends at the platform's edge. Pass `layer: native` to the same `act`/`observe` and you address the platform's own accessibility tree instead: permission dialogs and other native popups, a webview's DOM, another app the flow jumped to, and a screenshot of the *real device screen* rather than a raster of the Flutter layer. It is slower (Android ~4s a step; the iOS simulator ~0.6s) so it stays the fallback, and it is never taken for you — a drive refusal that could be a native thing says so. It does `observe`, `tap`, `enterText` (Android only) and `foreground`; targets are the same grammar minus `key`/`tooltip`/`within`, plus `{"role": …}` and `{"at": {"x": …, "y": …}}` for a point no element covers. Two rules worth knowing before they bite: on Android the tree is the **focused window**, so a dialog is fully there but the soft keyboard is not; on macOS it is for native chrome, because Flutter builds a semantics tree only when the *platform* asks and nothing flutterware does asks it — some processes have been asked by something else and then publish their whole UI here, which is a bonus rather than something to rely on.
- **A suspended iOS app is recoverable now.** `act {verb: foreground, layer: native}` brings a backgrounded simulator app back — Home, then its icon, because `simctl launch` would restart it and lose the state. The timeout that reports the problem says this too.
- **`navigate` jumps.** The shell registers the drive navigate handler (`app/lib/src/shell/drive_navigator.dart`), so one call — `flutterware_act {verb: navigate, route: "fw:///worktrees/<worktree>/<plugin>/<segments…>"}` — replaces a tap path through the rail. The grammar is the address bar's own `fw://`; refusals teach it and list the worktrees git knows, and every act reply carries `worktree`, so the route builds from what the last reply already told you.
- **You are co-driving one app with the human.** Every step lands in the run's journal (`~/.flutterware/run/<key>.journal.jsonl`) and shows in the GUI's Run → Steps tab; the human may have moved the app since your last step, so open with `observe`, never assume the screen is where you left it. What they did is not a guess: the reply's `human` field lists their taps since your last step (`tap "Pay"`), and the same entries precede your step in the journal as `actor: human`.
- **Phones drive the same way, foregrounded.** An Android emulator and an iOS simulator run the identical loop at desktop speed (measured 2026-08-11 — `docs/superpowers/specs/2026-08-11-run-drive-design.md` § Mobile), so `run/launch` on a device id is all it takes. Two differences to know: **iOS suspends a backgrounded app**, so an act against one comes back as a timeout telling you to bring it forward — a hidden desktop window and a backgrounded Android app both drive fine — and the screenshot is the Flutter layer tree only, so the soft keyboard and platform views are blank bands in it. Physical iOS additionally needs the project's Xcode signing to be set up.
- **Scenarios vs drive.** Scenarios stay the tool for deterministic, headless flows (milliseconds, FakeAsync). Reach for drive when it must be the real thing: real data, real backend, a real device, or this GUI itself.
- **To *look* at a widget, render it — never build a harness for it.** `previews screenshot` compiles one `@Preview` entry to a PNG with the real fonts and the real theme, at any device in the table and at that device's pixel ratio, so a 1px corner or a 16pt glyph comes back big enough to judge. **`node=<name>` photographs one widget** — `node=SplitButton`, `node=Save`, matched the way `find` matches — so the picture is the thing you asked about rather than it in the corner of a 900×700 canvas; several matches are refused with their ids rather than guessed at. That is the answer to "does this border survive its corner", "do these two icons read as two controls", "what does this look like in dark" — including for **this app's own widgets**, which is what `app/tool/catalog/demos/` is: the studio's controls, previewed in the studio. A control that is private to its panel cannot be an entry, so pull it into its own file first; that is a smaller price than the alternatives. Do not reach for `flutter test` + `RepaintBoundary.toImage` — measured 2026-08-17, it renders every glyph as a filled box because the test binding loads no font, so it cannot answer an icon question at all — and do not reload the whole studio to squint at a 130px control in a window screenshot.
- **One screen grammar, three surfaces.** A live app (`flutterware_act`), a preview (`previews inspect`) and a step a scenario captured (`scenarios read`) all answer with the same **screen** — the things carrying words or responding to touch, nested under the layout, with their boxes and their state — and all take the same questions: `find`, `at "x,y"`, `styles`, `tree` (expensive), and `lens: act|look|design|raw` for how much at once. `scenarios read` with no arguments takes the step the last run failed on, which is the read you want after a red suite; naming a directory refuses with a listing of what is in it.

## Scenarios: which half is published

The scenario code sits in two places and only one of them is API:

- `lib/src/scenarios/` — runs inside the user's Flutter test process, re-exported through `lib/flutter_test.dart`. **This half is published**: changing it changes what users' existing tests compile against.
- `app/lib/src/scenarios/` — the GUI and CLI side (panel, flow view, motion player, discovery, artifacts). Free to change.

Design: `docs/superpowers/specs/2026-07-30-scenarios-design.md`.

## Common commands

All commands run from the repo root unless noted. Always via `fvm` — see the toolchain section above.

```sh
# Static analysis (workspace-wide; CI runs the same pinned SDK)
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

`.github/workflows/analyze-and-test.yaml` reads `.fvmrc` and installs exactly that version, then runs `flutter`/`dart` straight off PATH — a runner has cheaper ways to place an SDK than fvm, and what has to match is the version. It will fail if `tool/prepare_submit.dart` produces any diff (excluding `pubspec.lock`). Always run that formatter before committing.

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

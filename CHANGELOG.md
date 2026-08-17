## 0.5.2

The UI catalog tool is now **Previews**, and entries are declared with
Flutter's own annotation. Breaking, with no deprecation path.

- **`@Demo` is gone.** Annotate with `@Preview` from
  `package:flutter/widget_previews.dart`; a preview written for Flutter's own
  previewer is an entry here with nothing to change. `formFactor:` went with
  it — pin a canvas from the panel instead.
- **The whole package is scanned**, not `demo/` only, so a preview beside the
  widget it shows is found. Files `git` ignores are skipped, and symlinks are
  not followed. `Previews(directory: …)` narrows the scan, and moves where
  `new` writes.
- **New library `previews.dart`** — what `@Preview` does not carry:
  `PreviewShell` and `PreviewAxes` for the top bar's axes, and `context.knobs.*`
  for knobs. It is imported only when you want one of those; declaring a preview
  imports nothing of flutterware's.
- **`TopBarState` is `PreviewAxes`**, and a shell's builder is handed `axes`
  rather than `topBar`. It named the furniture the switches are drawn on, which
  left nothing in the API to connect it to `--axes=`, `describe --axes=true` or
  the `axes:` on an artifact's address.
- **Knobs are called knobs in Dart too.** `context.previews.parameters.*` and
  `context.uiCatalog.parameters.*` are both now **`context.knobs.*`**, the type
  is `Knobs` (exported, so knob-setting can be factored out), and the devbar's
  `DevbarKnobs` typedef — which existed only to give the class the right name —
  is gone. The CLI's `--knobs=`, `KnobDescriptor` and the panel already said
  knob; only the Dart API disagreed, and "parameters" means the *non*-interactive
  tier in Storybook and the arguments of a function in Dart.
- **`ui_catalog.dart` is now only the in-app catalog** — `UICatalog`,
  `FormFactor`, `Figma`, plus `Knobs` — the browsable page you ship inside your
  own app. `CatalogShell` moved to `previews.dart` as `PreviewShell`;
  `UICatalogState` is gone, and `UICatalogStateProvider` is `KnobsProvider`.
- `ui_catalog_guest.dart`, which only generated code imports, is
  `previews_guest.dart`.
- The plugin is `Previews(...)` (was `UiCatalog(...)`) and its id is
  `flutterware.previews`, so the CLI reads `fw run previews …`.
- **A `Run` entry point declares `defines`, not `knobs`.** `LaunchKnob` is
  `DartDefine` (its `define:` field is now `name:`), `KnobSource` is
  `DefineSource`, `Entrypoint(knobs: …)` is `Entrypoint(defines: …)`, and
  `fw run run launch --knobs=` is `--defines=`. Both plugins spelled `--knobs=`
  for opposite costs: a preview knob is read while a widget builds and changing
  one costs a frame, while these are compiled in and changing one costs a full
  rebuild and reinstall. The manifest key and the `launch` result field follow.
- **`launch` selects an entry point by name as well as by path.** Declaring one
  file several times under different names is how one app is run against
  several configurations, so a path is not a unique handle — and the two places
  that assumed it was behaved badly: the `entrypoint` choice offered two options
  carrying the *same value*, and the ambiguity refusal answered
  `name one of: lib/main.dart, lib/main.dart`, a choice between identical
  strings that no caller could act on. The options are now the names, and the
  refusal asks for whichever of the name or the `package` actually separates the
  matches — or, when nothing the caller passes could, says to give two
  same-named declarations distinct names. Resolution already accepted a name, so
  a call that passes a path is unaffected.
- **An audit that finds something now exits 1.** `previews audit`,
  `previews check` and `assets audit` reported their findings and exited 0
  either way, so the obvious CI line — `fw run previews audit` — was green
  whatever the audit found, which is worse than not running it: the job reports
  a check that cannot fail, and a green pipeline is not something anyone goes
  and reads. Each of those results now carries its own verdict as an `ok` field
  and `fw` exits 1 when it is false, which is the rule `scenarios run` already
  followed. An unreachable package counts as a failure, for the reason it is
  reported separately at all. The report still prints in full, so anything
  parsing the JSON keeps working — and which actions gate is now written in
  `fw run <plugin> <action> --help` and in `docs/capabilities.md`, rather than
  being discoverable only by breaking something on purpose and reading `$?`.
- **A captured stdout gets the result and nothing else.** An action prints its
  result as JSON whether or not `--json` was asked for, and on a cold run the
  launcher's own progress narration went to stdout above it — so the first run
  on a fresh machine, which is every run CI makes, put `build the CLI… (~10s)`
  in front of the object something was about to parse. Narration now moves to
  stderr whenever stdout is not a person watching: piped, redirected, or a CI
  log. A terminal is unchanged.
- **Two cold `fw` runs on one machine no longer build over each other.** The
  tree under `~/.flutterware/<hash>` is one copy per flutterware version per
  *machine*, shared by every project that resolves that version — so two
  invocations starting cold at the same time unpacked into the same directory
  and then ran `dart build cli -o` against the same output path. Reproduced:
  two of three such pairs fail, either with `install_name_tool` refusing to add
  `@executable_path/..` to a binary that already has it or with a raw
  `writeFrom failed … Input/output error` from appending a snapshot to a file
  being replaced. A machine that only ever runs one cold build at a time never
  sees it; a CI runner with parallel jobs sees nothing else. Preparing the tree
  now takes a cross-process lock beside it, and the loser waits out the winner
  and finds the artifacts built — saying so on the same stream the rest of the
  narration uses, rather than blocking in silence.
- **Upgrading your Flutter no longer breaks `fw`.** The tools under
  `~/.flutterware/<hash>` were a function of flutterware's sources alone, and
  the copy carried flutterware's own `pubspec.lock` — so every project built
  the GUI from the package versions this repository resolved against *its*
  pinned SDK, and `pub get`, which preserves a lock by design, kept it that way
  forever. A project that moved to a newer Flutter got a resolution predating
  its SDK, and what that looks like is not a stale copy: it is a syntax error a
  minute into the GUI build, in a transitive package nobody chose — reported as
  `jni-1.0.0/lib/src/core_bindings.dart: The representation field can't have a
  trailing comma`, where `jni 1.0.3` had been available and parses. The copy is
  now resolved where it is built: the lock does not travel with it, and one
  left behind by an older flutterware is removed. The SDK also joins the source
  fingerprint, so changing it re-unpacks, re-resolves and rebuilds both
  binaries instead of leaving a resolution nothing would ever revisit. The
  first `fw` after this lands rebuilds the tools once.

### Motion — new

A timeline editor for widget animations whose file format is Dart. Additive:
nothing here changes existing code, and a project that does not declare
`Motion(...)` is unaffected.

- **`package:flutterware/motion.dart`** — `MotionScope`, `MotionValues`, `Seg`,
  `MotionController`, `MotionTarget`, `MotionBox`, `MotionExtent`. You name a
  target and read its properties where they are used; the tuned numbers live in
  a `<screen>.motion.dart` the editor writes and you do not. With no such file
  every property falls back to its resting value and the code still runs, so
  the tool is optional at runtime.
- **A motion is a pure function of `t`.** No wall clock in the model, which is
  what makes scrubbing, playing, headless capture and a golden frame the same
  code path.
- **`MotionExtent(target, child: …)`** applies nothing and exists only so the
  panel can ring the element a lane drives. A target is not a widget, so
  nothing can be inferred; `MotionBox` registers one itself.
- **`package:flutterware/flutter_test.dart`** gains `MotionTester` —
  `tester.seekMotion(0.5)`, `motionValue(…)`, `motionDuration()` — driving a
  motion in the test isolate with no RPC and no frame to wait for.
- **`package:flutterware/motion_vocabulary.dart`** is the same closed property
  set without Flutter, for tooling that reads code rather than running it.
- **The plugin** is `Motion(packages: [...])`, id `flutterware.motion`, with
  `fw run motion capture|filmstrip|list`.
- `MotionScope` now mixes in `TickerProviderStateMixin` rather than the single
  variant, so writing `MotionScope(controller: MotionController(...))` inline
  in a `build` no longer dies on the second build.
- **`fw.identity(ProjectIdentity(package: …, icon: …))`** says which package is
  the repository and which picture stands for it. One window per repository and
  several open at once all look the same; this is what puts the project's own
  icon in the Dock tile, in ⌘-Tab and in the tab band. `icon:` is a path
  relative to the package, and a path that is not there — or one Flutter has no
  decoder for, such as a `.ico` — is reported on the worktree rather than
  silently leaving the window blank. `fw init` scaffolds a guess.

## 0.5.1

- Upgrade dependencies

## 0.5.0

- Add Figma integration to `ui_catalog`

## 0.4.2

- Move the devbar button slightly

## 0.4.1

- Increase test_api constraint

## 0.4.0

- Improve `package:flutterware/devbar.dart`

## 0.3.0

- Rename `widget_book` to `ui_book`

## 0.2.1

- Add search field to up-coming `storybook` feature

## 0.2.0

- Support Flutter 3.13

## 0.1.2

- Internal maintenance to improve pub's score.

## 0.1.1

- Allow to start the app from pub cache.

## 0.1.0

- Test runner with screenshots & hot-reload
- Pub dependencies manager
- Launcher icon manager

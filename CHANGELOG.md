## Unreleased

- **The previews catalog runs your `transformers:`.** An asset declared with
  `transformers:` is compiled the way a build compiles it — the same
  `dart run <package> --input --output`, the same arguments, chained in order —
  and the bundle serves the *output* under the declared key. Until now it served
  the source, so an app loading a precompiled SVG through
  `AssetBytesLoader` got raw XML and drew nothing, in a preview every surface
  called healthy. `previews audit`, `previews inspect` and the panel all read
  the same bundle, so all three were blind to it together.
  - **Check your test-environment fallbacks.** An app that branches on the
    binding — `WidgetsBinding.instance is! WidgetsFlutterBinding`, then parse
    the source with `flutter_svg` — is working around `flutter test` serving
    untransformed assets. That branch also fired under `previews audit`, and now
    hands a compiled payload to a source parser. Plain `flutter test` still
    needs it; flutterware's lanes no longer do, and one binding check can no
    longer tell the two apart. If you have such a branch, gate it on something
    narrower than the binding.
  - Output is cached by content under `~/.flutterware/transformed`, keyed on the
    asset's bytes and each transformer's resolved package root and arguments —
    so bumping a transformer recompiles, an unchanged asset never does, and two
    worktrees share every hit. Measured on a real 21-vector catalog: 1.7s for
    the first bundle, 118ms for every one after. Entries nothing has produced
    for 30 days are swept on a miss.
  - A transformer that fails, or that exits 0 without writing its output, fails
    the sync and quotes what the process said. It does not fall back to the
    source: bytes that resolve and cannot be decoded are the failure this
    removes.
  - `assets audit` no longer reports `declared-missing` against a correct
    `transformers:` declaration. That finding described a limitation of the
    catalog rather than a defect in the project, and since 0.5.2 made the audit
    exit 1 it made the command unusable in CI for anyone shipping SVGs the
    documented way.
- **A `DevStack` says what to run with `StackRun`, and can name a script instead
  of an executable.** Breaking: `Probe.exitCode` / `Probe.json`, `start:`,
  `stop:` and `StackCommand`'s third argument all took a `List<String>` and now
  take a `StackRun` — `StackRun.command([...])` for what you wrote before, or
  `StackRun.script('tool/local_env.dart', args: [...])` to name a Dart file in
  the project and let flutterware supply the interpreter. That is the one thing
  a config file cannot know: the `dart` on PATH is routinely not the SDK the
  project pins, and `fvm` has to be *found* — a GUI started from the Dock does
  not have your shell's PATH. `DefineSource.script` has made this argument since
  0.5.0; both configs in this repository were working around its absence by
  computing `Platform.resolvedExecutable` and prepending it to six commands.
  - A script's path is relative to the stack's `workingDirectory` and runs
    there, so it is written the way you would type it having cd'd in. (That
    differs from `DefineSource.script`, which is relative to the worktree root —
    the difference is the `workingDirectory` this plugin has.)
  - Spawned as `dart <path>`, not `dart run <path>`: `run` re-resolves the
    package graph and executes every build hook in it on every invocation, which
    a probe would pay on every poll. Measured at 0.33s against 0.28s here and
    0.70s against 0.58s on a consumer's real probe — small, and it grows with
    the project. The cost of that is that build hooks do not run, so a script
    needing native assets built must be a `StackRun.command`.
  - The larger win is that flutterware resolves the SDK and spawns it directly
    rather than going through a version manager: the same consumer's probe went
    from ~5s to 0.58s, because `fvm dart --version` on a loaded machine was
    measured at 4.3–7.7s doing nothing at all.
  - Older configs still read. A bare `List` where a `StackRun` now goes is taken
    as a command, so a project pinning an older `flutterware` keeps working.
- **A slow probe now widens its own interval instead of saturating the core.**
  `poll:` is a floor rather than a promise: the interval becomes at least four
  times the last probe's duration, so a probe never occupies more than a quarter
  of it. A fast probe never reaches the multiplier and nothing changes. Only the
  last probe knows what a probe costs — a consumer measured a probe at 4.4s
  against a default 10s interval, and the project's only recourse was to write a
  bigger number into `poll:` and explain the tool's cost model in a comment.
  (That 4.4s was a version manager on a loaded machine, not the build hooks this
  changelog first blamed; the cost a probe can turn out to have is the point,
  and it is not capped by anything flutterware knows in advance.)
- **Two probes can no longer race.** The poll timer used to fire whether or not
  the last probe had come back, so a probe slower than the interval left two
  subprocesses both writing the reading and the panel showed whichever finished
  last. A second caller now joins the probe in flight — which is also what makes
  the `status` action honest, since asked to go and look while a poll is out it
  returns that look rather than the cache. And a probe that never answers is
  reported as `unavailable` rather than blocking every later one.
- **A `Run` entry point no longer has to be under `lib/`.** An entry point in
  `demo/` or `tool/` is wrapped in the run guest like any other, so it gets
  knobs, `inspect` and `act` — it used to launch uninstrumented, with the reason
  logged. The wrapper needs no `package:` URI for its target: it is written
  inside the package, so a path reaches anything the package holds, and a file
  outside `lib/` has no `package:` spelling for a path to conflict with. A `lib/`
  entry point is still named by its `package:` URI, and only that — a library
  reached under two URIs is two libraries. An entry point *outside* its package
  is still refused, for that same reason. **Except on web**, where the path is
  not a spelling the compiler shares: a target with no `package:` URI is rooted
  at its own directory, so the wrapper's `../` climbs out of the world. Such a
  launch goes uninstrumented and says which `lib/` move would fix it — it used
  to fail the compile instead, naming generated source.
- Relatedly, an entry point's own import that climbs out of `lib/` but stays in
  the package — `import '../tool/helpers.dart'` — is now copied into the wrapper
  rather than dropped, so a knob whose type is declared there works.
- **A `DevStack` command that never returns no longer takes the stack with it.**
  A transition in flight is what refuses the next one, so a command that hung
  held the stack for the rest of the session and every later `start`, `stop` and
  command was refused against it — `logs --follow` declared as an ordinary
  command is exactly that shape. `DevStack(commandTimeout:)` bounds the wait,
  defaulting to ten minutes, and `StackCommand(timeout:)` overrides it for the
  command that is not meant to finish. **Nothing is killed**: a `docker compose
  up` interrupted half way leaves a stack in a state nobody chose, so the
  process is left running and reported as running, and only flutterware's claim
  on it ends. A timed-out result has `timedOut: true` and no `exitCode`, because
  zero would say it worked.
- **`DevStackRunResult` reports `stdout` and `stderr` apart**, each trimmed to
  its own tail, so a renderer can put `Running build hooks...` somewhere other
  than under the reader's eye. The merged `output` stays — it is what the panel
  draws and what a terminal wants — and the split is omitted when a command said
  everything on one stream, rather than carrying the same text twice.
- **Correction to 0.5.2: a `Run` entry point declares `knobs`, not `defines`.**
  That entry announced a rename to `Entrypoint(defines:)` / `DartDefine` /
  `--defines=`; it was undone before release, because a value a run supplies is
  a session value rather than a build value and does not always cost a rebuild.
  What ships is `Entrypoint(knobs: …)`, the class `Knob`, and `fw run run launch
  --knobs=`. The one piece of that rename still standing is the source type,
  which is published as `DefineSource` with `ValueSource` as its alias — the
  noun outlived the defines. The API moved twice and only the first move was
  written down here, which is what a consumer pinning a git ref reads this file
  to find out.
- **An unencodable value in a reported event no longer takes the whole
  attachment down.** `FlutterwareServer.event` / `span` accept whatever a
  reporter binds — a `DateTime`, an enum, a non-finite double — and one of them
  used to throw inside the encode on the way to an attacher, which the inspector
  reads as a dead peer and disconnects. The event stayed in the ring, so every
  reattach died in the same place until it rolled out: one bound parameter put a
  server's panel out for the rest of the session. Values `jsonEncode` refuses
  are now replaced by their own `toString()` on the way into the ring, which is
  also the more useful answer — a reporter that bound a date wants to read the
  date. A type with a `toJson()` is still encoded whole.
- **`explain` and `requery` are handed the occurrence's parameters, not just its
  text.** A bound statement is reported with `$1` / `@name` / `?` in place so
  `normalizeSql` can group occurrences by shape, which means the text alone will
  not run — `EXPLAIN` on it fails outside a prepared statement, and that is
  every query worth explaining in a real application. Commands now carry
  `params` beside `query`, and the adapter snippets in
  `doc/server_inspection.md` bind them instead of interpolating. The postgres
  snippet also reports the parameter *map* rather than `.values.toList()`, which
  was throwing away the names that bind it back.
- **`requests` and `errors` take filters and can return captured details.**
  `path`, `minStatus` and `since` narrow the answer where only `last` did
  before, `details: true` attaches the redacted headers and capped bodies the
  middleware already captures — the half a 500 is opened for, previously
  reachable only from the GUI — and every row now carries its event `id`.
  Details are bounded by a byte budget per reply, and the reply says how many
  went without.
- **The MCP tools refuse a top-level argument they do not declare.** A call that
  misspelled the wrapper key — `parameters:` where `arguments:` goes — used to
  run the action with its defaults and answer as if it had been asked. All five
  tools now declare `additionalProperties: false` and name what they do take.
- **`flutterware_status` takes `brief` and `plugin`.** The panel projection is
  the inventory and measures 90% of the reply — 19.2k of 21.7k characters on
  this repository — which every agent session paid on first contact because the
  instructions say to start here. `brief` keeps the status lines and the
  per-package entries and drops the rest (21.7k → 2.4k); `plugin` answers one in
  full, loading only that core.

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

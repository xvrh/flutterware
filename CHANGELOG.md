## Unreleased

- **A finished copy stops carrying the build it will never build again.**
  `dart run flutterware` mirrors the package out of the pub cache into
  `~/.flutterware/<key>/` and builds the tools there. That copy is a mirror of
  an *immutable* pub-cache package, so its stamp never moves and nothing ever
  builds in it a second time — and yet it kept the whole incremental tree of
  the build that did happen. Measured on a real install: **1479 MB, of which
  the product is 65 MB and the `fw` binary 17 MB.**
  `FlutterMacOS.framework.dSYM` alone was 501 MB of engine debug symbols, in a
  release build, that nothing here symbolicates.

  A successful build now keeps the product and the two binaries and drops the
  rest: everything beside the product within `build/<platform>`,
  `app/.dart_tool/flutter_build`, and the workspace's `.dart_tool/hooks_runner`.
  **1479 MB → 107 MB, in 154 ms.** Nothing rebuilds because of it — the
  freshness test both build sites use is whether the product's executable
  exists, and a release bundle carries its own frameworks with rpaths relative
  to the executable, so nothing outside it was ever referenced.

  `build/` itself is never pruned: the `fw` binary, the warm compiler kernel
  under `build/catalog` and the build logs all live there, and the logs are the
  post-mortem for a build that failed. `.dart_tool/package_config.json` stays
  too — that is the resolution, and losing it would turn a warm run into a
  `pub get`.

  Only ever after a build that worked. A failed one leaves a half-finished
  incremental tree, and that tree is what the next attempt resumes from —
  reclaiming it would turn every retry into a cold build. The product existing
  is the precondition for all of it, so a copy that has only ever built the CLI
  keeps its 12 MB of `hooks_runner`, which is genuinely an input to the GUI
  build it has not run yet.

  Otherwise it runs on **every** launch from a copy, not only the one that built
  it, so a copy made by an older flutterware is reclaimed the next time anything
  starts it. With nothing to delete it is a handful of directory listings, at
  45–63 µs. A checkout is never touched: there the incremental state is the
  whole point.

- **A catalog can keep every locale on the key's own row.**
  `TranslationCatalog` read one shape: a file per locale, named for it, holding
  key to string. A project whose translations are filled in a key at a time — a
  row per key with the languages side by side, which is what a human or a
  translation service edits — had no way to say so, and the only way through
  was to generate the other shape beside it and keep the two in step. Two
  checked-in copies of one truth, and a CI gate to stop them drifting.

  ```dart
  TranslationCatalog.localesPerKey(name: 'server', file: 'tool/strings.json')
  ```

  **`TranslationCatalog` is sealed now**, the way `StackRun` is and for the
  same reason: the variants do not carry the same thing. One file per locale is
  found with a glob because there is one for each; every locale under a key is
  a single `file`, and `files` naming it would be a plural that is never
  plural. The gap widens with the next format rather than closing — an ARB
  carries its locale inside the file and hides metadata under `@` keys, a CSV
  needs a delimiter and a key column — and a class per format is where those
  answers go. The unnamed constructor is unchanged, so existing declarations go
  on compiling.

  **Declared rather than sniffed**, because the two JSON shapes are only almost
  distinguishable: a per-locale file is allowed to carry an object beside its
  strings, and there is a test pinning that it is skipped rather than read.
  Sniffed, that file would silently become a catalog of strange locales. A test
  now reads one file both ways and expects both answers.

  A layout a build does not know reads as **null** rather than as the shape it
  does know — guessing would read one format as another and report an empty
  catalog against a declaration that is right. The panel says the build is too
  old instead.

  Two things an empty catalog can now say apart: a glob that matched no files,
  and files that were read and yielded no key. They send a reader to opposite
  ends of the declaration.

  Also: **a path naming one file reads that file.** The walk starts at a glob's
  literal prefix, which for a wildcard-free path is the file itself — opened as
  a directory it does not exist, and a single-file catalog read as empty with
  nothing wrong with it.

- **A step's inline event titles are bounded in width as well as in count.**
  `eventTitles` kept twelve summaries per step and each could run to the
  stored title's 300 characters — 3,600 on one step, which is not a number
  anyone budgets in. Now that a `db` event's title is a whole SQL statement
  the case is ordinary rather than pathological: measured, twenty
  hand-formatted queries on one step put 1,980 bytes of titles in the run's
  answer, and 1,639 with the cap.

  120 characters keeps what a title is scanned for — `select … from … join …`,
  a method and its path — and a cut one ends in `…` like the count marker
  beside it. The detail is appended *after* the cut, so a status code or a row
  count is never the half lost to a long URL. The whole title is in the
  capture either way, which is what `scenarios read events: true` reads.

- **A `db` event is titled with its statement, not with its first keyword.**
  `AppEvent.query` cut the SQL at the first newline, so a statement a
  generator emitted on one line titled whole and one a person formatted across
  several titled `select …`. Measured on a real suite, 110 of 194 db events
  were that one string — which half of an app was legible depended only on who
  wrote its SQL.

  It folds whitespace now and keeps the literals. Blanking those is
  `normalizeSql`'s job and the right one for *grouping*; a title is read, and
  `version >= 3` says more than `version >= ?` for the same width.

  **This also fixes a silent false negative in the comparison channel.**
  `EventChannel.mask` keys an event on its channel and title, so every
  hand-formatted `select` shared one key — and a branch that swapped one query
  for another reported no difference at all. N+1 siblings still group, because
  the mask folds digits to `#` and the literals are still there to fold.

  The database browser's panel feed had the same first-line cut and now folds
  too. `AppEvent.query`'s docstring gained the trap worth knowing before
  wiring one: opening a database costs a dozen statements before the app has
  done anything, and on a real suite that was 89% of the channel.

- **`normalizeSql` no longer turns `?1` into `??`.** sqlite's numbered
  placeholder — what `sqlite3` and `sqlite_async` emit — fell past the
  explicit `$1` rule into the bare-number one, which ate the digit and left a
  second `?`. Stable enough to group by, and reading as a typo wherever the
  result is shown.

- **One report reaches every surface, and the reporting API is renamed to say
  so.** There were two app-side places to say what the app did, neither aware
  of the other: a project wired `DevbarHttpClient` and got a full Network tab
  with an empty scenario Events pane, or wired the scenario call and got the
  reverse. Both describe the same fact about the same app.

  `recordAppEvent` now writes the scenario buffer *and* notifies registered
  listeners, and a mounted devbar registers one. Three things follow:

  * **`DevbarHttpClient` fills the Events pane for free**, for every project
    that already wraps its client — no new API, no migration. A suite whose
    fakes sit under `package:http` needs no reporting code at all.
  * **A project reporting from its own fakes fills the devbar for free**,
    which is what a suite that fakes at the typed-client layer needs: nothing
    is serialised there, so `DevbarHttpClient` has nothing to wrap.
  * **The `db` channel has a devbar home**: `LogQueriesPlugin`, a `Queries`
    tab beside `DatabasePlugin`'s browser. One wrapper around a database now
    feeds both surfaces.

  The devbar routes only the channels it has no source of its own for —
  `network`, `analytics`, `db`. `log` is excluded because `LoggerPlugin`
  already listens on `Logger.root`, and routing it would show every record
  twice.

  **Breaking, and mechanical.** The old names said *scenario* about something
  that was never scenario-only, which was half of why the split went
  unnoticed:

  | was | is |
  |---|---|
  | `ScenarioEvent` | `AppEvent` |
  | `ScenarioChannel` | `AppChannel` |
  | `recordScenarioEvent` | `recordAppEvent` |
  | `package:flutterware/scenarios.dart` | `package:flutterware/app_events.dart` |

  A rename and an import rewrite; no call site changes shape. The `.events.json`
  wire format is untouched, so `scenarioRunReportVersion` did not move and an
  old run still reads.

  The empty Events pane now names the door rather than only reporting silence
  — it could not tell "the app did nothing" from "this project reports
  somewhere else".

  **`scenarios read` can answer about them too.** `events: true` hands back
  what the app did on the way to a step, with the payload each event carried;
  `channel: network,db` narrows; `errors: true` keeps only the ones that are
  themselves a problem. `system` is excluded unless `channel` names it — on
  the example suite it is 183 of 189 events and 98% of the bytes. `eventCount`
  and `eventChannels` ride on every read whether or not you ask, so a step
  that has events says so before anyone knows to look, and the `next` line
  names the flag. Pointing `step` at a `.events.json` leg used to answer
  silently about the widget tree instead; it answers about events now.

  `eventTitles` says when its cap bit, as a trailing `… N more`, rather than
  handing back twelve of forty in silence.

  `addAppEventListener` is published too, for a project that wants a live
  surface of its own. Reporting cannot disturb the app that reports: a
  listener that throws is sent to the `Zone` and skipped rather than surfacing
  in the caller, and one that unregisters itself mid-report costs its
  neighbours nothing. Pass `ignoreSource` to skip a reporter that already
  handed your surface a copy — `devbarHttpClientSource` is the one that
  exists, and it is how the devbar avoids listing a request twice.

- **`s.attach` is replaced by `await s.document(…)` and
  `await s.notification(…)`, and both are steps.** A flow produces beats, and
  most of them are screens — but a run that exports a receipt has a moment
  where the receipt is the thing on stage, and one whose backend pushes a
  notification has a moment that is the push. Those are now steps like any
  other: named, positioned, parented, carrying the events that led to them.
  `ScenarioRunStep.kind` says which of the three a step is, and `image`,
  `format`, `width`, `height` and `tree` are null on anything that is not a
  screen — a document has no frame, because there was no screen showing it.

  What this removes: `ScenarioRunAttachment` and its `after` flag,
  `ScenarioRunStep.attachments`, and the attachment level of the panel's
  address (a beat is addressed by its own step index now). `after` existed to
  say whether the screen an attachment belonged to was its step or its
  step's parent — a correction for the fact that a synchronous `attach` could
  not anchor at its own moment. A verb can.

  What it adds: a document has a name, so a cross-branch comparison aligns it
  at the same trust tier as an authored `Shot` — where attachments were
  invisible to a diff entirely. Neither kind renders, so neither costs a
  capture; and neither draws, so a `screen` after one still names the frame
  before it rather than photographing it again.

- **The `SCREENSHOTS_DESTINATION` lane names an anonymous step after its verb.**
  `1-pumpWidget.png` rather than `1-step_1.png`, which is how the runner's own
  lane has always spelled it. A document beat writes its payload under the same
  stem, and a notification writes its three strings — so a destination
  directory reads as the flow did rather than silently omitting the beats that
  are not screens.


- **`s.screen('Name')` names the picture the verb before it took, instead of
  taking the same one again.** Under `Shots.auto` every verb captures, so the
  ordinary `tap` then `screen` pair produced two steps of one frame — the
  second byte-identical to the first, contributing nothing but the name.
  Measured by a consumer on a 125-scenario suite: **666 of 775 named steps
  (86%)** were duplicates, and they cost **312 MB of the run's 863 MB of step
  artifacts (36%)**, multiplied by every device and language CI runs. Where no
  frame has been drawn since the previous capture, the name now lands on that
  capture and no second step exists — so writing a name costs nothing, and an
  author never has to weigh one against the picture it would duplicate. A
  `screen` whose frame *has* moved on — a `pump`, a completer, a late decode —
  still takes its own picture, which is what the verb is for. A name never
  overwrites a name, a split branch's first capture never renames the step
  before the fork, and `screen('X', force: true)` declines the adoption for a
  deliberate second picture. **Reports of the same suite now have fewer steps**,
  so anything pinned to step indices or artifact file names will move; the
  merged step carries both the author's name and the verb that drew the frame,
  which is a stronger anchor for a cross-branch comparison than either half was
  alone.
- **A stalled `screen` is no longer exempt from `unchanged`.** The flag skipped
  every `screen` on the grounds that it was a deliberate second picture of the
  same frame. It is not one any more, so the exclusion is gone and a named step
  that changed nothing says so — the case the flag was previously blind to.
- **A step's tree, semantics and translation keys are read at the shutter.**
  A capture waits one step to see whether a `screen` will name it rather than
  photograph the same frame again — and everything read when it is finally
  handed over was therefore read one verb late. On the example counter, step 1
  reported `texts: ['Count: 0']` beside a `tree.json` that said
  `Text("Count: 1")`: one record, two frames. The three reads now happen where
  the picture is taken and ride on the capture, so `tree.json`,
  `semantics.json` and `keys.json` describe the frame in the image beside them
  — for `scenarios read`, the panel's inspector, the label audits and the
  translation export alike. Nothing changes under a bare `flutter test`, which
  writes none of them and now pays for none of them.
- **`unchanged` compares the picture, not the tree.** A tree is not a
  projection of the pixels in either direction: typed text, an animation, an
  image and anything painted on a canvas move the picture without moving the
  dump, while a value that changed harmlessly moves the dump without moving
  the picture. Measured on a consumer suite of 1240 steps, the two agreed on
  22 of the 297 steps the tree flagged — every `enterText` in the suite was
  reported as a step where nothing happened — and 102 genuine repeats went
  unflagged. It is the `digest` the same step already carries, so a stall now
  reads as a stall. A `document` or `notification` beat draws nothing, so it
  passes the picture in force through to the step after it.

- **One preview that leaves a decode in flight no longer slows every preview
  after it.** The image cache is `PaintingBinding`'s and process-wide, and
  nothing in `flutter_test` empties it between test bodies — so an entry that
  ended with `pendingImageCount > 0` handed that count to every entry after it,
  each of which then waited out the whole real-work allowance on work that was
  not its own and would never land. Measured on a 126-entry catalog with one
  such entry sixth: every one of the 117 after it went from ~50ms to a flat
  ~2.4s, and the whole capture took **287s**. It now takes **18s**. Both
  harnesses reset the cache at the top of every body, the scenario lane
  included — a scenario leaking a pending image had exactly the same shape.
- **The real-work allowance is a second of clock, which is what it always
  said.** It was spent by counting waiting turns and charging each one the
  millisecond it asked to sleep — against the ~2.4ms a turn of the real loop
  actually costs under `runAsync` — so the one-second deadlock ceiling took two
  and a half seconds to reach, and longer on a slower machine. It reads a
  stopwatch now, so the ceiling is the same wherever it runs.
- **An asset preview of an image that will not decode no longer leaves the key
  pending for ever.** `MemoryImage` is the one provider that does not evict on a
  failed decode, the way `NetworkImage`, `FileImage` and `ResizeImage` all do;
  the asset inspector does it for itself. Everything reading
  `pendingImageCount` as "work is in flight" — the drive settle included — was
  waiting on an image the app already knew about.

- **`run inspect --native` reads the platform's own log — the half `flutter
  run` structurally cannot show you.** Its device-log filter admits a line only
  from the app's main executable, the engine or `libswiftCore`, and a plugin
  ships a framework, so *every* line a plugin logs natively was dropped before
  flutterware could see it. Measured on one simulator over a window holding two
  runs of an app with a push SDK: 1366 events came from the app's process,
  `flutter run` admitted 7, and 105 of the ones it dropped were the SDK's —
  the entire evidence of whether the integration worked. Android is blind the
  same way for a different reason: logcat is filtered to a tag allow-list, so a
  plugin's `Log.d` never arrives either.
  - Scoped to this run's process and lifetime, and to code that is not the OS —
    the last clause is what makes it readable, taking that same window from
    1889 lines to 141. iOS simulator, Android and macOS; a physical iOS device
    is refused with the command to run by hand.
  - Off by default, because it costs a `log show` or an `adb logcat` — about a
    second — and the answer carries the exact command it ran, as `nativeLog`.
  - **A log read on a device we are not reading now says so.** The failure this
    closes was silence: a healthy-looking launch answered `errors: []` and six
    lines of build narration while the native half was where the story was.
  - The Run panel's Logs tab gains a **Platform** filter alongside App and
    Build.

- **A guest that is gone is an answer, not an exception.** The tolerant form of
  a guest extension call excused an unregistered extension but not a *dead
  connection*, so teardown calls made from a `dispose` — `unwatch`,
  `clearLogs`, documented as tolerant and fired without awaiting — threw into
  the zone, putting a whole widget-unmount stack trace in the run's log on
  every hot restart. `unawaited` silences the lint, not the error. Both shapes
  are handled now: a call in flight when the client is disposed, and one made
  afterwards — which did not throw at all but *hung*, because the client errors
  the completers it holds and then clears them. Writes still refuse, and refuse
  at once rather than waiting out the registration window against a connection
  that can never answer.

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

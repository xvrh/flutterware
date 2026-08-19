# Scenarios — the authoring API, one day in

**Date:** 2026-07-31
**Status:** Phases A–E **built and landed 2026-07-31**. What shipped, and where it diverged from the proposal, is
recorded under "as built" after each.
**Lineage:** `2026-07-30-scenarios-design.md` (the design that shipped as
#60) — this reviews the surface that landed and says what it still owes a user
writing a real app's tests.
**Evidence:** the four probes below, run under bare `flutter test` against
`examples/example` on the pinned SDK. Every finding here is measured, not
inferred; the probe file is reproduced so it can be re-run.

## The surface that shipped

**High level — the authoring API** (`lib/src/scenarios/scenario.dart`, exported
by `lib/flutter_test.dart`):

| surface | signature |
|---|---|
| `scenario` | `scenario(String, Future<void> Function(ScenarioTester), {Shots shots})` |
| `s.pumpWidget` | `(Widget, {Shot? shot})` — pumps twice, never settles |
| `s.tap` | `(dynamic, {Shot? shot})` — `Finder \| String \| Key \| IconData \| Type`, then `pumpAndSettle` |
| `s.enterText` | `(dynamic, String, {Shot? shot})` — then `pumpAndSettle` |
| `s.screen` | `(String, {List<String> tags})` — capture without acting |
| `s.split` | `(Map<String, Future<void> Function()>)` — depth-first replay, nests |
| `s.tester` | the real `WidgetTester`; captures nothing |
| `Shot` / `Shot.skip` / `Shots.auto\|manual` | capture policy, per call and per scenario |

Four verbs and a fork.

**Config** — `ScenariosPackage(pkg, {directory, languages, captureScale})`,
declared from `tool/flutterware.dart`.

**Operator** — `list` / `run` / `restart`, one shape for GUI, `fw` and MCP.
`run` takes `package` / `file` / `scenario` / `output`, the axes (`device`,
`language`, `text-scale`, `brightness`, `bold-text`, `high-contrast`,
`invert-colors`) and `capture-scale` / `format`.

**Low level — the seams**, none of them exported:

- `harness.runHarness(Map<String, void Function()>)`, driven over the VM
  service by `ext.flutterware.scenarios.list` / `.run`, streaming
  `flutterware.scenarios.step`.
- `scenarioRunArgs` (`ScenarioRunArgs`, `ScenarioRunAccessibility`) and
  `scenarioRunListener` (`ScenarioStepCapture`).
- Standalone capture: `--dart-define=screenshots-destination=…` or
  `SCREENSHOTS_DESTINATION`.
- On-disk contract: `<out>/<file>/<scenario>/<index>-<name>.png` + `.tree.json`.
- Discovery: `ScenarioScanner` parses `scenario('literal', …)` calls; it never
  resolves or compiles.

## What was measured

```dart
// examples/example/test/probe_scratch_test.dart — throwaway, deleted after.
var setUpRuns = 0;

void main() {
  setUp(() => setUpRuns++);

  scenario('spinner on screen', (s) async {
    await s.pumpWidget(const _SpinnerApp());   // Column: Text, CircularProgressIndicator, TextButton
    await s.tap('Add');
  });

  scenario('split replay vs setUp', (s) async {
    await s.pumpWidget(const _PlainApp());
    await s.split({
      'a': () async => print('BRANCH a, setUpRuns=$setUpRuns'),
      'b': () async => print('BRANCH b, setUpRuns=$setUpRuns'),
    });
  });

  scenario('failure inside a branch', (s) async {
    await s.pumpWidget(const _PlainApp());
    await s.split({
      'good': () async {},
      'bad': () async => expect(find.text('nope'), findsOneWidget),
    });
  });

  scenario('ambiguous text target', (s) async {
    await s.pumpWidget(const _TwiceApp());     // two Text('Same')
    await s.tap('Same');
  });
}
```

1. **An indefinite animation breaks every verb.** `s.tap` on a screen holding a
   `CircularProgressIndicator` throws `pumpAndSettle timed out`. A repeating
   animation always has a frame scheduled, so `pumpAndSettle` spends its
   10-minute *fake* budget — instant in wall clock — and throws
   (`widget_tester.dart:717`). A loading spinner is the first thing most apps
   show, which makes this the feature's largest adoption blocker.
2. **`split` replays the body; `setUp` does not re-run.** Both branches printed
   `setUpRuns=2` — one increment per scenario, none per replay. The widget tree
   is rebuilt from nothing between paths, but a seeded repository, a mock, or a
   counter built in `setUp` is *shared*. Cross-branch contamination, silent.
3. **A branch failure never names its branch.** The report reads
   `The test description was: failure inside a branch`. Which of the paths
   failed is nowhere in the message — and the panel's own step record carries
   no branch on the failure either.
4. **Ambiguity falls through raw.** `s.tap('Same')` produces flutter_test's
   twenty-line `RichText(...)` dump. Accurate, and no hint that the fix is a
   `Key`, a scope, or `.first`.

## Gaps

**Verbs.** Four cover the demo. A real app needs `scroll` /
`scrollUntilVisible`, `drag`, `longPress`, `back` (the Android pop), and a
`wait(Duration)` that advances the fake clock — a splash screen that navigates
after a timer cannot be walked today, because `pumpAndSettle` returns
immediately when a pending timer schedules no frames. Every one of these means
dropping to `s.tester`, and the failure mode of dropping to `s.tester` is that
**the flow silently goes blank** — no capture, no warning.

**Finders.** No tooltip, no semantics label — the only handle on an unlabelled
`IconButton` — no scoping (`within(card, 'Buy')`), no ordinal. `dynamic` was
the right call; the vocabulary behind it is too thin.

**No capture on failure.** The `run` action advertises "the frame captured just
before it", and that is literally what arrives: the previous step. Under
`Shots.manual` there may be nothing at all. The frame worth looking at is the
one where it broke.

**No per-scenario axes, no matrix.** Axes are global to an invocation. "Every
scenario in en + fr on two devices" is four CLI calls with four output
directories; "this scenario is phone-only" is inexpressible. Store-screenshot
generation — the obvious commercial use — has no shape.

**`Shot.tags` is write-only.** Tags reach the step JSON and stop: no `--tag`
filter on `run`, nothing in the panel. They are the missing half of the matrix
story.

**`scenario()` lacks `skip` / `tags` / `timeout`**, which `testWidgets` has — a
dent in a surface that promises to be a superset.

**`list` and `run` disagree on vocabulary.** `list` scans for `scenario(`
calls; the harness's `run` walks *every* declared test, so a plain
`testWidgets` in `test/scenarios/` runs but never appears in the panel.

**`setUpAll` / `tearDownAll` never execute** — already recorded in the shipped
design's Known gaps, with a ~15-line fix.

**Determinism.** FakeAsync freezes timers, not `DateTime.now()`. Any screen
showing a date or a clock differs run to run, which quietly blocks the
baseline-diffing roadmap item before it starts.

**Docs are a publish blocker.** `README.md` and `doc/app_tests.md` still
document the removed `AppTest` API. Separately, the legacy `test_runner`
trees — ~9.5k lines across `lib/src/test_runner/` and
`app/lib/src/test_runner/` — are now dead: the rewrite they were waiting for
has landed, and nothing outside them imports them.

## Decision: one settle policy, every verb

Asked directly, and the answer is yes — **`pumpWidget`, `tap`, `enterText` and
`screen` all take the same policy, with the same default.** Three reasons, in
order of weight:

1. Per-verb divergence is exactly the knowledge a high-level API exists to
   remove. Today `tap` settles and `pumpWidget` pumps twice; nothing tells the
   reader, and the difference is visible only as a screenshot caught
   mid-animation.
2. `enterText` needs it as much as `tap` does — a field with an `onChanged`
   that filters a list, shows a validation error, or opens a suggestions
   overlay is not done at the end of the keystroke.
3. It is what makes finding 1 fixable *once* instead of three times.

The policy, replacing the bare `pumpAndSettle` call:

```dart
sealed class Settle {
  /// Pump until no frame is scheduled or [budget] of fake time is spent,
  /// whichever comes first. Giving up is silent to the flow and recorded on
  /// the step.
  const factory Settle.upTo(Duration budget) = _SettleBudget;

  /// Exactly [count] frames.
  const factory Settle.frames(int count) = _SettleFrames;

  /// One frame.
  static const none = Settle.frames(1);

  /// `pumpAndSettle`'s own semantics, throw included — for a scenario that
  /// wants a never-settling screen to be an error.
  static const full = _SettleFull();
}
```

- Default: `Settle.upTo(Duration(seconds: 5))` — 50 pumps of fake clock,
  instantaneous in wall clock, and far short of the SDK's 10-minute throw.
- Set per scenario (`scenario('…', settle: …)`) and overridden per call
  (`s.tap(target, settle: Settle.none)`).
- Implemented as our own loop, **not** `pumpAndSettle(timeout:)`: the SDK
  throws when the budget runs out, and we want to carry on and capture. `~15
  lines: pump while hasScheduledFrame && spent < budget`.
- When the budget runs out the step records `settled: false`, the panel shows
  it, and the run result carries it — a screen that never settles is worth
  seeing, just not worth failing on.

A screen with a permanent spinner pays the full budget on every verb (~50
frames, order 50ms). If that proves to matter, the scenario can remember it
failed to settle once and shrink the budget for later verbs — an optimisation,
not part of the first slice.

## Plan

**Phase A — make the four verbs survive a real app.** The agreed first slice.

1. The settle policy above, on all four verbs, with `settled: false` plumbed
   through `ScenarioStepCapture` → step JSON → `ScenarioRunStep` → panel.
2. Capture on failure: each verb catches, captures a step flagged `failed`
   carrying the error text, and rethrows. Makes the `run` action's existing
   promise true.
3. Branch context on failure: the error is prefixed with the split path
   (`a cappuccino › large cup`) and the path lands on the step record.
4. A scenario-level ambiguity error: *"3 widgets match 'Add' — pass a `Key`, or
   `s.tap(find.text('Add').first)"*, with the visible texts attached.

### Phase A, as built

All four items landed, with the settle policy in `lib/src/scenarios/settle.dart`
and everything else in `scenario.dart`. `settled` and `failure` ride
`ScenarioStepCapture` → the harness's step JSON → `ScenarioRunStep` → the
panel, where a failed step wears the error tone and its message sits above the
picture (`app/lib/src/scenarios/step_status.dart`). Both fields are written
only when the news is bad, so a healthy step's record is the size it was.

Two deliberate divergences from the proposal above:

1. **The branch annotation happens in `split`, not at the top.** Wrapping where
   the branch actually is means the trail is exact, nested splits annotate
   innermost-first, and — the reason it matters in practice — a scenario can
   assert on its own branch failures without failing itself, which is how the
   behaviour is tested at all. `Error.throwWithStackTrace` carries the original
   stack, so the report still points at the user's line.
2. **The failing verb captures its own frame, with the scenario-level catch as
   a backstop.** The proposal had one catch; one catch cannot see a failure the
   test itself intercepts. Both go through a guard that compares the *unwrapped*
   error, so an error travelling up through `split` yields exactly one failed
   step.

`Settle.full` is untested on purpose: `pumpAndSettle`'s throw escapes its own
`TestAsyncUtils.guard` after the body returns and fails the test whatever the
body does with it. That is the SDK behaviour every other policy exists to
avoid, and the note is in `test/scenarios/settle_test.dart` where the next
reader will look for it.

Verified: 16 new tests in the root package (`test/scenarios/`), the app suite
including a fresh end-to-end case that runs a spinner scenario and a failing
one through a real `flutter_tester` and reads both fields off the wire,
`flutter analyze` clean, `tool/prepare_submit.dart` no diff.

**Phase B — the missing verbs and finders.** `scroll`, `scrollUntilVisible`,
`drag`, `longPress`, `back`, `wait`; tooltip / semantics-label / `within` /
ordinal targets. Plus a diagnostic when a scenario reaches for `s.tester` to do
something a verb covers, so the flow never goes blank by accident.

### Phase B, as built

The verbs: `longPress`, `drag`, `scrollTo`, `back`, `wait`. All of them take
the same `Shot`/`Settle` arguments the first four do, so nothing about them is
a second dialect.

- **`scrollTo`** is the one with judgement in it. The scrollable defaults to
  the first on screen, as `flutter_test` itself defaults, and `within:` names
  another — a widget that *is* a `Scrollable` or contains one. A target
  already on screen is a no-op whether or not anything scrolls — a consumer
  walking pages of varying length found the earlier unconditional refusal made
  every walking scenario carry a guard, since which pages scroll depends on
  the device. Its failures say what to do: nothing on screen scrolls (target
  absent or laid out off screen), or *scrolled 50 times by 200 without
  reaching "Item 500" — wrong direction, wrong scrollable, or not in this
  list at all*. It is the one verb whose target legitimately matches nothing
  at the start, so it skips the exactly-one check the others make.
- **`back`** sends `popRoute` down `flutter/navigation` rather than calling
  the binding's `handlePopRoute`, which is `@protected @visibleForTesting` and
  analyzes as a violation from here. The message is the sanctioned route and
  it runs the app's `PopScope`s on the way in, which the direct call also
  would — the difference is that this one is public API.
- **`wait`** exists because settling waits out *animations*: a pending timer
  schedules no frames, so a splash screen that navigates after three seconds
  is unreachable by any settle policy. Instant regardless — the clock is fake.

The targets are a small sealed `Target` vocabulary in
`lib/src/scenarios/target.dart`: `label` (semantics), `tooltip`, `containing`,
`within(scope, child)`, `nth(target, index)`. They compose, and each one's
`toString` is the source that would have written it — so the ambiguity error
from Phase A now reads *2 widgets match Target.containing("Buy")* instead of
`Instance of '_Containing'`. `Target.label` turns the semantics tree on for
the rest of the scenario, lazily: `find.bySemanticsLabel` throws where
semantics are off, and this binding has them on today, so the handle is a
guarantee rather than a fix.

**The `s.tester` diagnostic became a step field**, `strayFrames`. A persistent
frame callback — registered once per binding, since they cannot be
unregistered — counts frames drawn; a verb reports how many happened since the
previous verb finished. Non-zero means the raw tester made the app do
something the flow has no picture of, and the panel says so on the step.

The measurement that shaped it: the test binding's `pump` **skips the frame
entirely when nothing is scheduled**, so an idle `s.tester.pump()` is not a
gap and does not read as one. The signal only fires when the app actually
drew — which is the signal worth having, and better than the one proposed.

Verified: 12 new tests in `test/scenarios/verbs_test.dart`, the panel notice
covered, and an end-to-end case that scrolls a 40-row list, taps a scoped icon
inside the row it reached, and waits out a timer through a real
`flutter_tester`. 299 root tests, 1452 app tests, the example suite, analyze
clean, formatter no diff.

**Phase C — make replay honest.** A per-replay reset hook
(`scenario('…', reset: () {…})`, run before every path) and the documented rule
that `setUp` is per-scenario, not per-branch. Land the specced `setUpAll` /
`tearDownAll` fix in the same pass, and add `skip` / `tags` / `timeout` to
`scenario()`.

### Phase C, as built — and the `setUp` question, settled

**The per-branch `setUp` was investigated and rejected, on three grounds.**

1. *The closures are not reachable.* `setUp` callbacks live in
   `Declarer._setUps`, private, run once by the private `_runSetUps()` inside
   the test body (`test_api/src/backend/declarer.dart:249`). The body's zone
   exposes the `Declarer`, but its public surface — `test`, `group`, `setUp`,
   `build` — has no way to re-run what is registered.
2. *The one route that exists is a trap.* We could `hide setUp` and export our
   own, recording callbacks to replay. That breaks the 1:1 re-export the design
   is explicit about, and makes `setUp` mean one thing in a file that imports
   flutterware and another in a file that imports `flutter_test`.
3. *`tearDown` could not follow.* Tear-downs are registered with
   `Invoker.addTearDown` and run when the **test** ends. Per-branch `setUp`
   with per-test `tearDown` is an asymmetry worse than the trap it fixes.

And the simplification was already there: **the body is what re-runs**, so
anything written in it is per-path for free. `setUp` is the one place it is
not, and that is `package:test`'s own rule — a `setUp` firing three times for
one test would be a surprise nothing in the file could explain. So the
proposed `reset:` hook was **dropped**: `scenario('x', reset: () => repo.seed())`
is the same keystrokes as `repo.seed()` on the body's first line, for one more
concept. What landed instead is the rule, documented on `split`, where the
surprise is.

**`setUpAll`/`tearDownAll` now run**, mirroring `test_core`'s `_runGroup`.
Two adaptations, both measured rather than assumed:

- *The filter is consulted first.* `test_core` never needs to — it filters by
  rebuilding the group tree, so an empty group never reaches the engine. We
  filter as we walk and the panel runs one scenario at a time, so without the
  pre-check, running one scenario would start every other file's fixtures.
- *The hooks get a zone of their own.* `test_api` builds both as **unguarded**
  tests (`guarded: false`), on the understanding that the runner supplies the
  error zone. Ours is `runHarness`'s outermost guard, which logs and swallows —
  and the LiveTest stays green, so the group would have run against a fixture
  that never got built. Found by the end-to-end test: a `setUpAll` that threw
  left its scenario *passing* until the hook ran inside its own zone.

Scope is one run request: each `run` declares afresh, so a fixture is built
per request and torn down after it — asserted end-to-end, where a second
request sees the guest's counter at 2.

A failing `setUpAll` is reported against **each scenario that would have run**,
not once against the group, so a caller who asked for one scenario finds that
scenario in the answer, failed and saying why. A failing `tearDownAll` gets an
outcome of its own: it belongs to nobody's scenario, and marking a scenario
that passed as failed would be a lie.

`skip` / `tags` / `timeout` pass straight through to `testWidgets`, closing the
last superset dent.

**Phase D — matrix and tags.** Designed with the owner 2026-07-31, against
dev_studio's answer rather than from scratch, and built the same day. See
"Phase D, as designed" below, then the six "as built" notes after it.

### Phase D, as designed

The starting question — "how does a user run a matrix of language × device
easily" — was answered by re-reading dev_studio, which the owner still uses.
What it does:

- The matrix is declared **once**, centrally:
  `TestRunner(scenarios, languages:, devices:, desktopDevices:)`. Nothing is
  repeated per test.
- A scenario carries **one flag**, not a list: `bool get isDesktop => false`,
  and `devicesForScenario(s) => (s.isDesktop ? desktopDevices : null) ?? devices`.
- That one flag drives three things: which pool CI iterates, which pool the
  toolbar *offers*, and — the detail that makes it livable — the toolbar keeps
  **two remembered selections**, `_mobileDevice` and `_desktopDevice`, so
  opening a desktop scenario never clobbers the phone you were on.
- There were **three entry points**: `runTests()` (the cross product, one
  `test()` per language × scenario × device), `runForDocumentation()`
  (screenshots, filtered to marked shots, at real pixel ratios), and the
  interactive toolbar.

**The model, generalised: profiles.** A profile names a pool and the languages
that go with it. Two rules settle everything the owner raised:

1. **The list is the *offered* set, and its head is the default.** The GUI shows
   all of it, a bare run takes the first — one list, no separate
   `defaultDevice:` field, and "GUI shows every phone, CI runs two" stops being
   a contradiction.
2. **CI brings its own list.** The profile never declares the CI matrix, so the
   two never fight.

A scenario picks its profile by **folder** (zero syntax, matches how projects
already organise) with a **tag** as the per-scenario override — `tags:` already
reaches `testWidgets` as of Phase C, so `Test.metadata.tags` is readable by the
harness and by the syntactic scanner.

**Spiked, not assumed** (2026-07-31): `flutter_test_config.dart` is discovered
by walking **up from each test file's own directory**, first hit wins, stopping
at the pubspec (`flutter_tools/src/test/test_config.dart:17`) — so per-folder
configuration is a native `flutter test` feature. And a loop in `testExecutable`
that calls `testMain()` once per assignment declares one real test per
combination: a 2×2 spike produced `Counter [iphone-se · en]` … `[pixel-7 · fr]`
from a single `flutter test` invocation. That is dev_studio's shape with no
generated files and nothing written per test.

Also spiked and **ruled out**: deriving the folder from a single root config.
`Platform.script` inside a test is a synthetic `main.dart`, not the test file,
so the hook has to live in the folder it describes.

**Decision — CI supplies axes by dart-define *and* environment, define first.**
`scenario.dart` already reads `screenshots-destination` then
`SCREENSHOTS_DESTINATION` for exactly this class of problem (the host telling
the test process something), and a second convention in the same file would be
a wart. Each has a real strength: a define is visible in the command and
reproducible by paste, an env var is what a CI job's `env:` block sets. The
recompile objection does not apply — the loop lives in the config file, so the
defines carry the *list* and one invocation compiles once.

**Decision — store screenshots are a separate action, not a profile.** A
profile partitions scenarios by suitability and is attached to a folder; store
shots come from the same mobile scenarios, selected by tag, so a `store`
profile would overlap `mobile` and profiles would stop partitioning — which
breaks the picker, the default device and the folder mapping at once. The
defaults differ too (native pixel ratio, tag filter, ordered fastlane-shaped
names, its own output tree): five flags on `run` that nobody uses 95% of the
time. And it is the ancestor's shape, proven in the owner's projects. So:
`fw run scenarios shots`, with its own MCP shape and doc entry.

**Landed 2026-07-31: the device table moved into the package.** Everything
above names devices from three places the GUI cannot reach — a project's
`tool/flutterware.dart`, a folder's `flutter_test_config.dart`, and CI — so the
table is now `lib/src/devices.dart`, exported by both `plugins.dart` and
`flutter_test.dart`. `Devices.iphone16` rather than a magic string, and
`Device(...)` for a screen the table does not have; a class of static consts
rather than an `enum`, because an enum cannot be extended and someone will want
a kiosk. The app keeps the *policy* (`defaultDeviceFor`, `resolveDevice`) and
re-exports the data, so its dozen importers were unchanged apart from
`CatalogDevice` → `Device`.

The refresh is **additive**, for a reason found while doing it: five ids map to
`device_frame`'s **hand-drawn bodies** and `frames_test.dart` pins those
measurements to ours, while the vendored artwork stops at the iPhone 13. So
current sizes (iPhone 16, 16 Pro Max, iPad Pro 13", a tall Android) join on the
generic silhouette, and nothing with a real body was removed or altered.
Noted for the measurement pass: `device_frame` records the 13 mini at
pixelRatio 2, where the device renders at 3 and downsamples — correcting it
means moving the frame and the table together.

**Landed 2026-07-31: the profile lane.** `ScenarioProfile` and `runScenarios`
(`lib/src/scenarios/profile.dart`), exported from `flutter_test.dart`. A folder
says what it is for in three lines, and `flutter test` needs nothing else:

```dart
// test/scenarios/mobile/flutter_test_config.dart
const phones = ScenarioProfile(
  'phones',
  devices: [Devices.iphone16, Devices.iphoneSe],
  languages: ['fr', 'en'],
);

Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, profile: phones);
```

- `flutter test` → one pass at the head of each list, names undecorated.
- `--dart-define=fw.devices=iphone-se,android-tall --dart-define=fw.languages=en,ja`
  → four tests, `[iPhone SE · en]` … `[Tall phone · ja]`, one invocation, one
  compile. `FW_DEVICES` / `FW_LANGUAGES` do the same; both verified by running
  them.
- The assignment is captured **at declaration**, not read when the body runs —
  which it has to be, since `testExecutable` has long returned by then. It is
  also on `s.assignment`, so a body can adapt an expectation to the screen it
  is on, and the fixture that proves all this is correct in both lanes because
  it reads its own assignment rather than pinning one.
- A run's own axes still win: `scenarioRunArgs ?? ambient`, so the runner
  answering a request is never second-guessed by a config file.
- The standalone capture path grew the axis above the scenario
  (`<dest>/<iphone-16-fr>/<scenario>/…`), because a matrix writing every
  combination into one destination would otherwise leave only the last
  language on disk.

**Landed 2026-07-31: the runner reads the same config, by running it.**

The plan had the scanner *parse* `flutter_test_config.dart` for its profile.
Building the lane made that the wrong route: parsing resolves a literal or a
const in the same file, but a project sharing profiles across folders
(`import '../profiles.dart'`) would need the scan to follow imports — exactly
the resolution work the discovery posture exists to avoid.

So the generated entrypoint imports each folder's config and hands it to
`runHarness(configs: {...})`, keyed by the folder it governs — found by the
same walk `flutter test` does (`findTestConfigs`, mirroring
`flutter_tools/src/test/test_config.dart`). The harness then **runs** it:
`scenarioProbing` makes `runScenarios` record its profile and decline to
declare, and `list` reports each scenario's profile, devices and languages.
Executed, never parsed, so an imported profile reads as well as an inline one.

Two things that shaped it:

- **Declaration must stay synchronous.** `test_api` builds the group the moment
  the declaring closure returns, so a config that awaits anything before
  calling `testMain` would declare into a group already built. Asking first and
  declaring after is what keeps the existing path intact.
- **A folder's config now applies under the runner at all**, which it never did
  — the same class of divergence as the `setUpAll` gap, found in the same
  place: whatever setup a folder wraps around `testMain` was silently skipped
  by everything except `flutter test`.

**Landed 2026-07-31: an unspecified device travels unresolved.**

The profile's head could not reach the runner, because `resolveScenarioDevice`
collapsed "nobody chose" into the literal id `iphone-13` at the two places a
request is read. By the time the run started, an unspecified device and an
explicitly chosen iPhone 13 were the same value, so nothing downstream could
substitute the folder's answer.

`ScenarioAxes.device` now has the three states `?device=` actually has —
**null** (unspecified), `fit` (the bare test surface, asked for), and an id —
which is what its own doc comment always claimed it carried. The resolution
moved to the one place that can do it: **the harness**, where the folder
profiles already live.

- The host sends `deviceUnspecified` plus a fallback geometry, and the harness
  overrides it per **file** with `_profileFor(file, profiles)`. One run over a
  mixed suite therefore frames the mobile folder as a phone and the desktop
  folder as a window, without the caller knowing either folder exists —
  verified end to end (a profiled folder answers `iphone-se` while a file
  outside it takes the host's `iphone-13`, in the same run).
- The fallback is a **parameter**, `harnessArgs(unspecifiedDevice:)` /
  `ScenarioRunner.run(unspecifiedDevice:)`, not a constant baked into the axes.
  The plugin holds that policy; a caller with none — the runner's own tests —
  passes nothing and gets the bare surface, which keeps "a run with no axes is
  byte-identical to a bare `flutter test`" true at the runner's boundary.
- The run **says what it ran as**: `device` on each outcome, and on every
  streamed step event, so the panel frames its first picture correctly instead
  of snapping into a phone when the run ends. Step addresses record the
  resolved id, so an artifact's link reopens the same picture.
- That answer is kept **beside** the asked axes (`ScenarioPanelRun.device`),
  not merged into them. Merging made the page see its own answer as a new
  assignment and re-run forever — caught by `panel_test.dart` on the first try.
- The device chip now lights up only when *you* picked something, and reads
  `iPhone SE (default)` when the folder picked it. Before a run there is no
  honest answer, and it says `Default`.

**Wired in the example, 2026-07-31.** `examples/example/test/scenarios/` now
has `mobile/` and `desktop/`, each with a three-line
`flutter_test_config.dart` naming a profile from a shared `profiles.dart`, plus
`counter_test.dart` left ungoverned at the root. One run over all three,
against the real runner:

```
LIST test/scenarios/counter_test.dart              profile=null
LIST test/scenarios/desktop/shop_window_test.dart  profile=desktop  devices=[macbook-pro, windows-laptop]  languages=[en]
LIST test/scenarios/mobile/shop_test.dart          profile=phones   devices=[iphone-16, iphone-se, android-tall]  languages=[en, fr]
RAN  test/scenarios/counter_test.dart              device=iphone-13   (the host's fallback)
RAN  test/scenarios/desktop/shop_window_test.dart  device=macbook-pro (the folder's head)
RAN  test/scenarios/mobile/shop_test.dart          device=iphone-16   (the folder's head)
```

`flutter test test/scenarios` runs all six at their folders' heads, and
`flutter test test/scenarios/mobile --dart-define=fw.devices=iphone-se,android-tall
--dart-define=fw.languages=en,fr` produces the 2×2×2 = 8 named tests. Note the
CI lists apply to **every** folder in the invocation, so a suite with two
matrices is two invocations — one per folder, which is what the folder split is
for.

Found while regenerating for this change: Phase A's `settled`, `strayFrames`
and `failure` were on `ScenarioRunStep` but never in `scenarios_results.g.dart`
or the capability shapes, so agents reading a run over MCP never saw them.
Regenerated.

**Landed 2026-07-31: the device is remembered per pool, not per session.**

The sticky `?device=` was one value across the whole plugin, so picking an
iPhone on a phone scenario and then opening a desktop one rendered a laptop
layout at 390 points — overflow stripes, not a picture. (The reverse is
harmless, which is why a phone pool makes a good default.) dev_studio's answer
was two remembered selections, `_mobileDevice` / `_desktopDevice`.

Generalised, and cheaper than the obvious route: the memory needs a stable
**identity per pool**, not the profile's name — and the governing folder is
exactly that, readable off the filesystem by the same walk `flutter test` does
(`testConfigFolderFor`). So no `list()`, no compile, nothing async, and no
first-run flash where the leftover device gets applied once before the profile
arrives.

- Crossing into another pool parks the current device under the pool being
  left and restores whatever the pool being entered last used — or nothing,
  which lets that folder's profile answer.
- The **first** pool observed adopts the address as it stands, so a pasted
  `?device=` link still opens on the device it names.
- Every pick is honoured, everywhere. Nothing overrides a chosen device — the
  alternative (the harness rejecting a device outside the folder's pool) would
  have been simpler still, but it would also have removed "show me this phone
  screen at desktop width", which is a legitimate thing to ask for.

**Landed 2026-07-31: the runner-side matrix, tags, and the store lane — D is
complete.**

*The matrix.* `run` takes `devices=` / `languages=`, the same plural
vocabulary as `--dart-define=fw.devices=`, so a project learns one and gets
both lanes. Each point writes into `<output>/<device>-<language>/` — the same
slug the standalone capture path already used — with an `index.json` beside
them mapping assignment to directory, pass/fail and counts, in **relative**
paths so the tree can be moved or uploaded as it stands. The per-entry
assignment moved onto `ScenarioRunPackage.axes`, because a matrix has no single
answer to "what did this run as"; `ScenarioRunResult.axes` stays for the
single-assignment case. A run that names at most one of each is untouched: flat
output, no index.

*Tags.* `Shot.tags` was write-only; the missing half was that **scenario** tags
were unreadable too. `run --tag` and `shots --tag` now filter, and the two are
deliberately different questions: `run --tag` selects *scenarios* by
`test_api`'s own tag — the same one `flutter test --tags` filters on, so a
suite tagged for one runner is tagged for both — while `shots --tag` selects
*captures* by the tag on the `Shot`. The live listing reports both a
scenario's tags and its profile; the syntactic scan can report neither, since
it never evaluates an argument.

*The store lane.* `fw run scenarios shots` keeps only **named** shots, at the
device's own pixel ratio, into `<output>/<language>/<device>/NN-name.png`. Two
decisions worth recording:

- Native resolution is a **guest-side** flag (`captureNative`), not a
  host-computed `captureScale`. The device may have come from the scenario's
  folder profile, which the host never saw — only the guest, at capture time,
  knows the ratio it is actually rendering at.
- The run goes to a scratch directory *under* the output and is deleted
  afterwards, and the output is emptied first. A store tree is a statement
  about the app as it is now; yesterday's screenshot of a screen that no
  longer exists must not ship beside today's.

Measured on the example, with no `devices` at all — the folders answer, and one
invocation produces three trees:

```
SET en/iphone-16    13 images   (the mobile folder's profile head)
SET en/macbook-pro   4 images   (the desktop folder's)
SET en/iphone-13     2 images   (counter_test, ungoverned → the fallback)
… and the same three again under fr/
```

*The picker.* The panel now asks the live harness for a listing when a
scenario is opened — the one caller already paying for a compiled harness,
since opening a scenario runs it — and puts the folder's own pool at the top
of the device menu under "This folder", with the whole table still below it. A
profile is an offer, not a fence. The language menu comes from the profile
where one speaks, and falls back to `tool/flutterware.dart`, which resolves the
second-source-of-truth wart the pool memory left behind.

Known and left alone: two scenarios in one folder that name the same shot
produce `04-order-placed.png` and `08-order-placed.png` — distinguished by
number, not by scenario. Tagging is the intended narrowing, and putting the
scenario in the filename would make store-ready names unusable.

**Phase E — hygiene.** `doc/app_tests.md` → `doc/scenarios.md` and the README
fixed before the next publish; the legacy `test_runner` trees deleted;
`list` and `run` reconciled on `testWidgets`; a fixed-clock knob as groundwork
for baseline diffing.

### Phase E, as built

**The legacy trees are gone — 82 files, 9,750 lines.** `lib/src/test_runner/`,
`app/lib/src/test_runner/`, their three re-export shims (`lib/src/web.dart`,
`lib/src/test_runner.dart`, `lib/src/test_runner_daemon.dart`), the standalone
web entry point and `app/examples/test_runner/`. The cluster was
self-contained apart from four threads, each cut: `Project.tests` (the last
field pointing into it — `Project` itself survives for `src/icon/` and
`src/overview/`), two references in the pre-shell `project_view.dart`, the
`paths.tests` route, and one link on the legacy overview screen. `json_rpc_2`
left with it; every other dependency is still used elsewhere.

**Docs.** `doc/scenarios.md` written from the shipped surface — verbs, targets,
settling, shots, `split`, profiles, the matrix, the actions, the store lane,
standalone captures. `doc/app_tests.md` deleted with the API it documented, and
the README gained a **Scenarios** section under Tools (the flagship feature had
none) plus a corrected Libraries row. Two screenshots of removed UI
(`screen_sizes.png`, `test_visualizer.png`) went too. Every other tool section
in the README carries a screenshot; scenarios has none yet, which needs a
running GUI to produce.

Also corrected while writing it: the `run` action still advertised "the frame
captured just before it", which Phase A made false — it captures **at** the
failure.

**`list` and `run` now agree.** A plain `testWidgets` in a scenario folder was
invisible to the scan and executed by the runner anyway. Neither reading of the
*source* can settle this — the scan cannot evaluate a non-literal name — so
`scenario()` announces itself as it declares: the harness sets a sink per file
while declaring it, and both `list` and `run` are restricted to what came
through that door. True by construction.

**The clock knob, measured first.** A probe under `flutter test` showed the
actual situation, which the gap list had wrong:

```
DATETIME 2026-07-31 17:05:07.812   CLOCK 2026-07-31 17:05:07.736
after s.wait(1 day):
DATETIME 2026-07-31 17:05:07.929   CLOCK 2026-08-01 17:05:07.936
```

`package:clock` is **already** fake inside a scenario — `FakeAsync` installs
it, so `s.wait` moves it — it merely *starts* at the wall time of the run. So
the knob is an **origin**, not a freeze: `--clock=2026-01-01T09:00:00Z` on
`run`, `ScenarioRunArgs.clockOrigin` through the seam, and `fw.clock` /
`FW_CLOCK` for the bare `flutter test` lane (the same define-then-environment
pair as `screenshots-destination`). Implemented by wrapping the scenario body
in a `Clock` offset from where FakeAsync started, so a flow that waits a day
still reads a day later — from a date identical on every run.

What it cannot do, stated in the parameter's own description: a direct
`DateTime.now()` is not interceptable by anything, in any test.

A and E are independent of everything else. A is where the value is: findings 1
and 3 are the difference between "it works on my app" and "it throws on the
login spinner".

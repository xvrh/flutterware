# S4 — `flutter_tester` as our guest: findings

**Date:** 2026-07-30
**Status:** Spike complete. **Succeeded**, with limits recorded below.
**Brief:** `2026-07-30-scenarios-design.md` § "Spike S4".
**Code:** `app/tool/scenarios/spike_scene.dart` (guest),
`app/tool/scenarios/run_spike.dart` (host).

## Verdict

The SDK's `flutter_tester` binary, spawned **directly** by our own host with a
kernel from our own resident `frontend_server`, runs a FakeAsync scenario
under `AutomatedTestWidgetsFlutterBinding`, captures real-font PNGs + text
projections per step, hot-reloads through `reloadSources`, and re-runs with
clean state — no `flutter run`, no `flutter test`, no fork, no C work.

Every success criterion from the brief passed, and the loop is *faster* than
S1's embedder numbers.

```
[spike] cold compile 365ms
[spike] guest ready in 134ms (spawn → fonts loaded → extension registered)
[run-0] step 0 "initial"        texts=[Taps: 0, Bold Roboto 700, こんにちは世界 …]
[run-0] step 2 "after enterText"
[run-0] completed — scenario 445ms
[hot] incremental compile 8ms · reload 50ms
[run-1-hot] completed — scenario 123ms
[hot] state reset between runs: yes (initial texts: [Count: 0, …])
```

(Cold compile is 2.4s on a cold filesystem cache, ~365ms warm. No
`--initialize-from-dill` was used; the daemon's warm-dill machinery would cut
the cold case further.)

Reproduce:

```bash
/Users/xavier/fvm/versions/3.47.0-0.1.pre/bin/dart run app/tool/scenarios/run_spike.dart --hot
```

## The fonts finding — the past pain has a name

The historic "incredibly frustrating font problem" is not an inherent
`flutter_tester` limitation. It is two flags `flutter_tools` **always passes**
(`packages/flutter_tools/lib/src/test/flutter_tester_device.dart:119-120`):

```
'--use-test-fonts',      // forces Ahem as the default font
'--disable-asset-fonts', // blocks the OS font manager entirely
```

Owning the spawn means simply not passing them. With that, plus loading
`FontManifest.json` at harness startup (the golden_toolkit dance, done once by
the harness instead of by every user), the captured PNGs show — verified by
eye:

- the project's own **Roboto**, regular *and* bold 700 (from
  `examples/example`'s bundle);
- **MaterialIcons** glyphs (favorite, add_a_photo, wifi);
- **CJK fallback** — こんにちは世界 in a real system font, no tofu;
- **color emoji** — 🎉 🚀 ❤️ via Apple Color Emoji;
- Material 3 chrome (AppBar, ElevatedButton) all in real type.

System-font fallback comes from the OS, so a Linux CI run will fall back
differently for CJK/emoji — that is baseline-keying policy, not a rendering
defect.

## What was proven

1. **Direct spawn works, with one flag the brief did not know about.** The
   engine exits 0 when `main` returns unless `--run-forever` is passed —
   a pending `Timer` does not hold it. The full argument list that works is in
   `run_spike.dart`; it is `flutter test`'s list minus the two font flags,
   plus `--run-forever`.
2. **The whole scenario surface is stock `flutter_test`.** The guest declares
   the scenario with real `testWidgets` (driven via `Declarer` + `LiveTest`,
   ~20 lines of `test_api` internals — the 2026-05 port's proven pattern), so
   `tap`, `pump`, `expect`, **and `enterText`** all just work.
   S1's "largest API gap" does not exist on this route: text entry through a
   real `TextField` is in the captured frames.
3. **The reload loop beats S1.** Incremental compile **8ms**, `reloadSources`
   **39-50ms** (S1's embedder: 11ms / 117ms). Both halves of one edit — the
   app's text *and* the scenario's assertion — took effect on re-run.
4. **State reset is inherent, not implemented.** S1 constraint 1 (hot reload
   preserves state; the runner must own app reset) dissolves: each run is a
   fresh `runTest`, and the re-run after reload started at `Count: 0` despite
   the previous run's taps. `flutter test`'s per-test reset semantics come
   with the harness.
5. **FakeAsync instantaneity is real.** A 3-step scenario with taps, text
   entry and three PNG captures: 445ms first run, **123ms warm** — and the
   captures dominate; the driving itself is single-digit ms.
6. **The request/response barrier is a service extension.**
   `ext.spike.run` runs the whole scenario and returns the step list — the
   exact "apply my edit, tell me when it's done" shape the catalog's
   agent-loop rule requires. No watch mode, no races.
7. **Two projections per step, same as the catalog.** PNG via
   `debugLayer.toImage` under `tester.runAsync` (software rendering, the
   flutter-test golden path) + the visible-text list. Tree dump was not wired
   but the same walk that produced texts reaches it.

## Constraints discovered

1. **Reload is `reloadSources` only — never `ext.flutter.reassemble`.**
   Under a test binding outside a test, reassemble awaits a frame that never
   comes; the first hot cycle hung exactly there. It is also unnecessary: the
   re-run builds a fresh tree from the reloaded code. This is the harness's
   reload rule, and it is *simpler* than the catalog's (which needs
   reassemble because its tree stays alive).
2. **`scheduleWarmUpFrame` must be suppressed outside `inTest`** — the same
   one-line binding override the 2026-05 port carried. A reload schedules a
   warm-up frame; outside a test it asserts.
3. **Top-level `final`s freeze across reloads** (not hit here, but the
   catalog's getter-not-final rule applies to whatever the runner's harness
   caches per-run).
4. **The scenario-under-edit must be restored by the driver, not trusted to
   `finally`** — two watchdog kills left the spike scene edited on disk. The
   real runner edits nothing; only the spike does.

## Not proven — honest limits

- **Linux.** `artifacts/engine/linux-x64/flutter_tester` ships with the SDK on
  Linux hosts, and nothing in the approach is macOS-specific, but no Linux run
  happened. First-class CI support should verify it early in M4 proper.
- **Multiple scenarios / files in one guest**, and listing them — the spike
  hardcodes one `testWidgets`.
- **The `flutter test` CI path** for the same file — layer-0 compat is by
  construction (it *is* `testWidgets`), but no plain `flutter test` run was
  exercised against the spike scene.
- **Tree dump per step** — texts only; `lib/src/inspect/` not wired.
- **Sharing the catalog's compiler daemon** — the spike ran its own
  `FrontendServer`. The daemon-identity split
  (`daemon_address.dart:25-42`) is still the integration step.
- **PNG capture cost** (~30KB, a few ms each) dominates warm runs; fine at
  this scale, worth watching for 50-step scenarios.

## Consequences for the design

- The substrate decision in `2026-07-30-scenarios-design.md` is **confirmed**:
  option (b) holds, the fallback to `flutter run -d flutter-tester` is not
  needed, and the M4 amendment in the master plan stands on measured ground.
- The design's fidelity section gains a concrete mechanism: harness loads
  `FontManifest.json` + never passes the two font flags. "Real good font
  support" is a startup default, not per-project work.
- Open question 3 of the design ("where the runner's harness `main` lives")
  now has evidence for the generated-entrypoint answer: the harness needs the
  scenario files imported and a `Declarer` fed — exactly the catalog's
  generated-entrypoint shape.

## Files

| Path | Role |
|---|---|
| `app/tool/scenarios/spike_scene.dart` | guest: font loader, `_SpikeBinding`, `ext.spike.run`, the scenario, capture |
| `app/tool/scenarios/run_spike.dart` | host: asset bundle, resident compiler, direct spawn, hot cycle, reset check |

Both lint-clean under the repo's `analysis_options.yaml`.

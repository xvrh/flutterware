# S1 — Running a scenario inside the embedder guest: findings

**Date:** 2026-07-26
**Status:** Spike complete. **Succeeded**, with limits recorded below.
**Brief:** `2026-07-25-overhaul-master-plan.md` § "Spike briefs → S1".
**Code:** `app/tool/embedder/scenario_scene.dart` (guest),
`app/tool/embedder/run_scenario.dart` (host).

## Verdict

A scenario can drive a real Flutter app inside the embedder guest, render real
frames, capture them per step, and **hot-reload both the app and the scenario
into the live guest without restarting anything**.

The spike beat its success criteria. It also invalidated its own premise in a
useful way: the answer is *not* `LiveTestWidgetsFlutterBinding` + `testWidgets`.

```
[scenario] cold compile 352ms
[run-0] step 0 "initial"            texts=[Taps: 0, Tap me, Scenario spike]
[run-0] step 3 "after theme toggle" texts=[Taps: 2, Tap me, Scenario spike]
[run-0] completed in 1753ms
[hot] edited the scenario, recompiling
[hot] incremental compile 11ms · reload 117ms
[run-1-hot] step 0 "initial (reloaded)" texts=[Count: 0, Tap me, Scenario spike]
[run-1-hot] completed in 1725ms
[scenario] OK — 159 guest frames
```

Reproduce:

```bash
/Users/xavier/fvm/versions/3.45.0-0.1.pre/bin/dart run app/tool/embedder/run_scenario.dart --hot
```

## The API shape — no test harness, no fork

The brief assumed `LiveTestWidgetsFlutterBinding`. That was wrong, and the real
answer is much cheaper. In the pinned SDK (3.45.0-0.1.pre):

- `controller.dart:2493` — `LiveWidgetController(super.binding)` is a **public
  constructor taking any `WidgetsBinding`**.
- `controller.dart:1911` — `sendEventToBinding` is just
  `binding.handlePointerEvent(event)`.
- `controller.dart:794` — the `tap` path resolves its view through
  `_maybeViewOf(finder)`, which walks to the `View` widget and returns a real
  `FlutterView`. **No `TestPlatformDispatcher` cast.**

So the guest is a **plain `WidgetsFlutterBinding` + `runApp` +
`LiveWidgetController`**. No test binding, no `package:test`, no `testWidgets`,
no forked Flutter source. The whole flutter_test surface used is:

```dart
import 'package:flutter_test/flutter_test.dart' show LiveWidgetController, find;
```

The `TestPlatformDispatcher` cast does exist, but only in the `view` /
`platformDispatcher` getters — reachable only if a scenario manipulates view
properties. That is the boundary to document, not a blocker.

### Why this matters for dev_studio (open question 1 — now answered)

dev_studio drives scenarios with `WidgetTester`, whose constructor
(`widget_tester.dart:542 WidgetTester._`) is private and test-harness-bound. To
get around that, dev_studio **vendored a 701-line copy of Flutter's own
`widget_tester.dart`** (Flutter Authors copyright,
`ignore_for_file: implementation_imports`) plus a custom binding.

The coupling is contained and measurable:

| dev_studio | lines | verdict |
|---|---|---|
| `lib/client/src/scenario_runner/runtime/` (8 files touching `WidgetTester`) | ~1,400 | **rewrite** on `LiveWidgetController` |
| `lib/src/` — GUI: flow graph, listing, detail, screens, protocol | ~8,200 | **reusable**, driving-mechanism agnostic |

**Recommendation: fork the design, not the code.** Take dev_studio's GUI,
protocol, and scenario-authoring ergonomics; rewrite the ~1,400-line runtime
against `LiveWidgetController`. That deletes the vendored Flutter fork — a
permanent maintenance tax that breaks on every SDK bump — and it is the smaller
half of the codebase.

## What was proven

1. **`dart:io` works in the guest.** The guest connects a Unix socket back to
   the host with **zero C changes** to `native/ipc.c` — the control-socket path
   is passed via an env var, which `Process.start` inherits. All the scenario
   plumbing is Dart.
2. **Driving works.** `controller.tap(find.text(...))` and
   `controller.tap(find.byIcon(Icons.palette))` both hit-test and dispatch
   correctly, including an AppBar action.
3. **Two projections, both live** (master plan decision 3):
   - *text* — `controller.widgetList<Text>(find.byType(Text))` →
     `[Taps: 2, Tap me, Scenario spike]`. This is literally "what is shown in
     the app" for an agent, and it cost four lines.
   - *pixels* — `renderView.debugLayer! as OffsetLayer` → `.toImage()` → PNG.
     Real 800×600 rasterised frames, verified visually per step.
4. **Real asset bundle.** Icons first rendered as `?` because the guest had only
   `kernel_blob.bin`. `flutter build bundle --asset-dir` produces the full
   bundle (fonts, `FontManifest.json`, `AssetManifest.bin`); the fast
   `frontend_server` kernel is then written over it. ~11s, cached, changes
   rarely. Icons render correctly after.
5. **Hot reload of the live guest.** Resident `FrontendServerClient` →
   `compile([editedUri])` → VM-service `reloadSources` with the incremental dill
   → `ext.flutter.reassemble`. **11ms compile, 117ms reload.** One edit changed
   both the app's UI (`Taps:` → `Count:`) and the scenario's own logic; both
   took effect. The guest, engine, and compiler all stayed warm.
   The spike drove the VM service with raw JSON-RPC over `web_socket_channel`.
   **Superseded 2026-07-27:** both this harness and the catalog now use
   `package:vm_service`, the generated client the Dart team ships. Hand-rolled
   JSON-RPC is fine for one request/response call and stops being fine at
   events — guest stdout, stderr and `Extension` streams arrive as
   server-initiated notifications with no request id, which a
   request/response-only client silently drops.

## Constraints discovered

These are design inputs for M3/M4, not defects.

1. **Hot reload preserves State — a re-run does not start clean.** The first
   hot cycle failed exactly this way: taps went `2 → 3 → 4`. Fix: remount the
   root under a fresh key per run (`runApp(App(key: ValueKey(gen++)))`). A
   scenario runner **must own app-lifecycle reset**; it cannot inherit
   `flutter test`'s "fresh isolate per test" assumption.
2. **`pumpAndSettle` never returns if the app has a repeating animation.**
   `LiveWidgetController.pumpAndSettle` loops while `binding.hasScheduledFrame`.
   The existing `tool/embedder/scene.dart` (a `repeat()`ing controller) would
   hang forever. Authoring guidance + a timeout are mandatory.
3. **`enterText` is not available.** It lives on `WidgetTester`
   (`widget_tester.dart:1158`), not `WidgetController`, and needs
   `TestTextInput` from a test binding. Text entry needs a different route —
   real key events through the C host, or a small re-implementation against the
   live binding. **Unresolved; the largest API gap.**
4. **Capture re-rasterises needlessly.** `layer.toImage()` re-renders a frame
   the guest already composited into a shared `IOSurface`. Grabbing the
   presented surface instead would be cheaper and would guarantee the captured
   image matches what the user saw. Optimisation, not a blocker.
5. **Run time is scenario semantics, not infrastructure.** ~1.75s for 4 steps is
   dominated by `pumpAndSettle`'s 100ms poll and PNG encoding. The
   infrastructure numbers are the 11ms/117ms ones.

## Plugins — investigated, and *not* the same as `flutter_tester`

The requirement is the same as `flutter test`: **fake everything ahead of use,
at the platform-interface layer** (`XxxPlatform.instance = Fake()`). That is
plain Dart, the framework is not involved, no channel call ever happens, and it
needs nothing from the guest. So plugins are not the M3/M4 blocker they looked
like.

The *failure mode* differs, though, and that is the part worth knowing:

| | unfaked plugin call |
|---|---|
| `flutter_tester` | throws `MissingPluginException` immediately |
| embedder guest | **hangs forever** — measured as `TimeoutException after 3004ms`, which was only my own timeout |

A missed fake therefore surfaces as a mysterious scenario timeout rather than a
named exception. For scenario authoring that is a meaningfully worse debugging
experience.

**Cause, established not guessed.** `MissingPluginException` is what Dart throws
when the platform returns a *null* reply. `app/native/host.c` never sets
`args.platform_message_callback`, so nothing ever replies. Registering one was
tried: the callback is **never invoked at all**, not even for the framework's
own startup messages — the host's main thread blocks in `ipc_read()` and never
services the platform task runner. A real fix needs `custom_task_runners` plus a
run loop interleaving socket reads with `FlutterEngineRunTask`. That is genuine
embedder work, so the attempt was reverted; `host.c` is unchanged.

**Also ruled out:** mixing `TestDefaultBinaryMessengerBinding` into the live
binding to get `setMockMethodCallHandler`. The mixin is declared
`on BindingBase, ServicesBinding` so it *compiles*, but it **deadlocks the guest
during binding init** — it never reaches `runApp`. Do not revisit; fake at the
platform interface.

## Not proven — honest limits

- **Display in the GUI.** The scenario ran under the headless host tool. The
  3a/3b texture bridge already shows live guest output in a flutterware window
  and is orthogonal to the scenario driver — but the two were **not wired
  together**. The "watch a scenario run live in the app" claim is inferred, not
  demonstrated.
- **Widget-tree inspection at a step.** The text projection is a flat list of
  `Text` widgets, not a real tree. The VM service is right there, unused.
- **Failure post-mortem.** A failing step reports a Dart exception + stack; it
  does not capture the frame at failure, the tree, or a diff.
- **Non-macOS**, multiple concurrent guests, and scenario **cancellation**.

## Consequences for the master plan

- **Open question 1 is answered** — fork dev_studio's design, rewrite its
  runtime. M4 is a rewrite against `LiveWidgetController`, not a port.
- **M3 and M4 do share one substrate.** The same guest, compiler, asset bundle,
  capture path, and reload loop serve both the UI catalog and the scenario
  runner. The unification in the master plan holds.
- **The "VERY VERY quick" goal has a number: ~130ms** edit-to-reloaded, plus
  whatever the scenario itself takes. That is the budget to defend.
- **Plugins are not a blocker** — fake at the platform interface, as with
  `flutter test`. But the guest needs a **platform task runner** in `host.c`
  before an unfaked call fails fast instead of hanging. Small, well-understood,
  and worth doing before scenario authoring starts in anger.
- Decision 3 (text + image projections) is validated at near-zero cost and
  should stay locked.

## Files

| Path | Role |
|---|---|
| `app/tool/embedder/scenario_scene.dart` | guest: demo app + `LiveWidgetController` driver + command loop |
| `app/tool/embedder/run_scenario.dart` | host: build, spawn, collect steps, `--hot` reload cycle |
| `app/lib/src/embedder/flutter_cache.dart` | added `flutterRoot` getter |

Both spike tools are lint-clean under the repo's `analysis_options.yaml`.

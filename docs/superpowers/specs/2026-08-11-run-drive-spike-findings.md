# Run drive spike — findings

**Date:** 2026-08-11
**Status:** Ran, five iterations, macOS debug. **Verdict: build it.** All four
questions from `2026-08-11-run-drive-design.md` answered; none killed the
design; question 4's answer is bigger than its question was.

**Setup:** `examples/example/tool/drive_spike.dart` — a live `flutter run`
app importing `package:flutter_test`, holding a
`LiveWidgetController(WidgetsBinding.instance)`, serving verbs over one
`ext.spike.call` extension (requests serialized on a queue). Driven by
`app/tool/drive_spike/driver.dart` over the VM service
(`flutter run -d macos --machine`, parse `app.debugPort`, connect). Both
files are throwaway spike code and stay.

The accidental stress test mattered more than the planned one: the app
window spent runs 2 and 4 **hidden** (spawned from a background session), so
every mechanism got measured in both window states. Run 4 executed the entire
suite with `framesEnabled: false` throughout and passed; run 5 repeated it
with the window visible and produced the same numbers.

## Q1 — `flutter_test` in a live app: yes

Compiles and runs under `flutter run -d macos` with `flutter_test` as an
ordinary dev dependency and the entrypoint outside `lib/` (where a generated
run entrypoint lives anyway). `LiveWidgetController` works as advertised:
`tap`, `getCenter`, `scrollUntilVisible` (drag-based, live pumps), finders,
all against the real binding.

One trap, measured: **`hitTestOnBinding` throws on a live binding** — its
default `viewId` comes from `WidgetController.view`, which casts the live
`PlatformDispatcher` to `TestPlatformDispatcher`. The public
`RendererBinding.hitTestInView(result, position, viewId)` is the same hit
test without the test-typed detour. The drive engine's reach check must use
it directly.

Numbers (warm): launch → `app.started` 11.5–13.5s (cold first build 33s),
extension answering 60–105ms after that, one tap dispatch ~30ms, guest-side
screenshot 69–73ms at 1600×1200 (correct pixels, verified by eye — the
`OffsetLayer.toImage` raster works in a live debug app, hidden window
included).

## Q2 — tap-by-Target under animation: zero wrong targets, ever

Stress: eight buttons oscillating vertically ±30px with staggered phases
(neighbours cross and overlap), 700ms period, resolve-at-act-time by
`find.text('Item 7')`.

- **Steady-state motion: 120/120 correct across runs** (30 unchecked + 30
  reach-checked per run), zero wrong, zero missed. Re-resolving the Target at
  act time inside the guest is reliable against continuous motion.
- **During a route transition, a blind tap is a silent miss — by framework
  design.** `ModalRoute` keeps an `IgnorePointer` up while its transition
  animates, so a tap into the entering page does nothing and reports nothing:
  10/10 missed. This is the unforgivable failure mode's cousin (silent
  no-op), and it is not an animation-speed problem — it is a rule.
- **The reach check converts the silence into a diagnosis**: hit-test at the
  target's center, require the target's RenderObject in the path — 10/10
  reported `covered` in the same window.
- **The retry ladder lands it**: reach-check, on `covered`/miss settle ~60ms
  and retry. **10/10 correct, uniformly 6 attempts (~360ms)** — the tap
  lands on the first frame after the transition's IgnorePointer lifts, and
  the oscillation still running underneath changes nothing.

Total across all five runs: **~250 taps, wrong-target count 0.** The one
driver lesson: retrying must *pump* the app between attempts (an `observe`
with a settle), not merely wait — on a hidden window, a plain sleep advances
zero frames and the retry loop starves (measured in run 3: 6/10 gave up;
fixed in run 4: 10/10).

## Q3 — enterText: both mechanisms work; no design change

Tap the field (focus), then push a `TextEditingValue`. Verified end to end —
controller updated, `onChanged` fired, the on-screen `Text` showing the
value rebuilt and read back through the tree:

- **Mechanism A — `EditableTextState.updateEditingValue(...)`** on the
  focused field (found via `find.byType(EditableText)` + `hasFocus`): works.
- **Mechanism B — `TextInput.updateEditingValue(...)`**, the static
  control-side API pushing to the attached connection: works, and needs no
  `TextInputControl` installed. (Installing one — the `GuestTextInput` route —
  *removes* the platform control from `TextInput`'s set, i.e. kills the
  system IME; not needed and not desirable on device.)

Tap-to-focus itself works in every lifecycle state once settle keeps
transitions from wedging (run 2's "focused count 0" was the frozen-transition
IgnorePointer swallowing the focus tap, not a focus policy — see Q4).

**Open on device, deliberately:** with either mechanism the *platform's* IME
may hold a diverging editing state (we never tell it). Harmless on desktop;
on a phone with the soft keyboard up, unverified. Check when a physical
device run lands; composition (dead keys, CJK) stays out of scope regardless.

> **Answered the same evening, and it was a bug** — the divergence is real on
> both mobile platforms: the human's next keystroke replaced the agent's text.
> Neither mechanism here is the right one; `userUpdateTextEditingValue` is.
> See `2026-08-11-run-drive-design.md` § Mobile.

## Q4 — settle: works, and found the load-bearing fact of the spike

The planned answer first: bounded wall-clock settle behaves —

| | settled | elapsed | frames |
|---|---|---|---|
| idle home | true | 16–19ms | 0 |
| infinite spinner, 1500ms budget | **false** | ~1505ms | ~180 |
| Navigator push, 3000ms budget | true | **529–532ms** | 61–62 |

Identical numbers whether the frames were natural (visible window) or forced
(hidden window).

The discovery: **a hidden macOS window disables frames, and everything an
agent does breaks downstream of that** unless the settle owns the problem.
When the window is hidden/occluded, `SchedulerBinding.framesEnabled` goes
false and `scheduleFrame` becomes a no-op. Consequences, all measured in
runs 1–2 before the fix:

- Route transitions **wedge mid-flight** (screenshot of a pop frozen
  half-slid), and their `IgnorePointer` stays up — every subsequent tap is
  silently swallowed, which cascaded into every "app stopped responding"
  anomaly in runs 1–2.
- `hasScheduledFrame` reads false while tickers are still waiting, so a
  naive settle reports **settled on a wedged app**.
- Rebuilds never flush: `onChanged` fires but the tree still shows the old
  text — an observation after an act reads **stale state that looks settled**.

The validated algorithm (now in the spike's `_settle`):

1. Pending = `hasScheduledFrame || transientCallbackCount > 0` — the ticker
   count is the honest "something animates" probe when frames are disabled.
2. When `!framesEnabled`, **always force one frame first**
   (`scheduleForcedFrame`) — a dirty element is invisible to both probes, and
   the unconditional flush is what turns "onChanged fired but the tree is
   stale" into a true read (run 4 failure → run 5 pass).
3. Loop: while pending and within budget, force a frame if frames are
   disabled, await `endOfFrame` capped at 250ms per wait.
4. On budget exhaustion return `settled: false` with the counts. Never throw,
   never hang — held across ~180 forced frames per spinner settle.

Run 4 — the entire suite, including the 10/10 retry ladder and both
enterText mechanisms — ran on a window that was hidden the whole time. **An
agent can drive an app the human isn't looking at**, which the co-driving
workflow does not need but CI and away-from-keyboard sessions will.

Every observation must carry `lifecycleState` (and `framesEnabled`): it is
one line, and it explains otherwise-mystifying behavior shifts to both the
agent and the human reading the journal.

## Q1b — device compile

`flutter build apk --debug -t tool/drive_spike.dart`: **builds** (139.9s
Gradle, `app-debug.apk` produced). `flutter_test` + `LiveWidgetController`
compile for Android; only runtime behavior (input, IME) remains for a
hardware session.

## What this amends in the design doc

1. The transaction's reach check uses `RendererBinding.hitTestInView`, not
   `WidgetController.hitTestOnBinding` (test-typed view getter throws live).
2. The design guessed "settle-before-resolve (slower, but honest)" as the
   fallback if act-time resolution flaked. Wrong shape: resolution never
   flaked — **actionability is what blocks, and the answer is
   retry-until-reachable within the verb's deadline, pumping (settling)
   between attempts.** The verb does this internally; a `covered` /
   `not found` error surfaces only when the deadline runs out.
3. The settle section gains the forced-frame algorithm above; `lifecycle` +
   `framesEnabled` join the observation bundle.
4. `enterText` is no longer an unknown: mechanism B
   (`TextInput.updateEditingValue`, no control installed) is the primary,
   with the on-device IME-divergence check parked as a device-spike item.

## Not answered here

- Real phone (Android/iOS) run — **since answered on an emulator and a
  simulator, `2026-08-11-run-drive-design.md` § Mobile.** Compile check only
  here (above); input + IME
  behavior on device is the remaining spike-shaped item, one afternoon with
  hardware.
- Profile mode (extensions register there; inspector-free operation is the
  design's plan anyway).
- `drag`/`scrollTo` beyond `scrollUntilVisible` (which worked first try).

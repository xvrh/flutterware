# Recording a transition's motion — spike findings

**Date:** 2026-08-11
**Status:** **Built.** The spike answered yes and the playable arrow was
implemented the same day — see "What was built" at the end for what shipped
and the three decisions the build changed. The spike is kept as the measurement
record: `test/scenarios/spike_motion_capture.dart`. Deliberately named
without a `_test` suffix so no glob runs it — it takes half a minute and
asserts almost nothing — and without the `_` prefix `.gitignore` drops, since
a measurement other people should be able to re-run has to be in the repo.
**Question:** can a scenario show the *motion* of a transition — the page
push, the expansion, the ripple — and not only its two endpoints?
**Answer:** yes, and it is a smaller change than it sounds, because the pump
loop is already ours (`lib/src/scenarios/settle.dart`) and the transport is
already file-by-path (`lib/src/scenarios/harness.dart:706`). No new
dependency, no video codec, no ffmpeg.
**Lineage:** a parallel spike in `/Users/xavier/projects/dev_studio` proved
the same mechanism on a different runner the same day. Its conclusions do not
all carry — see "Where this differs from the dev_studio spike".

## The mechanism

`OffsetLayer.toImageSync` works under `AutomatedTestWidgetsFlutterBinding`.
That is the unlock: the pump loop stays inside FakeAsync and takes an image
*handle* per frame, synchronously, and one `runAsync` at the end turns the
handles into bytes. No `runAsync` per frame — which is what makes it cheap.

The recording loop is `Settle.upTo` with a finer step and a sink:

```dart
frames.add(layer.toImageSync(bounds, pixelRatio: scale / dpr));
while (tester.binding.hasScheduledFrame && elapsed < cap) {
  await tester.pump(step);          // 16ms instead of 100ms
  elapsed += step;
  frames.add(layer.toImageSync(bounds, pixelRatio: scale / dpr));
}
```

That is the whole product change, structurally: `Settle.apply` gains a frame
sink and `_Budgeted` gains an `interval`. Every verb pumps through
`Settle.apply`, so every verb can record without any of them knowing.

## Measured

flutterware's own harness, Flutter 3.47.0-0.1.pre, macOS arm64. Full output
in the spike; the numbers that decide things:

| | frames | pump loop | → bytes | PNG on disk | raw in memory |
|---|---|---|---|---|---|
| page push, phone 393×852 @1× | 32 | 73 ms | 8 ms | 0.38 MB | 41 MB |
| page push, phone @3× | 32 | 347 ms | 66 ms | 1.33 MB | 368 MB |
| Hero flight, 800×600 | 31 | — | 9 ms | 0.14 MB | 57 MB |
| whole scenario, 4 verbs | 107 | 567 ms | 47 ms | 0.68 MB | 196 MB |
| indefinite spinner, 5 s budget | **314** | — | 133 ms | 2.06 MB | 575 MB |
| idle screen | **1** | ~0 | ~0 | — | — |

Per-frame, at phone size 1×: **2.3 ms to pump, 0.24 ms to read as rawRgba,
7.4 ms to encode as PNG.**

Three things fall out of that table.

**Pumping is the cost, not capture.** A recorded transition pumps 32 frames
where a `Settle.standard` pumps 7 — 4.5× the pumps at ~2.3 ms each. Reading
the pixels is a rounding error next to it. This inverts the assumption behind
`captureRaw`: for *one* shot per step, PNG encoding is 80% of the cost and raw
is the win (`run_args.dart:143`); for a *sequence*, the batched `toByteData`
costs 0.24 ms/frame and the pumping dominates.

**Frames follow the step's own format, and for the panel that is raw.** The
first draft of this document said "PNG always", on the 100× size difference —
1.28 MB/frame raw against 12 KB encoded. That was wrong, for two reasons the
owner pointed at: the panel already captures its *shots* raw for exactly this
reason (`run_args.dart:143`), and `scenarios_core.dart:386` deletes the
previous run's directory on every run, so the size is transient rather than
cumulative. Measured at the shipped settings, three transitions:

| | per frame | per run | on disk |
|---|---|---|---|
| raw | 0.17 ms | 10 ms | 18 MB, replaced each run |
| png | 2.05 ms | 113 ms | 0.29 MB |

Raw halves the whole recording cost and skips the decode on playback too. So
there is no special case: `captureRaw` decides for the frames as it decides
for the shot.

**1× is the only sane capture scale.** 3× costs 5× the pump time and 368 MB of
live `ui.Image` handles for one transition. The same conclusion the static
capture path already reached, for the same reason.

## Recording does not perturb the result

The test that mattered most, given the comparison work
(`2026-08-11-comparison-design.md`): a run that pumps at 16 ms and a run that
pumps at 100 ms land on **byte-identical settled frames** — 0 of 1,920,000
bytes differ. Recording is diff-safe, because the budget is spent in fake
*time* and not in frame count, so both loops stop at the same instant on the
fake clock.

The caveat is narrow but real: this holds for the frame at a given fake
timestamp. A step captured *mid-flight* (`Settle.none`, `Settle.frames`)
lands wherever its pump cadence puts it, and there the two cadences differ.
Recording must therefore not silently change the interval of a non-recording
policy.

## Memory: the frames must be bounded, and the format does not help

At the shot's own scale a phone-sized frame is **1.29 MB of decoded pixels**,
and one five-step scenario of the example app is 96 frames — **121 MB**.
Flutter's image cache holds 100 MB in total. So a scenario of any real length
does not merely fail to fit: it evicts the *screenshots the flow is made of*
and every node you pan back to reloads.

**Encoding does not help.** The image cache holds pixels, so PNG frames and
raw frames occupy exactly the same memory once decoded; PNG only shrinks the
disk. Measured on the same 5-step run:

| | encode | on disk / run | decoded / frame |
|---|---|---|---|
| raw | ~23 ms | 121 MB | 1.29 MB |
| png | ~630 ms | ~1.2 MB | 1.29 MB |

The run directory is deleted on the next run (`scenarios_core.dart:386`), so
disk is transient where memory is not — which is why the default stays raw and
the bound is on memory.

**The bound is `ScenarioMotionResidency`** (`motion_player.dart`): an MRU over
whole *transitions*, budgeted at 64 MB, well under the image cache's 100 MB so
the screenshots keep fitting beside the recordings. Properties it has to have,
all tested in `motion_residency_test.dart`:

- The transition being played is never the one evicted, however big it is.
- Walking back and forth between two neighbours never re-decodes.
- A re-run releases the frames it replaced — those files are already deleted.
- Twenty steps walked end to end stays under budget.
- An evicted transition stops being one the panel wants decoded. This is the
  one that is not obvious: sweeping the pointer across a flow starts a
  precache loop per node it crosses, and a loop that outlived its own
  eviction would put the frames it was still decoding straight back into the
  image cache — making the budget true only for somebody hovering slowly.

The unit is a whole transition, not a frame: half a recording is no use to
anybody.

**Frames are reused, not re-decoded.** `RawImageProvider`'s key is a value
type over `(width, height, format, path)`, so the provider rebuilt on every
tick resolves to the image already in the cache. The provider being a fresh
instance each frame costs nothing.

**A thing worth knowing when reading the numbers:** in the example run, the
`enterText` and `screen` steps banked 33 frames each — a blinking text cursor,
which is genuinely animating, so the recorder is right to keep pumping. 42 MB
of cursor blink is the honest cost of a screen that never settles. The levers
are the scenario's own: a shorter `Settle` budget, or `Shot.skip`.

## What it can and cannot show

It shows the animation's **ideal curve**. FakeAsync means every frame is
exactly 16 ms apart, no drops, no jitter, bit-reproducible run to run.
Slow-motion is free — pump 4 ms steps, play at 25 fps, that is 10× slow-mo of
the same motion.

It can therefore never say anything about **performance**. There is no jank in
a recording and there never will be; this answers "is the motion right", not
"is it fast". Selling it as a performance tool would be a lie the
implementation cannot make true.

Two hard limits, both inherited from the existing capture path:

- **No asset can load mid-recording.** Resolving an image needs `runAsync`,
  and you cannot pump inside `runAsync`. Anything that starts fetching during
  the transition renders as a hole for the whole recording.
- **An indefinite animation runs to the budget.** 314 frames of a spinner at
  the standard 5 s. A frame cap independent of the time cap is not optional —
  120 frames covers every real transition (a Material page push is 300 ms =
  19 frames) and bounds the memory at ~150 MB of handles at 1×.

## Where it plugs into flutterware

Four seams, all of which already exist:

1. **The pump loop.** `Settle.apply(tester)` is the single point every verb
   pumps through. It gains an optional frame sink; `_Budgeted` gains an
   interval. Four policies, ~10 lines.
2. **The step.** Frames belong to the *transition into* a step — exactly the
   lifetime `events` already has (`events.dart`, design
   `2026-08-11-scenario-transition-events.md`). Same drain-on-capture, same
   `discard()` on a split replay walking a captured prefix.
   `ScenarioStepCapture` gains `frames` and `frameInterval`.
3. **The transport.** The harness already writes each leg of the step to a
   file and puts the path in the record (`harness.dart:706-772`). Frames are a
   sixth leg: `$base.frames/0001.png`, `'frameCount'`, `'frameIntervalMs'`.
   **No protocol change.**
4. **The UI.** `flow_view.dart` draws the arrow between two steps with the
   verb and the event digest on it. The arrow becomes playable. `framed_shot.dart`
   already displays a shot inside a device body, and `RawImageProvider`
   already exists — the "player" is a `Ticker` swapping the image, inside the
   frame the panel already draws.

That last point is why **there is no video file in this design**. The panel is
Flutter; a frame sequence played by a widget is strictly better than an mp4 —
scrubbable, frame-steppable, and every frame carries an exact fake timestamp,
so the scrubber's axis is labelled in milliseconds of app time. Export to a
real video is a separate, later, optional question (animated PNG can be
written in pure Dart from these frames; do not take an ffmpeg dependency for
it).

## Always on, at a low frame rate

The spike's first conclusion was "on demand, by re-run", because always-on at
60fps and full scale is a 5× tax — 1.5 s for a 4-verb scenario against the
~300 ms a warm run costs. That conclusion did not survive measuring the thing
the owner had actually asked for, which was a *low* frame rate:

| 3 transitions, phone | frames | pump | encode |
|---|---|---|---|
| 60fps @1× | 105 | 454 ms | 683 ms |
| **30fps @0.5×** | **55** | **96 ms** | **113 ms** (10 ms raw) |
| 15fps @0.5× | 32 | 54 ms | 64 ms |

At 30fps and half scale a transition costs **~70 ms**, which is affordable on
every panel run — so recording is on by default and the switch is in the run
menu. That matters more than the milliseconds: a recording you have to ask for
is a recording nobody discovers, and the whole feature is hovering an arrow
and seeing what happened.

**Half scale was tried and reverted.** The argument for it was that the last
frame of a recording is the step's own full-scale screenshot, so a transition
would be soft while moving and crisp when it lands. In the panel that reads as
a blur that *snaps* sharp when the animation stops, and the snap is more
distracting than the work it saves. Frames now match the shot's scale
(`MotionRecording.scale` defaults to null, resolved through the same
`scenarioCaptureScale` the shot uses, so the last frame cannot drift from the
still it becomes).

What that costs is memory, and it is the reason the panel has a residency
budget — see below.

CLI and MCP runs never record. Nothing on the other end of those can watch a
movie, and the frames would be artifacts nobody opens.

## Where this differs from the dev_studio spike

| dev_studio's finding | here |
|---|---|
| the whole scenario becomes one movie for free | free only at a low frame rate — 70 ms a transition at 30fps/0.5×, against 380 ms at 60fps/1× |
| pipe raw RGBA to ffmpeg's stdin | no ffmpeg; the GUI is Flutter and plays frames itself |
| `WidgetTester` is our fork, add the sink there | `Settle` is ours; the fork question never arises |
| ffmpeg has no libwebp, use mp4 | no encoder at all; frames on disk in the step's own format |

Shared and confirmed: `toImageSync` under the test binding, PNG encoding as
the bottleneck, the asset-loading hole, the indefinite-animation cap, and the
observation that the real product is *deterministic motion capture* rather
than "a video".

## Worth building?

**Yes, narrowly.** The flow view is the one place in flutterware where motion
is invisible today, and two of the cases the spike recorded — the Hero flight
and the mid-transition cross-fade — are cases where the two endpoint
screenshots are actively misleading about what the user sees.

Ranked:

1. **The playable arrow in the flow view.** Built — see below.
2. **Showing what an unsettled step is still doing.** A step already records
   `settled: false` when the app was still animating when the budget ran out
   (`settle.dart:26`). That was a boolean; it is now the shimmer itself,
   playing. Free once (1) exists, and possibly the more valuable half.
3. **Animation regression goldens.** Not built. Technically the strongest case
   — capture is bit-reproducible — and the worst to live with: video goldens
   are miserable to maintain. Three PNG goldens at fixed fake timestamps
   (`Settle.frames` already does this) gets most of it for none of the pain.
4. **An agent-legible motion summary.** Not built, and speculative. An agent
   cannot watch a video, and "a 300 ms fade" is a sentence, not a recording.
   The only thing shipped for a reader that cannot see is the transition's
   duration on the arrow.

## What was built

(1) shipped, and (2) comes free with it — an unsettled step's shimmer is
simply what its recording plays.

**The guest.** `MotionRecording` and `ScenarioMotionRecorder`
(`lib/src/scenarios/motion.dart`); `Settle.apply` gained an optional frame
sink and `_Budgeted` pumps at the recorder's interval; frames drain in the
same `runAsync` the shot already opens, onto `ScenarioStepCapture.motion`. The
harness writes them as `<step>.frames/0000.<png|raw>` and puts the directory,
count, size and interval on the step record — a sixth leg beside the pixels,
the tree, the semantics and the events, and **no protocol change**.

**The panel.** Hovering a node in the flow rewinds its incoming transition and
plays it in place, landing on the screenshot that was already there — no
popover, no player chrome, nothing moving on the canvas. The step page gets a
transport under the frame: play/pause, frame-step, and a scrubber labelled in
the app's own milliseconds. The inspect overlay is suppressed while playback
is anywhere but the last frame, because every rectangle in the tree was
measured on the frame the step settled at.

**Three things the build changed from the spike's conclusions:** always-on at
a low frame rate rather than on-demand by re-run; frames following
`captureRaw` rather than always PNG; and frames at the shot's own scale rather
than half, with the memory that costs bounded by an MRU rather than by
recording something smaller. Each came from measuring, and the last two from
the owner looking at the thing and saying it was wrong.

**Verified** three ways, because none of them is sufficient alone. The unit
tests cover the recorder, the residency and the panel wiring.
`app/test/scenarios/manual_motion_dump.dart` records `examples/example`'s
counter scenario through a real `flutter_tester` and leaves the frames in
`build/motion-dump/` — run it when changing any of this, because a green
assertion cannot tell you the frames are not blank. And the owner has watched
it in the GUI, which is the only check that can judge whether the motion reads
right; it is what rejected half-scale frames.

**Not built, deliberately:** keyboard shortcuts on the transport — the
buttons and the scrubber are enough, decided after using it. And any encoder. Exporting a transition as a real
video for a PR comment is a separate question, and animated PNG can be written
in pure Dart from these frames if it ever earns its place. Do not take an
ffmpeg dependency for it.

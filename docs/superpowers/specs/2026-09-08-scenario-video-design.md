# Scenario video — the run is the film, the cursor is the only thing invented

**Date:** 2026-09-08
**Status:** a design, decided with the owner in one session. The mechanism is
grounded in code that exists and in measurements already on the record; every
number below is **cited** from an earlier document or is arithmetic over one.
**Nothing was measured today**, and the places where that matters are named in
"What to measure before building the rest".
**Leans on:** `2026-08-11-scenario-motion-capture-findings.md` (the recorder,
the frame rate, the costs), `2026-08-31-widget-export-design.md` and the scene
export (`app/lib/src/scene/export/video.dart` — the encoder this reuses whole),
`2026-08-24-human-beats-design.md` (beats as steps).
**Reverses, narrowly:** the motion-capture findings' closing instruction —
*"do not take an ffmpeg dependency"*. That was an argument against an encoder
**for the panel's player**, where a widget playing frames is strictly better
and still is. Scene export has since taken `ffmpeg` as a hard dependency that
refuses cleanly when it is missing, and this takes the same one. What survives
of the old conclusion is *refuse loudly*, not *no ffmpeg*.

## What this is

`scenarios video` renders one scenario to an mp4 you would put on a landing
page or in documentation: the app moving under a cursor that travels, presses
and drags, at a pace a human would have set.

It is **not** the evidence clip. A film run captures no shots, no trees and no
semantics; it is a second run of the same body whose only product is a video.
The panel's frame player remains what you use to see what a transition did.

## What is already built

| | |
|---|---|
| **The encoder** | `VideoEncoder` (`app/lib/src/scene/export/video.dart`) takes packed RGBA on `ffmpeg`'s stdin — fixed size, even-dimension pad, `yuv420p`, `+faststart`, clean refusal with no `ffmpeg`, `abort()` for a render that died partway. Nothing in it is scene-shaped. Its one caller today is `scene_core.dart:443`. |
| **Frame capture under fake time** | `ScenarioMotionRecorder` (`lib/src/scenarios/motion.dart`) banks a `toImageSync` per pump and pays for the pixels once, later, inside the `runAsync` the capture already opens. |
| **Where the finger went** | `ScenarioAim` (`lib/src/scenarios/aim.dart`) rides every step: resolved box, derived contact point, `dx`/`dy` for a drag, `toward` for a region verb. |
| **A lane that streams frames to an encoder** | `TesterRenderer.walk` (`app/lib/src/previews/tester_renderer.dart:112`) yields frames lazily off disk and sweeps them behind itself, because a clip is bigger than memory. |
| **A fixed path through a branching scenario** | `_SplitPlan` (`lib/src/scenarios/scenario.dart:721`) already exists to walk one path per replay; `split` consults it at `scenario.dart:1874`. |

So the missing middle is small: frames exist, an encoder exists, a path
selector exists, and where the finger went exists. What does not exist is a
**film** — a continuous timeline with human pacing and a cursor on it.

## Decided by the owner

| decision | consequence |
|---|---|
| The product is a **polished reel** for a landing page or docs. | Quality beats speed everywhere the two trade. |
| The foundation is a **cinematic re-run**, not a post-process of a run that already happened. | Typing types, drags drag, the resolution is the film's, and a pause keeps the app animating. |
| The cursor is **painted afterwards** — never in the app's widget tree. | The app's pixels are the app's. The cursor cannot change a layout or trip a rebuild. |
| **Fused**: one process from pump to frame; no separate compositor pass. | A cursor tweak costs a re-run. The timeline file is written anyway, so a compositor pass is an addition later rather than a rewrite. |
| **No device bezel** in v1. | The film is the app's screen. A bezel is a compositor's job and lands with captions, when captions land. |
| **Branching scenarios are refused** unless the exact branches are named. | A film is one path, and which path is the author's call, never a default. |

Later — kept in mind, **not designed here**: text over the film timed to a
moment, injected pauses beyond the built-in beats, zooms, a bezel, captions,
a loop-friendly first-equals-last frame. The one thing built for them now is
the timeline file, below.

## The cinematic run

A cinematic run separates two things an ordinary run conflates: **when the app
is pumped** and **when a verb fires**. Everything follows from that.

A film is a list of beats, and every beat is *pump N frames, maybe fire a
verb*:

| beat | what happens | default |
|---|---|---|
| `open` | nothing fires; the app runs. The viewer reads the first screen. | 500ms |
| `travel` | the cursor reaches for the verb's contact point; the app runs. | 350ms nominal |
| `press` | the cursor contracts and ripples; then the verb fires. | 120ms |
| `act` | the verb's own transition, recorded as it happens. | the app's |
| `dwell` | nothing fires; the app runs, so the eye can read the result. | 600ms |
| `close` | a held ending. | 800ms |

Fake time advances **exactly one frame of the film's fps per pump**, so the
curves are the app's ideal ones: no drops, no jitter, no compositor stutter.
A screen recording of a debug build cannot look this good, and that is the
whole reason the film is rendered rather than captured.

**Arriving and acting are two moments.** Nobody lands on a button and presses
it in the same instant, and without the `aim` beat between them every verb
reads as hurried however gently the reach itself is paced — the owner's note
on the first film with a cursor on it, and the cheapest beat in the table.

**A pause keeps the app alive.** `open`, `dwell` and `close` pump time without
acting, so a spinner keeps spinning and a game keeps playing while the "user"
does nothing. This is what a post-process could never have done — a hold there
is one still repeated — and it is why the re-run is the foundation.

### What makes a reach look like a hand

Three things, none of which costs a frame, and the first matters most:

- **Time grows with the log of the distance, not with the distance** — Fitts.
  A cursor that spends the same 350ms crossing a whole screen and hopping to
  the chip beside it is the least human thing about it: the long move looks
  hurried and the short one looks like it is thinking about it. The setting
  names the nominal — a phone-screen sweep — and a hop takes 45% of it.
- **The speed profile is minimum jerk** — `10t³ − 15t⁴ + 6t⁵`, the classic
  model of a human reaching for something, and visibly gentler at both ends
  than the `easeInOut` it replaced: it leaves rest slowly and settles onto the
  target rather than arriving at it.

No overshoot-and-correct. Real pointing has it; a reel does not want it.

**And the path is straight, which was tried the other way.** An arm is a pair
of hinges, so a real reach arcs, and a Bézier bowed 7% perpendicular to the
line is what that looks like on paper. Watched, it reads as a drift rather
than as a hand — the owner's call, on the film. The timing and the speed
profile are what carry this; the bow was the least evidenced of the three and
is gone rather than tuned down.

### The pointer track is recorded, not reconstructed

Every frame the film keeps gets a pointer sample: position, whether it is
down, and which kind. During `travel` the sample comes from the beat
scheduler, because no pointer exists yet. During `press`, `act` and any
gesture, it comes from **the synthetic pointer the harness actually
dispatched**. That is the honest source, it generalises to verbs we have not
written, and it cannot drift from what the app was told.

Two verbs have to change for that to be true, and both changes are what stops
the film looking fake:

- **`enterText` types.** Today it sets the value in one pump, which reads as a
  paste. The film's variant enters a character per pump, at a rate with a
  little jitter on it.
- **`drag` pumps.** `scenario.dart:1104` goes through `tester.drag`, which
  sends down, moves and up with **no frames between them** — the recorded
  motion is the fling *after* the finger left. The film's variant is
  `startGesture` + `moveBy` + pump, repeated, which also hands the scroll
  physics real deltas over real (fake) time, so the fling is more natural than
  the one an ordinary run produces.

Both live behind the film flag. An ordinary run's verbs are untouched, so no
existing scenario's evidence moves by a pixel.

### Travel, and the mouse that is really there

On a scenario staged as **desktop or web**, `travel` moves a real
`PointerDeviceKind.mouse` gesture in steps rather than only moving a drawing.
Buttons then light up as the cursor passes them, tooltips appear where the app
shows them on hover, and a row highlights before it is clicked — which is a
large part of what makes a desktop reel read as real rather than as a slideshow
with an arrow on it.

On a **touch** device travel dispatches nothing: there is no hover on a phone,
and inventing one would be a lie in the direction of prettier.

## The cursor

Painted per frame, over the captured image, never in the widget tree.

Two looks, chosen by the staged platform, not by a flag:

- **touch** — a soft filled disc at the contact point, about the 22pt fingertip
  `ScenarioAimPainter` already uses (`app/lib/src/scenarios/aim_overlay.dart`),
  contracting on press with one expanding ripple behind it. **Quiet at rest**:
  a fingertip spends most of a film touching nothing, and at the weight the
  press needs it sits on the screen like a smudge and competes with the app —
  which is the one thing the app's own film must not do. The fill, the ring and
  the shadow all lighten when the finger is up.
- **pointer** — an arrow with a white outline so it survives any background,
  and a ripple on click. `longPress` holds a second ring, exactly as the aim
  overlay tells a held press from a tap today.

The verb decides the choreography, and the switch is the one the aim painter
already makes. `keyboard` gets no finger — there is nothing to point at; in
v1 it gets nothing at all, and a keycap card is a caption feature.

**How it composites, and what that costs — measured 2026-09-08.** The obvious
way is a second raster: `PictureRecorder`, draw the captured image, draw the
cursor, `toImageSync`. The cheap way would be to append a `PictureLayer` to the
root `OffsetLayer` before the capture, compositing in the same raster — a
layer-tree mutation between frames, and a spike before it could be trusted.

**It is not worth building.** A/B on the real lane, the same 331-frame film at
780×1688 with the cursor drawn and with `_compose` short-circuited: the whole
spill — rasterise, read back, write — goes from **853ms to 952ms**. That is
**0.3ms a frame**, 12% of the spill and 2.5% of a 3.9s render. The separation
between the app's pixels and the cursor's costs almost nothing, so it is kept
whole. `composeMs` and `writeMs` ride the timeline, so the number stays
answerable rather than remembered.

**The one thing a film changes in the app's tree: the checked-mode banner.**
Found by looking at the first film rather than by reasoning — a scenario runs
in debug, so `MaterialApp` puts a red ribbon in the corner of every frame, and
no landing page can carry it. `WidgetsApp.debugAllowBannerOverride = false`
for the film run and back afterwards, because the alternative is asking every
project to edit its app to be filmable.

The film's painter lives in `lib/src/scenarios/film.dart` — inside the
published package but **not re-exported** through `lib/flutter_test.dart`, so
it is not API and can change freely. That is the same line `scenarioRunArgs`
sits on. Its *settings* live one file over in `film_settings.dart`, free of
Flutter: the CLI names them in a request and is compiled with
`dart compile exe`, where `package:flutter` cannot load —
`app/test/utils/entry_point_purity_test.dart` fails the build over exactly
that, which is how the split was found.

## Frames, and why nothing large lands on disk

The guest writes each kept frame as raw RGBA into the film directory, numbered
the way recorded frames already are (`0000.raw`, `0001.raw`, …), written to a
`.part` name and renamed into place so a reader can never see half a file.

The host **drains as it goes**: start `VideoEncoder`, then feed and delete
frame *N* as soon as *N+1* exists, and after the guest exits feed whatever is
left. Arithmetic on cited numbers says the consumer is not the problem —
`ffmpeg` eats phone-sized raw at ~2.9GB/s, so a 10.1MB frame is ~3.5ms, while
the producer has to build, lay out, paint and rasterise a frame. Disk therefore
holds a handful of frames rather than the clip.

That matters because the clip is large: 30 seconds at 30fps is 900 frames, and
at 1080×2340 that is **9.1GB** if it is all materialised first. Writing PNGs
instead would trade ~7.5ms of encoder per frame (cited, at phone 1×, so more
here) for ~30× less disk — worth having as a flag if the drain disappoints,
not worth having as the default.

The head and the timeline are renamed into place too, and that was measured
the hard way: written in place, an encode died on `Unexpected end of input`
reading a head that was half on disk.

If the run fails partway, the host calls `abort()` and there is no file. A
truncated reel that looks finished is worse than no reel.

## Branching is refused, by name

A film is one path. `split` gives a scenario several, and which one is the
film is the author's decision, never a default.

The film's plan is `_SplitPlan` with the choices stated instead of enumerated:
each `--branch` names the branch to take at the next split reached, outermost
first. Reaching a split with nothing left to consume is a refusal, and the
refusal is the instruction:

```
`Around the shop` splits into `pay by card` and `payment fails`, and a film is
one path. Name it:  --branch='pay by card'
Nested splits take one --branch each, outermost first.
```

Naming a branch that is not there lists the ones that are. A scenario with no
split needs no flag and takes none.

The menu is discoverable without the treadmill: an ordinary run walks **every**
path, and its report already carries each branch's label
(`ScenarioRunStep.branch`), so the panel and the CLI's help can read the choices
off the last run rather than making the author find them one refusal at a time.

## The action

`scenarios video`, beside `scenarios export`, returning
`Artifact(kind: Artifact.mp4)` exactly as scene's video export does — so the
panel surfaces it with the machinery that already exists.

| argument | default |
|---|---|
| `file` / `scenario` | required — one scenario, selected as every other scenario action selects one |
| `branch` (repeatable) | none; required where the scenario splits |
| `fps` | 30 |
| `scale` | 3 — the film's own capture scale, not the run's `1.0` |
| `device`, `language`, `brightness`, … | the scenario's staging, overridable as the existing run axes are |
| `travelMs`, `pressMs`, `dwellMs`, `openMs`, `closeMs` | the beat table above |
| `crf`, `preset` | 18, `slow` |
| `output` | `build/flutterware/video/<scenario>.mp4` |

Meta on the artifact follows `MotionVideo`'s: frames, fps, durationMs,
renderMs, encodeMs, bytes — plus the branch path, so a file can say which path
it filmed.

The host probes `ffmpeg -version` **before** launching the run. Learning that
`ffmpeg` is missing after forty seconds of rendering is a bad way to learn it.

## Encoding, for a reel rather than for a build

The scene export's defaults are tuned for a pipeline; a reel wants the other
side of the same trade, and it is nearly free. Cited: the whole preset span
from `medium` to `ultrafast` is 15% of an export's clock for 2.6× the file,
because the time goes into moving pixels. So `preset slow` and `crf 18` cost
little against a render that is already pixel-bound.

Two constraints that shape what the file looks like:

- **`yuv420p` is not optional** — libx264 defaults to `yuv444p` for RGBA input
  and QuickTime and most browsers refuse it. Chroma subsampling softens crisp
  UI text, which is why the film's capture scale defaults to 3 rather than the
  run's 1: encode above the size it will be displayed at and the softening
  falls below the pixel the viewer sees.
- **Even dimensions**, already handled by the encoder's pad filter.

## Where it is in the GUI

**Under the Run arrow, on the scenario's own page.** Per scenario rather than
per package, unlike the web export beside it: a page is a whole suite and a
film is one flow. In the run menu because it *is* a run — a second one, paced
for a viewer — and under the arrow rather than beside it because a reel is a
rarer thing to want than a run.

The dialog asks only what somebody exporting a clip actually chooses: how big,
how smooth, how heavy, and — where the scenario forks — which way. The device,
the language and the brightness are the page's own axes and are shown a foot
above it, so it inherits them rather than asking twice; the pacing beats tune
what films look like in general rather than this one, and stay on the action.
It prints the command that does the same thing, as the export dialog does, and
a test checks every flag in that line against the ones the action declares.

**What it shows while it works is a frame count.** A render is the only thing
in this GUI that takes tens of seconds with nothing to show for it, and the
frame count is the one number that is honest the whole way through: nothing
while the harness compiles and boots, counting up while the film is drawn, and
only a *fraction* once the timeline lands and there is something to be a
fraction of. The options scroll; the progress does not — on a short window a
bar below the fold is a bar nobody sees, which is how the first version drew
it.

`ScenarioVideoDialogView` takes values and hands back callbacks, so
`app/tool/catalog/demos/video_dialog.dart` previews every state it has — idle,
preparing, counting, encoding, rendered, refused — with no harness, no
scenario and no `ffmpeg`.

## The timeline file

Written beside the mp4, whether or not anything reads it yet:

```jsonc
{
  "fps": 30, "width": 1080, "height": 2340, "scale": 3,
  "scenario": "Around the shop", "branches": ["pay by card"],
  "beats": [ {"kind": "travel", "frame": 15, "frames": 11, "step": 3,
              "verb": "tap", "target": "Cappuccino"} ],
  "pointer": [ {"frame": 15, "x": 190.5, "y": 612.0, "down": false} ]
}
```

This is the seam every later authoring feature edits — a caption is a beat
with words, an injected pause is a beat with no verb, a zoom is a beat with a
rect. Writing it now costs a serialiser and buys the compositor pass its
input, which is the whole of what "keep it in mind, don't plan for it" can
honestly mean.

## What v1 does not do

No captions, no bezel, no zoom, no authored pauses, no audio, no GIF or WebM,
no loop matching, no multi-scenario reel. `keyboard` verbs draw nothing.
Assertions and `expect`s are as they are: a film run runs the real body, and a
body that fails ends the film with no file.

## Found on the way

**A guest spawned from inside `flutter test` answered every asset read from
the wrong bundle.** `flutter test` sets `UNIT_TEST_ASSETS` in the process it
runs a test in, `TesterHost` inherited it, and the guest then installed the
Dart-side `flutter/assets` handler pointed at the *host* package's bundle: the
app under test failed with "the asset does not exist" for files sitting in its
own. Invisible until a scenario with assets was run from a test — which is
exactly what filming the shop from `manual_film_dump.dart` is. `TesterHost`
now copies the parent environment by hand and drops that variable. Nothing to
do with film; it was in the way of one.

## What to measure before building the rest

1. ~~Does appending a `PictureLayer` to the root layer before `toImageSync`
   composite cleanly?~~ **Answered by measuring the alternative instead**: the
   second raster costs 0.3ms a frame, so there is nothing to buy.
2. **What does a film frame actually cost** end to end — build, layout, paint,
   rasterise, composite, write — at scale 3? Everything about the drain and
   about sane defaults rests on the producer being much slower than the
   encoder, which is expected and unproven.
3. ~~Does a pumped drag land where `tester.drag` lands?~~ **Answered: yes, to
   half a pixel**, and only because the finger rests before it lifts —
   *stationary moves*, not stillness, since a velocity estimate is built from
   samples and pumping without them leaves the tracker holding the last
   velocity it saw. `film_test.dart` compares the two drags directly.
4. **Does hover travel disturb anything on a phone-staged run?** It must not
   run at all there — worth an assertion, not just a branch.
5. **Per-character typing under `RealWork`**: a field that fires a debounced
   search per keystroke will now fire many. That is the truth of typing and
   the film should show it, but it is the case most likely to make a film run
   diverge from its scenario's ordinary run.

## Verification

Green tests cannot tell you a cursor is forty pixels off, that the dwell is
too short to read, or that the travel curve looks robotic. This gets the same
treatment the motion recorder got: **watch the file**. The build is not done
until the owner has played a reel of the example app's coffee scenario and
said the pacing is right — that is what the beat defaults are, a first guess
to be corrected by looking.

Mechanical checks worth having anyway, **all four done**: a film of a two-tap
scenario has the frame count the beat table predicts; the encoder is aborted
and no file remains when the body throws; a branching scenario refuses with its
branch names in the message; and an ordinary run is byte-identical with the
film code present — measured 2026-09-08 by running the shop scenario on this
branch and on the commit it forks from and comparing: **seven of seven step
digests equal, seven of seven PNGs byte-identical**. That is what keeps the
evidence lane honest, and it is the property comparison depends on.

## Build order

1. **Film mode in the harness** — the beat scheduler, continuous capture at
   the film's fps, frames and timeline on disk, pointer samples recorded. The
   cursor is a debug dot. **Built 2026-09-08**: `lib/src/scenarios/film.dart`,
   the `ScenarioFrameSink` seam under the settle policies, `--branch` stated
   through `_SplitPlan`, and `ScenarioRunner.run(film:)` carrying it over the
   wire. Measured on the example Counter scenario at an iPhone 13, scale 2:
   **194 frames of 780×1688 in 3.0s** — 6.5s of film, rendered faster than it
   plays. Watched as `build/film-dump/film.mp4`
   (`app/test/scenarios/manual_film_dump.dart`).
2. **The host** — `ffmpeg` probe, the drain, `VideoEncoder`, the
   `scenarios video` action and its artifact. First playable file.
   **Built 2026-09-08**: `app/lib/src/scenarios/film_encode.dart` drains the
   directory as it fills, `scenarios video` returns an `Artifact(mp4)`, and
   `VideoEncoder` gained a `crf` knob and an `available` probe. Measured on
   the example shop's `Order a cappuccino` at an iPhone 13, scale 2: **331
   frames of 780×1688 — 11.0s of film — rendered and encoded in 3.8s**, 684KB.
   A nested-split path (`--branch='a cappuccino' --branch='large cup'`) renders
   the same length; an unnamed split refuses with the four branch names.
3. **The cursor** — two looks, per-verb choreography, composited in the guest.
   **Built 2026-09-08**: `lib/src/scenarios/film_cursor.dart` — a fingertip
   that shrinks under the press and an arrow that dips, each with a ripple that
   outlives the press, and every mark drawn as ink over paper so it survives a
   white card and a brown button alike. Per-verb so far: a `longPress` is
   **held** for 550ms of film, because `tester.longPress` spends no fake time
   and a tap and a hold were otherwise the same picture.
4. **The verbs** — per-character typing, pumped drags, a thumb for `scrollTo`,
   hover travel on desktop. **Built 2026-09-08**, with the human reach above. Typing goes in a
   character at a time (95ms, and 1.6× for a word gap) because `enterText`
   spends no fake time of its own. A drag moves the finger frame by frame and
   then **holds it still, still reporting**, before it lifts — measured: the
   filmed drag and `tester.drag` leave the list at exactly the same offset,
   which is what keeps a film from being of a different app than the suite.
   A drag the author gave a `duration:` keeps its fling. `scrollTo` swipes the
   pane once per iteration and lands where `scrollUntilVisible` lands. Desktop
   travel dispatches a real mouse, and the app answers: filmed on the shop's
   laptop window, the menu row lights up as the arrow reaches it. The example
   project gained `test/scenarios/mobile/beans_test.dart` for it — the shop's
   five drinks fit on every phone in the profile, so nothing there could
   demonstrate a scroll.
5. **The pacing pass** — defaults corrected by watching, which is the only way
   they can be.

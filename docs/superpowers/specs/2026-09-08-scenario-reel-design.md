# Scenario reels — the stage is a scene, the scenario is a slot in it

**Date:** 2026-09-08
**Status:** a design, reached with the owner over one session, on top of the
video lane that shipped the same day. Three probes were run today and their
numbers are in "Measured today"; everything else is cited from code that
exists.
**Leans on:** `2026-09-08-scenario-video-design.md` (the film, the beats, the
cursor, the drain — this generalises it), `2026-08-31-scene-v1-design.md` and
the scene master plan (the scene, its params, its motion runtime), and the
comparison lane's build isolation (`BuildLane`, which is what makes a pool of
guests possible at all).
**Supersedes, narrowly:** the video design's "the cursor is the only thing
invented". It stops being the only thing, and it stops being drawn by the
film — a reel's stage draws it, because a camera that zooms would otherwise
grow the fingertip with the app.

## What this is

A **reel** is a scenario rendered as an authored video: the app playing inside
a stage that can title it, frame it, push in on what is being tapped, hold on
a moment, cut, lay two devices side by side, and — when the 3D branch lands —
map the running app onto a surface.

The film that shipped today renders one path at one size with a cursor over
it, and that is the whole of it. A reel is the same run seen through something
that was designed.

**It is not an authoring tool for videos in general.** It is the smallest
thing that lets a scenario — which already knows what it did, where, and
when — be presented.

## What is already built

The reason this design is small is that almost none of it is new.

| | |
|---|---|
| **The animation runtime** | `Playable` (`lib/src/scene/core/motion_runtime.dart`) with `apply(Duration t)` — evaluate the whole animation at an arbitrary time — and the composition algebra `_Par`, `_Seq`, `_At`, `_Speed`, `_Repeat`. `BoundGroup` writes values into nodes through `writeFx`. |
| **Proof that seek is pure** | `motion_runtime_test`: *"pause holds, seek is pure in any direction"*, *"a parked seek repaints SceneView with the parked frame"*. `walk_determinism_test` takes a scene clip forwards, backwards and twice and expects identical pixels. |
| **A scene and a motion built in code** | `app/tool/catalog/demos/scene_clip.dart` builds a `SceneDocument` and its motion programmatically, binds with `BoundMotion.bind`, and mounts `SceneView.document(scene, motion: motion)`. That is the shape an edit returns. |
| **Typed transform writes** | `Effect` (`lib/src/scene/core/model.dart:553`) exposes `opacity`, `scale`, `translateX`, `translateY`, `rotate` as `double?`. A camera move needs no new track kind. |
| **Structure that varies with data** | `SceneParamKind.list` + `SceneRepeat` — a repeat is a parameter whose value is a list. A grid of N screens and a caption per step are both list params. |
| **A film that is a scheduler** | `ScenarioFilm` (`lib/src/scenarios/film.dart`) already drives pump loops of its own between the settle loops. Pumping the app while nobody touches it is the mechanism a hold needs, and it exists. |
| **Concurrent guests on one package** | `BuildLane` — a host that cannot have the lane it wanted takes a claim of its own. Six concurrent scenario guests work today. |
| **The encoder and the drain** | `ScenarioFilmEncode` eats frames as they are written. Unchanged. |

The missing middle: a screen node, a pool, and a player that steps at 1/fps.

## Decided by the owner

1. **The stage is a scene**, not a painter and not a new document format. It is
   hand-authored in the scene editor, with declared params.
2. **The reel's timeline is a `Playable`** — the motion runtime that exists.
   There is no second animation model.
3. **Sources are live instances, pulled per output frame**, not recordings.
   The renderer holds only the frames visible at that instant.
4. **No restriction on how many sources are visible.** Dissolve any number,
   lay out a grid, picture-in-picture a second scenario. An earlier draft
   restricted cross-dissolves to "at most one side moving" on the assumption
   that passes ran to completion and their frames were buffered. That
   assumption was wrong and the restriction is withdrawn.
5. **Idle is pumping**, not a predicted slack budget. An earlier draft had the
   dry pass publish how long the app could safely be frozen; it is not needed,
   because the renderer drives a live app and can simply pump more.
6. **No magic strings.** Beats are a sealed hierarchy matched with patterns;
   custom cues are the author's own Dart types.
7. **The function is the edit**, not a plan — it returns a finished thing.

## The model

For each output frame the renderer evaluates the reel at that time, reads what
each visible screen slot now demands, pumps those instances to those times,
and composites. Nothing is produced ahead of time and nothing is buffered.

```
Take   ← a dry pass: what the scenario did, where, and when
  ↓ edit(Take)
Reel   = a scene (the stage) + a Playable (the timing) + the source list
  ↓ a player stepping at 1/fps, pulling frames from a pool of instances
frames → ffmpeg
```

### The trick, stated plainly

A screen slot's **source time is a param like any other**, so a slice of
scenario is one tween:

```dart
// reel 3.0s → 5.4s shows scenario 6.2s → 8.6s, live, pushing in on the way
Par([
  At(3.s, Tween(stage.screen.at, 6.2.s, 8.6.s, over: 2.4.s)),
  At(3.s, Tween(stage.zoom, 1.0, 2.4, over: 400.ms, curve: Curves.easeOutCubic)),
])
```

Rate 1 is a slope of 1. Slow motion is a shallower slope. A freeze is flat. A
cut is a jump. `_Par` of two screen slots is a dissolve or a grid. There is no
"play a slice" primitive to build — it is `Tween` on one number.

## The laws

**An instance only moves forward.** Scenario time is pumped, never rewound. A
reel that shows 4.0s and later 2.0s again needs two instances. A decreasing
`at` is refused, and the refusal names the second instance as the fix — which
is worth saying out loud because, per the measurements below, that instance
costs seconds rather than nothing.

**There are two clocks.** Reel time and source time diverge the moment a title
takes two seconds of reel and none of scenario. Managing them by hand is the
thing that makes an edit miserable to write, so the builder owns both and no
edit ever adds to a single cursor.

**`hold` is not `freeze`.** A hold advances both clocks with no verb running —
the app keeps animating, a spinner keeps spinning. A freeze advances reel time
only. They look identical when the app is still and nothing alike when it is
not, so both are in the vocabulary from the first line.

**The pool opens up front.** Every instance a reel will use is opened in
parallel before rendering starts, never lazily mid-render.

**The Take is a map, not a recording.** It says what beats exist and where
things were, so the edit can plan. The truth is whatever the live instances do
when driven. Where an edit inserts time, the *sequence* of beats is preserved
but their times are not — so the drift guard compares beat sequences, never
timestamps, and a divergence is a refusal rather than a seam.

## The vocabulary

### What the Take hands you

```dart
sealed class Beat {
  Duration get at;        // where in the scenario
  Duration get duration;  // how long it took there
}

class Opened   extends Beat { final Size view; }
class Tapped   extends Beat { final Rect target; final String label; }
class Typed    extends Beat { final Rect field; final String text; }
class Scrolled extends Beat { final Rect pane; final Offset by; }
class Said     extends Beat { final Cue cue; }   // whatever s.film.emit sent
class Idled    extends Beat {}
```

### What the scenario can say

Stock cues are sugar over one emit, and the stock stage is simply a stage that
knows them:

```dart
s.title('Order a coffee');
await s.pause(1.5.s);              // real time: the app keeps running
s.film.emit(const Basket(3));      // your class, in your package
```

A cue is a no-op when nothing is filming, and lands as a beat in the flow
canvas and the report — so annotating for a reel makes the test read better
before any reel exists. That is the same species as `s.document()` and
`s.notification()`, which already do this.

### The builder that owns both clocks

```dart
class ReelBuilder {
  Duration reel;      // where we are in the output
  Duration source;    // where the instance is

  void play(Duration of, {double rate = 1});  // advances both
  void hold(Duration d);                      // advances both; no verbs run
  void freeze(Duration d);                    // advances reel only
  void cut(Duration to);                      // advances source only
  void add(Playable p);                       // anything else, anchored at `reel`
}
```

### An edit

```dart
class StockReel extends ScenarioReel {
  @override
  Reel edit(Take take) {
    var stage = StockStage();          // the hand-authored scene
    var b = ReelBuilder(stage);

    for (var beat in take.beats) {
      switch (beat) {
        case Said(cue: Title(:var text)):
          b.add(fadeInTitle(stage, text, over: 1.6.s));
          b.hold(1.6.s);                             // app runs under the card

        case Tapped(:var target):
          b.add(At(b.reel - 300.ms, pushIn(stage, target)));
          b.play(beat.duration);
          b.freeze(250.ms);
          b.add(pullOut(stage));

        case _:
          b.play(beat.duration);
      }
    }
    b.freeze(800.ms);
    return Reel(stage, b.build());
  }
}
```

`At(b.reel - 300.ms, …)` is **writing into the past**: the camera starts moving
before the tap it is moving toward. That is the whole reason the edit builds a
structure instead of consuming a stream, and it costs nothing here.

An edit that knows the app puts app types in the patterns:

```dart
case Said(cue: Basket(:var count)) when count == 1:
  b.add(At(b.reel, sideNote(stage, 'first item added')));
```

`Basket` is the author's class. No map, no registry, no cast.

## Measured today

All on the shop scenario, 355 frames, iPhone 13, this machine.

### A dry pass against a filmed one

`maxFrames: 0` refuses every frame at capture and changes nothing else — the
beats still pump, the clock still advances, the timeline is still written. So
the difference is exactly what pixels cost.

| pass | wall | of which pixels (`writeMs`) | cursor (`composeMs`) |
|---|---|---|---|
| dry | **284–420 ms** | — | — |
| film @scale 2 · 780×1688 | 1273–1556 ms | 840–1020 ms | 68–101 ms |
| film @scale 3 · 1170×2532 | 2365 ms | 1843 ms | 101 ms |

Pixels are 66–70% of a filmed pass at scale 2 and 78% at scale 3. The
cross-check holds: `film − dry` is 989 ms against a reported `writeMs` of
840 ms, the extra ~150 ms being `toImageSync` banking and the GC behind it,
which a dry pass also skips. The cursor is ~0.25 ms/frame, consistent with
what the video design measured before shipping.

Instrument: `app/test/scenarios/manual_dry_run_cost.dart`.

**Absolutes are load-sensitive; shares are not.** Re-run on a busy machine
(straight after a full suite) every wall time moved by 2–3× — a dry pass
between 505 ms and 1875 ms, the same filmed pass between 1.9 s and 4.5 s — while
`writeMs` held at 66–71% of the filmed wall in every run. Quote the share;
treat the absolute as an order of magnitude.

### The instance pool

Fresh runners per round, each with its own `BuildLane`, all runs concurrent.

| | 1 instance | 2 | 6 |
|---|---|---|---|
| cold lanes | 4.2 s | 5.2 s | 6.4 s |
| warm lanes | 3.2 s | 2.7 s | 6.9 s |
| ~RSS each | 129 MB | 159 MB | 196–223 MB |

Read it twice.

**Opening scales well.** Six concurrent instances cost about twice one, not
six times — spawns and compiles overlap almost completely. Six guests is
~1.3 GB, which wants a cap but is not a wall. A grid is affordable.

**But opening costs seconds where pumping costs milliseconds.** Against the
~300 ms a *whole* dry pass takes inside an already-open instance, a 3-second
spawn is enormous. This is the measurement behind "the pool opens up front".

Caveats on the numbers: the RSS average includes the harness's own
`flutter_tester`, and the warm rounds still pay guest spawn — only the dill is
cached — so these are **open** costs, not steady state. The 6-warm figure
sitting above 6-cold is contention noise; do not read a trend into it.

Instrument: `app/test/scenarios/manual_instance_pool_cost.dart`.

### The scene under the test binding

Not measured — already proven. `motion_runtime_test` pumps
`SceneView.document` under `testWidgets`, inside the test binding and its fake
zone, with *"seek is pure in any direction"* among its cases;
`walk_determinism_test` takes a scene clip forwards, backwards and twice for
identical pixels. Both green here: 27 tests, 7 s.

That is precisely what a renderer stepping to arbitrary times needs, and it
was true before this design asked for it.

## What has to be built

Short and specific, which is the point of the probes. Written before the
build; annotated after it (2026-09-09), because five of the eight turned out
to be one week's work and the list read as if none of it existed.

1. **A screen node kind** — an external node whose value is a frame, with
   `at`, `scale` and a source reference as args. *Built* as `ScreenArgs`,
   without the source reference: one source until step 3.
2. **Typed arg accessors.** Node args are string-keyed at the runtime layer
   (`'args.${key}'`). `Tween(stage.basket.count, …)` needs generated accessors
   over machinery that exists — the scene already generates a typed args class
   per external widget. *Not built*; only a data-driven caption needs it.
3. **Per-row group binding** — whether a motion group can bind to a repeated
   row. This is the one gap found today that has not been confirmed either
   way, and captions-per-step depend on it. *Still unconfirmed*; the stock
   edit makes one node per caption instead.
4. **A film player** stepping at 1/fps instead of on vsync, claiming the
   playable's driver the way the editor's player does. *Built* — the stage
   calls `apply(at)` itself, which turned out to need no player at all.
5. **The instance pool** — open up front in parallel, cap it, dispose at the
   end, refuse a decreasing `at`. *Not built*: step 3.
6. **The Take** — the dry pass as a first-class mode plus the typed beat
   hierarchy. *Built.*
7. **The cue channel** — `s.film.emit` with typed values, stock sugar over it,
   and a no-op path for the evidence lane. *Built.*
8. **The cursor moves out of `_compose`** into a stock stage node. Forced by
   zoom, and the better factoring regardless. *Built* as `Pointer`.

Two things explicitly do *not* need building: a reel format, and an animation
runtime.

## What v1 does not do

- **3D.** A screen node inside a surface node should be nothing but nesting,
  but the surface kind is on a branch that has not landed, and
  `flutter_scene`'s memoized init is zone-bound — which is a real hazard for
  something evaluated inside a fake zone. Out of scope, unblocked by nothing
  in this design.
- **A reel-level scrub.** The stage scrubs in the editor today with sample
  values, which is where the look is designed. Scrubbing the *composed* reel
  needs a frame cache from the last render, because dragging a scrubber
  backwards is the illegal direction for an instance. Later, and cheap when it
  comes.
- **A track view in the studio.** The reel is generated by code; the editor is
  where the stage lives, not the edit.
- **Audio, voiceover, captions burned from the transcript.**
- **Reels spanning several scenarios.** The model allows it — a source list is
  a list — but nothing in v1 asks for it.

## Build order

1. **The Take and the scenario's voice.** — **Built 2026-09-08.**
   `FilmSettings.pixels` is the dry mode: every beat pumps, the pointer is
   still tracked, the timeline is still written, nothing rasterises. Beats
   carry `atMs`/`durationMs` and the box the verb aimed at. `s.film.emit(cue)`
   and `s.title(text)` record what the scenario said. `Take` reads it back as
   types — `package:flutterware/reel.dart`. Timeline version 2.

   Three things the build settled that the design had not:

   - **`ScenarioTitle`, not `Title`.** `Title` is a Flutter widget and a
     scenario file imports both.
   - **A cue merges, it does not sort.** `List.sort` is not stable, and the tie
     is the case that matters: a cue said in the breath before a verb is said
     *at* the frame that verb starts on. A stable merge preferring the cue puts
     the caption before the tap it introduces; a sort put it either side at
     random.
   - **A verb's word had to be carried forward.** `approach` runs inside the
     verb, is told the aim and not the word the author wrote, and *its* marks
     are the ones that survive — the mark `act` makes before it covers no
     frames and is dropped. Without carrying it, every take read back a tap
     that named nothing.

   Not done, deliberately: cues do **not** yet land in the flow canvas or the
   report. That needs a new `ScenarioStepKind`, which is published report
   format touched by nine files, and it should wait until a cue's shape has
   been used in anger by an edit.
2. **Render a reel through a scene.** — **Built 2026-09-08**, in two halves;
   the second is below the first.

   *The scene half.* `SceneStage` is a stage whose picture is a
   `SceneDocument` and whose timing is a `Playable` bound to it; `ScreenArgs`
   and `PointerArgs` are external nodes the app's frame and the cursor come in
   through, placed and animated like any node. `StockSceneReel` is the demo
   the design was written toward: a lower-third caption per `s.title`, a
   push-in that starts 420 ms *before* the press, a hold after the first tap,
   the last frame held and dimmed under the scenario's name — and every one of
   those is a `TextNode`, a `scale`/`translate` on the node the screen is in,
   or an opacity track, in **reel** time, which the builder already keeps.
   `cameraOffset` is the push-in's arithmetic: scale is about the node's
   centre, so the compensating translate is `−(p − c)·z`, clamped so the
   frame never shows past the app's edge. Proved on pixels: the closing dims
   the app to 35% over a ground no app has, and the last frame is that colour.

   Four things the scene half settled, three of them by failing first:

   - **A GlobalKey cannot be reparented in an offscreen tree.** The scene view
     wrapped a node in `Opacity` only while its value was below 1, so on the
     frame a fade reached 1.0 the keyed node moved out from under the wrapper
     — and a GlobalKey reparent resolves through the *binding's* build owner,
     which knows nothing of a tree mounted on an owner of its own. The
     framework asserted a duplicate key on exactly that frame. The fix is in
     the view and is better for the editor too: a wrapper stays for as long
     as a writer holds the property (`hasFx`), so nothing deactivates and
     re-inflates mid-motion.
   - **The fx flush is synchronous for the span of an apply.** The scene
     coalesces notifications through `sceneFlushScheduler`, a post-frame
     callback under Flutter; a stage pumps a pipeline that never frames. The
     stage swaps in `(flush) => flush()` around `motion.apply` and restores.
   - **A document adopts at construction.** `SceneDocument(root)` sweeps the
     tree once; a node appended afterwards has no document to tell when its
     fx move. An edit builds the whole tree, then the document, then binds.
   - **Opacity fx multiplies.** A caption authored at opacity 0 to start
     hidden stays at 0 whatever a track says. Authored at 1; the track's first
     key is 0, and `At` clamps to it before the window opens.

   And one that was not a failure but a silent success: the film had been
   mounting the *bare* stage under a reel that carried a scene, and every
   frame-count assertion passed. The scene test now reads pixels.

   *Found on the way, not fixed:* an app with a permanent animation — a
   spinner — never lets a step settle, so every verb runs to the settle
   ceiling and the take is padded with idle: `pumpWidget` alone measured
   **5.07 s** on the demo. A reel of such an app is twice as long as it should
   be. The lever is the step's `Settle` budget, which is the author's to set;
   whether a reel should default to a shorter one is an open question.

   *Still not driven:* the two-pass orchestration. `manual_scene_reel_dump`
   shows the shape — one `scenario` for the take, one for the film, the second
   reading what the first wrote — but nothing in the harness or the GUI runs
   it. Also: the bare `flutter test` lane loads no font and draws every glyph
   as a box; the dump calls `loadDefaultScenarioFonts()` so the stills can be
   read, and the harness lane never needed it.

   *The stage half, built first* — **2026-09-08.**

   *Landed:* the stage is a widget tree mounted in its own build/layout/paint
   pipeline (`OffscreenWidget`, which the vector-export lane already built) and
   pumped once per frame, so a caption is not a widget a finder can match and a
   camera cannot change the app's layout. `Screen` and `Pointer` are widgets;
   the cursor has left `_compose` — parity checked by the existing cursor-pixel
   assertions and by looking at the dump. `Reel` / `ReelShot` / `CueSpan` /
   `ReelBuilder` own **both clocks**, and a projector turns pumped frames into
   output frames: a freeze repeats the last one and consumes no source, a shot
   the source never reaches is dropped, the tail flushes at the end. A hold
   reaches the *run* — an edit keys it on a phase index and the film lengthens
   that pause, so the app really keeps animating.

   *Not landed:* **tweened stage values**, and the reason is worth writing
   down. The motion algebra (`_Par`, `_Seq`, `_At`, `_Speed`, `_Repeat`) is
   only reachable through `playTimeline` over a `SceneMotion` document, so
   *"the reel's timing is a Playable"* and *"the stage is a scene"* are **one
   piece of work, not two**. Until then a cue carries its own span and the
   stage interpolates from it, which covers captions and fades and does not
   cover a push-in. Also not landed: the two-pass orchestration — rendering a
   reel means running dry for the take, editing, then filming, and nothing
   drives that yet; the tests hand a `Reel` straight in.

   Three collisions the build found, all now settled: `ScenarioTitle` not
   `Title` (a Flutter widget), `ReelShot` not `Shot` (already a screenshot
   request in the scenario lane, and an edit imports both), and — caught by a
   test rather than by reading — **a freeze holds the whole picture, cursor
   included**. Handing a frozen frame the source frame that is *arriving* drew
   the hand where it had got to over a screen that had stopped.
3. **The two passes, driven.** — **Built 2026-09-09.** One request renders
   a reel end to end: the harness runs the body dry into a take directory
   beside the film's, collects the finished film, hands its take to the edit
   the scenario declared (or `StockSceneReel`), and runs the body again under
   the reel. `scenario(reel:)` and `runScenarios(reel:)` are the ladder — the
   same shape as `settle:`, captured at declaration, folder beaten by
   scenario. The studio asks for it with one flag (`filmReel`, `--reel=true`,
   a *Cut* picker in the dialog), and the edit stays a Dart object that never
   crosses the wire: it lives in the test process, which is the only place a
   take's cue objects exist.

   Three things the build settled:

   - **The timeline's `frames` is the film's, not the pump's.** Under a reel
     the two part — a hold lengthens the run, a freeze lengthens the film, a
     cut shortens it — and the drain counts to `frames`. Reading the pumped
     count it would have stopped early on a reel that holds and waited
     forever on one that cuts. `pumped` now says how long the app ran.
   - **The take lands beside the frames, never among them.** The drain
     watches the film's directory for a head the dry pass never writes;
     `<dir>.take` is where the first pass goes.
   - **The dry pass's failure is the answer.** A scenario that broke before
     there was anything to cut reports as that scenario failing, with its
     errors; an edit that throws reports the same way, against the scenario it
     was cutting. Neither is a harness error, because neither is one.

   Measured on the example's `Counter` through a real guest: the film pass
   pumps exactly 24 frames more than the take (the stock hold after the first
   tap, 800 ms at 30 fps) and writes 60 more (36 of them the frozen tail).

4. **Many sources.** Pool above one: dissolve, grid, replay.
5. **The desk.** A frame-cache scrub, provenance from a rendered frame back
   to the edit line that made it. Reel selection is done (3).

1, 2 and 3 are one PR: the first thing to land is "a scenario renders as an
authored reel from the studio", not a foundation.

## Verification

- **Parity.** Today's film, rendered through the new spine with the stock
  stage and stock reel, matches what the current lane produces. This is the
  regression that makes the refactor safe to do at all.
- **Determinism.** A reel rendered twice is byte-identical. `apply(t)` is
  already order-free and pure by `walk_determinism_test`; what is new is the
  pool, so the test that matters is two renders with instances opened in
  different orders.
- **The drift guard.** A reel whose edit inserts holds still walks the same
  beat *sequence* as its Take. Assert on the sequence; never on times.
- **The forward law.** A decreasing `at` is refused with a message naming the
  second instance.
- **The evidence lane is untouched.** Ordinary scenario runs stay
  byte-identical — the same check the video lane passed on 7/7 digests and
  7/7 PNGs.
- **Look at it.** A reel is a picture; the demo reel gets watched before any
  beat default is touched, the way `manual_film_dump.dart` exists to be
  watched.

## Open

- **Naming.** `Take`, `Reel`, `edit`, stage, screen slot. Settled enough to
  write with; not blessed.
- **Per-row group binding** (item 3 above) — the one unconfirmed gap.
- **What a screen slot shows in the editor with no run behind it.** A
  checkerboard, a chosen still, or the last frame that slot rendered. The
  third is nicest and needs a cache.
- **A cap on the pool**, and what happens when a reel asks for more instances
  than the cap allows: refuse, or serialise and accept that a dissolve
  degrades.

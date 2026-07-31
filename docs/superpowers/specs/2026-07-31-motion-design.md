# Motion — a timeline editor whose file format is Dart

**Date:** 2026-07-31
**Status:** design, brainstormed with the owner. **Nothing is built** beyond the
spike. **Spikes S5 and A ran the same day and both succeeded** — the seek is
0.23ms against a 16.6ms frame, one seek dirties one scope, read-tracking works,
and `timeDilation` freezes the stage's own animations. Results and the two
corrections they force are below. The API and the panel remain proposals.
**Leans on:** `2026-07-25-overhaul-master-plan.md` (decisions 2, 3, 9),
`2026-07-26-ui-catalog-entry-model.md` (the entry model, axes on artifacts),
`2026-07-27-knobs-static-and-runtime.md` (declare-by-reading, and its costs),
`2026-07-30-scenarios-design.md` (plugin shape, artifact-driven agent loop).
**Prior art in-tree:** `app/lib/src/drawing/` — a working editor that parses
Dart, holds a mutable model, and re-emits with `DartFormatter`. It is the
closest thing to this that already exists, and most of what follows is an
argument about what to copy from it and what not to.

## The one word

**Motion.** Not *Timeline* (`dart:developer` owns it, and DevTools' performance
view is called that), not *Animation* (`package:flutter/animation.dart` owns
`Animation<T>` — a name collision that would be fatal at the call site).

| surface | name |
|---|---|
| scope widget | `MotionScope` |
| anchor handle | `MotionAnchor`, obtained by `m.anchor('title')` |
| generated file | `<screen>.motion.dart` |
| plugin id | `flutterware.motion` |
| CLI | `fw run motion capture …` |
| GUI label | Motion |
| package config | `MotionPackage(directory:)` |

## The honest thesis

Write the plain-Flutter equivalent of any example below and compare. The
build-method half is **the same size** — a `MotionScope` builder is an
`AnimatedBuilder` by another name. What this API removes is the
`Tween` / `CurvedAnimation` / `Interval` declaration block, the
`SingleTickerProviderStateMixin`, the `dispose`, and `ColorTween`'s `.value!`.
Call it 30% less boilerplate, on the part you write once.

That is not why anyone adopts a tool.

> **The value is the editor and the preview loop. The runtime API is the price
> of admission for them, and should be designed to be cheap to pay — not to win
> an argument against hand-written Flutter, which it will not.**

Everything that follows is downstream of taking that literally: the API is
optimised for *machine-legibility and a short authoring gesture*, and every
place where the API could be richer at the cost of the loop, the loop wins.

## The law

> **A Motion is a pure function of `t`.** `evaluate(t) → values`. No wall clock,
> no controller graph, no listeners in the model.

This is what makes scrubbing, playing, headless capture, filmstrip export and
golden frames at fixed `t` all the *same code path*. A controller graph would
make scrubbing backwards a different (and buggier) path from playing forwards,
and headless capture would need a fake clock.

The price this was expected to carry — *implicit animations inside the stage do
not obey the playhead* — **turned out not to be owed.** S5b measured it: an
`AnimationController.repeat()` in the stage does run free on wall time, and
`timeDilation` freezes it while leaving `t` alone, because `t` is written by the
host rather than by a ticker. The panel sets `timeDilation` while scrubbing and
restores it on play. No v1 rule about owning all movement is needed.

Scope, so nobody is surprised: designed choreography with a fixed duration.
Hero transitions, interactive dismiss, velocity-dependent physics, implicit
animations and data-driven reorders are all **outside**. That is perhaps 20% of
what a real app animates — coherent, since that 20% is exactly what a timeline
editor is for, but it has to be said in the README rather than discovered.

## The API

```dart
// your code — the tool never writes here
MotionScope(
  motion: onboardingMotion,
  builder: (m) {
    var title = m.anchor('title');
    var cta = m.anchor('cta');
    return Column(children: [
      Opacity(
        opacity: title.opacity,
        child: Transform.translate(offset: title.translate, child: TextField()),
      ),
      Button(color: cta.color ?? Colors.white),
    ]);
  },
)
```

Four properties hold this together:

1. **`MotionAnchor` is a framework class** declaring the whole closed
   vocabulary. `title.` autocompletes everything. **Nothing is generated on the
   read path**, so no member can fail to resolve and no editor ever has to
   repair your file to make it compile.
2. **Identity is the string, written once.** The local variable carries it to
   every read site, so renaming the variable is an IDE refactor that cannot
   touch the persisted key. Renaming the *string* orphans the tuning — loudly,
   as one untuned group beside one orphan, recoverable by a panel re-key.
3. **Properties with a natural identity are getters returning non-null**
   (`opacity`→1, `translate`→zero, `scale`→1). Properties with no identity
   (`color`, `size`, `style`) return nullable, and `?? Colors.white` at the read
   site is where the un-animated value belongs.
4. **The tool writes exactly one file, and it is not yours.**

### Rebuilding

The builder reruns every frame while the Motion runs. For a 400ms screen
entrance that is ~24 rebuilds of a subtree — the same cost as a `setState` at
the top of a screen, and fine. It is *not* fine for a looping ambient animation
or scroll-driven parallax over a long list.

No API is needed to escape it. Hoist the expensive widget into the **enclosing**
build:

```dart
Widget build(BuildContext context) {
  final field = TextField();     // enclosing build — not per frame
  return MotionScope(motion: …, builder: (m) => … child: field …);
}
```

Flutter's element update short-circuits on an identical widget instance; it is
the mechanism `AnimatedBuilder`'s `child:` already relies on. An earlier draft
proposed a `children:` record parameter for this. It is unnecessary — dropped.

### Drivers

`t` lives on the scope's `State`. A **driver** writes it. Only one of them needs
a ticker:

| driver | ticker? |
|---|---|
| self-playback | yes |
| an `Animation<double>` — route transition, scroll, dismiss | no |
| **the editor's scrubber** | no |
| headless capture, tests, golden frames | no |

So `t` is a plain settable value and the ticker is one optional way to write it.
With no scope in the tree it degrades to a frozen `t`, which is exactly right
for the scroll-driven case and for tests. `MotionScope` also gets `TickerMode`
correctness for free, which hand-rolled controllers routinely miss.

**The editor is just another driver**, which is why this factoring is not
speculative — the tool needs that door regardless.

Because the scope owns the instance, list items each get their own playhead
automatically. Three earlier rounds of argument about global instances,
double-attach asserts and per-`State` lifetimes all dissolve here.

### Timing

`Duration`, matching Flutter — there is no `.ms` extension in the framework and
inventing a house dialect for a generated file buys nothing.

Flutter's *staggering* story is worth copying though: a controller carries one
`duration`, and each part is an `Interval(begin, end)` in normalised 0..1 space.
That is the answer to time-vs-progress — **both, at different layers**. Segments
are authored in `Duration` (the ruler is in milliseconds and that is what a
designer says), the total is derived from the last segment's end, and the
internal representation is normalised.

## The generated file

```dart
//@flutterware:motion=1.0
// Tuned in the flutterware Motion editor. Structure lives in the code that
// reads these; this file carries only what the editor tuned.
// A SOURCE OF TRUTH, not a derivative. Do not regenerate. Do not delete.

const onboardingMotion = MotionValues(
  duration: Duration(milliseconds: 700),
  anchors: {
    'title': {
      'opacity': [
        Seg<double>(start: Duration(milliseconds: 100),
                    end: Duration(milliseconds: 400),
                    from: 1, to: 0, curve: Curves.easeInOut),
      ],
      'translate': [Seg<Offset>(…)],
    },
    'cta': {'color': [Seg<Color>(…)]},
  },
);
```

- Fully `const` — `Duration`, `Color` and `Curves.easeInOut` all are — so it is
  compiled data with no allocation and no parsing.
- A **list per property**, because several segments on one property *is* the
  keyframe case.
- Two rules that must be stated or they will be ambiguous forever:
  **hold** (before the first segment a property is its `from`; after the last,
  its `to`) and **overlap** (two segments on one property with intersecting
  windows is an error the editor cannot produce and the parser reports).
- One heterogeneous-map cast (`Seg<Object?>` → `Seg<double>`) at the lookup
  boundary. It lives in the framework and appears once.
- Found by convention: `onboarding.dart` → `onboarding.motion.dart`. The tool
  creates it, so the convention is never violated by hand.

**Naming trap, load-bearing.** This file is not derived from anything — it is
authored *through* the editor. Naming it `.g.dart` would be actively dangerous:
someone runs a clean-and-regenerate and the choreography is gone. The
regeneration-produces-no-diff check that guards `catalog.g.dart` does **not**
apply. Treat it like an `.arb`.

**Hand-edits must round-trip or fail loudly.** The drawing plugin's
`DrawingPath.fromCode` returns `null` on anything it does not recognise and the
entry silently vanishes (`app/lib/src/drawing/model/path.dart:19`). That is the
one thing from it not to copy.

## The edit loop

| edit | mechanism | cost |
|---|---|---|
| move the playhead | transport RPC; the guest owns playback | one frame |
| **drag a keyframe** | numeric overlay over the VM service, rebuild in place | one frame |
| add/remove a property, change a curve | write the const file → compile → reload | ~130ms |
| edit the stage widget | same | ~130ms |

Numbers from `2026-07-27-gui-slice-findings.md`: compile 5–10ms, reload
85–117ms, `+0 libs` on revisit.

The overlay is what makes dragging possible at all — you cannot write-and-reload
per drag frame. It carries **only numbers**, never structure; structure always
goes through the file. This is the same discipline as knobs-vs-reload in the
catalog.

Walked through:

0. Panel open on the demo, guest live, no anchors.
1. You type `opacity: title.opacity`. Save.
2. Reload (~130ms). The read is recorded; the panel shows a **dashed** row.
   It is already animating on the default.
3. You drag. Each frame: panel model → `ext.flutterware.motion.setOverlay` →
   guest marks the scope dirty → one frame. No compile, no disk.
4. You release. The panel emits the whole const file and formats it. Whole-file
   emit is safe *because the tool owns the file* — that is the drawing plugin's
   proven move, and it is precisely what would have been unacceptable against
   hand-written code.
5. The write reloads (~130ms) and the overlay clears, so what you see and what
   is on disk are the same thing.

**Drag is frame-rate, commit is 130ms, your source is never touched.**

## Three states, not two

The question "does the panel show only the properties in use, or all of them?"
has a third answer. Reads are observable — `title.opacity` is a getter on a
framework object, so it records into a per-frame set and is reported over the
extension, exactly as `EditableParameters` records which knobs the last build
read.

1. **read + tuned** — a normal row.
2. **read + untuned** — dashed. *This is the creation path*: wire it, reload,
   drag.
3. **tuned + not read** — dead tuning. Distinct state, prune action.

So: show the rows that are read, plus a `+` listing the rest of the vocabulary.
Choosing one from `+` creates the entry (so it is tunable) and hands you the
snippet to paste — the tool does the half it can and is honest about the half
it cannot. Until pasted, the row sits in state 3 and says so.

State 3 is also what a *conditional* read looks like (`if (dense) title.scale`).
The syntactic scan sees it either way, so scan ∪ registry separates "never
wired" from "not on this build". Same doctrine as everywhere: scan provisional,
guest ground truth, disagreement is the diagnostic.

## Discovery

One scanner, the established three sources:

- **Config** — `MotionPackage(directory:)`.
- **Syntactic scan** — `m.anchor('<literal>')` inside a `MotionScope` builder,
  plus `<var>.<property>` reads against that local. Both are local to one
  closure, so no resolution is needed. Gives badges and `fw list` with nothing
  running. Provisional.
- **Runtime registry** — what the last build actually read, with each
  property's state and current value. Ground truth.

No generated entrypoint is needed, because the stage is a `@Demo` and the
catalog's entrypoint already imports it.

## The plugin

- **Id** `flutterware.motion`. Shares the catalog's *compiler and guest*, not
  its panel — the same relationship scenarios has.
- **Stage** — a `@Demo`, so discovery, the accumulating entrypoint, the hot
  switch, devices and axes all come for free. The link is found by scanning the
  demo for `MotionScope(motion: <identifier>`; the warm guest is ground truth.
- **Actions** — `list` (motions, anchors, properties, states), `capture --at=`,
  `filmstrip --frames=N`, `new`.
- **Artifacts** — PNG at `t`, the widget tree at `t`, and a **filmstrip contact
  sheet**, which is what an agent should get instead of a video: one image, N
  times, token-cheap.
- **Address** —
  `fw:///<worktree>/flutterware.motion/<pkg>/<file>/<motion>?t=0.42&device=…`
  `t` behaves exactly like the catalog's applied axes and is recorded on every
  artifact, per the rule that a screenshot is under-specified without its axis
  assignment.
- **Golden frames** fall out: the scenarios substrate is already a deterministic
  FakeAsync clock, and a Motion is already a function of `t`, so baselines at
  `t ∈ {0, .25, .5, .75, 1}` are nearly free. This is scenarios' roadmap item 3
  arriving early.

## The panel

Concept, interactive:
`https://claude.ai/code/artifact/b4488f80-9760-4412-8da2-ec95d7e9afd0`
(built on `app/lib/src/ui/design/` tokens, so density and colour are the app's
own; the stage and the filmstrip are driven by the same pure function of `t`).

### Prior art, checked rather than recalled

**Theatre.js** (`theatrejs.com`) is this design, already built, for the web:
props declared *in code* on a "Sheet Object", `@theatre/studio` as a dev-only
editor, `@theatre/core` playing in production. Years of real use, so the
ergonomics are not a bet.

**Its persistence is the weak part, and it is exactly our differentiator.**
Theatre stores project state as JSON in `localStorage`; you commit it by
clicking *Export*, downloading `state.json`, and moving the file into the
project. So tuning lives in a browser, drifts from what is committed, and needs
a ritual to land. Our editor writes a Dart file in the repo, on drag-release,
reviewable in `git diff`. That is the claim worth making, and it is not the part
that demos well.

Worth taking from their sequence editor: **aggregate keyframes** (a parent row
summarising child rows), **static-vs-sequenced props convertible by context
menu** (which is our read+untuned → read+tuned transition, already proven as a
UI concept), click-a-keyframe-for-a-popup-editor, a curve icon per track opening
a handle editor, shift-drag rubber-band selection, and a **focus range** for
isolating a slice of a long sequence.

From **Chrome DevTools' Animations panel**: the playhead is draggable and the
timeline is click-to-seek with playback state preserved; **speed control (25%,
10%) is a first-class button** and is the most-used affordance there — cheap for
us, since `t` is a pure function. One detail maps onto the driver model: DevTools
switches the ruler between **ms for time-based and pixels for scroll-driven**
animations. A scroll-driven Motion's ruler should say px.

**Rive** is not the comparison — it owns its own art pipeline — beyond proving a
timeline editor of this fidelity is buildable in Flutter, since its editor is.

### Layout decisions

- **No separate anchor rail.** An outline panel plus lane names is the same
  information twice. The sequencer's gutter *is* the anchor list: state badge,
  anchor, indented properties, `+ add property`. Theatre keeps them separate
  because its Outline is a scene graph it owns; ours is a registry we read.
- **Two lane levels with an aggregate bar**, so an 8-anchor screen collapses to
  8 rows for judging choreography and expands one for tuning.
- **Inspector on the right** (AE/Rive convention), which also gives the
  "tuned but never read" snippet a permanent home instead of a toast.
- **Filmstrip directly under the ruler**, so it reads as the ruler illustrated.
  It is the thing neither reference has, and it doubles as the agent artifact.

## Rejected variants, and why each died

Recorded because the reasons are not recoverable from the final shape.

**1. A separate `Timeline` declaration with tweens naming anchors.** Died on the
authoring loop: adding a property meant editing the timeline file, switching to
the widget, wiring it, switching back, reloading. Everything else about it
worked; that loop was fatal.

**2. Typed anchors as generated fields (`myMotion.button.color`).** The move
that gave real type safety, and it created the tension that killed variant 1:
the stage can no longer introduce an anchor, because the anchor must exist
before it can be referenced. Type safety and discovery pulled in opposite
directions.

**3. Two attachment modes — a wrapping `Animated(anchor, child:)` beside
read-mode.** Justified by "outside properties (opacity, transform) can be
imposed by a parent, inside properties (a `Button`'s colour) cannot". Died on
`AnimatedBuilder`'s `child:`, which gives read-mode the same repaint-only
property, removing the only argument for a second mode.

**4. The editor performing surgical edits into hand-written code.** Technically
tractable — literals only, located structurally, refused on content drift,
explicit Apply with a diff. Rejected by the owner on principle, and the
principle is sound: **blast radius zero** is worth more for adoption than any
ergonomic win. Every later variant is constrained by this and is better for it.

**5. Inline declaration at the read site (`v.fade(from: 1, to: 0, start: …)`).**
The most compact authoring gesture of any variant, and it converges on
`flutter_animate`'s proven ergonomics. Died because persisting a drag then
requires writing the user's file — variant 4 — and because a lane needed a
builder anyway to scope the rebuild.

**6. `m.opacity.textfield` (property first, anchor as a generated member).**
Invented to solve a real hole: you cannot autocomplete a member you are
inventing, so anchor-first gave no vocabulary help when creating the *first*
property of a new anchor. It worked, but split one anchor across N generated
classes, so an IDE rename silently split a lane. Fixable by decoupling member
from storage key — and then made moot, because once the anchor became a runtime
object nothing is generated, and anchor-first regains full autocomplete.

**7. `const textfield = Anchor('textfield')` at top level.** Correct, and one
step from the final shape. Died only on ergonomics: the name is written twice,
and the declaration sits away from the read site.

The trajectory is the point: **every variant made the implementation smaller.**
The final one generates no classes, resolves no cross-file references, and
reduces the editor's entire write job to emitting one const structure.

## Open questions

1. **Imperative control.** The scope owns the playhead, so `play()`,
   `reverse()` and `seek()` from user code need a handle
   (`MotionScope(controller: …)`). Small, and it will be the first request.
2. **Extension point.** The vocabulary is closed and framework-owned; a project
   cannot add `elevation`. Acceptable for v1 if stated; it arrives as a demand
   in week three.
3. **Decomposition.** `Matrix4` does not lerp meaningfully and `TextStyle` is a
   dozen animatable dimensions in a trench coat. Both want tuned sub-properties
   (`translate`/`rotate`/`scale`) composed into a read (`transform`). What
   exactly is in the closed vocabulary is undecided.
4. **Getters vs methods.** Getters read better; methods would let no-identity
   properties take `or: Colors.white` instead of `??`. Currently: getters, and
   `??` is where the un-animated value is stated.
5. **Step identity for baselines**, when golden frames land — the same question
   scenarios has open, and probably the same answer (only named things may be
   keyed on).

## Spike S5 — ran 2026-07-31, all three questions answered

Code: `app/tool/catalog/demos/motion.dart` (hardcoded values, the target call
sites, three extensions) and `app/tool/catalog/motion_spike.dart` (the host).
Throwaway, kept because re-deriving the harness is the expensive part.

```sh
cd app && dart run tool/catalog/motion_spike.dart
```

### 1. A seek costs one frame — confirmed

| | n | min | median | p90 | max |
|---|---|---|---|---|---|
| seek RPC only | 60 | 0.19ms | **0.23ms** | 0.33ms | 13.06ms |
| seek + frame + capture | 30 | 13.99ms | **16.62ms** | 17.94ms | 18.65ms |
| frame + capture alone | 30 | 13.09ms | **16.57ms** | 18.26ms | 18.61ms |

The transport RPC is **0.23ms** and the seek adds **0.05ms** to a frame that
costs 16.6ms — one 60Hz period. Scrubbing is a frame, not a loop. The tail
(13ms max on the RPC) is GC/scheduling noise, not a floor.

Measured with the capture path, which is `fw capture`'s. The panel renders into
a shared `IOSurface` and pays no capture, so its seek is strictly cheaper.

### 2. One seek dirties exactly one scope — confirmed

10 seeks → **10 builds** of the `MotionScope`. Nothing above or below rebuilds.

### 3. Read-tracking works — confirmed

The runtime reported, unprompted, exactly what the last build read:
`title.opacity, title.translate, field.opacity, field.translate, cta.scale,
cta.color`. **The three-state panel's mechanism is real**, on the same footing
as `EditableParameters` — a getter on a framework object is enough, no
analysis, no annotation.

### 4. S5b — the stage's clock is ours, via `timeDilation`

| | ticks / 600ms | free-running controller advanced |
|---|---|---|
| `timeDilation = 1` | 36 | 0.75 → 0.05 (a full wrap) |
| `timeDilation = 1e5` | 37 | 0.050000 → 0.050003 |

An `AnimationController.repeat()` in the stage **does** run free on wall time —
the engine delivers frames at ~60Hz even in a headless capture-only guest. And
`timeDilation` freezes it: the ticker still fires, but time advances 100000×
slower, which is indistinguishable from frozen at any scrub rate.

**This is better than the design assumed.** The doc's stated fallback — "the v1
rule is that the Motion owns all movement on the stage" — is not needed. The
lever exists, it is one global from `package:flutter/scheduler.dart`, and
critically it does **not** touch us: `t` is written by the host, not by a
ticker, so dilating freezes the stage's own animations while the playhead stays
under our control. That is exactly the property the law needs.

Open follow-up: `timeDilation` is global, so it also freezes anything the
*panel* animates inside the guest. Nothing does today.

### Also learned

- **The heterogeneous const map compiles and works.** `Seg<double>` and
  `Seg<Color>` in one `Map<String, Map<String, List<Seg<Object?>>>>`, fully
  `const`, read back with one `is` check per property under `strict-casts`.
  The doc's "one cast at the lookup boundary" claim holds.
- **`currentFrameTimeStamp` asserts outside a frame**, and in this guest builds
  happen outside the frame pipeline — so it throws in `build`. Use
  `currentSystemFrameTimeStamp`. Cost one spike run, and would have cost the
  panel one too.
- Three of the four bugs in this spike were in the *instrumentation*, not the
  design: a lazy `late final` that never constructed, an
  `AnimationController.value` setter that calls `stop()`, and the assert above.
  A build that increments its counter but records no reads is the signature of
  a throwing builder — ask `ext.flutterware.errors` before theorising.

## Spike A — ran 2026-07-31, the call sites

Written by hand in `motion.dart` against the faked runtime, then compiled and
rendered. Verdict: **the shape is right, one name is wrong, and the nesting is
the real cost.**

- The `var title = m.anchor('title');` block at the top of the builder reads as
  a manifest of what this screen animates. Better than expected.
- `cta.color ?? Colors.white` reads fine, and puts the un-animated value where
  someone would look for it.
- **`translate` should be `translateY` / `translateX`, or return an `Offset`.**
  Writing `Offset(0, title.translate)` and having to remember the axis is the
  one thing that felt wrong on first use.
- **Two wrapper widgets per animated element is the cost.** An element that
  fades *and* moves is `Opacity(child: Transform.translate(child: …))`, and a
  five-element screen nests deeply. This is precisely what the rejected
  wrap-mode would have solved.

  The fix without reintroducing a second mode is a plain widget that takes
  *values*, not anchors:

  ```dart
  MotionBox(
    opacity: title.opacity,
    translateY: title.translate,
    child: const Text('Welcome back'),
  )
  ```

  It knows nothing about anchors, so it is user-code sugar rather than a second
  attachment mode — the distinction that killed variant 3.
- One unplanned benefit of the nesting: every animated value lands on a
  *wrapper*, so the children stay `const`. The verbosity buys cheap rebuilds.

## Spike S5 — the brief, as written before it ran

**Question.** Against a hardcoded `MotionValues` const in the catalog's existing
guest: does a seek cost one frame? Can the guest's clock be controlled well
enough that an `AnimatedContainer` on the stage does not fight the playhead?
Does rebuilding the whole builder every frame perform acceptably on a real
screen?

**Why it matters.** All three are unmeasured and all three are upstream of the
API. If seeking is not instant the tool is a worse hot reload, and nothing above
is worth building.

**Success.** A slider in a panel drives `t` in a live guest at frame rate; a
frame is captured at an arbitrary `t`; the stage's own implicit animation is
either frozen or documented as un-freezable.

**Kill criteria.** If a seek cannot be made to cost one frame within ~2 days,
the feature is a filmstrip generator rather than a scrubber, and the panel
design changes completely.

**Do not** build the plugin, the panel, the scan, the file writer, or the API.
Hardcode everything.

## What the spikes changed

Two corrections to the design above, both from measurement rather than
argument:

1. **`translate` becomes `translateY` / `translateX`** (or returns an `Offset`).
   Naming the axis at the read site is the only thing that felt wrong to write.
2. **Ship a `MotionBox`** — a plain widget taking *values*, not anchors — so an
   element that fades and moves is one wrapper instead of two nested ones. It
   is user-code sugar, not a second attachment mode.

And one claim retired: the stage's implicit animations do not need a rule,
because `timeDilation` freezes them.

Nothing found argues against the shape. The next real decision is scope, not
feasibility.

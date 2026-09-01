# The motion API on mutable ground — sketches 17–20

**Date:** 2026-09-01
**Status:** round three of the sketches, opened by one owner question: *the
scene became a live model with an `fx` plane — what does that open for the
motion API? Should the animation/timeline be mutable too? It must be
nestable, copyable, playable independently. Evaluate all our options.*
Three probes ran for real (quoted verbatim); nothing is decided.
**Leans on:** `2026-08-31-scene-runtime-sketches.md` (sketches 8–16, the
two planes, the round-three probes), `2026-08-28-motion-v2-design.md` (the
law, the operator table).

**The probes, first:**

```
# M1 — mutable timeline under a running player
before: eval(200)=0.5
after value edit: eval(200)=0.9 (live, no rebuild)
drag 300->450 (past neighbour): keys at [0.0, 450.0, 400.0]
  eval(420)=1.000   eval(500)=1.000        # hold rule silently broken
through the door: eval(420)=0.800  eval(500)=0.500   # sort restores it
after insert: duration=800.0  eval(600)=0.5  # a playing track extends live
empty track: StateError — the door must keep >=1 key

# M2 — one playable interface, combinators, nesting
independent play: headlineIn alone at t=130: op=0.50 y=12.0 (badge untouched)
Seq(headlineIn, badgePop) at t=300: headline=1.00 badge=0.17
Par(headlineIn, Seq(headlineIn)): doubleApplies=2 (detected at the sink)
Repeat(3, Speed(0.5, Seq(...))): duration=3000, last frame holds the END

# M3 — copying the pair
copy the scene, keep the motion: original animated, copy DEAD (the trap)
  REFUSED at mount: motion targets a node the mounted scene does not own
copy scene + reconstruct motion: 0.21 us/pair
mutated motion, deep copy + retarget via parallel-walk map: independent
```

---

## Sketch 17 — the timeline is a live model too

The scene's settlement was: all properties mutable with auto-notify;
structure through a door; the editor brings its own operation layer. The
symmetric question for the motion object: are `Track`s and `Key`s mutable,
with a running player reflecting the edit next frame?

**The options:**

- **Immutable tracks, rebuild to edit.** The editor holds a document model
  of its own and reconstructs the motion per edit. Construction is free
  (0.11µs scenes; motions are smaller), so this *works* — but it forks the
  architecture: the scene edits in place and the motion edits by
  replacement, two mental models, and every held reference
  (`intro.headlineIn`, a player mid-play, a machine mid-transit) dies per
  edit and needs re-wiring.
- **Mutable, same shape as the scene.** `key.value = 0.9` while the player
  is parked at the key's time updates the picture next frame — probed:
  `evaluate(t)` over live-edited keys is well defined with no rebuild and
  no player restart. One mechanism everywhere.

**The finding that shapes the mutable option: the sorted-keys invariant is
the timeline's structural door.** A key's *value* is a free retune. A
key's *time* is structure in disguise: the everyday editor drag —
a key pulled past its neighbour — leaves the list unsorted, and the hold
rule breaks *silently* (probed: `eval(500)` answers the wrong key's value;
no crash, just wrong pictures). Same for insert/remove (a track must keep
≥1 key or the lane has no contribution — the empty track throws). So the
scene's own line transfers verbatim: **retune values freely; move, insert
and remove keys through operations** (`track.moveKey`, `insertKey`,
`removeKey`) that re-sort, validate, notify, and journal for undo. The
door is three tiny methods, not a framework.

Two consequences worth naming:

- **Duration is live, and that is a feature.** `duration` derives from the
  last key; inserting a key past the end *extends a playing motion* — the
  hold un-holds and the player simply keeps going (probed). Combinator
  durations (`Seq`, `Repeat`) recompute through the same getters. No
  cached-length invalidation exists because no cached length exists.
- **Scrub is player state, not document state — so the motion needs no fx
  plane of its own.** The scene needed two planes because motion output
  and authored values share slots. The timeline has no second writer: the
  editor's scrub moves the *player's* `t` (never a document field), and
  edits move authored keys. Save-safety needs no plane split here — parking
  the playhead and dragging a key are writes to two different objects.
  (If a motion's own parameters ever become animatable by another motion,
  the split recurses — no use case yet, deferred.)
- **Pause needs a nudge.** While playing, an edit is picked up by the next
  tick anyway. Parked, the player must re-apply at the current `t` when
  the motion dirties — so the motion document gets the same tiny
  dirty→notify organ the scene has, with the player as its one listener.

## Sketch 18 — the playable algebra: one interface, and everything falls out

The owner's three requirements — nestable, copyable, playable
independently — and the first two sketches' machinery converge on one
move: **everything that can play implements one small interface** —
a duration, and `apply(t, fx)` writing contributions into the fx sink
(apply-into-sink rather than return-a-value, because a motion is
multi-target). Probed end to end:

- **A `Track` lane, an `Animate` group, a whole motion class, and every
  combinator are the same kind of thing.** `Par`, `Seq`, `At` (offset),
  `Speed`, `Repeat` are each ~6 lines over the interface, all pure in `t`,
  all holding at their edges (a child before its window applies at 0,
  after it at its end — the hold rule, generalized upward).
- **Playable independently is free:** `MotionPlayer(intro.headlineIn)` —
  a group is a playable, so playing one animation of a motion is the same
  call as playing the motion (probed: the group animates its node, the
  rest of the scene untouched).
- **Nesting is free, including the nested scene's own motion:** a slot
  filled by a scene brings its motion as just another child —
  `At(200, Speed(2, HeroPulse(scene.hero)))` placed and retimed like any
  lane (probed; AE's precomp + time-remap, Rive's nested artboards, and
  GSAP's nested timelines are the three precedents, and GSAP's
  `timeline.add(child, position)` is the most-loved API in the family).
- **Arbitrary depth costs nothing:** `Repeat(3, Speed(0.5, Seq(...)))`
  works by construction — with one authored decision probed in: the last
  frame of a `Repeat` holds the child's *end*, not cycle-0 (naive `t %
  duration` snaps a finished repeat back to its first frame).
- **Seek, export, scrub inherit purity.** Every combinator is a pure time
  transform, so `evaluate`-at-any-`t`, backwards scrub, and the parallel
  video render pass through unchanged.

**The one hazard the algebra creates: double reach.** If `headlineIn` is a
field *and* an arrangement references it, a naive root (`Par` of all
fields + the arrangement) applies it twice per frame at two local times —
last write wins, order-dependent. Probed: the fx sink detects this for
free (a second write from one lane in one frame), so it cannot happen
silently. The rule to pick:

- **(a) No arrangement field → all `Animate` fields play in `Par`** (the
  current sketch-16 behavior, zero ceremony for the common case).
- **(b) An arrangement field (say `timeline`) present → it alone is the
  motion's root**; fields it does not reference do not autoplay but stay
  independently playable. The sink's double-apply check remains as the
  debug assert for genuine double-reach inside one arrangement.

This is Figma's "smart animate default vs explicit prototype" shape and it
keeps the file declarative: combinators are ordinary expressions over
`Animate` fields, well inside the grammar (`Seq([headlineIn, badgePop])`
parses exactly like `children: [headline, cta]` does in a scene).

**What the timeline editor gets from the same rule:** the panel's groups
are the `Animate` fields (already decided); an arrangement is one more
field the editor can *show* as the top-level track order — Seq/At offsets
are the horizontal positions it already draws.

## Sketch 19 — copying the pair, and the trap the guard turns into a refusal

A motion holds **live typed references** into one scene instance — that is
what makes `scene.headline` compile-checked and mutation-composable. The
cost surfaces exactly at copy time, and the probe makes it concrete:

**The trap:** copy the scene, keep the motion → the motion still animates
the *original*'s nodes; the copy renders dead. No error anywhere — the
composed frames are simply wrong. This is sketch 12's irreducible aliasing
price arriving at its most likely address.

**The three legitimate relationships, sorted:**

1. **Shared on purpose** — one scene, one motion, many `SceneView`s is not
   a copy at all; and a shared `Param` box across scenes is aliasing as
   binding. Nothing to fix.
2. **The derivable pair — reconstruct.** `scene.copy()` then
   `BannerIntro(copy)`: every `late final` re-derives against the copy, so
   targets rebind *by construction*. Probed at **0.21µs per pair** —
   construction is never the cost, third confirmation. This is the whole
   story for the standing clone-and-tweak requirement (`dark` banner,
   tweaked copy per list item) when the *motion* itself is untweaked.
3. **The mutated motion — deep copy + retarget.** A runtime-tweaked
   timeline cannot be reconstructed from `(class, args)` (derivability was
   spent at the first setter — the known price). The mechanism probed:
   `scene.copy()` returns the copy *and* an old→new node map built by a
   **parallel tree walk** — same class, same structure, so pairing needs
   no names and no reflection — and `motion.copyFor(copy, map)` deep-copies
   tracks and swaps each lane's target through the map, refusing a node
   the map does not know. Copies verified independent (tweaking one leaves
   the other).

**One design question the probe surfaces:** a generic `copy()` must
construct a sibling instance, and Dart cannot `new` a class generically.
Since parameters are primary-constructor fields, the caller can always
say it in one line — `BannerScene(title: s.title)` — and the framework's
parallel walk does the rest (`s.copyStateInto(fresh)` returning the map).
Tool-emitted per-class `copy()` would remove that line at the price of
generated members in the model file — the direction every previous door
refused. Recommendation: the one-line spelling; revisit only if it bites.

**The guard:** `SceneView` (and the export renderer) can ask the scene
whether it *owns* every target the motion reaches — one tree walk at
mount, probed as `REFUSED at mount: motion targets a node the mounted
scene does not own`. The trap becomes a named, teaching refusal instead
of a dead-looking screen. Same family as the applicator's
unmounted-target reporting (sketch 14), checked one moment earlier.

## Sketch 20 — machines ride along; they are not playables

A `StateMachine` is deliberately *not* on the interface: it is not a pure
function of `t` (it answers to events — `go(GlowState.excited)`), so
making it a `Playable` would poison seek/export purity for everything
containing one. The relationship instead:

- a machine **owns playables** — each state's tracks are a looping
  playable, a transit blends two — and contributes to the same fx sink as
  one more writer (the operator table composes it over the timeline's
  writers; probed back in the fx miniature as the second × writer);
- nesting and independent play carry machines along naturally: playing a
  nested motion ticks its machines on the player's clock (Rive's nested
  artboards run their state machines independently — the precedent);
- export of a machine state remains what motion v2 decided: a chosen
  state/transit rendered deterministically, the event dimension explored
  by scenario capture, not by the video renderer.

## Sketch 21 — the API, both halves, on the settled ground

Two spelling probes ran before this sketch:

```
# M4 — the motion class header
class BannerIntro(super.scene, {final double slideFrom = 24})
    extends SceneMotion<BannerScene> { … }        # compiles on the pin;
super.scene in a primary constructor: node from 24.0   # params default and pass

# M5 — the decided Animate.text spelling cannot type the mutation surface
factory static type: TextAnimate seen as Animate —
    intrinsic tracks unreachable without a cast
class-name form: statically typed
```

M5 matters: a named or redirecting constructor's static type is the base
class, so with `Animate.text(…)` the runtime handle `intro.headlineIn`
loses its per-kind tracks — `intro.headlineIn.color` does not resolve.
Play-only, that was invisible; a *mutable* motion makes the group's static
type API. The two spellings that keep both directions typed are in the
questions below; the sketch uses the extension form.

### Half 1 — the generated motion file

```dart
//@flutterware:motion=2.0
// Owned by the flutterware Motion editor. Hand edits welcome inside the
// grammar; anything outside it is refused with a line number.

import 'package:flutterware/motion.dart';
import 'banner.scene.dart';

class BannerIntro(super.scene, {final double slideFrom = 24})
    extends SceneMotion<BannerScene> {

  late final headlineIn = scene.headline.animate(
    opacity: Track([
      Key(at: 0.ms, value: 0),
      Key(at: 260.ms, value: 1, curve: Curves.easeOut),
    ]),
    translateY: Track([
      Key(at: 0.ms, value: slideFrom),
      Key(at: 260.ms, value: 0, curve: Curves.easeOut),
    ]),
  );

  late final badgePop = scene.badge.animate(
    scale: Track([
      Key(at: 0.ms, value: 0.6),
      Key(at: 240.ms, value: 1, curve: Curves.easeOutBack),
    ]),
    args: {
      'progress': Track([Key(at: 0.ms, value: 0), Key(at: 300.ms, value: 1)]),
    },
  );

  late final glowMood = scene.glow.animate(
    machine: StateMachine(
      initial: GlowState.calm,
      states: { /* as sketch 16 */ },
    ),
  );

  // Mandatory, like a scene's `root`: THE thing that plays. The tool
  // maintains it (default: everything in Par); hand edits rearrange.
  late final timeline = Par([
    headlineIn,
    At(400.ms, badgePop),
    glowMood,
  ]);
}

enum GlowState { calm, excited }
```

The base class is small and closes the discovery problem: `SceneMotion`
implements `Playable` by delegating to the abstract `timeline` (a field
override in the subclass), which also gives `copyStateInto` its walkable
graph. A scene has `root`; a motion has `timeline`; both are the one
mandatory field, and the double-apply ambiguity of sketch 18 dissolves —
there is no "default Par" rule because the Par is written down.

### Half 2 — playing

```dart
final scene = BannerScene(title: t.banner.title);
final intro = BannerIntro(scene);

SceneView(scene, motion: intro);                          // autoplay on mount
SceneView(scene, motion: intro, drive: Drive.progress(scrollFraction));

final player = MotionPlayer(intro);                       // manual control
player.play();  player.pause();  player.seek(300.ms);  player.rate = 0.5;

// Any group or combinator is a playable — independent play is the same call:
MotionPlayer(intro.headlineIn).play();
SceneView(scene, motion: Repeat(3, intro.headlineIn));
SceneView(scene, motion: Par([intro, shake]));            // several motions: compose

intro.glowMood.machine.go(GlowState.excited);             // events, as before
```

### Half 3 — modifying, live

```dart
// Value retunes: plain setters, free, picked up by a running player next
// tick; a PAUSED player re-applies at its parked t when the motion dirties.
intro.headlineIn.opacity.keys[1].value = 0.9;
intro.headlineIn.opacity.keys[1].curve = Curves.easeInOut;

// Timing and key structure: the door — sorts, validates, notifies,
// journals for undo. A Key is a handle: identity survives re-sorts.
final k = intro.headlineIn.opacity.keys.last;
intro.headlineIn.opacity.moveKey(k, 320.ms);
intro.headlineIn.opacity.insertKey(Key(at: 500.ms, value: 0.5));
intro.headlineIn.opacity.removeKey(k);

// Animate a property the file never mentioned: every per-kind property is
// an always-present track, empty until a key arrives (question 3 below).
intro.headlineIn.fontSize
  ..insertKey(Key(at: 0.ms, value: 34))
  ..insertKey(Key(at: 300.ms, value: 54));

// Growing a motion structurally: COMPOSE, never inject — a class cannot
// gain fields at runtime, and does not need to:
final shake = scene.glow.animate(translateX: Track([...]));
SceneView(scene, motion: Par([intro, shake]));
```

### Half 4 — copying the pair

```dart
// Untweaked motion: reconstruct — every target rebinds by construction.
final dark = BannerScene(title: scene.title)..root.fill = const Color(0xFF14100C);
final darkIntro = BannerIntro(dark, slideFrom: 40);

// Runtime-tweaked state: reconstruct, then carry state by parallel walk.
final dark = BannerScene(title: scene.title);
scene.copyStateInto(dark);        // node properties over; returns old→new map
final darkIntro = BannerIntro(dark);
intro.copyStateInto(darkIntro);   // walks both timelines (same class, same
                                  // graph), carries key lists wholesale —
                                  // targets are already the copy's own
```

*(Superseded in the settled decisions below: the owner chose a
tool-emitted `copy()` wrapping this same walk — `scene.copy()` /
`intro.copy(dark)` — so the construct lines above move into the model
files as one forwarding expression each.)*

Because runtime growth is composition (never field injection), the two
timelines of one class always have the same graph shape — the parallel
walk never desynchronizes, and no retarget map is needed on the motion
side at all. The map from probe M3 remains the mechanism for the one case
outside this spelling: deep-copying a runtime-composed playable graph
that references scene nodes directly.

## Sketch 22 — the view is a reader; `motion:` is the autoplay shortcut

The owner's question: is coupling the motion to `SceneView` the right
call, versus instantiating the animation separately and playing it
manually — or is standalone the default and `motion:` mere sugar?

**Standalone is the architecture; `motion:` is exactly sugar.** The reason
is already built: the fx plane lives *on the scene's nodes*, and fx writes
ride the same dirty→flush pipeline as authored writes. So rendering is
motion-blind — `SceneView(scene)` is complete, and a player is a
freestanding object that writes fx and marks dirty:

```dart
final scene = BannerScene(title: t.banner.title);
// The view knows nothing about motion:
SceneView(scene);

// Anyone, anywhere, animates it:
final player = MotionPlayer(BannerIntro(scene));   // owns its Ticker
player.play();                                     // the view just repaints
// … caller disposes: player.dispose()

// Event-fired fragments need no view cooperation:
onTap: () => MotionPlayer(intro.tapPulse).play();

// Drivers attach to the player, not the view:
MotionPlayer(intro, drive: Drive.progress(scrollFraction));
```

What `SceneView(scene, motion: intro)` then *is*: construct a player,
autoplay on mount, dispose on unmount — the lifecycle chore handled for
the 90% case — plus it is the one place holding both halves of the pair,
so the mount guard (sketch 19) lives there and in the export renderer.
Nothing else is special about it; the sugar calls the same player.

Consequences worth naming:

- **Two views of one scene both show the animation** — fx is model state
  (evaluated plane), not view state. That is the correct reading of "the
  scene is live": a mirror, a picture-in-picture thumbnail, the editor's
  canvas all agree for free.
- **Several animators are just several fx writers** — a second player, an
  `AnimationController` listener, a hover effect: the operator table
  composes them; no privileged path through the view exists to fight over.
- **One player per playable instance at a time** — two players ticking one
  lane are a per-frame double-write, which the sink already detects
  (sketch 18); the second `play()` on an already-driven playable refuses
  with the teaching message.
- The user-owned player has a user-owned lifecycle (dispose) — the honest
  cost of standalone, and the thing the sugar exists to absorb.

## Sketch 23 — timeline-wide operations: the ripple family, probed

The owner's second ask: modify *all* keyframes of the timeline at once —
introduce a pause at time x, displacing every key after it. This is video
editing's **ripple edit**, and probe M6 ran it against the full playable
graph. The probe's headline finding:

```
naive ripple (shift every key at/after x):    RIPPLE INVARIANT BROKEN
pinned ripple (hold-keys at both gap edges):  RIPPLE INVARIANT HOLDS
```

**The invariant that defines a correct ripple:** for `t < x` output is
unchanged; for old time `t ≥ x`, `new(t + d) == old(t)`. The naive
shift-everything-after breaks it on *both* sides whenever `x` falls inside
an interpolated segment — the segment stretches, changing the slope before
the gap too (measured: hero 0.75 → 0.70 at t=150, well before the gap).
The correct op is **pin, then shift**: sample the value at `x`, shift the
later keys, and insert hold-keys `(x, v)` and `(x+d, v)` — the pause is
those two pins, and for linear segments the pre-gap line is preserved
*exactly* (a point on a line splits it into the same line). One honest
limit: a **curved** segment cannot be split exactly — a Flutter `Curve` is
a black-box function, not a subdividable Bézier — so a gap cutting a
curved segment refuses with a teaching message (move the gap to a key
boundary) rather than silently reshaping it.

**The op travels the graph structurally** — combinator timing is timing:

- `At`: gap before the window → the *offset* shifts; inside → recurse.
- `Seq`: recurse into the child containing `x` only — later children
  shift for free, because their starts derive from the grown duration.
- `Speed(f)`: recurse with `x·f` and `d·f` — the global gap stays `d`.
- `Repeat`: **refuses** — one global time falls inside every repetition
  at once; the message says to ripple the repeated child instead.
- Verified end-to-end: duration grows by exactly `d`, and every sampled
  frame obeys the invariant through all of the above at once.

**The API, three levels, all doors** (sort-preserving by construction,
one undo entry each):

```dart
intro.headlineIn.opacity.insertGap(at: 300.ms, duration: 200.ms); // one track
intro.headlineIn.insertGap(at: 300.ms, duration: 200.ms);         // one group
intro.insertGap(at: 300.ms, duration: 200.ms);   // the whole timeline,
                                                 // At-offsets included

intro.removeGap(at: 300.ms, duration: 200.ms);   // inverse; a key inside
                                                 // the removed range refuses, named
intro.headlineIn.opacity.shift(after: 260.ms, by: 100.ms);        // plain shift
intro.headlineIn.scale(from: 0.ms, to: 260.ms, factor: 1.5);      // stretch a range
```

`shift` and `scale` are the selection-sized siblings (the editor's
drag-a-selection and stretch-handles); `scale` multiplies key times in the
range and needs no pins when the range edges sit on keys — the editor's
handles are the keys, so that is the normal case.

*Owner's framing note: the gap was one example of a family — the precise
operator vocabulary is deliberately left for a later round. What this
sketch pins is the family's mechanics: the correctness invariant, the
pin-then-shift rule, the structural walk through combinators, and
operations-as-doors.*

## Sketch 24 — the player: why not AnimationController, and who owns the
## ticker

Three owner questions, two probed in a real widget test (M7):

```
at 200ms of 400: value=0.5
100ms after duration doubled: value=0.75   # still on the OLD schedule
under TickerMode(enabled: false): vsync ticker fired 0 times,
                                  raw Ticker fired 5 times
[framework] _HostState was disposed with an active Ticker  # loud, vsync-only
```

**Can AnimationController be the player? No — and the probe names the
sharpest reason: it cannot host a live timeline.** Its `duration` is a
snapshot read when `forward()` starts; changing it mid-flight does
nothing until the next start (probed: value marched to 1.0 on the old
400ms schedule after the duration doubled). Our timeline's duration is
*live* — a key inserted mid-play extends the motion under the playhead
(probe M1). Beyond that mismatch: the controller's value is normalized
progress (seek means computing a fraction, in tension with a moving
denominator), it has no `rate`, and — decisive — the player's real job
was never ticking. It is the **applicator**: call `apply(t, fx)` per
frame, clear fx on stop/cancel (the probed cancel semantics — base
untouched), host the machines' clock and their `go()` events, refuse a
second driver on an already-driven playable. AnimationController does
none of that; some object must; that object is `MotionPlayer` whatever
it wraps internally (a raw `Ticker`, whose elapsed `Duration` is
motion time with no normalization to fight).

**Nothing is lost:** AnimationController remains a first-class *clock* —
`Drive.animation(controller)` drives progress through it, so springs,
fling, curves and reverse all reach a motion unchanged. The layering:
player = applicator + motion-native transport (time-based seek, live
duration, rate); controller = one of its optional clocks.

**The vsync question: optional, with the sugar always providing it.**
The probe shows what `vsync:` buys: TickerMode muting (a route hidden
under an opaque route stops paying — 0 ticks vs 5) and the framework's
loud leak-on-dispose diagnostics (the quoted error is the probe's own
vsync ticker being caught; the raw ticker would have leaked silently).
But *requiring* vsync chains every player to a `State` with a mixin —
hostile to controllers-layer and event-handler use, which sketch 22 just
opened. So:

```dart
MotionPlayer(intro)                    // raw Ticker: works anywhere,
                                       // not muted by TickerMode
MotionPlayer(intro, vsync: this)       // muting + leak diagnostics
SceneView(scene, motion: intro)        // sugar: its own State's vsync,
                                       // muting and dispose for free
```

**Dispose: yes, and the teeth are mostly pulled.** A non-looping player
auto-stops at completion, and a stopped player holds no frame callbacks —
it is plain garbage; forgetting `dispose()` on it is harmless. The real
hazard is a player *still playing* (a looping machine motion) with no
owner: it ticks and writes fx forever. `dispose()` = stop + clear fx +
release the ticker — same discipline as AnimationController, needed
exactly when the player might still be running; the sugar absorbs it for
the mount-and-autoplay case, and passing `vsync` buys the loud leak
detection for the rest.

## Sketch 25 — the fx spelling: writer handles, because one slot is a
## collision

The owner's question: one fx lane per property, or several keyed by
writer (`head.scale.fx(myMotion) = 0.1`)? And what do others do?

**The engine never had one lane.** Since the compose probe the sink has
keyed contributions by *(writer, node, property)* — that is what lets two
motions and a machine share one property through the operator table, and
what makes the writer-stack order normative. Only the *app-facing
spelling* was one-slot: sketch 16's `scene.cta.fx.scale = …` implied one
anonymous slot per node. The question is which surface to expose.

**The survey — the field is unanimous, writer-keyed:**

- **Core Animation** (the closest architectural neighbour: its model vs
  presentation layer is exactly authored vs rendered) — every animation
  is *added under a key* (`layer.add(anim, forKey:)`), removable
  individually; additive animations stack on one keyPath, which is how
  UIKit's smooth spring retargeting works.
- **Web Animations API** — `element.animate(…)` returns an `Animation`
  handle; each has its own `composite: replace|add|accumulate` and its
  own `cancel()`; `getAnimations()` enumerates the writers. CSS grew
  `animation-composition` for the same reason.
- **GSAP** — every tween is a handle with `kill()`; same-property
  collisions are its notorious `overwrite` modes: writer identity
  retrofitted after one-slot pain.
- **Unity / Unreal** — named animation layers with blend mode and
  weight, composited in declared order.
- **SwiftUI** is the one handle-less design (additive, system-owned) —
  and it affords that only because the system owns retargeting entirely.

Nobody ships a single anonymous slot: two effects collide immediately.

**Probe M8** ran the handle shape: a motion lane plus two independent app
effects compose on one property (`1.2 × 1.04 × 0.96`, exact); clearing
one handle leaves the others; `hover.scale = null` removes one property
of one writer; and a re-write does not move a writer's stack position
(first write fixes it — the determinism the golden-frame rule needs).
The anonymous slot, for contrast: the hover write is silently gone the
moment press writes.

**The spelling.** The owner's literal form cannot exist in Dart — a
method invocation is not an assignment target — and would put the
*motion* in app code's mouth, which is the player's job (motion lanes
are already writer-keyed internally; the app never writes "as" a
motion). The handle-first form:

```dart
final hover = scene.cta.effect();     // mint a writer
hover.scale = 1.04;                   // composes with motions and other effects
hover.scale = null;                   // remove one property
hover.clear();                        // remove this writer entirely
```

Recommendation: **handles are the only app surface** — sketch 16's
anonymous `node.fx.…` is dropped rather than kept as sugar, closing the
collision door completely; the one-line cost is minting the handle. A
per-handle `weight` (Unity's layer weight) is the natural future knob and
changes nothing structural. `node.rendered.scale` stays the composed
read.

## The scoreboard, and what is for the owner to pick

What the probes settled:

- **Mutable timeline works and matches the scene**: values retune freely;
  key time-moves, inserts and removes are a three-method door (sort,
  ≥1-key, notify, undo journal). Scrub is player state, so the motion
  needs no fx plane and no Save mask.
- **One playable interface buys everything asked**: nestable (including a
  nested scene's motion, retimed), playable independently
  (`player(intro.headlineIn)`), combinators at any depth, purity of
  seek/export preserved. Double reach is detectable at the sink for free.
- **Copying the pair has a trap, a cheap path and a full path**:
  reconstruct at 0.21µs when the motion is unmutated; parallel-walk map +
  retargeted deep copy when it is; a mount guard turns the
  wrong-instance mistake into a refusal.

### Settled by the owner, 2026-09-01

All six spelling questions closed in one sitting (question 1 of the
first draft had already dissolved into the mandatory `timeline` field):

1. **The group spelling is the extension form** —
   `scene.headline.animate(opacity: …, color: …)`: target reads first,
   matching the editor gesture, and the static return type carries the
   per-kind tracks (probe M5 had killed `Animate.text(…)` for a mutable
   motion: a named constructor's static type hides them).
2. **Unplaced groups are allowed, as library assets.** A group not in the
   `timeline` does not autoplay but stays independently playable
   (`MotionPlayer(intro.tapPulse)` fired on events); the editor shows
   them in a separate library section of the panel. Motion earns the
   asymmetry with scene orphans: event-fired fragments are a real need.
3. **Tracks are always present, empty until a key arrives.** Empty
   contributes nothing; Save writes only non-empty tracks; inserting one
   key brings any property alive at runtime or in the editor, no null
   anywhere. Accepted consequence: deleting a track's last key silently
   disables that lane.
4. **Ext args stay stringly** — `args: {'progress': Track(…)}` is the one
   boundary of the no-magic-strings rule, because the type information
   genuinely lives outside our system (discovered by scan). A typo fails
   loudly through the not-seen-read reporting.
5. **The pair copies through a tool-emitted `copy()` in the model file**
   — the owner took the one-call spelling over the caller-writes-the-
   construct-line recommendation. What keeps it cheap: the generic
   parallel walk stays in the framework's base classes, so the emitted
   member is a *single forwarding expression* the grammar can verify
   mechanically —

   ```dart
   // in banner.scene.dart, tool-maintained:
   BannerScene copy() => copyStateInto(BannerScene(title: title));
   // in the motion file — takes the copied scene:
   BannerIntro copy(BannerScene scene) =>
       copyStateInto(BannerIntro(scene, slideFrom: slideFrom));
   // at the call site:
   final dark = scene.copy();
   final darkIntro = intro.copy(dark);
   ```

   Grammar treatment, per the invariant triple: `copy()` is *derived*
   from the header — the parser accepts a stale or missing one as a
   tolerated spelling and the next emit converges it (a hand-added
   parameter never has to touch it by hand); anything other than the
   canonical single-expression form is refused with a teaching message.
6. **The mount guard refuses loudly.** A motion whose targets the
   mounted scene does not own is a named, teaching error at mount —
   naming both instances and pointing at the reconstruct/copy spelling —
   in `SceneView` and the export renderer both.

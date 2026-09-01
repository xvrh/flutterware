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

Open, for the owner:

1. **The arrangement rule** — no arrangement field means all `Animate`
   fields in `Par`; a `timeline` field present means it alone plays
   (recommended), or some other default?
2. **Combinator vocabulary in the file grammar** — `Seq/Par/At/Speed/
   Repeat` as node expressions over `Animate` fields (recommended,
   parses like `children:`), or arrangement kept runtime-only at first?
3. **The pair-copy spelling** — the one-line reconstruct +
   `copyStateInto` walk (recommended), or tool-emitted per-class `copy()`?
4. **The mount guard** — refuse at mount (recommended), or warn-and-render?

# Motion on scene ground — what the fold dissolves, keeps, and newly asks

**Date:** 2026-08-31
**Status:** a reconciliation, not new design. This document maps
`2026-08-28-motion-v2-design.md` onto the ground `2026-08-31-scene-v1-design.md`
settled three days later, and proposes what the fold means. Nothing here is
owner-decided except where it quotes a decision already made; no code was
written and nothing was measured. Where a proposal needs the owner's signature,
the section says so.
**Leans on:** both documents above, and `2026-07-31-motion-design.md` (v1) for
what the experimental plugin actually ships today.

## The reversal, named

Motion v2's host chapter asked *"slot into a scene, or bind onto a build
method"* and answered: **build B** (bind onto the app's build method — the
hybrid mode, `MotionSlot` in your own code), express A (the scene hosts) as a
built-in host. Two reasons were given: B is strictly harder, so building A
first bakes "the model owns layout" into the core and B spends its life
unwinding it; and the draft/bound tab switch only proves something if both tabs
run one code path.

Scene v1 changes the premise both reasons stood on. They were arguments
against a world where the tool-owned scene is a *toy* — placeholders on a
private canvas, the real screen elsewhere. The discovery week spent itself
making the tool-owned scene not a toy: rendered by a guest compiled against the
user's package, inheriting the app's theme by construction, hosting the user's
real widgets live. What direction B protected — realness — the guest now
provides, and the draft-versus-real distinction B existed to bridge has no
sides left.

So the fold's headline:

> **A is the model. B is dissolved as a mechanism, not demoted to secondary.**
> The app never hosts motion internals; it mounts a scene widget and supplies
> parameters and a driver.

This is a reversal of motion v2's verdict, and it is proposed here rather than
decided — but note that motion v2's own text flagged it: *"stage and
composition could collapse entirely… which may be the real answer and is too
clever to adopt untested."* The scene spike was the test.

## The ledger

### Dissolved

- **`Slot`.** A scene node is a slot whose content is already in it. Motion
  v2's three field kinds map one-to-one: a bare `Track<double>` stays a bare
  lane; an imposed-only `Slot` becomes *any node target* (opacity, translate,
  scale, blur work on every node kind — that was imposed's defining property);
  `Slot<TextValues>` becomes *a target that is a Text node*, whose intrinsic
  vocabulary is the node's typed content. No slot is ever declared, because
  the scene already declared everything.
- **The stage file and the draft.** Already recorded in scene v1: a scene
  with parameter defaults *is* the stage, and the mockup is the default value.
  `DraftText`/`DraftBox` and the whole draft-host chapter go with them.
- **`MotionSlot`/`MotionScope` in user build methods** — direction B's
  binding surface. The shipped artifact is the scene widget itself.
- **Extent-based measurement as box provenance.** B had to measure the app's
  layout (`extent.dart`, transform-not-measure); the guest returns measured
  rects on every apply, so box provenance is the wire, not a feature. The
  extent machinery survives for whatever else uses it; motion no longer needs
  it.

### Survives untouched

Everything motion v2 marked *agreed*, which is the striking part — the fold
consumes the chapters that were still moving and leaves the settled ones
alone:

- **The law.** `evaluate(t) → values`, pure, no clock. Every consumer built
  on it — scrub, filmstrip, golden frames, `fw run motion capture --t=` —
  survives by construction.
- **`Track`/`Key`**, hold and the impossibility of overlap.
- **Two writers compose like transforms**, the operator derived from the
  property's identity element, ordering only for `replace`.
- **Machines: one mechanism at two scopes.** Motion scope is unchanged; slot
  scope becomes *node* scope — a machine attached to a node target, content a
  property bag over that node. The evaluation algorithm is identical.
- **Clock provenance** — embedded, trigger, rate-governed trigger — and
  nesting under the law.
- **The drivers table.** The onboarding `PageView` is a driver writing `t`
  from a page controller; a state machine is the fifth row. Nothing about
  what drives a motion changes because the stage under it changed.
- **The video half wholesale.** A scene with its motion is one clip;
  `Sequence`, resolve-then-render, the render gate, two clocks, the encoder
  decision — none of it touches the host question.

### Changes spelling only

- **Intrinsic bundles are the scene's typed content.** `TextValues` and the
  Text node's content must be *one set of types, defined once* — a fontSize
  track animates the same field the inspector edits. The imposed/intrinsic
  seam stops being motion's private taxonomy and becomes the join between the
  two documents: imposed = what applies to the uniform bag, intrinsic = what
  a node's kind must be asked about. (This is not a new arrival of the
  pattern — it is scene v1's third arrival and motion v2's original line
  turning out to be the same line viewed from both sides, which is better.)
- **A node-scope machine is declared in the motion file**, targeting a node —
  never in the scene file. The rule that keeps the two grammars from bleeding
  into each other: **the scene is timeless; all time lives in motion files.**
- **An external node's intrinsic vocabulary is its wire-able args.** A track
  on a registered widget's `progress` argument, validated against the
  registration's tunable surface. This is a capability the hybrid mode never
  had: v1 could only animate what a hand-written builder chose to read.

## Where motion lives: a sibling file that names its scene

Proposed: **the motion is a separate tool-owned file that declares which
scene it plays on** — `banner.scene.dart` beside `banner_entrance.motion.dart`
(spelling of the declaration undecided; the declaration itself is the point).

The arguments, none individually decisive but all pointing one way:

- A scene without motion is the common case (the banner matrix needs none).
- Several motions per scene is wanted — an entrance and an ambient loop — and
  they compose over the same nodes under the already-decided two-writers
  rule. Motions pluralise; the scene does not.
- Two small grammars stay two small grammars. The scene grammar gains
  nothing; the motion grammar loses its slot declarations.
- The pair diffs independently: retiming an entrance touches no scene lines.

One motion targets exactly one scene. Cross-scene time belongs to the video
half's compositions, which are programs and may schedule many clips; letting a
motion span scenes would smuggle the composition's job into the model.

## The addressing question — the one genuinely new thing

Motion v2 put slots *inside* the motion file specifically to kill a
chicken-and-egg: typed members referencing another file died (variants 2 and
6) because the other file was hand-written user code. The fold moves the scene
out again — but into **another tool-owned file**, and that changes every term
of the old argument:

- The editor renames atomically across the pair; the data never orphans.
- The scene's parse door already enforces unique node names, so a name is a
  stable address minted at the one door everything enters through.
- `fw scene check` grows a pair mode: every target names an existing node;
  every intrinsic track matches its node's kind; every arg track matches the
  registration's wire-able surface.

And the strongest simplification, which the old argument could not have seen:
**external read sites nearly vanish.** Motion v2's case for typed members was
the user's code reading `m.title.opacity` — a rename had to break *their*
call sites loudly. In the fold, the scene runtime applies values internally;
user code supplies parameters and drivers and reads nothing back. The
compile-time-rename argument loses its subject. What remains is tool-internal
addressing between two files the tool always parses together.

**Proposal: targets are names.** The motion file spells `target: 'title'` (or
positionally); the pair is validated at the door; the editor can never emit a
dangling target, and a hand or agent edit that dangles one is caught by
`fw scene check` with a refusal naming both files. The honest cost: an agent
editing only the motion file learns of its dangling target at check/load
rather than at compile — the same trade the scene file already made
everywhere else. Refusals at the door are this format's compiler.

What typed members bought that names do not, and where it went:

| typed members bought | where it lands now |
|---|---|
| rename breaks external call sites at compile time | external call sites no longer exist |
| autocomplete on `m.title` | the editor's job, both files in hand |
| two motions' identical field names cannot collide | node names are unique per scene at the parse door |
| a mistyped key fails loudly | `fw scene check`'s pair mode, and load |

## The hybrid trade, stated for signature

What direction B could do that the fold cannot: **choreograph inside a
hand-written tree.** Animating the title inside a screen you built by hand,
without rebuilding that screen, was v1's mode of existence and B's whole
case. The replacement ladder:

1. **Whole-widget imposition.** Your screen enters as one external node — a
   one-node scene in the degenerate case — and imposed properties apply from
   outside: fade it, slide it, scale it, blur it.
2. **Arg-level animation.** Tracks on the registration's wire-able args — the
   new capability above.
3. **Rebuild the composition as a scene** and inject the interior pieces as
   external nodes. This is the bet: interior choreography is what the scene
   editor is *for*.
4. **Scenario capture** for anything owing a live backend (registration
   rung 3), as already decided.

Given up, permanently, under this proposal: the tool never binds motion into
a build method it does not own. The claim to sign is that the hybrid was v1's
experimental scaffolding, not the product — and that a user reaching for
"animate the title inside my screen" is better served by rungs 1–3 than by a
binding API whose box provenance, draft hosts and dead-lane detection
consumed most of motion v2's open complexity.

## Migration: a clean break, and the one check before it

The experimental plugin's public surface — `MotionValues` files at tier 1,
`m.target('title')` string reads, `MotionScope`/extent opt-in — takes a clean
break. Experimental status is *for* this, and motion v2 already reversed the
string-identity model independently; the fold merely removes the transitional
step of migrating those files into slot-bearing motion files, since slots no
longer exist to migrate into.

What survives the break: the panel mechanics (scrub, filmstrip, capture at
fixed `t`), the agent surface built on `evaluate(t)`, and `values_file.dart`'s
parse-and-emit lesson, already absorbed into the tier-2 engine.

The one thing to do before the break ships, carried over from motion v2's
open question 5 and still nobody has checked: **count the consumer call
sites.** A grep across the real consumer projects for `MotionValues` /
`target(` is an afternoon and turns "we believe the break is cheap" into a
number.

## Parameters across the pair

Scene v1's onboarding configures *text, image, timing*. Text and image are
scene parameters; **timing is the motion's** — a `tempo`, a stagger, a curve.
So the shipped widget's constructor draws on both files, and the parameter
grammar (scene v1's next step 2) must decide the seam. Two shapes:

- **(a) one merged surface** — `OnboardingScene(title: …, tempo: …)`; the
  generated widget flattens both files' parameters. Best in the consumer's
  hands; costs a namespace (a scene param and a motion param may not share a
  name) and a generation step that reads the pair.
- **(b) two surfaces** — `OnboardingScene(title: …, entrance:
  OnboardingEntrance(tempo: …))`. Honest about ownership; noisier at every
  call site, and the common case (no motion params touched) pays the noise.

Leaning (a), because the consumer should not need to know which file a knob
lives in — that is the tool's seam, not theirs. Undecided; this is the first
question the parameter grammar work must answer, which is exactly why this
document was written before it.

## Open questions

1. **The pairing spelling** — how a motion file names its scene, and whether
   the scene name participates in the motion file's marker.
2. **The parameter seam** — (a) or (b) above. Feeds the grammar directly.
3. **Node-scope machine spelling** — a machine targeting a node from the
   motion file; the two-scope semantics are settled, the syntax is not.
4. **Animating content vs styling** — a Text node's fontSize is intrinsic and
   animatable; is its *string*? (Per-character text animation is a text-layer
   question, not answered here; the cheap v1 line is "content is not
   animatable, styling is".)
5. **The timeline over the canvas** — owed by the nesting research
   (`2026-08-31-nesting-and-parameters-ux-research.md`) and the panel design
   after it; nothing in the fold constrains it beyond the precomp model
   already adopted.
6. **The consumer call-site count** before the clean break.

## What this unblocks

- **Scene v1's step 1 (save/load + `fw scene check`) is untouched** — wire it
  any time.
- **Step 2 (the parameter grammar) should be written against this document**:
  declaration and call in one pass, the pair seam decided first.
- The motion grammar's rewrite — slots out, targets in, machines retargeted —
  waits until a scene file exists to target; it is smaller than motion v2's
  version of itself, which is the fold's quiet dividend.

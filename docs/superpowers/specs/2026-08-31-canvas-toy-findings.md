# Canvas toy — a disposable drawing surface, and what using it settled

**Date:** 2026-08-31
**Status:** findings from a working experiment. The toy is real and runnable —
`app/lib/canvas_toy/` behind the *Canvas toy* entry point — and every claim
below was observed by driving it live, not predicted. The code is an
instrument, not a foundation: nothing in it is designed to survive.
**Context:** the second scene-editor discovery experiment, after
`2026-08-31-scene-editor-discovery-findings.md`. The question it was built to
feel: does a *uniform* node (one styling bag on every node, Figma's shape) fit
Flutter, or does the model have to mirror Flutter's heterogeneous widgets?
**What it is:** ~900 lines. A tree panel, a zoomable canvas
(`InteractiveViewer`), and an inspector, over a mutable scene model of three
node kinds — `Frame` (absolute / row / column), `Text`, `Shape` — each
carrying the same geometry slots (x, y, nullable width/height) and the same
styling bag (fill, corner radius, opacity). Seeded with an "agent draft" of
the coffee store banner and refined by direct manipulation, entirely through
the drive layer.

## The headline: the uniform bag survived, and the seam is familiar

For poster-scope nodes the uniform bet held with no fight: fill, corner and
opacity sat on every node, the inspector's top half is one component for every
selection, and nothing demanded a per-widget property model. What stayed typed
was **content** — a text's string/size/weight, a frame's layout knobs, a
shape's circle flag — and the inspector mirrors that exactly: a uniform upper
half, a typed lower half.

That split has a name in this repo already. It is **imposed vs intrinsic** —
motion v2's slot rule — arriving in the scene model unprompted: *the uniform
bag is what the editor can apply to anything; the typed remainder is what a
node must be asked about.* Same line, third arrival. The scene design should
draw it deliberately rather than rediscover it.

## Geometry is read back, and it pays for itself twice

The editor cannot know where a flex child sits without asking the render tree,
so every node carries a `GlobalKey` and a post-frame sweep writes each node's
laid-out rect (artboard coordinates) into the model, bumping an epoch the
overlays listen to. Box provenance — *authored* in absolute frames, *measured*
in flex — became working code on day one, and the inspector states it: a flex
child's X/Y fields are disabled under the caption *"Position measured by
parent layout."*

Two things the measured rects then bought, unplanned:

- **The layout-mode switch became a geometry transaction.** Toggling Copy from
  column to Free first piled all three children at the frame origin — their
  authored x/y had never been written, the classic mode-switch wreck,
  reproduced on demand. The fix was one loop each way: entering Free **bakes
  measured positions into authored x/y**; entering flex **sorts children by
  visual position**. Verified live: the toggle is now visually lossless in
  both directions. The scariest absolute↔flex UX cliff dissolves *only*
  because measured geometry exists in the model.
- **Hit-testing needed no coordinate math at all** — next section.

## Selection is hit-test structure, and the click ladder is z-order

The first hit-testing design — one full-canvas gesture layer doing
`hitTest(point)` against measured rects — was replaced wholesale, and its
replacement is the finding:

> **One transparent hit target per addressable node, positioned from its
> measured rect — where the addressable set derives from the selection**:
> top-level nodes always, plus the children of the selected node's frame
> chain, stacked above.

Figma's enter-a-group ladder then *emerges from paint order*: with nothing
selected, a click lands on a top-level frame; select it and its children's
targets now sit on top, so the next click picks a child. Level stickiness,
descend-on-repeat, sibling picking — none of it is code; it is which targets
exist. Deselection is a layer under everything. The editor contains no
pointer-to-node coordinate lookup anywhere.

Two gesture-arena rules the surface enforced on pain of dead clicks:

- **Never register a double-tap recognizer on a canvas.** It holds every
  single tap hostage for its timeout (~300ms of selection lag, measured as
  taps resolving after the drive's settle). Repeat-click detection is a
  timestamp comparison in the tap handler.
- **A pan handler must apply `panStart`'s own displacement.** A fast drag —
  the drive's synthetic one, or a human flick — is down, one large move, up:
  the recognizer accepts on that single move, `panStart` arrives already
  displaced, and `panUpdate` never fires. Both the node-drag and the resize
  handle shipped this bug independently; the fix is capturing the down point
  and treating start-minus-down as the first delta.

The feared `InteractiveViewer` arbitration never materialized: node drags win
over canvas pans when they start on a node, empty-space drags pan the canvas,
and the split feels right. (Selection handles do scale with zoom — a real
editor draws its overlay in screen space; noted, not fixed.)

## Drag means what the parent's layout mode says it means

One `onPanUpdate`, two meanings, and both were exercised live: in an absolute
frame the delta moves the node (the cup, to fractional artboard coordinates —
window deltas divide by the zoom into artboard units through the transformed
subtree, no explicit conversion anywhere); in a flex frame the pointer's
main-axis position reorders the children (the headline dragged below the
subtitle and back). The mode-dependence read naturally in use — it is Figma's
own behavior — but it means drag feedback must telegraph the mode (an
insertion caret vs a floating ghost), which the toy does not.

## Sizing is a three-state, not a nullable double

`width: double?` (null = hug) died in the first resize: a corner-handle drag
on a hug-sized frame **materializes both axes** — there is no way to say
"widen, but keep hugging vertically," and afterwards no way back to hug except
blanking a field. Then the frozen height bit again: adding a child to the
now-fixed-height column overflowed it, and **Flutter's yellow-black overflow
stripes rendered on the design canvas**. Two findings in one:

- Per-axis sizing wants Figma's mature answer — **fixed / hug / fill as an
  explicit per-axis mode**, with per-edge resize handles — not an optional
  number.
- The canvas needs an **overflow policy**. Hazard stripes are the wrong
  clothes, but they are the *honest body*: the shipped widget would overflow
  exactly there. The right surface is probably clip-plus-warning-badge — keep
  the honesty (this is the German-headline problem from
  `2026-08-28-onboarding-validation.md` surfacing in the editor, which is
  precisely where it should surface), lose the debug paint.

## The inspector: live commit, and the canvas is the feedback

Number fields began commit-on-submit and it was wrong twice over: a synthetic
Enter never fires `onSubmitted` (a key event is not the platform text input —
the drive layer's standing lesson, met again from the app side), and a human
watching the canvas wants the value to land per keystroke anyway. Live commit
of every parseable edit made font size, gap, and coordinates feel immediate,
and text content edits reflowed the column as typed. The editor's real undo
requirement starts here: live commit without undo is a one-way street, and the
toy has no undo. **Undo is day-one infrastructure for the real thing, and the
model should be designed for it** (command log or immutable snapshots) rather
than retrofitted.

## The agent drove all of it, because the surface was named

Every interaction above was performed through `flutterware_act`: hit targets
carry `ValueKey('node:<name>')` so canvas nodes are addressed as
`{"key": "node:Headline"}`, inspector fields resolve by their labels, toolbar
buttons by tooltip. Nothing was screenshot-pixel-guessed. Two drive-layer
facts found on the way, worth recording for the papercuts list:

- An `{"at": {x,y}}` target resolves to the innermost *widget* under the
  point and then acts at that widget's **center** — so a single full-canvas
  gesture layer is undrivable (every point collapses to its center; measured:
  taps at the artboard's exact center landing in the gap between two nodes).
  Per-node targets fixed this as a side effect. A point-precise act verb
  remains missing from the drive grammar.
- A drag under ~30 window px can die entirely under the pan recognizer's
  touch slop; drive drags need margin over `kTouchSlop`.

The general lesson is the AI-first one: **an editor whose interactive surface
is keyed and labeled is agent-operable for free**, and the same keys are what
a test would use. The naming discipline costs nothing at authoring time and
should be a rule of the real editor, not a retrofit.

## What the toy deliberately did not test

Persistence and round-trip (the model never touched disk — the grammar spike
is separate), undo, multi-select and marquee, snapping/guides, constraints
and responsive variants, text layers, images and assets, rendering fidelity,
performance beyond a ten-node scene, keyboard nudging — and **the
Flutter-mirror alternative was never built**, so the fork was felt from one
side only. The mirror's case would have to beat the uniform bag's showing
here, and after this session the bar is: the uniform core cost nothing, the
typed remainder was small, and the imposed/intrinsic seam gave both halves a
principled home.

## What this changes in the discovery plan

1. **The model fork has a working answer to beat**: uniform geometry+style
   bag, typed content per node kind, imposed/intrinsic as the seam. Write the
   scene sketches against this shape.
2. **Measured geometry is a first-class model citizen** — the sweep, the
   epoch, and provenance-aware fields move into any real design as-is; the
   mode-switch bake depends on them.
3. **Three UX laws are now evidence-backed**: no double-tap recognizer,
   panStart displacement handling, live commit. Plus two requirements
   promoted to day-one: per-axis fixed/hug/fill sizing, and undo designed
   into the model.
4. **Addressability is the editor's own structure**: selection-derived hit
   targets, named for humans (tree), agents (keys) and tests alike.

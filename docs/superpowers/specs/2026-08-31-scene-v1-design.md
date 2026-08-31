# Scene v1 — data at edit time, code at rest, and the guest is the only renderer

**Date:** 2026-08-31
**Status:** a distillation, not a brainstorm. Every load-bearing claim below
was **measured this week** in one of five discovery experiments, or decided
by the owner during them; the findings documents hold the evidence and this
document holds the decisions. Where something is still a first shape, the
settledness table says so.
**Leans on:** `2026-08-28-motion-v2-design.md` (the motion model — settled
there, layered here), `2026-08-28-onboarding-validation.md` (the component
build this validates against).
**Evidence:** `2026-08-31-scene-editor-discovery-findings.md` (the deleted
drawing editor exhumed; the SDK mined), `2026-08-31-canvas-toy-findings.md`
(the model, felt), `2026-08-31-widget-registration-findings.md` (measured on
five real widgets), `2026-08-31-remote-canvas-spike-findings.md` (four
rounds, ending composited at one guest frame per drag),
`2026-08-31-scene-grammar-roundtrip-findings.md` (fuzzed, hostile-tested).
**Working artifacts:** `app/lib/canvas_toy/` (model, editor, file engine),
`app/lib/main_scene_canvas_dev.dart` (the composited editor),
`examples/example/demo/scene_host.dart` + `scene_canvas.dart` (the guest).
All spike-grade; the shapes are the deliverable, not the code.

## What this is

One plugin — Motion grows into it — whose document is a **scene**: a tree of
design nodes and injected widgets that is simultaneously

- an **artifact source**: a store banner exported as PNG across a
  language×device matrix, the composed content of a promo video;
- a **shipped widget**: an onboarding page added to an app and configured —
  text, image, timing, the gesture that drives it — through parameters;
- the **stage motion plays on**: motion v2's slots attach to scene nodes, and
  its deferred "stage file" dissolves into a scene whose parameter defaults
  are the mockups.

First customer: the example coffee app's store pipeline (banner, video,
onboarding), so every papercut is ours before it is anyone else's.

## How settled is this

| | |
|---|---|
| **Measured, and decided by the numbers** | The guest-rendered canvas: edits travel as data over a VM-service extension, and under drag the round trip **is one guest frame** (22.2ms rtt, 20.7ms frame; pipe ~1.5ms). Guest frame cost flat from 11 to 415 nodes. The model: a uniform styling bag on every node plus typed content per kind. Registration: the scan recovers everything but domain objects, so **a preview entry is the registration**. The file: a one-page tier-2 grammar whose 300-document fuzz passed first run, under the invariant triple and one collecting refusal policy. Measured geometry lives in the model. |
| **Decided by the owner during discovery** | One plugin, motion fades into it. Both layout modes on equal footing from the start. Parameters are the crux of the shipped-widget half. Poster nodes first; app-screen content injected over mockups. Rendering must not rasterize external widgets, must inherit the app's theme — which is what forced (and rewarded) the guest architecture. |
| **Leaning, with a reason** | Per-axis sizing as fixed/hug/fill (a corner resize destroyed `double?`-as-hug in first use). Overflow as clip-plus-badge (honest body, better clothes). Undo designed into the model from day one (live commit is a one-way street without it). Editor overlay in screen space (handles currently scale with zoom). |
| **First shape only** | The node spellings (`Frame`/`Text`/`Shape`/`Ext` collide with Flutter's names if ever compiled against material). The text layer stack. Breakpoint variants. Palette curation over the generated catalog. The parameter grammar. |
| **Not designed at all** | Multi-select, marquee, snapping and guides. PDF/SVG emitters beyond "walk the model". The motion timeline drawn over a scene. Server-delivered scenes (explicitly out — a different product). |

## The three pillars

### 1. The scene is data at edit time and code at rest

"Compile in the loop" conflated two changes. An *edit* is a data change — the
model is a value, ~2KB of JSON for the banner, pushed over a VM-service
extension and coalesced in flight. A *code* change (the user edits a widget)
is hot reload, already ~300–700ms. Dart-as-file is the **persistence**
format, never the edit-time transport. This is what makes the canvas fast
and the compiler irrelevant to its feel.

At rest, the file is tier-2 Dart under the grammar (below), diffable and
agent-writable — the AI-first surface: an agent authors a scene with no
editor running, `fw scene check` (this parser behind a CLI door, unbuilt)
tells it loudly when it is wrong, and the render lane shows it the result.

### 2. The guest is the only renderer

The scene renders in a process compiled against the user's package — booted
by the same `CatalogSession` machinery previews and motion use — and the
editor composites its texture, owning only chrome and overlay. Nothing
interprets in the editor process; the interpret-vs-compile fork is dissolved,
not decided.

What this bought, all observed: **theme inheritance by construction** (the
guest wraps in the app's own ambient stack); **external widgets live** — a
spinner spins on the canvas, a button takes the app's theme, mockup domain
objects never serialize; **many guests from one model** — the same push loop
drove a desktop guest and a phone-simulator guest at once, which is the
export matrix's interactive twin; **the whole drive grammar against the
rendered scene** — one `styles` call returned the banner's type ramp
including a style the editor never authored.

And the miniature that proves the law: the editor's local mirror looked right
while the real render had no `Material` and yellow-underlined every text.
Two renderers diverge; the cure is owning one. **A scene guest's ambient
stack (`Material`, theme, directionality, `MediaQuery`) is part of the scene
runtime's contract** — the same mechanism as the previews `wrapper:`, which
is also where registration already gets it.

The editor's geometry is what the guest measured: laid-out rects return with
every apply and feed selection, hit targets and handles. Box provenance —
authored in absolute frames, measured in flex — is not a concept in a
document; it is the wire.

### 3. One uniform bag, typed content — the imposed/intrinsic seam again

Every node carries the same geometry slots (x, y, per-axis size) and the same
styling bag (fill, corner, opacity); each node *kind* carries its typed
content (a text's string and type, a frame's layout knobs, an external's
entry and args). The inspector mirrors the split: one component for the top
half of every selection, a typed section below.

This is motion v2's imposed/intrinsic line arriving unprompted in the scene
model — *the uniform bag is what the editor can apply to anything; the typed
remainder is what a node must be asked about* — its third independent
arrival, which is the repo's standing threshold for trusting a boundary.

## The model, beyond the seam

- **Four node kinds** in v1: `Frame` (absolute / row / column), `Text`,
  `Shape`, and the **external node** — a widget the editor never compiled
  against, addressed by its registration entry, rendered natively by the
  guest, tunable only in its wire-able args.
- **A name is identity**, unique by construction, enforced at the parse door
  and used everywhere: the file, the wire, the rects, the editor's hit-target
  keys (`node:<name>`), which is also what makes the whole editor
  agent-operable for free.
- **Layout-mode switching is a geometry transaction.** Entering Free bakes
  each child's measured position into authored x/y; entering flex re-derives
  order from visual position. Verified lossless both ways — and possible
  *only* because measured geometry is in the model.
- **Sizing is per-axis fixed/hug/fill**, not a nullable number: the first
  corner-drag on a hug-sized frame froze both axes with no way back, and the
  frozen height then overflowed — which also set the **overflow policy**:
  clip plus a warning badge. The overflow is the honest body (the shipped
  widget would overflow exactly there — the localized-headline problem
  surfacing in the editor, where it should); the hazard stripes are the wrong
  clothes.
- **Drag means what the parent's layout says**: move in absolute, reorder in
  flex — so drag feedback must telegraph the mode.

## The file

The grammar fits on a page (it is the header comment of
`scene_file.dart`): marker, file-header region, one class, one
`final root = Frame(…)`, nodes as constructor invocations with fixed named
vocabularies, values limited to literals, `Color(0x…)`, allowlisted enums,
child lists and literal `args` maps. Nothing else.

**The invariant is a triple**, not motion v2's single equation — the spike's
sharpest correction. `emit(parse(f)) == f` cannot survive the first friendly
tolerance (accept `1024.0`, emit `1024`) and refusing tolerances makes
hand-editing hostile. What holds, fuzzed over 300 documents:

1. `parse(emit(m))` reproduces the model;
2. `emit ∘ parse` is the identity on canonical files (emit's image);
3. an accepted non-canonical file converges to canonical in one emit.

**One refusal policy: collect, name, and yield nothing.** Every
out-of-grammar construct is reported — construct, line, expectation — all at
once, and a file with any refusal loads no document. A partial scene is the
lie the editor must never tell; the deleted drawing editor's parse-drop plus
emit-regenerate *deleted hand-written code from disk*, and that shredder is
the failure this policy exists to make impossible. Comments inside the scene
are refused at the door for the same reason (nothing that can enter can be
lost); the modelled note field remains the way to give them back.

Canonical spelling is three rules (integral doubles as ints plus Dart's
lossless `toString`; uppercase `Color(0x…)`; single-quoted strings, six
escapes) — and the formatter is part of the identity, so its version belongs
to the format.

## Registration: a preview entry is the registration

Measured on five real widgets: the syntactic scan recovers every scalar,
enum, child and default — **a registration owes only domain objects** — and
a one-regex body scan names the context a wrapper must provide
(`{ShopStrings, Theme, Cart, Navigator}` for a real screen), turning the
worst failure (a guest throw) into a named requirement. The user-scan's enum
gaps are closed by the generated SDK catalog: one extractor, two corpora,
completing each other.

So registration is a ladder priced by what a widget withholds:

1. **owes nothing** → auto-registered from the scan (the long tail);
2. **owes a domain object or context** → one preview entry — which the demo
   culture writes anyway — whose *grammar-shaped body* defines the tunable
   surface (fixed mockups stay verbatim; representable args become
   overridable) via a generated bridge, mockups living guest-side and never
   serializing;
3. **owes a live backend** → never placeable; scenario capture is that
   content's transport.

Annotation-on-the-widget is rejected (const mockups — motion v2's finding 4,
third arrival); config-file builders are demoted to configuration.

## Parameters — the crux of the shipped-widget half

A scene is a function: typed holes, filled by the export matrix (a language's
strings) or by the app (`OnboardingScene(title: …, hero: …, tempo: …)`), with
**the mockup as the default value** — the poster's content and the app's
placeholder are one field read by two callers. This dissolves motion v2's
separate stage file: a scene with defaulted parameters *is* the stage, and it
ships.

Boundaries, each already settled three times elsewhere: **parameters retune
and rebind, never restructure** (a 4-page onboarding is four scenes in an
app-owned `PageView`); scroll-driving is v1's drivers table (`evaluate(t)`,
`t` from the page controller); and text content gains a **provenance** —
literal, parameter, or translation key — the sixth arrival of the provenance
pattern, and the bridge to the existing translations index and the
language-axis export.

The cost is the grammar's one deliberate widening, scene-only: a constructor
with named parameters and initializer-list defaults.

## The editor surface

- **Selection is hit-test structure.** One transparent target per addressable
  node, positioned from measured rects, where addressability derives from the
  selection (top-level always; children of the selected chain stacked above).
  The Figma click ladder emerges from z-order; the editor contains no
  pointer-to-node math.
- **Three gesture laws, each paid for:** no double-tap recognizer on a canvas
  (it holds every tap for its timeout); pan handlers apply `panStart`'s own
  displacement (a fast drag can deliver no `panUpdate` at all — two widgets
  shipped that bug independently); number fields live-commit (the canvas is
  the feedback).
- **Undo is day-one model infrastructure**, not a retrofit — live commit
  without it is a one-way street.
- **The overlay draws in editor space** above the texture: selection and
  handles track the cursor at editor-local latency while content trails ≤1
  guest frame — the reason the composited canvas *feels* instant and not
  merely measures well.
- **Beats and captures follow the co-driving rules learned here**: journal
  captures arm on first consumer contact, and macOS guests stay painted
  through rasters. An editor canvas is exactly the surface those defaults
  were wrong for.

## The product frame (unchanged from the brainstorm, restated as scope law)

Deliverable ladder = adoption ladder = build ladder: **artifacts first**
(banner matrix, video content — nothing ships in the user's binary),
**tuning always**, **shipped widgets when trust is earned**. Three standing
refusals: not a general design tool (assets are imported, not drawn — the
parametric wave stays parameters), not an app builder (no navigation, no
state, no data binding beyond parameters), not a runtime platform (no
server-delivered scenes in v1).

## Rejected and reversed, with reasons

- **An editor-process (interpreted) canvas** — dissolved by pillar 2: it can
  never inherit the app's ambient stack, and it is a second renderer waiting
  to diverge (the `Material` bug is the proof in miniature).
- **Rasterized external nodes** — reversed by the same spike: liveness and
  theme come free once the whole canvas is the guest's.
- **`emit(parse(f)) == f` as the single invariant** — replaced by the triple.
- **Annotation registration** — const mockups; **config-builder
  registration** — needs exactly the machinery a preview entry already has.
- **`double?` as hug** — replaced by per-axis fixed/hug/fill.
- **A `DoubleTapGestureRecognizer` on the canvas**; **always-on human-beat
  capture** — both reversed on first human contact with the real surface.
- **Flavor-blind fixture launches** — not scene work, but the discovery paid
  for it: `default-flavor` broke every macOS launch of the example under the
  pinned SDK (workaround shipped; proper fix tasked separately).

## Open questions

1. **Node naming** — `Frame`/`Text` collide with Flutter's names the moment a
   scene file is compiled against material. `SceneText`-style names, or no
   material import (which costs `Color`'s spelling). Must be settled before
   any real file ships; renames after are exactly the migration the format
   avoids.
2. **The parameter grammar** — sketched in prose, unwritten in the parser.
   The one widening; write it next to the save/load wiring.
3. **The note field** — comments' replacement; shape undecided.
4. **Zoom fidelity** — the texture blurs past 1×; resolution-tracking resizes
   (blur-then-sharpen) are the known pattern, unbuilt.
5. **Palette curation** over the generated SDK catalog — generation supplies
   data, curation supplies the product; nobody has curated yet.
6. **Breakpoint variants** — flex survives resize but does not respond to it
   (the tablet finding); responsive means variants, and variants are
   undesigned.
7. **The text layer stack** — one content, N paints; the gorgeous-text
   subproject is untouched beyond its framing.
8. **Undo's mechanism** — command log vs snapshots; decided *that*, not
   *how*.
9. **Window capture of spike guests** — agent screenshots show a hole where
   the composited canvas is; the live window is fine.
10. **The headless twin** — the tester lane rendering the same scene JSON for
    export; asserted by architecture, unbuilt.

## What to do next

1. **Wire persistence into the composited editor** — save/load through the
   round-trip engine, plus `fw scene check`. Closes the loop between two
   finished spikes; small.
2. **The parameter grammar and one parameterized scene** rendered at two
   argument sets — the crux feature, exercised before any UI exists for it.
3. **Then the first deliverable end to end**: the coffee banner exported
   across the language×device matrix through the headless twin, which is
   where the translations index, the axes machinery and open question 10
   meet reality.

Motion v2's own next steps are unchanged; it arrives as a layer on this
document's ground, and nothing measured this week moved anything it settled.

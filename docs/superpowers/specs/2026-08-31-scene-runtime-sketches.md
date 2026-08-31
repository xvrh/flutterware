# Scene runtime — drive, notify, and the slot: sketches 8–12

**Date:** 2026-08-31
**Status:** round two of the parameter sketches, opened by three owner
questions: *can the edit API of a scene drive the animation? can property
writes auto-notify (with optimization) so the widget updates itself? and
what does a direct widget — or another scene — as a parameter look like?*
Three probes ran for real (quoted verbatim); the sketches around them are
unexecuted Dart written carefully. Nothing is decided.
**Leans on:** `2026-08-31-scene-parameter-sketches.md` (sketches 1–7 and
the widget-vs-model fork), `2026-08-28-motion-v2-design.md` (the law, the
composition rule), `2026-08-31-remote-canvas-spike-findings.md` (the
415-node flat frame).

**The probes, first:**

```
burst: 1000 writes -> 1 notification(s), 50 node(s) were dirty
drive: 60 frames x 3 writes -> 60 notification(s)
no-op writes -> 0 notification(s)

construct+touch 11-node scene: 0.11 us/instance

this.hero = HeroCard()  ->  Error: Constant expression expected.
```

The third is load-bearing for sketch 10: **a scene can never be a default
value**, because default values must be const and a class with `late final`
fields cannot have a const constructor — the same rule that makes the
hot-reload trap unwritable now forces the mock off the parameter. The
second says a full 415-node tree constructs in ~10µs against a 16,667µs
frame budget: *construction is never the cost, anywhere in this design.*

---

## Sketch 8 — the edit API and the animation: one pipeline, two planes

The question has three readings, and they get different answers.

**(a) Can the app animate by mutating? Yes — it is the escape hatch, and
auto-notify makes it real.**

```dart
controller.addListener(() {
  scene.glow.opacity = 0.6 + 0.4 * pulse.value;   // auto-notifies, coalesced
});
```

Measured above: sixty frames of writes produce sixty notifications, one
per frame, and writes that change nothing cost nothing. The law is
untouched — *a Motion is a pure function of `t`* governs the Motion
system, not what user code may do with a mutable model. Simple imperative
animation needs no motion file at all.

**(b) Can the Motion system apply its output through the same writes? No —
refused by the Save test.** Every write the edit API accepts is a write
Save persists. If `evaluate(t)` wrote its output into authored properties:

- a Save mid-play would capture frame state into the file — a
  shredder-class bug, the mid-breath opacity of an ink ripple committed as
  the authored value;
- composition would eat its own operand: the rule is
  `value = base op contribution`, and a writer that stores its result in
  `base` has destroyed what the *other* writer composes over. Two writers
  on one property — the design's most ordinary case — becomes impossible.

So the model has **two planes**: the **authored** plane (persistent, the
editor's and the app's retunes, what Save reads) and the **evaluated**
plane (per-frame, composed over the authored value by the operator table,
never saved). The provenance pattern again, this time on the value itself.

**(c) Can the two planes share one mechanism? Yes — that is the actual
unification on offer.**

```dart
// The same handle, a different plane:
scene.glow.opacity = 0.8;        // authored: persists, Save sees it
scene.glow.fx.opacity = 0.3;     // evaluated: composed over 0.8 this
                                 // frame, invisible to Save
```

The `fx` overlay rides the identical dirty set, flush, and wire (the guest
apply payload carries `{scene, fx}`); the renderer computes
`base op fx` per the derived operator table; motion's applicator writes
only `fx`. And the overlay is not motion-private: the *app* writing `fx`
gets cosmetic, non-persistent effects (a hover glow, a drag highlight)
through the same door — a fourth consumer.

A simpler alternative was considered and kept as fallback: a per-frame
**presentation clone** (construct authored, apply evaluated onto the
clone, render the clone) — affordable at 10µs, and the guest already keys
widget state by *name* rather than object identity, so clones render
stably. The overlay is preferred for producing no garbage and keeping
object identity for the editor; the clone is the shape to retreat to if
overlay plumbing grows arms.

## Sketch 9 — auto-notify, and where the optimization actually is

The shape, probed above:

```dart
sealed class SceneNode {
  SceneDocument? _doc;              // set when placed
  double _opacity = 1;
  double get opacity => _opacity;
  set opacity(double v) {
    if (v == _opacity) return;      // no-op writes are free
    _opacity = v;
    _doc?.markDirty(this);          // adds to the dirty set,
  }                                 // schedules ONE flush
}
```

**Findings:**

- **The optimization that matters is coalescing, and it is the mechanism
  itself** — a thousand writes in a burst are one notification, because
  `markDirty` schedules a single flush. There is no naive version to
  optimize later; the batched version *is* the simple version.
- **Per-node invalidation is deferred, on evidence.** The remote spike
  measured the guest frame **flat from 11 to 415 nodes** — the full
  re-apply/rebuild path does not scale with node count at poster scale —
  and construction is 10µs. The dirty *set* is plumbed from day one (it is
  how `markDirty` works), so targeted rebuild/`markNeedsPaint` per node is
  a consumer of existing data whenever profiling ever asks for it; nothing
  is rebuilt to add it.
- **The flush must be frame-aligned, not microtask-aligned, in Flutter** —
  a microtask can fire mid-build, and notifying listeners during build is
  the `setState during build` error. The probe's microtask proves the
  coalescing shape; the real flush schedules for the next frame.
- **The uniform bag pays a third time**: the setters live once, on
  `SceneNode`, for every geometry and styling property of every node kind.
  A typed-content property (a Text's string) writes the same `markDirty`.
- **This closes the fork harder.** Sketch 4's fork (scene as Widget vs
  scene as model behind `SceneView`) now has a second structural argument
  for the model: auto-notify needs an owner pointer and mutable state on
  the nodes — a Widget can be neither the owner nor mutable. And the
  explicit `notify()` from sketch 5 disappears; the app just writes.

## Sketch 10 — a widget or a scene as a parameter: the slot, forced into
## the better shape

The probe's refusal decides the spelling. The mock cannot be the
parameter's default value (not const-able), so the parameter is a nullable
hole and **the mock lives on the node field**:

```dart
class OnboardingPage1 {
  OnboardingPage1({this.title = 'Welcome back', this.hero});

  final String title;
  final Widget? hero;                 // or `Scene? hero` — see below

  late final heroSlot = Slot(hero, mock: Use(HeroCard(title: title)));
  late final caption = Text(title, fontSize: 34);
  late final root = Frame(children: [heroSlot, caption]);
}

// The app fills the hole; the poster and the editor never do.
OnboardingPage1(title: t.welcome, hero: Image.asset('assets/hero.png'))
```

**Findings:**

- **Dart's const rule forced the design that was wanted anyway.** As a
  default value the mock would be an opaque constant. As a node it is
  *editable on the canvas, rendered by the export matrix, addressable by a
  motion* — the crux sentence ("typed holes, with the mockup as the
  default value") made literal, with the mock in the one place all three
  consumers can reach it.
- **`Slot` returns, meaning less than it used to.** Motion v2's `Slot`
  carried the whole attachment story and dissolved into scene nodes. This
  one means exactly "a hole with a mock": a node kind whose content is
  *either* its mock (nothing injected — editor, matrix) *or* the caller's
  filler (runtime). Child provenance, previously a table row, now has a
  spelling.
- **`Widget?` and `Scene?` fillers differ in exactly one way.** A widget
  filler is opaque: rendered natively, imposed-only for motion — an Ext
  the caller supplied. A *scene* filler keeps its declared surface: typed
  parameters, intrinsic access for motion, internals still sealed. A
  scene-typed slot with a scene mock is **instance swap** — the last
  component-property kind from the UX research (text, boolean, variant,
  *instance-swap*) arriving through the same door as everything else.
- **The grammar widening is one item**: `Slot(<paramName>, mock: <node>)`,
  where the mock is any node expression including `Use(…)`. The parameter
  type vocabulary in formals grows by `Widget?`/`Scene?` (and the class
  names of known scenes).
- Motion: imposed properties work on the slot node regardless of filler;
  intrinsic tracks address the *mock or scene filler* only — the runtime
  surprise ("animated against the draft, dead on the real widget") is
  exactly motion v2's known footgun, and the slot is where its
  *not-seen-read* reporting will point.

---

## Sketch 11 — should parameters be non-final? The three coherent designs

The owner's closing question: is there an advantage to scene *parameters*
(not node properties) being non-final, auto-notifying on change? Probed
first, because there is a bite:

```
// String title;  late final headline = Text(title);
s.title = 'Hello';
param: Hello / node: Welcome        // ← stale: late final captured a value
```

**A plain mutable parameter is a lie.** The `late final` node initializer
snapshots the value on first access; mutating the field afterwards updates
nothing, and worse, the scene becomes *incoherent* — the parameter reports
one value while the node it feeds shows another. So "just drop `final`" is
not one of the options. The real options are three:

**(A) Parameters stay final — configuration, not state.** Runtime control
goes through node mutation (`scene.headline.text = …`), which sketch 9
already made live.
*Pro:* zero machinery; parameters keep the semantics every constructor in
Flutter has.
*Con:* incoherence by another road — after `headline.text = 'Hi'`,
`scene.title` still answers the old value, so the declared surface and the
rendered truth diverge. And for a **nested** scene it fails structurally:
an instance's internals are sealed (the round's own law), so its
parameters are the *only* legal write surface — final parameters make a
sealed instance uncontrollable at runtime except by instance swap, which
is exactly the motion-rebind hazard sketch 5 documented.

**(B) Parameters mutable, with re-derivation.** A setter that rewrites the
nodes that consumed the parameter. The dependency map is statically known
(the parser sees every parameter identifier), but at *runtime* it must
exist in compiled Dart — meaning tool-emitted derived setters in the scene
file. *Con:* that is generated boilerplate inside the model file, a second
statement of truth the grammar must police, and the one direction this
design has refused at every previous door. Dead unless both other options
fail.

**(C) The field stays final; the value inside is live.** A parameter is a
box:

```
final Param<String> title;          // final field, mutable value
late final headline = Text(title);  // the node stores the box
s.title.value = 'Hello';
param: Hello / node: Hello / notified: 1
```

Staleness is impossible by construction — the node holds the box, not a
snapshot — and the box is where auto-notify hooks, riding the same dirty
pipeline. *Pros:* coherence (one door, parameter and node can never
disagree); the nested-scene control story works (a sealed instance's
public boxes *are* its runtime surface — Rive's view-model binding,
arriving as plain Dart); binding without instance swap (a long-lived scene
under a long-lived motion, values flowing through — the rebind hazard
never fires); and the caller can hand over a *shared* box
(`title: cart.headline`) for app-state binding with no framework. *Cons:*
every param-feedable node property becomes value-or-box typed (content
provenance turning from a display fact into a runtime type — real model
weight); two-level spellings in cascades (`.title.value =`); and the
constructor needs an initializer list (`: title = Param(title)`) so bare
values stay ergonomic at call sites — one more grammar item.

**The recommendation:** never (B). Ship **(A)** first — the export matrix
and the onboarding mount construct-and-forget, so v1's deliverables never
mutate a parameter post-construction — but design the node property slots
as value-or-box from the start, because **(C) is where the owner's
runtime-control requirement lands** the moment a nested sealed instance
needs live control or a binding must survive without an instance swap. The
box is additive: (A)'s files are valid (C) files with every box holding a
literal.

## Sketch 12 — all-in mutability: where the cons actually live

The owner's follow-up: assume full auto-notify and make *everything*
mutable — properties, nodes, collections — so an instantiated scene is a
fully live document and every change shows on screen. What are the cons?

The split that organizes the answer: **the property plane is already won**
(sketches 9 and 11 — mutable, coalesced, coherent, cheap), and none of the
serious cons live there. They all live in **structural** mutability —
`children.add/remove`, reparenting, runtime-born nodes. Five, by severity:

1. **The door moves from parse to every mutation site.** The parse door
   enforces unique names, one parent, no cycles, root-not-a-child — once,
   collecting, refusing whole documents. Naked `children.add(n)` must
   enforce all of it per call, with doc-wide context, at runtime — and a
   runtime violation has no collecting-refusal analogue: it either throws
   (an app crash from a listener) or silently auto-fixes (reparent-on-add
   — magic). The format's whole integrity story currently lives at one
   door; full structural mutability distributes it everywhere.
2. **Runtime-born nodes break name-as-identity.** A node added at runtime
   has no field, so no name — and the wire, the rects, the hit targets and
   motion targeting all key on names. A second identity scheme for
   dynamic nodes is exactly the dual-identity mess the field decision just
   cleaned up.
3. **The silently dead lane returns.** A motion holds typed references
   into the scene; `remove(headline)` leaves `headline`'s tracks animating
   a node no longer in any tree — no compile error, no refusal, nothing.
   Structural mutation reintroduces at runtime the failure mode typed
   fields were chosen to kill.
4. **The scene stops being a value.** Today an instance's state is
   derivable from `(class, args)` — two instances differ exactly by their
   arguments, which is what makes diffing, comparison, "what changed", and
   undo-as-transactions tractable. Arbitrarily mutated instances are
   arbitrary documents; every tool that reasons about scenes weakens.
5. **Reach-inside returns through the runtime door.** Nested scenes are
   objects with public fields; a fully mutable graph lets the app do
   `page.heroSlot.mock.headline.color = …` — Figma's override-anything,
   reborn at runtime. Nothing persists, so it is less fatal than Figma's
   version, but the sealed-internals law becomes a convention the object
   model itself contradicts, and motion/editor tooling that validates
   against declared surfaces starts lying.

Plus three mechanical costs, real but payable: observable collections
(plain `List` cannot notify, so custom list/map types appear in every
signature and every list method needs forwarding); a re-entrancy rule
(writes from flush listeners are feedback loops — refuse or
converge-detect); and an expectation gradient — a fully live object model
invites derived relationships ("this width is half of that"), which is a
constraint system knocking on a design that deliberately has no
expressions.

**The mitigation is the design's own oldest line.** Retune freely;
restructure through a door. All properties and parameter boxes mutable
with auto-notify — that is the all-in worth going. Structure changes go
through *document operations* (`doc.add(parent, node, name: …)`,
`doc.remove`, `doc.move`) rather than naked collections: an operation can
validate the invariants, mint the name, notify, dangle-check motion
targets, and record itself for undo — everything a bare `List.add` cannot.
The five cons above are not costs of liveness; they are costs of
*structure without a door*.

### Corrected by the owner: the question was runtime-only

The list above conflates two planes, and the owner's clarification —
*mutability is for the runtime, not for edition* — collapses it. Names,
the wire, rects and Save are the **editor's** data plane; a shipped app
has none of them, and runtime identity is the object reference. So for a
runtime instance, cons 1 (the naming half) and 2 are **withdrawn**, con 4
shrinks to "cloning a mutated instance needs a real `copy()` — construct
no longer reproduces it," and con 5 shrinks to convention. What stands:

- **two invariants Flutter enforces violently** — a cycle is infinite
  recursion at build, a node under two parents is a duplicate-GlobalKey
  exception mid-frame — so `add`/`remove` must check them to fail with a
  named error instead of a framework crash;
- **silent dangling on structural removal** (con 3, unchanged): a motion's
  typed reference keeps animating an unmounted node; judging-by-running is
  the planned mitigation, not a mutability restriction;
- the mechanical three (observable collections, the re-entrancy rule, the
  expectation gradient).

A runtime-restructured scene being beyond what the file can express is
**not** a con — the file authors the starting point, the app owns the
instance, exactly as with any widget tree built in code. And the shape has
strong precedent: a fully mutable object graph with `markNeeds*` batching
is Flutter's own render tree. The clean resolution, since the editor's
document and the runtime instance are one class: **the class is maximally
mutable; the editor brings its own door** — the operation layer it needs
anyway for undo, name-minting and round-tripping — while the app uses the
raw graph and pays only the two runtime costs above.

### What is engineering, and what is irreducible

Pressed once more — *which pushbacks are not fixable?* — the surviving
list sorts almost entirely into the fixable column: the two violent
invariants (checked operations), observable collections (tax), the
re-entrancy rule (an assert), the mutated-instance clone (`copy()`).
What remains, unfixable in kind and only manageable in degree:

1. **Aliasing.** Shared mutable state is action at a distance: two holders
   of one instance, and one's writes are the other's surprise; "who set my
   opacity" has no local answer. Debug-mode write provenance makes it
   *debuggable*; nothing makes it absent. (It is also the binding feature
   — a shared `Param` box is aliasing *on purpose* — which is exactly why
   it cannot be engineered away.)
2. **Loss of derivability.** A mutated instance's state is
   history-dependent — never again reproducible from `(class, args)`.
   Snapshots and journals patch specific needs (repro, persistence,
   comparison), but the property itself is spent the moment the first
   setter runs.
3. **No static safety for structure.** A runtime removal orphaning a
   typed reference, an invariant broken by a bad add — these move from
   compile/parse time to runtime detection permanently. They can all be
   made *loud*; none can be made *impossible*.
4. **UI-thread confinement.** A mutable object graph cannot cross
   isolates or be mutated off-thread; an immutable value could. Dart-level
   and, for objects that exist to be rendered, mostly theoretical.

Flutter's own render tree lives with 1 and 3 for the same reasons; the
editor keeps derivability where it is load-bearing (files, documents); and
4 is the domain's natural habitat. These are the honest prices of the
all-in, and they are prices, not blockers.

## Round-2 scoreboard

- **The edit API can drive animation** as the app's escape hatch (measured
  working shape), **cannot** be Motion's semantic write target (the Save
  test + the composition operand), and **should** share its whole
  mechanism with motion through the `fx` overlay — one pipeline, two
  planes, four consumers (editor, program, app, evaluator).
- **Auto-notify is the design**, not an optimization pass: setter →
  dirty-set → one frame-aligned flush, no-ops free, coalescing measured.
  Per-node invalidation stays a documented consumer of the dirty set,
  unbuilt until profiling asks.
- **Widget/scene parameters are slots**, with the mock forced onto the
  node field by the const rule — and better there. Instance swap falls
  out.
- **The fork tilts further to (ii)** — scene as live model behind
  `SceneView` — now needed by auto-notify's owner pointer, not just
  preferred for cascades.

**Newly open:**

1. The `fx` overlay's exact shape — sparse per-node map vs a parallel
   bag — and whether `node.fx.opacity` or `motion-internal only` is the
   app-facing spelling.
2. Flush timing details: writes arriving *during* a build (legal? deferred
   to next frame? asserted against?).
3. `Scene` as a grammar type name — the formals vocabulary now names scene
   classes; the same `show`-combinator reasoning should cover it.
4. Whether a slot's filler can itself be observed by the editor when the
   app runs under drive (the run cockpit showing the filled state while
   the canvas shows the mock).

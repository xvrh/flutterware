# Nested scenes and parameters — what five systems settled, and the laws to take

**Date:** 2026-08-31
**Status:** desk research, not measurement. Claims about the reference systems
come from working knowledge as of early 2026, spot-verified against vendor
documentation and public forums where marked ⁽ᵛ⁾; nothing was re-tested
hands-on. The *proposals* at the end are for the owner; the *findings* are as
solid as their sources.
**Leans on:** `2026-08-31-scene-v1-design.md` (the ground),
`2026-08-31-motion-on-scene-ground.md` (the fold — nested motion's clock story
lives there), `2026-08-28-motion-v2-design.md` § *What each reference system
actually does* (the motion-side reference table this complements).

## Why nesting and parameters are one research question

A nested scene instance with overridden text **is a scene call with
arguments**. Figma spells it components/instances/overrides; we spell it a
constructor invocation — but it is the same object: a reusable definition, a
use site, and the delta the use site is allowed to carry. Grammatically the
two halves are one construct: the parameter grammar (scene v1's next step 2)
is the *declaration* side, and a nested-scene reference is the *call* side.
Designing one without the other is designing half a function — which is why
this research was pulled ahead of the grammar.

## The eight questions

1. **Enter-to-edit** — how do you open a nested thing to change its innards,
   and does editing happen in place or elsewhere?
2. **Instance legibility** — how does the surface show *this is a use, not
   the definition*?
3. **Overrides** — what does an overridden value look like, and how does
   reset-to-default read?
4. **The tunable surface** — is what an instance may change *declared* by the
   definition, or *discovered* by reaching inside?
5. **Nested time in the parent timeline** — how does a child's animation
   appear, and can the parent retime it?
6. **Driving from the parent** — how does a parent trigger or feed a child's
   animation?
7. **Depth** — what breaks at three levels?
8. **Propagation** — what happens to instances when the definition changes
   under them?

## What each system does

### Figma — components, instances, overrides

The instance inherits everything and may override properties locally; when
the main component changes, instances update **except for whatever was
overridden** — a field-level merge, not a version fork ⁽ᵛ⁾. Overrides began
as *reach inside anything*: deep-select into an instance's internals and
change text, fills, visibility. Figma has since retrofitted **component
properties** — text, boolean, instance-swap and variant props declared on the
component, surfaced as one clean controls section on the instance ⁽ᵛ⁾.

The retrofit exists because reach-inside does not scale, and Figma's own
forums document the tax ⁽ᵛ⁾: only first-level nested components surface
their properties on the outer instance; overrides on nested internals are
lost when the parent swaps variants; overrides stop registering as overrides
while still rendering. The failure mode is structural — an override addresses
an internal by identity, and the definition's internals are exactly what the
definition is free to restructure. **An override onto an undeclared internal
is a reference into someone else's private tree**, and it breaks the way such
references always break.

Enter-to-edit is a jump ("go to main component"), never in place; instance
edits in place are only overrides. Depth is where it hurts (Q7): the
first-level-only surfacing means deep composition forces either prop
plumbing through every level by hand, or reach-inside with the fragility
above.

### After Effects — precomps and Essential Properties

A precomp opens as its own tab — never edited in place — and the known depth
pain is navigation: tabs pile up and "which comp am I in" is a real question
the mini-flowchart never quite answered (Q1, Q7). A precomp is a **layer in
the parent's timeline**: a span, time-remappable by a lane, collapsible —
the model motion v2 already adopted for embedded nested motion (Q5).
Definition edits propagate to every use; there are no per-use structural
overrides at all (Q8) — per-use variation arrived late, as **Essential
Properties**: the *source comp declares* which of its properties are exposed,
and the parent adjusts exactly those on the layer, without opening the
precomp ⁽ᵛ⁾ (Q4, Q6).

That is the same retrofit as Figma's, from the opposite starting point:
AE began with *nothing* tunable per use and added a declared surface; Figma
began with *everything* tunable and is narrowing toward a declared surface.

### Rive — nested artboards, inputs, view models

A nested artboard is a component with its own animations and state machines.
The parent's way in is **inputs** — number/boolean/trigger declared on the
child's state machine and explicitly marked *exposed to the main artboard*;
the parent sees and drives exactly those ⁽ᵛ⁾ (Q4, Q6). Data binding
generalises the same shape: view models nest as properties, a parent passes
one down ⁽ᵛ⁾. Internals are not addressable from outside at all; editing the
child means opening its artboard (Q1). The child's timeline does **not**
appear inside the parent's — the child runs behind its state machine, the
parent sends triggers (Q5): Rive has the *trigger* half of clock provenance
and lacks the *embedded span* half, precisely mirroring AE, which has the
span and (before Essential Properties) lacked the inputs.

### Framer — property controls

Components declare property controls (typed, named, with defaults); an
instance is configured through the props panel and nothing else. Born
declared — there was never a reach-inside to retreat from.

### Flutter itself — the null hypothesis

A widget's constructor *is* its declared surface; internals are sealed by
the language; a rename is a refactor; per-use variation is arguments and
nothing else. The platform under all of this already enforces the strictest
version of the pattern — which matters, because a scene file compiles to a
widget, and any nesting semantics we invent must survive translation into a
constructor call.

## The one finding that towers over the rest

Four commercial tools, four different starting points, one destination:

> **The tunable surface of a nested thing is declared by its definition, not
> discovered by reaching inside it.**

Figma is retreating to it (component properties) and pays a public bug tax
for every step not yet taken ⁽ᵛ⁾. AE advanced to it (Essential Properties)
because zero-tunability made precomps copy-paste factories. Rive and Framer
were born on it. Flutter enforces it at the language level. There is no
counterexample among the systems anyone would want to copy.

For scene v1 this settles Q4 before any UI exists, and it settles it as a
**model law, not a UI preference**:

> **An instance's internals are not addressable. Its parameters are.**

And it hands over a unification for free: from the editor's seat, **a nested
scene and an external node are the same kind of thing** — rendered by the
guest, internals sealed, tunable exactly in a declared surface, spelled as a
call with args. The registration ladder's rung 2 (a preview entry's
grammar-shaped body defines the tunable surface) and a scene's parameter list
are the same declaration made by different authors. One inspector section,
one hit-target behavior, one grammar shape covers both — the fold document's
"arg-level animation on external nodes" and "a track on a nested scene's
parameter" become one feature, which is also exactly Rive's
parent-drives-inputs, arriving through our own front door.

## Proposed answers, question by question

Each is a proposal unless marked otherwise.

- **Q1 (enter-to-edit): open the definition as its own document.** A jump —
  like every system surveyed; none edits a definition in place from a use
  site, and the one that lets you *override* in place (Figma) is the one with
  the bug tax. In-place definition editing means two documents live on one
  canvas — v2 material at best. The jump is cheap for us: the editor already
  navigates by `fw://` routes.
- **Q2 (legibility): the boundary is the selection.** An instance gets one
  hit target and its selection stops at the boundary — which the editor's
  existing law gives us free, since hit targets derive from addressability
  and internals are not addressable. Distinct selection chrome for
  instances, and an "open definition" affordance on the selection.
- **Q3 (overrides): a parameter row shows value-or-default.** Unset shows
  the default (the mockup — already decided) visibly *as* a default;
  overridden shows the value with a reset control. Field-level merge on
  definition edits follows from the model: an instance stores only its args.
- **Q4 (tunable surface): declared parameters only, as law.** Above. No
  reach-inside override exists, ever — not as an escape hatch, because the
  escape hatch is where Figma's bug tax lives. The pressure it relieves
  ("I just want this one instance's padding different") is answered the
  Flutter way: promote a parameter, or fork the definition.
- **Q5/Q6 (nested time): both halves of clock provenance, because each
  reference system proves the other's absence hurts.** Embedded = a span in
  the parent timeline, retimeable by the parent (AE's precomp — already
  adopted by motion v2). Triggered = a marker plus declared inputs the parent
  drives (Rive). AE without inputs and Rive without spans are each half a
  tool; the fold's clock-provenance table already carries both modes, so this
  is confirmation, not new design.
- **Q7 (depth): depth is a navigation problem, not a nesting problem.** A
  breadcrumb of the open-definition path, and parameters do **not**
  auto-surface through levels (Figma's first-level-only surfacing is the
  honest version of this; their forums show users wanting more and the
  feature buckling ⁽ᵛ⁾). A level that wants to re-expose a child's parameter
  declares its own and passes it down — parameter plumbing, exactly as in
  code, visible in the file.
- **Q8 (propagation): definition edits propagate; parameter *removal* is a
  refusal at the call site.** An instance's args can only name declared
  parameters, so a definition restructuring its internals can never orphan an
  override — the Figma failure is unrepresentable. Removing a parameter that
  instances still pass fails at the parse door with a refusal naming both
  files, the same loud-beats-silent trade as everywhere else in the format.

## What this research deliberately does not answer

- **The timeline's visual design** — spans, folding, lanes. The *model* under
  it is settled (clock provenance, two machine scopes); the drawing is panel
  design work, after the fold's grammar exists.
- **Variants and breakpoints.** Figma's variants conflate enum-valued
  parameters with responsive states; scene v1 should not inherit the
  conflation. A variant axis may just be an enum parameter — but responsive
  variants (open question 6 of the design doc) stay undesigned.
- **The text layer stack** — untouched, still its own subproject.
- **Component *libraries*** — publishing, versioning, cross-project reuse.
  All five systems have one; scene v1's scope law (not a general design
  tool) keeps this out until a real consumer asks.

## Next

- The **parameter grammar** should be written as one pass over declaration
  and call, with the fold's parameter-seam question
  (`motion-on-scene-ground` open question 2) decided first.
- When the editor grows nesting, the four laws above — internals sealed,
  jump to edit, value-or-default rows, refusal on removed parameters — are
  the spec, and each traces to a named system's scar rather than to taste.

## Sources

Spot-verifications marked ⁽ᵛ⁾ above:

- Figma: [component properties](https://help.figma.com/hc/en-us/articles/5579474826519-Explore-component-properties),
  [editing instances with them](https://help.figma.com/hc/en-us/articles/8883757553943-Edit-instances-with-component-properties),
  and the nested-override fragility threads —
  [second-level nesting not surfaced](https://forum.figma.com/t/instance-and-property-overrides-for-second-level-nested-components/21511),
  [nested overrides lost](https://forum.figma.com/ask-the-community-7/issue-components-do-not-remember-nested-instance-overrides-16379),
  [overrides not registering](https://forum.figma.com/t/instance-overrides-are-not-showing-up-as-overrides/36727).
- After Effects: [Essential Properties](https://helpx.adobe.com/uk/after-effects/using/essential-properties.html),
  [workflow overview](https://blog.nobledesktop.com/learn/after-effects/essential-properties).
- Rive: [nested artboards and exposed inputs](https://help.rive.app/editor/fundamentals/nested-artboards),
  [data binding and nested view models](https://rive.app/blog/getting-started-with-data-binding).

# Motion v2 — a typed model the editor reads and writes, and the video tool above it

**Date:** 2026-08-28
**Status:** **brainstorm, not a decision.** Four rounds with the owner, no code
written, nothing measured. Some of this is settled enough to build against;
much of it is a first shape that needs another pass. Read the *How settled is
this* table before quoting anything here as agreed.
**Leans on:** `2026-07-31-motion-design.md` (v1 — the law, the API, the rejected
variants, the measurements; **read it first**), `2026-08-11-scenario-motion-capture-findings.md`
(deterministic frame capture, and the no-encoder decision this reverses),
`2026-07-26-ui-catalog-entry-model.md` (entries, axes), `2026-08-27-store-screenshots-design.md`
(the store deliverable).
**Prior art in-tree:** `app/lib/src/motion/values_file.dart` (parse-and-emit at
tier 1), `lib/src/motion/extent.dart` (says where a target is, and does nothing
else).
**Companion:** `2026-08-28-motion-v2-api-sketches.md` — seven speculative files
and the nine findings this document has been reconciled against.
**Prior art no longer in-tree:** `app/lib/src/drawing/` — the editor whose file
format was Dart, which v1 leaned on throughout — **has been deleted since v1 was
written.** Its lessons are quoted below from v1's spec; the code is not there to
read, so treat every claim about it as second-hand. Recovering it from git
history is worth an hour before the spike.

## What this is

Two things that turned out to be one thing.

1. **A rewrite of the Motion plugin** — the in-app animation editor — around a
   model that is *typed Dart the editor reads and writes*, with a scene of
   slots that real widgets are injected into.
2. **A video tool** — compositions, time transforms, an encoder — for which a
   Motion is one clip among several.

The reason they are one thing: a Motion is `evaluate(t) → values` either way.
The video tool is a scheduler and an encoder sitting *above* a Motion; it does
not change what a Motion is.

**But they are one law over two artefact kinds, and an earlier draft of this
document conflated them.** Writing file 5 of the sketches forced the
distinction:

| | **a motion file** | **a composition** |
|---|---|---|
| what it is | model | a program |
| who writes it | the editor, in the grammar | you, in ordinary Dart |
| may contain a loop | **no** — tier 3 | **yes**, and must |
| the editor's relationship | reads *and writes* | reads at most, to display a resolved schedule |

The forcing case: a composition that emits one segment per scenario step does
not know its cardinality until a run is in hand, so it needs `for`. A loop is
tier 3 and is banned from the grammar. The alternative was a declarative
`Repeat(over:, template:)` node — the first step down the slide toward tier 3 —
and it was not taken.

This is round two's line arriving from the other side: **the studio owns shape,
the program owns schedule.** It also explains a UI decision that had been
asserted without a reason — the studio's timeline shows program-owned spans as
locked, and they are locked because *they are someone else's code*.

## How settled is this

| | |
|---|---|
| **Agreed** | A machine is one mechanism at two scopes — motion-scope content is a `Motion`, slot-scope content is a property bag — spelled with a type parameter, and it widens the grammar not at all. Two writers compose like transforms; a property composes iff it reads non-null. The model is **not** `const` — tuning lives in field initializers, `.ms` is available, and each instance is a fresh tree. Motions nest, and the law is preserved under nesting. The v1 law survives: a Motion is a pure function of `t`, reads no clock. Code is the model — a limited declarative Dart subset, tool-owned file, round-trip identity fuzzed, refuse rather than approximate. The model is 100% typed: `m.title.opacity`, never `m.target('title').opacity`. A rename that breaks call sites is *correct* — a compile error beats a silent orphan. ffmpeg is an acceptable dependency for the video half. |
| **Leaning, with a reason** | Build the bind-onto-a-build-method host first and express the draft scene as a built-in host, so both tabs run one code path. Resolve-then-render, with cardinality, duration **and geometry** all frozen before frame zero. Immutable model, mutable draft for clone-and-tweak. Imposed vs intrinsic properties split by which constructor you reach for. |
| **First shape only — needs another pass** | Everything in the three code sketches below. The grammar's exact extent. Where layout lives. How the draft host and a real host share an interface. Whether `Track`/`Key` or `Seg` is the tuning unit. The whole video half beyond the shape named in the last section. |
| **Not discussed at all** | Audio beyond "declare, never record". 3D. Anything about performance. Migration mechanics for existing `MotionValues` files. What the panel looks like. |
| **Decided by writing the files** | Two writers on one property **compose like transforms**, and the operator is derived from the property's identity element — which turns out to be the partition v1 already drew for read-site nullability. |

Round four (2026-08-28) changed three things, recorded in their own sections
below: **slots are typed by an intrinsic bundle** rather than being one
undifferentiated `Slot`; **`dead` is decided by running, not by scanning** —
the owner rejected the scan and was right, and the claim made for it here was
too strong; and **a state system is admitted as a driver**, which is where it
costs nothing. The first closes two of v1's open questions. The third is
deferred but leaves one cheap reservation that must be made now.

**Nothing here is built.** Every number quoted is from v1's spikes or from
scenario capture, and is carried over, not re-measured.

## The law, unchanged

> **A Motion is a pure function of `t`.** `evaluate(t) → values`. No wall clock,
> no controller graph, no listeners in the model.

Everything v1 bought with this — one code path for scrub, play, headless
capture, filmstrip and golden frames at fixed `t` — is bought again, and
`fw run motion capture --t=`, `filmstrip`, and the `HeadlessCatalog` path all
survive the rewrite untouched. That is most of the existing agent surface, and
it is the reason a rewrite of the model is affordable at all.

The video half adds one phase in front of it and one behind it. Nothing in the
middle moves.

## Code is the model

### Three tiers, and which one this is

| tier | what it is | cost |
|---|---|---|
| 1 — data literal | one const expression rewritten by source offsets | **proven in-tree** (`values_file.dart`) |
| **2 — declarative construction** | a tree of constructor calls where nesting and ordering *are* the model; structural inserts and reorders | **the bet** |
| 3 — arbitrary Dart | loops, helpers, computed names | not editable, ever |

Tier 2 is a real step up from what is proven here, and it is the only part of
this design where failure is architectural rather than inconvenient. Every
previous attempt at code-as-model in the industry — Interface Builder, GWT
Designer, the old Android layout editor — died the same death: a human writes
something the editor cannot parse and the tool either destroys it or goes
read-only forever.

The owner has built this before and reports it working well. The four
mitigations, all of which are already this repo's instincts:

- **The file is generated and tool-owned.** Never a hand-written file. The
  `x.motion.dart` convention from v1 carries over, and so does its naming trap:
  **not** `.g.dart`, because this is a source of truth and a
  clean-and-regenerate must never eat it. Treat it like an `.arb`.
- **A written-down grammar, small enough to fuzz.** Below.
- **Refuse rather than approximate.** v1's rule, needing teeth it did not need
  at tier 1 because the surface is roughly twenty times bigger. v1 records the
  anti-pattern: the drawing plugin's `DrawingPath.fromCode` returned `null` on
  anything it did not recognise and the entry silently vanished. That file is
  gone from the tree, so this is quoted rather than verified — but *silent
  vanishing* is the failure mode to design against either way.
- **The invariant:** `emit(parse(f)) == f` for every file the editor accepts.
  Fuzz it. That single property test is worth more than the rest of the suite.

### The grammar, as a first cut

Permitted:

1. one class declaration extending `Motion` — **not** const; see finding 4
2. field declarations with initializers, types inferred
3. constructor invocations with named and positional arguments
4. literals — num, String, bool, null
5. collection literals
6. identifiers from a **declared allowlist** (`Curves.*`, `Colors.*`,
   `Alignment.*`, `Duration`, `Offset`, and the motion vocabulary's own enums)
7. references to the enclosing class's own fields — needed by the draft host,
   and cheaply checkable because the declaration is in the same file
8. a small allowlist of pure extension getters on numeric literals: `.ms`, `.s`
9. **enum declarations**, which a state machine forces — see below

Two rules the sketches added, both narrow and both load-bearing:

- **A `Track` must carry its type argument explicitly** — `Track<double>([…])`,
  never `Track([…])`. With it, the parser knows a track's value type **without
  resolving anything**, including inside a custom bundle whose class it has
  never seen. Without it, the editor cannot tell a track of doubles from a track
  of colours and cannot offer the right property editor. One token that keeps
  parse-never-resolve viable at the exact place it was going to fail.
- **A state enum must be declared in this file.** A machine's transitions name
  two states, and if states were fields a transition would have to reference
  `this.idle` from a sibling initializer — which Dart does not allow, and which
  is variant 2's chicken-and-egg returning in a new place. An enum is the only
  spelling that is typed and referenceable from a sibling. Parse-never-resolve
  then means the editor can only enumerate an enum it can *see*, so the enum
  lives in the tool-owned file. **Agreed 2026-08-28**, and the owner's reason is
  the stronger one: the alternative has *generated code importing yours*, which
  is the delicate direction. User code importing generated code is ordinary.

  Which flags a tension the sketches had not connected: **a user-declared value
  bundle already runs the delicate direction** — the motion file imports
  `chart_values.dart`. The specific hazard is a cycle, since your widget file
  imports the motion file to reach `m.chart`. So a custom bundle must live in a
  **leaf file that imports nothing of the motion's**, and that constraint should
  be documented at the extension point rather than discovered.

Note what item 8 costs. The model is **not** `const` (sketches finding 4), so
Dart no longer refuses a non-constant construct on the tool's behalf. **The
grammar is now the only thing limiting the file**, and a hand edit outside it
compiles cleanly into something the editor cannot read. That is the argument for
`fw motion check` in CI rather than as a convenience.

Refused, with an offset and a sentence that names the construct: method calls,
operators, string interpolation, conditionals, loops, `late`, anything not on
the allowlist.

Parse, never resolve — the same discipline as v1's scan.

### Comments, and the cost accepted

At tier 2, preserving freeform comments through a structural insert is hard
enough that it would compromise the round-trip invariant. **Proposal:** fully
regenerate the file, and make a comment a *modelled field* — a note per node,
round-tripped like any other value. You lose freeform comments; you gain an
achievable identity test. Stated as a cost rather than discovered as a bug.
Not agreed.

### The failure UI, which must exist on day one

*"This file uses Dart the editor cannot represent — line 47, a `for` loop."*
Not a crash, not a silent read-only. Rive and Figma never face this because
their format is binary; a diffable-Dart format pays this and it is worth it.

### An agent editing the file

Raised by the owner: v1 predates agents writing code, and an agent will want to
tweak the generated file.

This is an argument **for** the format, not a risk. An agent authoring animation
in typed Dart, checked by the compiler, is a far better surface than a binary
format or a JSON blob — it can write a motion with no editor running and be
wrong in ways that fail loudly. Two cheap additions make it work:

- **A header comment in every generated file** stating that the editor owns the
  file and what the grammar permits. Agents read those. So do humans.
- **`fw run motion check <file>`** — validate against the grammar, report
  offsets, exit non-zero. An agent verifies its own edit without the GUI, and
  CI enforces the invariant.

The hazard is not malformed Dart, which is caught. It is **valid Dart outside
the grammar** — an agent reaches for a `for` loop because that is good Dart. So
the refusal must teach: name the construct, name the line, say what the grammar
accepts instead. The same standard as the drive layer's refusals.

## Everything is typed, and a rename is a compile error

v1's identity was a string written once (`m.target('title')`), and generated
typed members were rejected twice — variant 2 and variant 6 — because a rename
**silently split a lane**.

Two things reverse that here.

**First, the scene moved into the model.** Variant 2 died because the read site
was hand-written user code, so a generated member created a chicken-and-egg
between two files: the stage could not introduce an anchor, because the anchor
had to exist before it could be referenced. With slots declared in the model,
the file is self-contained. The chicken-and-egg dissolves.

**Second, the failure mode inverts.** The editor owns the file, so a rename
moves the declaration and its tuning atomically — the data never orphans. Only
*external* references break, and they break at compile time. **Identity lives in
a symbol, and the compiler is the rename infrastructure.** A red squiggle is the
best failure mode in this space; a silently dead lane is the worst. The owner
accepts the compile errors deliberately.

Sweetener, zero blast radius because it is the tool's own file — on rename,
emit a forwarding getter for one cycle:

```dart
@Deprecated('renamed to titleFade')
Track<double> get fade => titleFade;
```

### What typing does *not* buy: the scan is still incomplete

An earlier draft of this document claimed that typed members make the
`wired` / `dead` / `untuned` states **provable**, because the analyzer can find
every reference to a member where it could never find every string. **That was
too strong and the owner rejected it.** It holds only under a *resolved*
analysis, and resolution is exactly what parse-never-resolve refuses — the
discipline that keeps the tool cheap and keeps it from needing a correct view
of the user's whole program.

Typed members do improve the scan. They do not complete it. v1's standing rule
stands: **never present the scan as complete.**

See *Judging by running* below for where judgement actually belongs.

## Sketch 1 — what the model file could look like

**Hypothetical.** Every name here is a first guess.

```dart
//@flutterware:motion=2.0
// Owned by the flutterware Motion editor, which reads and writes this whole
// file. A SOURCE OF TRUTH, not a derivative — do not regenerate, do not delete.
// Hand edits are welcome inside the grammar: constructor calls, literals, const
// collections, allowlisted constants and `.ms`. Anything else is refused with a line
// number rather than silently dropped. Validate with `fw run motion check`.

import 'package:flutter/material.dart';
import 'package:flutterware/motion.dart';

class OnboardingMotion extends Motion {
  final duration = 700.ms;

  // A bare lane. Nothing on screen, no binding, no extent ring — just a number
  // the screen reads. Spelled differently because it *is* different.
  final reveal = Track<double>([
    Key(at: 0.ms, value: 0),
    Key(at: 700.ms, value: 1),
  ]);

  final title = Slot<TextValues>(
    draft: DraftText('Welcome back'),
    opacity: Track<double>([
      Key(at: 0.ms, value: 0),
      Key(at: 260.ms, value: 1, curve: Curves.easeOut),
    ]),
    translateY: Track<double>([
      Key(at: 0.ms, value: 24),
      Key(at: 260.ms, value: 0, curve: Curves.easeOut),
    ]),
  );

  final email = Slot<BoxValues>(
    draft: DraftBox(width: 280, height: 48),
    opacity: Track<double>([
      Key(at: 120.ms, value: 0),
      Key(at: 420.ms, value: 1, curve: Curves.easeOut),
    ]),
    // Intrinsic — lives in the bundle, reachable only through a builder.
    values: BoxValues(
      fillColor: Track<Color>([
        Key(at: 120.ms, value: Color(0xFFF2F2F7)),
        Key(at: 520.ms, value: Color(0xFFFFFFFF)),
      ]),
    ),
  );

  // No intrinsic bundle: imposed properties only, binds to anything, and there
  // is no builder form — so a dead intrinsic lane is unwritable here.
  final cta = Slot(
    draft: DraftBox(width: 280, height: 52),
    scale: Track<double>([
      Key(at: 400.ms, value: 0.94),
      Key(at: 700.ms, value: 1, curve: Curves.easeOutBack),
    ]),
  );
}
```

Notes on the shape, all arguable:

- **The tuning is field initializers, and the model is not `const`.** Decided
  2026-08-28 — see the sketches document, finding 4. Constructor *defaults* must
  be constant expressions in Dart, so const and constructor-defaults are one
  package, and taking it would have banned `.ms` and made every field appear
  twice (once as a parameter, once as a declaration).

  **Tweak-by-argument is not lost, only unbilled by default.** A `late final`
  field assigned in the constructor, or an initializer-list `??`, restores it —
  initializer expressions need not be const. What it costs is the double
  declaration back for every field so parameterised, and a constructor body with
  assignments widens the grammar toward statements. So it is available, not
  emitted by default, and `edit()` stays the door.

  What *is* lost is the compile-time backstop that used to catch a construct
  slipping past the parser.
- **A `Track` is a list of `Key`s**, because several keys on one property *is*
  the keyframe case — v1's reason for a list per property, kept. v1's two
  disambiguating rules come with it and must be restated in the runtime docs:
  **hold** (before the first key a property is that key's value; after the last,
  the last) and **overlap** (an error the editor cannot produce and the parser
  reports).
- **`draft` should not be here at all.** Shown for continuity only; the fix is
  the next section, and this is the first thing to move out.
- The property vocabulary on `Slot` stays **closed and framework-owned** — v1's
  decision, and the reason nothing is generated. `Slot` is a framework class;
  `title` is a field. Autocomplete works on both halves without codegen.
- Open: whether `Key`/`Track` or v1's `Seg(start:, end:, from:, to:)` is the
  better unit. Keys compose better for editing; segments state intent better
  for reading. Not decided.

## Sketch 2 — instantiation and tweak

**Hypothetical.**

```dart
// The whole model is const. Instantiating costs nothing.
const onboarding = OnboardingMotion();

// Tweak by argument, because the tuning is the defaults.
const punchy = OnboardingMotion(
  duration: Duration(milliseconds: 420),
);

// Tweak deeply: a mutable draft, frozen on return. Typed all the way down —
// a rename in the editor breaks this line at compile time, on purpose.
final slower = onboarding.edit((d) {
  d.duration = 1200.ms;
  d.title.opacity.last.curve = Curves.easeInOutCubic;
  d.email.translateY?.scaleBy(1.5);
  d.cta.scale.shiftBy(80.ms);
});

// Derive a variant without touching the original — the model is a value.
final dark = onboarding.edit((d) {
  d.email.fillColor.setAll(const Color(0xFF1C1C1E));
});
```

The architectural claim this is really making:

> **The editor is a GUI over the same draft API a user can call.** Parse →
> draft → mutate → emit. Nothing the editor can do is unavailable to code,
> because the editor does it *through* the public API.

That makes the serializer testable with no GUI in the loop, and stops the API
rotting into whatever the panel happens to need — a failure this repo has hit
before, when the demos' `t` knob was mistaken for a capability
(`2026-07-31-motion-design.md` § *The estimate was wrong*).

Two things writing this API at depth settled:

- **Storage shape and edit shape may differ, and the draft is where they differ.**
  A state machine's transitions are stored in a map keyed by a
  `(from, to)` record — const-free, typed, and correct as storage. As an edit
  target that is a record literal in a subscript plus a `!` for the nullable
  lookup plus no way to add an edge that does not exist. The draft exposes a
  **find-or-create method** instead:
  `d.field.machine.transit(FieldState.idle, FieldState.focused).duration = 120.ms`.
- **The edit API retunes; it cannot restructure.** No call adds a slot, because a
  slot is a field on a class and only the thing that writes the file can add a
  field. This is not a gap to close:

  > **The editor owns what and whether. The edit API owns when and how much.**

  Which is the studio/program line arriving a third time, now between the file
  writer and the runtime. Three independent arrivals at one boundary is worth
  trusting.

The papercut this exposed: `d.card.inner.badge.scale.last` is five hops, and
`inner` compounds at depth on both the read and the write side. Dropping the
wrapper leaves nowhere for `at:`/`speed:`; forwarding needs codegen this design
does not have.

**File 8 bounded it.** Depth 3 did *not* make it worse, because a composition is
ordinary Dart and a local variable relieves it. In a **motion file** that move is
unavailable — no statements, so no locals, so every reference is written from the
root. The problem is therefore not *"deep paths are bad"* but **"deep paths in a
grammar with no locals are bad"**, and it is confined to one artefact kind. Which
suggests the mitigation is a grammar item — a `final` local at the top of the
class, referenceable by later fields — rather than a shorter API. Untested.

## The draft is a stage, and it lives in its own file

The sketch above puts a `draft` getter on the model. The host section argues the
opposite — *the draft scene is not a mode, it is a build method the editor
happens to have written* — and a build method is not a field on the model.
Putting it there says the draft is part of the animation, and it is not: **the
draft is a stage set, not part of the play.**

Four costs of leaving it on the model:

1. **Asymmetric ownership.** The model owns the draft host and not the real
   host, so one relationship has two mechanisms — a member for one, an
   annotation reference for the other.
2. **The model cannot be host-agnostic.** A motion destined only for a real
   build method still carries a draft, or the member is nullable and half the
   model is optional.
3. **You get exactly one draft.** But a phone draft and a tablet draft, a light
   and a dark, one with a string long enough to overflow, are all reasonable —
   and those are *hosts*, which pluralise, exactly as preview entries do.
4. **Layout leaks into the model.** A `DraftColumn` with padding is layout, and
   layout belongs to the host. Whenever a real host is mounted that layout is
   dead weight: live in one mode, ignored in the other — the same all-or-nothing
   smell the single `Slot` had.

One argument made against it does **not** hold, and is recorded so it is not
made again: *"the tab switch stops proving anything because the two tabs run
different trees."* The trees **should** differ; that is what the comparison is
for. What is shared is track evaluation, imposed-property application, box
measurement and resolve, and that sharing survives either placement.

**Proposed fix:** the draft scene is a **separate tool-owned file** —
`onboarding.stage.dart` beside `onboarding.motion.dart`. Both in the grammar,
both editor-authored, and the motion does not depend on the stage. The editor
can still author layout, which the video half *requires* since there is no app
and the scene is the deliverable; the model stays host-agnostic, which the
in-app half requires; stages pluralise; and the host section's claim becomes
true rather than aspirational:

> **A stage is a host the tool owns. A preview entry is a host the app owns.**
> Same interface, different ownership.

Two alternatives, neither taken. Draft scenes as hand-written entries is simpler
but gives up the editor authoring layout, which kills the video half. And
**stage and composition could collapse entirely** — a video composition already
*is* a scene with a timeline — which may be the real answer and is too clever to
adopt untested.

## Slots: imposed and intrinsic

> **A slot's animatable properties are exactly those a parent can impose.**

This is v1's rejected variant 3 promoted from dead idea to load-bearing law.
`opacity`, `translate`, `scale`, `rotate`, `clip`, `blur`, `elevation`, and
size-via-constraints are pure wrapper — they work on a real `TextFormField` the
tool has never seen. `fillColor`, `textStyle`, `borderRadius` are **not**
impositions; you cannot recolour an arbitrary injected widget from outside.

The footgun is silence: an intrinsic track animates against the draft and does
nothing on the real widget, with no error. **Proposal: make the unreachable
tier not exist in scope.**

```dart
// Imposed only. There is no value object, because the wrapper already applied
// everything. You cannot name `.fillColor` here — it is not in scope.
MotionSlot(m.cta, child: const FilledButton(child: Text('Continue')))

// Intrinsic in scope, and only here. `v` is typed by the slot — see the next
// section, which is where the two constructors stop being a convention.
MotionSlot(m.email, builder: (v) => TextFormField(
  decoration: InputDecoration(filled: true, fillColor: v.fillColor),
))
```

To animate an intrinsic property you must have written the builder that receives
it, so the mistake becomes a place you had to reach for rather than a runtime
surprise.

The residual case — you took the builder and ignored `v.fillColor` — is not
caught by the type system, and is where *Judging by running* picks up.

## Slots are typed by their intrinsic bundle

An earlier draft had one undifferentiated `Slot`, and the owner's objection is
correct: it cannot tell whether a lane targets a `Text`, a `Container`, a
`TextStyle` or a raw progress value, and it is all-or-nothing — every slot
carries the whole vocabulary whether or not any of it applies.

The separating line is the one already load-bearing. **Imposed properties never
need a type** — working on anything is their defining property. **Intrinsic
properties are the only reason a slot needs to know what it is.** So there are
three field kinds, not one:

| field | what it is | binds to | builder form |
|---|---|---|---|
| `Track<double> reveal` | a bare lane; nothing on screen | nothing | n/a |
| `Slot logo` | a target, imposed properties only | anything | **none** |
| `Slot<TextValues> title` | a target with an intrinsic vocabulary | a widget that reads `TextValues` | `builder: (v) => …` |

The type parameter does real work:

- **The builder's argument type falls out of it**, so last round's
  two-constructors story stops being a convention and becomes type inference.
- **A bare `Slot` has no builder form at all**, so a dead intrinsic lane is not
  merely discouraged, it is unwritable — there is no `v` through which to name
  a property.
- The editor knows which property editors to offer, and the draft placeholder
  defaults from the bundle.
- The draft placeholder is itself a widget that consumes the bundle
  (`DraftWidget<V>`), which makes **the draft the first binding** — the same
  recursion as the draft scene being the first host.

Spelling is arguable: `Slot<TextValues>` versus `TextSlot`. The generic is
preferred for the first bullet only; the structure is what matters.

### A track is never null

Forced by writing the edit API, and it fixes a problem in two places at once.

If a slot's tracks are nullable — a slot need not animate opacity — then every
line of the edit API carries a `!`, and tuning something not yet animated
crashes. The obvious fix is a draft type whose accessors auto-vivify, and it
costs a **parallel type hierarchy**: every model class needs a hand-written
draft counterpart, and with no codegen in this design **a project defining a
custom bundle would have to write `ChartValuesDraft` too.** That is a large tax
on the extension point this section had just made cheap.

Remove the nullability instead:

> **A track is never null. An unanimated property is an empty track**
> (`Track.empty()`). A draft is then a plain mutable copy of the same shape —
> no vivification, no parallel hierarchy.

It does **not** collide with v1's rule that no-identity properties read as
nullable, because those are two different nulls: *the track is empty* is a
storage fact, *the evaluated value is absent* is a read-time fact. A property
with an empty track evaluates to `null`, and `?? Colors.white` at the read site
still works.

The cost lands on whoever writes a custom bundle, who must default each track to
`Track.empty()` in an initializer list rather than leaving it null. Slightly
ugly, and paid once per bundle.

### This closes two of v1's open questions

**Decomposition (v1 open Q3).** v1 left open that "`Matrix4` does not lerp
meaningfully and `TextStyle` is a dozen animatable dimensions in a trench coat",
wanting tuned sub-properties composed into a read. **A bundle is that.**
`TextValues` holds `fontSize`, `letterSpacing` and `color` as separate tracks
and the read site assembles the `TextStyle`. Nothing ever lerps a `TextStyle`.

**The extension point (v1 open Q4).** v1 recorded that a closed
framework-owned vocabulary means "a project cannot add `elevation`", and that
this "arrives as a demand in week three". It does not, because a custom bundle
is a plain hand-written class holding tracks — no codegen, no registration. So
**the imposed vocabulary stays closed** (framework-owned wrappers) and **the
intrinsic vocabulary is open** (values a widget reads). The only real contract
is that a track's value type must be lerpable.

The honest limit that comes with it: the editor can **tune** any track written
in the file, but can only **offer** a not-yet-used property for bundles it can
enumerate — a built-in table for framework bundles, nothing for custom ones. For
a custom bundle you write the field by hand once and the editor owns it after
that. Which is exactly v1's edit-loop steps 1–2, the declare-by-reading pattern,
unchanged.

## Judging by running, not by scanning

**Decided by the owner in round four, against the earlier draft.** Judgement
about whether a lane is consumed does not come from parsing user code. It comes
from watching the animation run.

The mechanism is already proven. v1's spike S5 result 3: the runtime *"reported,
unprompted, exactly what the last build read"* — `title.opacity, title.translate,
field.opacity, …` — and the conclusion recorded there is that **a getter on a
framework object is enough, no analysis, no annotation.** A value bundle is
exactly such an object. The instrumentation exists.

> **The scan offers. The run judges.**

The scan's job shrinks to enumeration — populating an "add a track" menu —
where incompleteness is a mild inconvenience rather than a wrong answer.

It has to be stated weakly, because **it is a lower bound and not a proof.** A
property read only under a branch that did not execute, or only at `t > 0.8`,
reads as unread. Two things make it usable:

- **Sweep `t` during detection** rather than sampling one frame. `filmstrip`
  already does this — one guest, N seeks, at v1's measured 0.05ms of seek added
  to a 16.6ms frame.
- **Union the read set across the session.** Every run — scrub, preview, test,
  capture — adds to it, so a property seen read once is never reported unread
  again. A weak signal that strengthens. Transient session state; nothing to
  persist.

Two consequences for the panel:

- **The state's name must change with its epistemology.** Not `dead` but
  something like *not seen read*. v1's three states were computed in the runtime
  rather than by each consumer, which is already the right home for this.
- **It must say against which host.** *"Read against the draft, never read
  against the real screen"* is precisely the injection bug this design most
  needs to catch, and it is only expressible because judgement is an observation.

**Deferred.** The owner wants thinking and experiment here before it is built.
Recorded now because the mechanism is proven and the placement is decided.

## A state system, and where it goes

Raised by the owner: a slot might have states — `idle` as a breathing loop,
others with transitions between them — and it is unclear whether that is the
same system, a subsystem, or a different thing.

**It is a subsystem, and it goes where the drivers go.**

The first thing to notice is that it has already been described in this document
under another name. The pose/transit/hold model in *The video half* — a pose is
a named static configuration with no duration, a transit is parameterised on its
own `u`, a hold is not authored because an idle has no shape — **is a state
machine.** A pose is a state, a transit is a transition, a hold is *stay until
told otherwise*. It was reached from the phone rig; the owner reached the same
structure from the slot side. Two independent routes to one shape is reasonable
evidence it is the right one, and it means this is **one** subsystem rather than
two.

The reconciliation with the law:

> **A state machine chooses which pure functions to evaluate and what local time
> to feed them. It never lives inside `evaluate(t)`.**

v1's *drivers* table already has the slot: self-playback, an `Animation<double>`,
the editor's scrubber, headless capture — each writes `t`, and only one needs a
ticker. **A state machine is the fifth row.** Nothing about what a Motion *is*
changes.

That placement is what resolves the seekability worry, because the two halves
need different things and both get them:

| | how the machine runs | seekable |
|---|---|---|
| **video** | at **resolve** time — inputs produce a concrete schedule (`idle 1.2s → transit 300ms → focused 0.8s`), then frozen | **yes**, and parallel and cacheable |
| **in-app** | live, on real events | **no** — and that is fine, because in-app playback never seeks |

Two levels of composition, worth separating because they are different
questions:

- **States over time** — the machine schedules which state is active.
- **Time within a state** — a state's *content* is itself a motion on its own
  local clock. `idle` is a looping breathe; `focused` is a settled pose plus a
  pulse.

And a state's local clock is a time transform of its parent's, which is **the
same `Sequence` primitive as the video half.** A real unification, not a
coincidence.

### The two scopes, settled

**Agreed 2026-08-28.** An earlier draft said per-slot, because a screen does not
have one state and the card and the button are in different ones. File 8 showed
that is true and insufficient — a real state usually spans slots (*presenting*
moves the device **and** the glow **and** the caption) — and that the reverse
fails too: if a machine sits on a slot, a state's content can only animate *that
slot*, so a content-**motion**'s own slots have nowhere to map, and the *"a state
is a motion"* justification for nesting contradicts the placement.

**They are one mechanism at two scopes, and the scope is decided by where the
machine is declared.**

| declared as | scope | a state's content addresses |
|---|---|---|
| a field on the `Motion` | the motion's slots | several slots at once — content is a `Motion` |
| `machine:` on a `Slot` | that slot's properties | one slot — content is a property bag |

The unification: **a state's content is a motion over the machine's scope.** At
slot scope that motion is degenerate — one anonymous slot, which is the slot the
machine is attached to — and `StateDef.properties(…)` is sugar for exactly that.
The evaluation algorithm is identical at both scopes: pick the active state and
transit, evaluate the content at its local time, compose the result over the
base. Only the address space differs.

So *"a state is a motion"* is true, with a qualifier the earlier draft omitted:
**a motion over the machine's scope**, which at slot scope is a property bag
wearing a motion's clothes. Nesting remains the enabling mechanism.

### It is spelled with a type parameter, not two classes

One class, and the content type is a parameter — the same move already made for
`Slot<V>`, and it stops you passing the wrong content:

```dart
class PhoneRigMotion extends Motion {
  // Motion scope: a field. Content is a Motion, with slots of its own.
  final rig = StateMachine<RigState, Motion>(
    states: {RigState.presenting: StateDef(content: PresentingMotion(), loop: true)},
    …
  );

  final caption = Slot<TextValues>(
    translateY: Track<double>([…]),
    // Slot scope: an argument. Content is a property bag over this slot.
    machine: StateMachine<CaptionState, SlotContent>(
      states: {CaptionState.nudging: StateDef.properties(
        loop: true,
        translateY: Track<double>([…]),
      )},
      …
    ),
  );
}
```

Both parameters are inferred from usage, so neither is written at a real call
site. A motion may carry **several** machines, each a named field with its own
enum — which is how the original per-slot argument (the card and the button in
different states at once) is satisfied without per-slot being the only option.

**The grammar needs nothing new.** Both spellings are constructor invocations
with named arguments, and enum declarations were already added for the state
enum. That is the main practical result of settling this: it does not widen the
file format at all.

### The full layer stack, which two scopes make necessary

With both scopes live, a single property can have **three** writers — its own
track, a motion-scope machine, and its slot's machine. The composition rule
handles the arithmetic; what it did not yet specify is the order. Base to top:

1. **the slot's tracks** — the slot's own choreography
2. **a motion-scope machine** — a global mode over everything
3. **the slot's own machine** — the most local mode

For every composable property this ordering is **irrelevant**, because × and +
are commutative and associative. It matters only for `replace` properties, where
the rule is *the more specific writer wins* and the stack above states what
specific means.

Two honest limits:

- **Specificity is a proxy for intent, and sometimes the wrong one.** A
  motion-scope `error` state setting a colour red loses to a slot-scope
  `focused` state setting it blue, which is arguably backwards. The system
  cannot know urgency; it can only know scope. Where the rule is wrong, do not
  write both.
- **Silence is the risk, so the panel must speak.** Any property with more than
  one writer should show its stack — *"3 writers: track + rig + caption →
  caption wins"*. This is the same surface as *not seen read*, and the same
  argument: a composition that resolved differently from what you expected is
  invisible until something says so.

### Recursion, permitted and untested

A state's content is a motion, and a motion may carry machines, so a machine may
appear inside a state's content. Nothing forbids it and the evaluation is
well-defined as long as every level is embedded. **Untested**, and the first
place to look if depth-3 state nesting ever behaves oddly.

**The hard part is blending, and it is hard.** Cutting from `idle` to `focused`
mid-breath must blend from *wherever the breath was*, not from `idle`'s start. So
a transition's `from` is a **snapshot of current output values** taken at
transition time, not a `t`. That is what makes the live case irreducibly
stateful — and equally why the resolved case is fine, since the resolver picks a
phase and freezes it.

### Nesting is in, and the law is what makes it safe

**Agreed 2026-08-28.** A Motion may contain Motions on their own clocks. The
justification is not taste, it is that purity survives it:

```
parent.evaluate(t)  →  u = transform(t)  →  child.evaluate(u)
```

Pure at every level, so seek, parallel render and golden frames survive
arbitrary depth. A state is therefore a motion, and the machine is only a
chooser — no parallel mechanism bolted alongside.

**The prior art is After Effects' precomp**: a composition used as a layer in
another composition, with its own timeline, which the parent may time-stretch,
time-remap and collapse. Everything the owner asked for — a transition that can
be slowed, accelerated and seen in the parent's timeline — is what a precomp
does, and its UI is settled by decades of practice: a collapsible group in the
parent timeline, time-remapped by a lane like any other.

### Provenance, which is now the design rather than a pattern in it

Clock provenance is the **third** the design has had to settle, and file 8 found
a fourth. All four are the same shape:

| provenance | the sources |
|---|---|
| **child** — what fills a slot | injected at runtime, or written in place |
| **box** — a slot's constraints | authored, measured, or host-supplied |
| **clock** — who drives a state's time | the child's own, or the parent's |
| **schedule** — when a machine's states change | authored in the model, or supplied by the program at resolve |

> A motion declares what it needs; a host provides it; **which** host provides it
> is settled at bind or resolve time.

Four independent arrivals at one shape. At this point it is not a pattern in the
design, it *is* the design, and it should be named once in the framework rather
than re-derived per feature. Schedule provenance is forced by the same case that
forced finding 2: a composition's timing derives from a scenario step's
duration, so the model cannot author it.

### Clock provenance — how a state hooks in

The owner's two modes.

| | **trigger** — the child's own clock | **embedded** — the parent's clock |
|---|---|---|
| parent may slow or accelerate it | no | **yes** |
| visible in the parent timeline | no — a marker | **yes** — a span |
| seekable from the parent | no | yes |
| contributes to parent duration | no | yes |
| needs resolving before video export | **yes** — pick a phase, freeze it | **no**, it is already pure |

The last row shrinks the resolve phase: **an embedded child needs no resolution
at all.** Only detached things do.

The constraint that explains the two modes rather than merely listing them:

> **A transition may live on the parent's timeline only if the parent knows when
> it starts.** Reactive states are detached by necessity; authored state changes
> may be embedded.

A hover transition cannot go on a screen's timeline — a hover happens at wall
time and the timeline has reserved no room for it.

### "When" and "how fast" are separate bits

Which produces a third mode that is not obvious and is probably the one most
worth having:

| | child sets the rate | parent sets the rate |
|---|---|---|
| **parent schedules the start** | place, do not stretch | **fully embedded** |
| **an event triggers the start** | fully detached | **rate-governed trigger** |

Bottom-right: the transition fires whenever the user hovers, but runs at the
rate the parent dictates. **That is what recording a demo video at 0.5× needs**
— the choreography slows because the timeline slowed, and the reactive
transitions slow with it instead of snapping past at full speed.

The mechanism is half-proven. v1's S5b measured that `timeDilation` freezes a
free-running `AnimationController` while `t` stays under host control — the
global version of parent-sets-the-rate — and v1 flagged its own defect: it is
global, so it also freezes anything the panel animates in the guest. The scoped
version is a small missing piece in Flutter itself:

> Flutter has `TickerMode` (enabled / disabled) but no inherited **rate**. A
> `MotionClock` inherited widget carrying a base and a rate gives a parent
> per-subtree governance without `timeDilation`'s blast radius, and it composes,
> because nested rates multiply — the same monoid as `Sequence`.

Worth spiking early. It is small, and it is the difference between *slow-motion
works* and *slow-motion works except for everything reactive*.

**Clock provenance must be declared, never inferred.** An accidentally-detached
child silently costs seekability, which is the one property the whole
architecture is buying.

## The host question: slot into a scene, or bind onto a build method

The owner's question, and the answer is *both* — but they must not be two
mechanisms.

| | **A — the scene hosts** | **B — the build method hosts** |
|---|---|---|
| owns the tree | the model | the app |
| where the child comes from | injected at runtime | written in place |
| where the box comes from | authored in the draft | measured from the real layout |
| what the editor shows | placeholders | the real screen |
| right for | video, where there is no app | in-app, where the tool may not write your build method |

The model is identical in both. The only differences are **child provenance**
and **box provenance**, and both are resolve-time facts.

> **Build B. Express A as a built-in host.** The draft scene is not a mode — it
> is a build method the editor happens to have written, whose boxes happen to be
> authored rather than measured.

Two reasons, one architectural and one about trust:

- **B is strictly harder** — a host you do not control, a tree you cannot write,
  boxes you must measure. Build A first and "the model owns layout" and "boxes
  are authored" get baked into the core, and B spends its life unwinding both.
- **The two tabs only mean something if they share a code path.** If draft and
  bound run different implementations, the bound tab proves nothing — it agrees
  with the first by luck. One host interface with two hosts mounted into it
  makes the tab switch a swap, and what you see in tab 2 is what ships.

There is also an expressiveness reason. A knows the spatial relationship between
slots and can author *"the card flies from where the thumbnail is to where the
detail sits"*. B can only do that if it **measures** — which is what `Hero`
does, and what `lib/src/motion/extent.dart` already does. v1's 2026-08-10 work
settled that a target's rect is *transformed, not measured*, and that the extent
is opted into separately from behaviour. **That is B's box-provenance mechanism,
already built.** Making B primary promotes it from a side feature to the spine.

## Sketch 3 — hosts and preview registration

**Hypothetical.**

```dart
// The real screen — an ordinary preview entry, and an ordinary widget. The
// motion is bound onto its build method (direction B).
@Preview(name: 'Onboarding', wrapper: wrapInApp)
Widget onboarding() => const OnboardingScreen();

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MotionScope(
      motion: const OnboardingMotion(),
      builder: (context, m) => Column(
        children: [
          MotionSlot(m.title, child: const Text('Welcome back')),
          MotionSlot(m.email, builder: (v) => TextFormField(
            decoration: InputDecoration(filled: true, fillColor: v.fillColor),
          )),
          MotionSlot(m.cta, child: const FilledButton(child: Text('Continue'))),
        ],
      ),
    );
  }
}

// Registering the motion itself. `host:` is what tab 2 mounts — a tear-off of a
// preview entry, so it is typed and survives a rename.
@MotionPreview(name: 'Onboarding entrance', host: onboarding)
Motion onboardingEntrance() => const OnboardingMotion();

// Direction A: the draft scene, with real widgets bound per slot. Typed, so no
// symbol keys and no string map.
@MotionPreview(name: 'Onboarding entrance (draft, real field)')
Motion onboardingEntranceDraft() => const OnboardingMotion().bind((b) {
  b.email.widget = (v) => TextFormField(
    decoration: InputDecoration(filled: true, fillColor: v.fillColor),
  );
});
```

What this buys, and it is close to free: **the editor's "real configuration" tab
is the previews lane**, with the real fonts, the real theme, and any device in
the table at that device's pixel ratio. The editor does not need a widget-hosting
story; it needs an `id` field. That is the cheapest part of the whole design and
it should be built early for that reason.

Open: whether `@MotionPreview` is its own annotation or a `@Preview` whose
return type is a `Motion`. The second is fewer concepts and probably right.

## Two writers on one property — decided

**Agreed 2026-08-28: compose like transforms.** This was the last blocking
question, and it had to be settled before the state system could be designed,
because file 8 showed it fires on the most ordinary usage there is.

### It is not an edge case

An earlier draft framed this as *two motions over one widget*, which sounds
rare. File 8 showed the same collision inside **one** motion on **one** slot: a
caption with a `translateY` track for its entrance and a slot-level machine
whose `nudging` state also writes `translateY` — which is just *"slide in, then
idle with a nudge"*.

> **Any slot carrying both tracks and a machine has two writers, always.**

### The operator is the property's own group

The rule generalises rather than being a table of taste:

> **A property composes in the group whose identity element is its default.**

Which means the per-property answer is *derived*, not chosen:

| property | default | operator |
|---|---|---|
| `opacity` | 1 | **×** — alpha multiplies, as in real compositing: two layers at 0.5 give 0.25 |
| `scale`, `scaleX`, `scaleY` | 1 | **×** — nested scales multiply, as transforms do |
| `translateX`, `translateY` | 0 | **+** |
| `rotate` | 0 | **+** |
| `blur` | 0 | **+** |
| `elevation` | 0 | **+** |
| `padding` | 0 | **+** |
| `color`, `width`, `height`, `borderRadius`, `textStyle` | none | **replace** |

**And the partition is one this design already had.** v1 split the vocabulary
for an unrelated reason — *"properties with a natural identity are getters
returning non-null (`opacity`→1, `translate`→zero, `scale`→1); properties with
no identity return nullable"* — to decide where `?? Colors.white` belongs at a
read site. That is exactly the composable/non-composable line. **No new
taxonomy: a property composes if and only if it reads non-null.** Two different
questions, one partition, and the second falling out of the first is the
strongest evidence available that the partition is real.

`progress` was the one apparent exception — default 0, but adding two of them
means nothing. It resolves by leaving: a raw number a widget interprets is a
bare `Track<double>`, not a slot property, under the three field kinds already
decided. The exception disappears rather than needing a rule.

One honesty note: additive `blur` is not physically what two blur passes do
(σ = √(σ₁² + σ₂²)). Values are composed and one blur is applied, so addition is
the predictable choice rather than the accurate one. Worth a line in the docs so
nobody reports it as a bug.

### Layers, and why ordering barely matters

Writers stack: **tracks are the base, a machine composes over them.** A layer's
contribution is always eased from its own identity, which gives one formula for
all three operators —

```
×        below × lerp(1, value, u)
+        below + lerp(0, value, u)
replace  lerp(below, value, u)
```

— where `u` is the transit's progress. For `replace`, "identity" is *the value
below*, which is why a transition's `from` must be a **snapshot of current
output** rather than a `t`; that requirement was already identified from the
blending case and this derives it a second way.

**Ordering only exists for `replace`.** Multiplication and addition are
commutative and associative, so for every composable property the stack order is
irrelevant and no rule is needed. Where it does matter, **the more specific
writer wins**: a slot machine over that slot's tracks, a slot-level machine over
a motion-level one. A mode overrides a transition into existence.

### One mechanism, both halves

This is the same rule as the video half's **additive layers** — author the
ambient float as a loop on one layer and the push-in as a transit on another,
and compose. The document previously promised that for the video half only while
this was an in-app case. It is one mechanism, decided once, or the same motion
composes differently in an export than it does in the app — the single failure
the whole architecture exists to prevent.

## A scope needs an id, and it is the one place typing cannot reach

Three instances of one `CardMotion` on one screen are three registry entries, and
the editor's `seekMotion` addresses one of them. v1's registry keys by id and its
demos had one scope each, so the question never arose.

`id:` on `MotionScope` is the answer, and it **reintroduces a string** — in the
one place the typing decision genuinely cannot reach, because these identities
are created by a runtime loop over data rather than written in a file. That is
acceptable, because it names an *instance* rather than a *property*, and the two
failure modes are different: a mistyped property key silently animates nothing,
a mistyped instance key addresses the wrong card visibly. But it should be a
deliberate exception rather than an oversight, and the panel has to show three
addressable rows where it shows one today.

Worth noting what did **not** collide: `HeaderMotion.name` and
`FollowButtonMotion.name` are different symbols on different classes, so two
motions on one screen need no scoping rule at all. Under v1's string identity
both would have been `'name'` in a shared registry. **That is a dividend of the
typing decision that nobody argued for in advance.**

## The video half, in one page

Unchanged from the brainstorm, and much less developed than the model above.

**A Motion is one clip.** The clip vocabulary is `{motion, image, video, app-run}`,
where an app-run clip is a scenario's captured frames — the C use case. The
scheduler sits above:

- **`Sequence` is to time what `Transform` is to space.** It offsets and scales
  the time origin for its subtree, so a clip authored in local time can be
  placed anywhere, and time transforms compose down the tree exactly as matrices
  do. `Loop`, `Freeze` and `playbackRate` are the rest of the algebra. A
  sequence **unmounts** outside its range, or every frame builds the whole film.
  Storage is `speed:`, which composes multiplicatively; but a caller knows the
  *target* length and the motion knows its *natural* one, so `Sequence` also
  needs a **`fit:` policy** — scale to fill, play-and-hold, or play-and-clip —
  or every call site computes `natural / target` by hand.
- **Resolve, then render.** The program runs over its dynamic inputs and emits a
  frozen schedule — clips, start frames, durations. **Cardinality, duration,
  geometry and the phase of any detached child all resolve here**, before frame
  zero. An *embedded* child needs no resolution — it is already a pure function
  of the parent's `t`. Then every frame is a pure
  function of `(schedule, frame)`: seekable, cacheable, and parallel across
  frame ranges on N processes. **Dynamism at resolve time, never at frame time**
  — the moment frame *n* depends on anything else, seek and parallel render die,
  and those are what the whole architecture is buying.
- **Studio owns shape; the program owns schedule.** A **pose** is a named static
  configuration and has no duration. A **transit** is how you get between two
  poses, parameterised on its own `u ∈ [0,1]` and therefore retimeable by
  construction. A **hold** is not authored at all, because an idle has no shape
  — its duration is whatever the resolver says. This is the answer to "how long
  do we idle at this position", and the reason it beats keyframes at absolute
  times is that **a keyframe timeline is not invariant under retiming**.
- **A render gate.** Remotion's `delayRender`/`continueRender`: no frame is
  captured while a ticket is outstanding. `Settle` waits for *frames to stop*,
  which is a different question from *has this ImageProvider resolved* — and the
  second one is what ships a blank logo in frame 1.
- **Audio is declared, never recorded.** Flutter has no offline audio graph.
  Clips contribute to a manifest and the mux mixes; volume may itself be a
  function of frame.
- **Two clocks.** A scenario's frames arrive at its fake-time cadence; the film
  has its own fps. The film asks a clip *what is your content at local `u`* and a
  scenario-backed clip answers with a nearest/hold sample against its recorded
  fake timestamps. **The mapping between the two clocks is itself an authored
  lane** — After Effects' time remapping — and it is what makes "freeze on the
  tap while the camera pushes in" expressible.
- **Additive layers**, from the game animation systems. Author the ambient float
  as a loop on one layer and the push-in as a transit on another, and compose
  them. Without this you author the cross product of every combination. **This
  is not a video-half mechanism** — see *Two motions over one widget* below,
  which is the same question arriving in-app.
- **Interpolate in the space the pose was authored in.** Camera positions lerp
  through the model in cartesian and must be spherical; rotations want
  quaternion slerp. Getting this wrong reads as *the tool is bad*.

### The encoder reverses a standing decision

`2026-08-11-scenario-motion-capture-findings.md` rejects ffmpeg explicitly — *no
encoder at all; frames on disk in the step's own format* — and that argument was
correct **for a scrubbable in-GUI player**, where a frame sequence played by a
widget beats an mp4. It does not transfer when the deliverable is the file: a
store preview video is an H.264 mp4 with muxed audio. The owner has accepted the
dependency. The old decision stands for the scenarios panel; this is a second
consumer with a different deliverable, not a reversal of the first argument.

## What each reference system actually does

Recorded because the reasons are not recoverable from the final shape, and
because three of them were considered and only partly adopted.

| system | where the data lives | how it retimes | what we took |
|---|---|---|---|
| **Remotion** | in the code — `interpolate(frame, …)` | `calculateMetadata()` computes duration from props before rendering | resolve-then-render; `Sequence` as a time transform; the render gate; audio declared not recorded |
| **Theatre.js** | a JSON blob the studio owns and you commit | externally driven `sequence.position` | the studio-owns-values idea, but in Dart rather than JSON |
| **Lottie** | baked keyframes at absolute frames | it does not — markers address a named range, and that is all | the dynamic-property/slot idea |
| **Rive** | authored timelines under a state machine | a state means *stay until an input fires*, so a hold is never authored | poses/transits/holds; inputs at resolve time |
| **Mecanim / AnimGraph** | clips as assets, blend trees, layers | blend duration is the universal glue | **additive layers**; post-evaluation override |
| **After Effects** | keyframes plus expressions | time remapping | the two-clocks lane |

The one formulation underneath all of them, and it is already v1's *drivers*
table: **an animation is a function of progress, and what drives progress is a
separate, swappable object.**

## Rejected and reversed, with reasons

- **v1 variant 2 and 6 — typed generated members — are reversed.** They died on
  a chicken-and-egg between two files, and on a rename silently splitting a
  lane. Putting the scene in the model removes the first; owning the file and
  letting the compiler catch external references removes the second. *Both
  reversals depend on the scene being in the model; neither survives without it.*
- **v1 variant 3 — the imposed/intrinsic distinction — is promoted**, from a
  rejected second attachment mode to the rule that makes injection sound.
- **v1 variant 4 — surgical edits into hand-written code — stays dead.** Blast
  radius zero is unchanged and is why the app's build method is never written by
  the tool, which is in turn why direction B has to measure.
- **Stable-id-plus-derived-field-name was proposed and rejected by the owner.**
  The field name is the identity, and a rename produces compile errors at the
  call sites. Deliberate: loud beats silent.
- **A symbol-keyed bind map (`bind: {#email: …}`) was rejected** for losing the
  typing that is the whole point. Binding happens in code, through the draft
  API.
- **One undifferentiated `Slot` was rejected** by the owner in round four: it
  cannot distinguish a `Text` target from a `Container` from a raw progress
  value, and it is all-or-nothing. Replaced by three field kinds, with the
  intrinsic bundle as the type parameter.
- **`const` was taken and then dropped.** The model was const so it could be
  "compiled data with no allocation"; the sketches showed const and
  constructor-defaults are one package in Dart, and that package costs `.ms` and
  makes every field appear twice. The allocation it saved was never hot — a
  motion is built at mount, not per frame.
- **A declarative `Repeat(over:, template:)` node was considered for
  compositions and rejected** as the first step down the slide to tier 3.
  Compositions are programs instead.
- **A draft type with auto-vivifying accessors was considered and rejected**: it
  needs a parallel type hierarchy, and with no codegen that tax lands on anyone
  writing a custom bundle. Non-nullable tracks removed the need.
- **"Typed members make the three states provable" was claimed here and
  withdrawn.** It holds only under a resolved analysis, which parse-never-resolve
  refuses. Judgement moved to runtime read-tracking, which v1 had already spiked
  and which this document had failed to reach for. *A design that had to be
  corrected by the owner twice in one round is a design still moving.*

## Open questions

Renumbered after the sketches pass. Three were closed by it and are recorded in
*Closed by the sketches* below.

1. **How the two artefact kinds meet.** Compositions are programs and motion
   files are model. What exactly can a composition read off a motion, and what
   does the editor display of a composition it may not write?
2. **The stage file.** Proposed above, unwritten. Does a stage need its own
   grammar, or is it the same one with a different root class? And does
   collapsing stage into composition turn out to be the right move after all?
3. **Comments as a modelled field**, or offset-preserving structural edits.
   Proposed the first; not agreed.
4. **The lerp contract for custom bundles.** A track's value type must be
   lerpable by something. `Lerp<T>` as an explicit contract, or lean on `Tween`?
5. **Migration.** Existing `MotionValues` files and `m.target('x')` call sites.
   The read-based API survives as the intrinsic tier, so most call sites should
   live — but nobody has checked.
6. **Cardinality and per-instance tuning.** A template per *kind* of segment,
   keyed on a stable id from the dynamic source — v1's open question 5 (*only
   named things may be keyed on*) recurring identically. That it recurs is
   evidence it is the right invariant.
7. **3D.** `flutter_scene` on Flutter GPU versus a perspective `Transform` over
   the vendored `device_frame`. The second covers tilt-and-push and fails only
   on a true orbit; determinism of the first under offline render is unproven.
8. **What *not seen read* costs to detect**, and whether sweep-and-union
   survives contact. The mechanism is proven; the ergonomics are not.
9. **What the editor shows for a machine.** Placement, nesting, clock
   provenance, the enum requirement, the two scopes and the layer stack are all
   settled; the panel is not. It now owes two things it did not before: a lane
   group per machine at two different nesting levels, and a writer stack for any
   property with more than one.
10. **`MotionClock`, the inherited rate.** Does a scoped rate compose with
   `AnimationController`, or does it need every descendant to take its time from
   the clock rather than a `Ticker`? The second is likely, and it bounds what a
   rate-governed trigger can govern: *motions*, not arbitrary Flutter animation.
11. **A `final` local inside a motion class?** The one mitigation for deep paths
   that fits the artefact kind that suffers from them. Widens the grammar by a
   statement-shaped thing, which is the direction to be careful in.
13. **Does `Slot<V>` or `TextSlot` read better**, and does the draft placeholder
   default from the bundle or stay explicit?
14. **A `fit:` policy on `Sequence`** — scale, hold, or clip. Small, and unwritten.
15. **A leaf-file rule for custom bundles**, so the one place generated code
   imports yours cannot form a cycle. Needs to be documented at the extension
   point, and possibly checked by `fw motion check`.

### Closed by the sketches

- **The two machine scopes — one mechanism, two scopes, a type parameter.**
  Decided 2026-08-28. Motion-scope content is a `Motion`; slot-scope content is
  a property bag, which is the degenerate one-slot case of the same thing. The
  grammar is unchanged.

- **The composition rule for two writers — compose like transforms.** Decided
  2026-08-28; the per-property table is derived from each property's identity
  element, and ordering turns out to matter only for `replace`.

- **May the tool own a type the user's code imports? Yes** — the state enum
  lives in the tool-owned file. Decided 2026-08-28 on the owner's reason: the
  alternative runs the *delicate* direction, generated code importing yours.
- **Is a machine per-slot or per-motion? Both**, with different content types —
  see the state section.

- **`Track`/`Key` versus v1's `Seg` — keys.** The field is near-unanimous (AE,
  Lottie, Rive, Unity, Blender, CSS, WAAPI); the only segment-shaped things are
  `TweenSequence` and `Interval`, which is why v1 reached for `Seg`, and which is
  a weaker reason than it looked — `Interval` is a staggering mechanism for one
  controller, not a storage format. Lottie shipped the redundancy and removed it.
  Decisive argument: **v1's overlap rule disappears**, because a sorted list of
  instants cannot overlap. A rule you delete beats a rule you enforce.
- **Where layout lives** — in a stage file, not on the model. See above.
- **The extension point and decomposition** — closed earlier, by the bundle.

## What to do next

**The spike order changed.** This document originally put the tier-2 round-trip
first, on the grounds that it is the only architectural risk. The owner's
correction: the Dart parse-and-emit is engineering with known failure modes and
has been built before — **the risk is the surface, not the parser.** Hence the
sketches, which found fifteen things prose had not.

**Nothing open can still move the model.** The two blocking questions — the
composition rule for two writers, and the two machine scopes — were both settled
on 2026-08-28, and neither widened the file format. What remains is measurement
and build order.

1. **The round-trip spike** — grammar on a page, parse and emit for three
   node types, fuzz `emit(parse(x)) == x`, and hand-edit hostilely to see what
   the failure UX is. Note that this got *more* important when `const` was
   dropped: the compiler no longer refuses a non-constant construct on the
   tool's behalf, so the parser is now the only thing between a hand edit and a
   file the editor cannot read.
2. **flutter_tester fidelity at 1080p**, independently useful and unblocked —
   blur, `BackdropFilter` and fragment shaders under software Skia versus
   Impeller on the guest. It picks the render lane for the video half.
   Scenario capture's measured numbers (2.3ms to pump a frame, 0.24ms raw,
   7.4ms to PNG at 393×852) scale by area to roughly 15ms + 45ms per 1080p
   frame, so a 60s/30fps film is ~2 minutes single-process and parallel across
   frame ranges. **That arithmetic is an extrapolation, not a measurement.**

Eight files have been written (`…-api-sketches.md`), and each round corrected
something prose had asserted. A ninth is worth writing only when there is a new
mechanism to stress, not on principle — and there is not one now.

**What is still unwritten and will be needed early**, none of it blocking: the
stage file's own shape, the panel (open 9), and the migration check against
existing `MotionValues` call sites (open 5).

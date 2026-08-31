# Scene editor discovery — the drawing plugin exhumed, and the SDK mined

**Date:** 2026-08-31
**Status:** findings from two discovery experiments, run before any scene
design is settled. Nothing here decides the model; everything here informs it.
**Context:** the Motion plugin is growing into a scene/motion editor
(`2026-08-28-motion-v2-design.md` is the model half; the scene half is in
discovery). Two experiments were greenlit: recover the deleted drawing plugin
for its read/write-code system, and measure what a catalog generated from the
Flutter SDK's own sources would cover.
**Artifacts:** the drawing plugin's ten files are recoverable at
`git show 5e760cc35^:app/lib/src/drawing/…` (deleted in #108, ~1,130 lines);
the mining script is `app/tool/sdk_mining_spike.dart` (disposable, run with
`cd app && fvm dart tool/sdk_mining_spike.dart`).

## Part 1 — the drawing plugin, read first-hand

v1 and v2 of the motion design quote the drawing plugin's lessons second-hand;
the code is small and worth the hour. What it was: an editor for `Path`
drawings whose file format was Dart — `.gen.dart` files carrying a
`//@flutterware:drawing=1.0` tag, discovered by a directory walk plus a file
watcher, parsed with the analyzer's `parseString` (syntactic only —
parse-never-resolve *predates* the doctrine), edited as a mutable
`ChangeNotifier` tree, and saved by regenerating the whole file through
`DartFormatter`.

### The silent-vanish failure is worse than the quote

The standing quote is *"`DrawingPath.fromCode` returned `null` on anything it
did not recognise and the entry silently vanished."* True, and missing the
sharp half: **save regenerates the whole file from the model**, so a vanished
entry is not merely invisible in the editor — the next editor write **deletes
it from disk**. Parse-drop plus emit-regenerate is a shredder for anything
outside the grammar. And the failure policy was inconsistent per node: unknown
path commands inside a recognized `PathBuilder` were silently skipped, while a
non-literal coordinate **threw**. Three behaviours (drop, skip, throw) in one
small parser, none of them a refusal with an offset. v2's
refuse-rather-than-approximate, with `fw scene check` in CI, is the direct
answer, and this code is the evidence it needs teeth.

### Comments-as-metadata was already tried, and its cost is visible

Motion v2's open question 3 (comments as modelled fields) has a precedent: the
drawing plugin stored mockup underlays and preview settings as
`// [mockup] path="…" x=12 w=100` comments above declarations, parsed by a
**second grammar** — ~200 lines of petitparser for a JSON-ish property-bag
dialect. It worked. It also meant: two parsers to maintain, data the compiler
cannot see or check, a mini-language nobody else can read, and values whose
only spec was the parser itself. Lesson: model metadata as real constructor
arguments inside the one grammar; the only comment a generated file needs is
its header.

### Smaller findings, each usable

- **Round-trip needs canonical numbers.** `numToCode(maxDigits: 3)` with
  trailing-zero trimming existed because emit must spell a double one way.
  Any `emit(parse(f)) == f` fuzz needs a canonical number policy stated up
  front, and formatter output pinned (they pinned `DartFormatter` to a
  language version).
- **The watcher dedupes its own writes by comparing emitted code** — parse the
  changed file, `toCode()` both, replace the model only when they differ. The
  watch-your-own-writes problem is real and this is a clean answer.
- **The edit surface prior art matches later decisions independently:**
  `InteractiveViewer` (unconstrained, oversized canvas, shifted origin) over a
  `CustomPaint`, with a `Positioned` editor widget per draggable vertex and
  per-entry `AnimatedBuilder`s for granular repaint. The previews zoom work
  reached `InteractiveViewer` separately in 2026-08.
- **A mockup underlay is a good idea worth keeping**: the editor could place a
  reference image (path/x/y/w/h/opacity) under the drawing to trace over. A
  scene editor wants the same for matching a design reference.
- **No model/draft split**: the parsed tree *was* the mutable editing state,
  one `ValueNotifier` per property. Fine at this size; noted as the
  before-picture of v2's storage-shape-vs-edit-shape rule.

## Part 2 — mining the SDK for a generated catalog

Question: if the editor's widget catalog were generated from the pinned SDK's
sources — every property detected, options generated — what would coverage
be? Method: syntactic parse (never resolve) of
`packages/flutter/lib/src/{widgets,material,cupertino}` for widget classes
(superclass chain walked to the `*Widget` roots within the corpus), plus a
whole-SDK pass collecting enum declarations. Constructor parameters typed via
`this.`/`super.` field lookup through the class chain. Measured on
3.48.0-0.2.pre, runtime a few seconds.

### The numbers

| | |
|---|---|
| concrete public widgets | **552** (305 widgets, 189 material, 58 cupertino) |
| every one carrying a doc comment | 552 / 552 |
| non-key constructor params | 4,931 |
| **directly editable** (scalar 48.4% + child 11.3% + enum 9.6%) | **69.3%** |
| callbacks (wireable, not value-editable) | 11.7% |
| runtime objects (controllers, focus nodes…) | 4.5% |
| theme/style objects | 2.1% |
| unclassified | 12.4% |
| params with a default value | 1,137 — **all 1,137 recoverable syntactically** |
| widgets ≥75% editable | 274 / 552 |
| instantiable from editor-supplied values alone (all required params editable) | **320 / 552** |

Spot checks: `Row` is fully editable (6 enums, spacing, children); `Container`
14 of 15; `Text` 14 of 17; `TextField` is 72 params of which 41 scalar+enum —
and `ElevatedButton` is the honest counterexample: its essence is 4 callbacks
plus a style object, so button-like widgets are palette-worthy only once the
editor has a callback story (stub, or wire-to-nothing).

### The tail is named-constant classes, not chaos

The unclassified 12.4% is dominated by a *pattern*, not a long tail:
`WidgetStateProperty<T>` (58 across instantiations), `MouseCursor` (43),
`TextInputType` (13), `TextInputAction` (9) — classes whose values are a
closed set of static consts, enumerable by the same syntactic scan that found
the enums. A handful of dedicated editors for these pushes direct coverage
toward ~80%.

### What mining cannot know

Ranges and semantics. A `double` might be an opacity (0–1), a pixel length,
or a flex factor; the scan cannot tell. Name heuristics (`opacity`,
`padding`, `elevation`) recover some; the rest is exactly the curation layer's
job. Generation supplies **data** — types, defaults, docs, enumerations —
and curation supplies the **product**: which dozen nodes sit in the palette,
which properties lead, what a slider's range is.

### The same extractor is the registration story

Pointed at user code instead of the SDK, the identical scan yields the
identical schema — types, defaults, doc comments — with no resolved analysis,
which is the constraint the owner set for external-widget registration. One
extractor, two corpora: the SDK at its tag (generated once per pin, the
`rules.json` pattern from the lints panel, now verified to work for widgets),
and the user's own files at scan time, with a codegen'd entry-point
declaration carrying whatever minimal extra the user must state (mockup
values, size hints).

## What these two experiments settle for the design ahead

1. **Refusal must be uniform and total** — one policy, offsets and names, CI
   teeth. The drawing plugin shows all three softer alternatives shipping in
   one file, and the shredder that emit-regenerate makes of them.
2. **One grammar; no comment dialects.** The second grammar was tried and its
   costs are visible in the diff.
3. **A generated catalog is viable as the data layer** — 69% raw, ~80% with
   four const-set editors, defaults included, at seconds of build time per SDK
   tag. The palette stays curated; the inspector and the long tail
   ("insert any widget by name") ride the generated schemas.
4. **Registration can stay syntactic**, and it is the same machinery as the
   catalog — build it once.

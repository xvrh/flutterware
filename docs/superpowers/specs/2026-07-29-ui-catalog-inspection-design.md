# Inspecting a catalog entry — the feature list, and what builds it

**Date:** 2026-07-29
**Status:** design, with one spike run. The findings in "What is already true"
are verified against the code and the pinned SDK; "The spike, run" is measured
against a live guest by `app/tool/catalog/inspect_spike.dart`. Everything else
is a proposal.

**One decision came out of it:** turn `--track-widget-creation` on. Hot reload
does not measurably change, and without it the summary tree is not a smaller
tree — it is the same tree.
**Extends:** `2026-07-27-gui-cli-mcp-architecture.md` (decisions 1–6 hold),
`2026-07-26-ui-catalog-entry-model.md`.

## The question

We can preview an entry. What does it mean to *inspect* one — and do we wire
Flutter DevTools, rebuild an inspector, or dump a tree?

## The short answer

**None of the three as stated.** Own the inspection *data*; borrow the
framework's *computation*; treat DevTools as an escape hatch.

| | verdict | why |
|---|---|---|
| Embed DevTools | **no** | it is a Flutter **web** app with no library form; embedding needs a webview, and a DevTools panel is a capability only the GUI has — which is the parity rule inverted |
| Rebuild an inspector | **the UI, yes; the machinery, no** | `DiagnosticsNode`, `RenderFlex` introspection, hit-testing and a11y evaluation are all in the framework already. What we write is a projection and a panel |
| A tree dump | **the right first slice, wrong shape** | `debugDumpApp()` returns a string. A string cannot be filtered, cannot carry node ids, and cannot feed `screenshot --node` |
| Point DevTools at the guest | **yes, ~20 lines** | `fw devtools --entry=…` prints the VM service URI. Honest about being human-only |

## What is already true (verified)

Six facts that decide most of the design. Each was checked, not recalled.

### 1. The full inspector is live in the guest today

`WidgetInspectorService.initServiceExtensions` is registered inside an
`assert(() {…}())` — `packages/flutter/lib/src/widgets/binding.dart:798-814` in
`3.47.0-0.1.pre`. So the whole `ext.flutter.inspector.*` surface exists **iff
Dart asserts are enabled**.

They are. `ext.flutter.reassemble` is registered in the *same* way
(`foundation/binding.dart:553-559`), and
[`GuestVmService.reload`](app/lib/src/embedder/guest_vm_service.dart:60) calls
it after every `reloadSources` **without** the 32601 swallow that
[`callExtension`](app/lib/src/embedder/guest_vm_service.dart:83) applies. Hot
reload works, therefore `reassemble` resolves, therefore asserts are on,
therefore the inspector is registered.

Available without writing a line of guest code:

| | |
|---|---|
| `ext.flutter.inspector.screenshot` | `id`, `width`, `height`, `margin`, `maxPixelRatio`, **`debugPaint`** → base64 PNG (`widget_inspector.dart:1308-1334`) |
| `ext.flutter.inspector.getRootWidgetTree` | `isSummaryTree`, `withPreviews`, `fullDetails` (`:1272`, params read at `:2101-2110`) |
| `ext.flutter.inspector.getLayoutExplorerNode` | flex geometry (`:1335`) |
| `ext.flutter.inspector.setFlexFit` / `setFlexFactor` / `setFlexProperties` | **live flex editing** (`:1340-1354`) |
| `ext.flutter.inspector.setSelectionById`, `getParentChain`, `getProperties`, `getChildren` | `:1224-1243` |
| `ext.flutter.accessibilityEvaluations` | `MinimumTextContrastEvaluation`, `MinimumTapTargetEvaluation`, `LabeledTapTargetEvaluation` → `[{nodeId, message}]` (`widgets/binding.dart:757-793`, inside `!kReleaseMode`) |

The last row is worth stopping on: **contrast, tap-target size and unlabeled-tap-target
checks ship in the framework.** We do not write an a11y auditor; we call one.

### 2. Widget creation is *not* tracked

`--track-widget-creation` is passed nowhere —
[`frontend_server.dart:69-85`](app/lib/src/embedder/frontend_server.dart:69)
builds the argument list and neither of its two callers
([`compiler.dart:20`](app/lib/src/embedder/compiler.dart:20),
[`resident_compiler.dart:85`](app/lib/src/embedder/resident_compiler.dart:85))
passes `extraArguments`.

Consequences, all confirmed in the SDK:

- **No `file:line` for any widget.** The single most useful datum for an agent
  that is about to edit the file.
- **`trackRebuildDirtyWidgets`, `trackRepaintWidgets` and `widgetLocationIdMap`
  are not registered at all** — `widget_inspector.dart:1103` gates them on
  `isWidgetCreationTracked()`.
- **The summary tree does nothing whatsoever**, since "created by user code" is
  exactly the creation location. Measured: identical to the full tree, node for
  node.

The hook already exists (`extraArguments`), so this is a one-line change. It has
now been measured and the answer is to take it — see "The spike, run".

### 3. The catalog is a far better inspection target than an app

The guest runs a generated `main` that mounts **one** demo under a thin host:
`_CatalogHost` → `CatalogGuest` → `KeyedSubtree(key: ValueKey(entryId))` →
`wrapper(_builder())`
([`entrypoint_generator.dart:262-281`](app/lib/src/catalog/entrypoint_generator.dart:262)).

So flutterware knows **exactly** where the demo subtree begins. DevTools' whole
pub-root-directory filtering apparatus exists to guess that boundary in a real
app; here it is a constant. Scoping is by construction, not by heuristic.

### 4. Node ids must be deterministic, and DevTools' are not

Every `fw` invocation and every MCP tool call opens a fresh `Session` and holds
nothing — the rule from the architecture doc, and the reason the two fake
actions were deleted. DevTools ids are minted per *object group*, refcounted,
disposed via `disposeGroup`, and die with the process.

An agent that runs `tree`, reads id `inspector-42`, and then runs
`screenshot --node=inspector-42` **gets a different tree in a different process
and a meaningless id.** This is not a detail; it disqualifies the inspector's
id model for the AI surface outright.

> **Node ids are structural and derived, so the same address yields the same
> ids in a process that has never seen the previous one.**

Proposed form: the child-index path, carrying the type for legibility and drift
detection — `2/0/1` rendered as `Column/Row[1]/Text[0]`, matched on the path and
warned on when the type at that path changed. `Address` already has the
precedent: identity is derived, not assigned.

### 5. `Artifact.widgetTree` exists and has zero usages

[`lib/src/plugins/artifact.dart:19`](lib/src/plugins/artifact.dart:19). The
tree was anticipated as an artifact kind and never produced. That is the slot
this design fills.

### 6. Two live gaps this design depends on

- ~~**Axes are GUI-only.**~~ **Closed in S4.** `HeadlessCatalog.applyAxes` and
  `describe --axes`; every action that renders takes `--axes`, and they land on
  the address prefixed `axis.` beside `knob.`.
- **A knob bug that makes `--knobs` a no-op on the headless path.** The guest
  registers `ext.flutterware.setParameters`
  ([`guest.dart:94`](lib/src/ui_catalog/guest.dart:94)); the headless caller
  sends `ext.flutterware.setParameter`, singular
  ([`headless_catalog.dart:446`](app/lib/src/catalog/headless_catalog.dart:446),
  and three sites in `headless_check.dart`). Renamed by `ca40bef`, callers
  missed. Because `callExtension` returns `null` on RPC 32601, it fails
  **silently**: the screenshot is taken with default knobs and reports success.
  The harness assertion `set?['applied'] == true` reads `null != true` and does
  not fire.

  The bug and its invisibility are the same fact. The swallow at
  `guest_vm_service.dart:83-86` is right for "does this old guest have the
  extension"; it is wrong for "call this extension I know exists". Those want
  two methods.

## The design line, stated so it can be wrong

> **We own the tree, its ids and its schema. We borrow every computation the
> framework already performs. We never make the GUI a required participant.**

Concretely: **write a guest-side walker over `Element`/`RenderObject` using
`DiagnosticsNode` for property formatting; do not use `ext.flutter.inspector.*`
for the tree or its ids; do use it for global debug flags, live flex editing and
a11y evaluation.**

**Amended once it was built.** A widget's creation location is stored behind
`_HasCreationLocation`, a private interface in `package:flutter`, and Dart
mangles private names per library — so no code outside that library can read
it, dynamically or otherwise. And since "summary tree" *means* "created by user
code", losing the location loses the filtering with it. Four of the five rows
below survive; the walk itself does not.

So what shipped is the hybrid: **the framework supplies the structure and the
locations, we supply the identity and the geometry.** `WidgetInspectorService`
turns out to be reachable in-process — `getRootWidgetSummaryTree`, `toObject`
and `disposeGroup` are all public — so the join is by object identity rather
than by matching two tree shapes, and one guest call answers everything.

Why our own *ids and geometry* beat the inspector's:

| | ours | `getRootWidgetTree` |
|---|---|---|
| scope | the demo subtree, by construction (finding 3) | whole app; needs pub-root filtering that needs finding 2 |
| ids | deterministic, survive a fresh process (finding 4) | ephemeral, group-scoped, refcounted |
| schema | our class → `ShapeExtractor` publishes it to `--help`, `docs/capabilities.md` and MCP for free | untyped JSON we would re-shape anyway |
| layout | same node, one round trip | a second RPC per node |
| lifecycle | none — serialise inside the call | `disposeGroup` bookkeeping across a process that dies each call |

The cost of owning it is one walker (~200 lines guest-side) and the discipline of
keeping it in `package:flutterware`, which the user's app links.

**One extension worth taking:** put the walker in a neutral `lib/src/inspect/`
rather than inside `CatalogGuest`, so `lib/devbar.dart` can mount it too. Then
"inspect the demo" and "inspect my actual running app" are one feature with two
mounting points. This is cheap now and expensive later.

## The features

Grouped by the tier table from the architecture doc. Everything below tier
**Viewer** reaches the GUI, `fw` and MCP from a single `PluginAction` on
`UiCatalogCore` — no adapter edits, automatic parity coverage, automatic docs,
and an `Artifact` whose `kind` starting `image/` is auto-upgraded to a real
picture over MCP.

### Job tier — the actions

#### 1. `tree` — the backbone

```
fw run ui_catalog tree --entry=<id> [--mode=summary|full] [--depth=N]
                       [--node=<id>] [--properties] [--axes=theme=dark] [--knobs=…]
```

Returns `CatalogTreeResult { entryId, address, nodes[] }`, node =
`{id, type, key?, depth, childIds, properties?, source?}`.

Guest side: `ext.flutterware.tree`, walking `Element`s from the `KeyedSubtree`
down, with `element.widget.toDiagnosticsNode()` supplying properties in the
framework's own formatting. Artifact kind: `Artifact.widgetTree`, already
reserved.

Renders three ways from one result: an indented text tree for `fw` and MCP
(the `ResultShape.toText` precedent), a `TreeView` in the panel, JSON under
`--json`.

#### 2. `layout` — geometry, folded into the tree node

`{size, offsetFromRoot, constraints, isRepaintBoundary, needsCompositing,
flex?{direction, flex, fit, mainAxisAlignment}, text?{fontSize, height,
baseline}, clipped, overflowed}`.

Guest side, from `element.renderObject`: `RenderBox.size`, `localToGlobal`,
`constraints`, plus a `RenderFlex` case mirroring what `getLayoutExplorerNode`
computes.

This is the feature that lets an agent answer *why is this zero-height* and
*is this tap target 44pt*, which it currently cannot do at any price.

#### 3. `find` — locate before you dump

`--type=ElevatedButton`, `--text="Save"`, `--key=submit` → node ids plus their
layout. Exists so that the answer to "where is the submit button" is forty
tokens rather than a whole tree. **This is the token-budget feature**, and it
should land with `tree`, not after it.

#### 4. `at` — hit test

`--x --y` → the node chain at that point, outermost to innermost. Powers the
GUI's click-to-select and the agent's "what is at this pixel", from one
implementation. Guest side, `RenderObject.hitTest` from the demo root.

#### 5. `errors` — does it render, not just compile

`check` answers "does it compile". Nothing answers "does it throw while
building", and a demo that throws paints Flutter's red `ErrorWidget` while every
assertion about compiling and reloading passes.

Half-built already: the generated entrypoint installs `FlutterError.onError` and
prints `FW-ERROR: …`
([`entrypoint_generator.dart:255-258`](app/lib/src/catalog/entrypoint_generator.dart:255)).
Upgrade to a ring buffer of structured `FlutterErrorDetails` behind
`ext.flutterware.errors`: `{exception, library, context, widgetPath,
stackSummary}`. Overflow arrives free — a `RenderFlex` overflow *is* a
`FlutterError`.

#### 6. `audit` — the catalog lint

Every entry, one warm guest: does it compile, does it throw, does it overflow,
does it render blank, does it pass the three framework a11y evaluations.
Reuses the `captureAll` batch economics — first entry pays a cold compile, the
rest are hot reloads.

**This is the highest-leverage AI feature in the list**, and the only one that
is also a CI story. One command tells an agent the state of the entire UI
surface of a repo; today that question has no answer at all.

#### 7. `semantics`

The semantics tree plus the framework's evaluations. Guest side, holding a
`SemanticsBinding.instance.ensureSemantics()` handle for the duration — without
it the tree does not exist — then walking
`pipelineOwner.semanticsOwner.rootSemanticsNode`, and calling
`ext.flutter.accessibilityEvaluations` three times for the violations.

#### 8. `screenshot --node=<id>` and `--annotate`

- **Crop.** Host-side, from the node's rect, on the frame that was already
  captured. `package:image` is already a dependency. Better than
  `ext.flutter.inspector.screenshot`, which renders the node in isolation and
  therefore out of context.
- **Annotate.** Draw the boxes and their node ids onto the PNG, host-side.

Annotate is the one that closes the loop: an agent reads a tree with ids, then
receives a picture with the same ids drawn on it. Pixels and structure stop
being two disconnected observations.

#### 9. Headless axes, and debug flags as axes

Close gap 6, then add the framework's debug toggles as further axes:
`debugPaint`, `baselines`, `repaintRainbow`, `semanticsDebugger`, `textScale`,
`platform`, `timeDilation` — all existing `ext.flutter.*` bool extensions,
pushed before the frame in the shape `_pushAxes` already has
(`catalog_session.dart:566-582`).

They go on the `Address` because they are applied, not identity — so
`?theme=dark&debugPaint=1` is a complete, reproducible capture spec, the
filename derives from it, and the GUI toolbar toggle and the agent's flag are
the same thing written twice.

#### 10. `compare` — the same entry, two axis assignments

Tree diff plus image diff (delta percentage and a diff PNG). *Does this survive
dark mode / RTL / textScale 2.0 / a small phone.* The classic regression an
agent cannot presently see. Depends on 9.

#### 11. Goldens

There is no golden pipeline for catalog entries — verified, none. `captureAll`
is the batch primitive, `Artifact.address` is a complete capture spec, and the
address-derived filename is already collision-free. `snapshot` writes a
baseline; `verify` compares. Mostly assembly.

#### 12. Rebuild and repaint counts

`trackRebuildDirtyWidgets` / `trackRepaintWidgets`. Verified present the moment
creation tracking is on, absent without it. "Turning this knob rebuilt 340
widgets" is a good answer to have.

#### 13. `source` — node → `file:line`

Same gate, and the highest-value item behind it: an agent told *`_Dashboard` at
`tool/catalog/demos/dashboard.dart:10`* can go edit it, where one told *a
`Padding` is wrong* cannot. Measured at ~82% of summary nodes resolving into
demo source.

Both were blocked when this document was written. The spike unblocked them; they
now depend only on landing the flag.

### Viewer tier — the panel

- **Inspector side panel**: tree, and a detail pane with properties / layout /
  semantics.
- **Select-in-preview**: a mode toggle; while on, pointer events hit-test
  instead of reaching the demo. The coordinate transform already exists —
  `catalog_view.dart:374-412` scales by `dpr` in both directions.
- **Highlight overlay**: draw the selected node's rect *over* the `Texture`,
  host-side. No guest repaint, no round trip, because the host already knows the
  rect and the transform. Cheap and smooth.
- **Layout explorer with live flex editing**: `setFlexFit` / `setFlexFactor` /
  `setFlexProperties` are framework extensions. Dragging a `Row`'s flex and
  watching it reflow without touching the source is nearly free and is the most
  demo-able thing in this document.
- **Problems panel** over `errors` / `audit`; a badge on the entry row.
- **"Open in DevTools"**: prints/opens the guest's VM service URI. The escape
  hatch, explicitly human-only.

### The AI surface

**No new MCP tools.** Everything arrives through `flutterware_invoke`, per the
existing doctrine — a fixed small tool set, promotion reserved for where a good
name beats a discovery round-trip.

One candidate is worth putting on the record rather than deciding now:
`flutterware_inspect`, bundling tree + layout + annotated screenshot for one
entry. The doctrine says nothing has earned promotion yet; a UI-editing loop
that runs this on every iteration is the first thing that plausibly does.
Decide with a real client in front of us, which is the same standard the
original decision used.

**Token budget is a design constraint, not an optimisation, and it is now
measured.** A full tree is 231–695 nodes and 7.8k–22.9k tokens; the summary tree
with creation tracking on is 22–145 nodes and 0.8k–5.2k. So the defaults write
themselves: **`mode=summary` always**, details opt-in (they cost 2–3× — 145
nodes go from 5.2k to 16.7k tokens), text rather than JSON, `find` before
`tree`, and an annotated screenshot in place of a property dump.

Our own walker should beat even the summary figures, because it starts at the
demo subtree instead of the root and drops the 13-node framework chain the raw
tree carries — measured, `[root] > View > RawView > … > _CatalogHost` before
anything of the demo appears.

## The spike, run — and it settles the question

`app/tool/catalog/inspect_spike.dart` brings up a real daemon and a real
embedder guest, reads the isolate's registered extensions, pulls trees at three
detail levels, and times 38 entry switches. Run once as-is and once with
`FW_TRACK_WIDGET_CREATION=1`, killing the daemon and removing
`app/build/catalog` between runs.

### The inspector is reachable — confirmed empirically

**29 `ext.flutter.inspector.*` extensions registered**, out of 60 `ext.flutter.*`
total, including `getRootWidgetTree`, `screenshot`, `getLayoutExplorerNode`,
`setFlexFactor` and `accessibilityEvaluations`. The argument from the `assert`
in finding 1 holds. `isWidgetCreationTracked -> false`, and
`trackRebuildDirtyWidgets` / `widgetLocationIdMap` are absent exactly as the
gate at `widget_inspector.dart:1103` predicts.

### Without creation tracking the summary tree does nothing at all

This is stronger than "degrades", which is what this document said before it was
measured. `isSummaryTree: true` returns **byte-for-byte the same tree** as
`isSummaryTree: false`:

| demo | full | summary |
|---|---|---|
| `avatar_tile#avatarTileEmpty` | 231 nodes, 30.0 KB | **231 nodes, 30.0 KB** |
| `command_palette#paletteAwkward` | 555 nodes, 68.6 KB | **555 nodes, 68.6 KB** |
| `dashboard#dashboard` | 695 nodes, 88.0 KB | **695 nodes, 88.0 KB** |

There is no filtering because there is no creation location to filter on. An
agent asking for the "summary" tree of an *empty avatar tile* gets ~7,700
tokens; `dashboard` costs ~22,500.

### With it on, the summary tree becomes the feature

| demo | full, lean | summary, lean | summary + details |
|---|---|---|---|
| `avatar_tile` | 231 nodes / ~7,821 tok | **22 / ~841** | 22 / ~2,616 |
| `command_palette` | 555 / ~18,617 | **145 / ~5,206** | 145 / ~16,729 |
| `dashboard` | 695 / ~22,901 | **51 / ~1,879** | 51 / ~5,956 |

`dashboard` drops from 695 nodes to 51 — **13.6× fewer nodes, 92% fewer
tokens** — and every node carries a `createdByLocalProject` flag and a
`file:line:col`.

**And the locations point at the demo, not at the wrapper**, which was the risk
worth checking. Of `dashboard`'s 51 summary nodes: 34 in
`tool/catalog/demos/dashboard.dart`, 8 in the demo's `shell.dart`, 5 in the
generated `entrypoint/main.dart`, 3 in framework or `lib/src/ui_catalog/`
plumbing. **~82% resolve to source a developer or an agent can open and edit.**

### The cost is nearly nothing

| | baseline | tracked | delta |
|---|---|---|---|
| cold compile | 4632ms | 4811–4822ms | **+4%** |
| prepared kernel | 43.24 MB | 43.54 MB | **+0.7%** |
| incremental compile (median, n=38) | 7ms | 7ms | **0** |
| **entry switch, first pass** (median, n=19) | **110ms** | **110ms** | **0** |
| entry switch, all (mean, n=38) | 120.3ms | 120.8 / 121.5 / 122.9ms | +0.4…+2.2% |

Three tracked runs against one baseline. The first-pass median is *identical* to
the millisecond, and the overall mean moves by less than a fifth of the
run-to-run standard deviation (≈15ms). **The hot-reload cost is not merely under
the 20% threshold this document set — it is not measurable.**

> **Decision: turn `--track-widget-creation` on unconditionally.** It costs 4% of
> a cold compile once and 0.3 MB, and it is the difference between a summary
> tree that does nothing and one that is 13× smaller with a source location on
> every node.

**Landed.** `DaemonConfig.trackWidgetCreation`, defaulting to true, threaded to
`ResidentCompiler.start` and into the warm-dill stamp. A field rather than a
constant so the daemon address forks on it — verified: flipping it moved the
build directory from `84bd206d9d607ee1` to `b4f93d107beddff7`, so a kernel
compiled one way can never prime a compiler running the other. The spike takes
`--no-track-widget-creation` to re-measure the baseline.

### An unrelated finding worth recording

**The second pass over the same entries is consistently ~20% slower than the
first** — median 110ms on lap 0 against 130–136ms on lap 1, reproduced in all
four runs, with compile time flat at 7ms throughout. So it is in the reload, not
the compiler. Nobody has looked at what a guest accumulates across ~20 reloads;
this is the first measurement that shows it accumulating something.

## Sequencing

Each step was worth having if the next was abandoned. **S0–S4 have landed**;
what remains is below them.

### Landed

| | | |
|---|---|---|
| **S0a** | `trackWidgetCreation` as a `DaemonConfig` field | measured first — see "The spike, run" |
| **S0b** | the `setParameter`/`setParameters` mismatch | and `callExtension` split into a tolerant and a required form, since the swallow is why the rename survived a week |
| **S1** | `ext.flutterware.tree`, `lib/src/inspect/`, `tree`, `find` | the backbone, with the token-budget answer beside it |
| **S2** | layout folded into every node; `ext.flutterware.hitTest`, `at` | where "why is this zero-height" became answerable |
| **S3** | structured `errors`; `audit` | compile failures, build-time throws, overflows; `--path` narrows to a folder or a file |
| **S4** | headless axes; `screenshot --node` / `--annotate` | closed the axes gap and the pixels↔structure loop |
| — | coverage | 15 wire-format tests in CI, 18 live checks in `headless_check` |
| — | `Artifact` publishes a shape | read from its hand-written `toJson`, so all nine actions publish one |

### Remaining

| | | |
|---|---|---|
| **S3b** | the three framework a11y evaluations | needs `ensureSemantics()` **held** and a frame pumped while held — they do `view.owner!.semanticsOwner!.rootSemanticsNode!`, so with no handle the call *throws* rather than returning empty. A behaviour change in the guest, not a read, which is why it is separate. |
| **S4b** | `debugPaint`, `repaintRainbow`, `textScale`, `timeDilation` | bundled into S4 as "flags as axes" and they are not axes: an axis is declared by a shell and pushed to it, these are `ext.flutter.*` toggles on the guest *process*. Same address, different push. |
| **S5** | the panel | the first step that needs a window — and the cheapest it will ever be: `at` is already the whole of click-to-select, `InspectLayout` is already the highlight rect, `tree` is the tree view, `audit` is the problems list, and `setFlexFit`/`setFlexFactor` are framework extensions so live flex editing is nearly free. |
| **S7** | `compare`, goldens | assembly over S4 — axes are reachable now and `Artifact.address` is already a complete capture spec |
| — | rebuild/repaint counts | `trackRebuildDirtyWidgets` is registered now that creation tracking is on; nothing wires it |
| — | interaction | no tap, type or scroll, so anything behind a state change is invisible to an agent. The largest remaining gap in the AI surface, and a design question rather than a wiring one. |
| — | `fw devtools <entry>` | the escape hatch: print the guest's VM service URI. ~20 lines, explicitly human-only |

**Blank-frame detection is dropped, not deferred.** It was on the list as part
of `audit`. It is a heuristic — "is the frame uniform" — that false-positives
on a legitimately flat demo, and an agent already has `screenshot` and
`--annotate` for that question. Declaring it would have been the third
capability in this branch that reads as a feature and does nothing.

`semantics` (7) is independent of everything else and is the cheapest item
remaining relative to its value, because the framework already computes the
violations — it is only the handle that makes it S3b rather than an afternoon.

### What building S1–S3 corrected

Four things, all found by running rather than by reading — which is the method
note worth keeping.

- **A `full` parameter that shipped nothing.** Declared on `tree` and `find`,
  and measured at 44 nodes either way with zero non-local: the only public
  in-process reader returns the summary tree *already* filtered, so the flag
  filtered a filtered list. Removed. Same category as the two fake actions in
  `2026-07-27-gui-cli-mcp-architecture.md`, and caught the same way.
- **Searching by the words on screen matched nothing.** The summary tree
  describes a `Text` as `Text`; the richer `Text("Save")` form comes from
  `withPreviews`, which is extension-only. So `--query=Save`, the first thing
  anyone would try, found zero. The preview is read off the widget now.
- **`jsonEncode` throws on `double.infinity`.** An unbounded `maxWidth` is what
  most of a real tree is laid out under, so the first entry with a `Column` in
  it failed to encode at all. Unbounded travels as `null`.
- **`RenderFlex` reports an overflow only if it has a size.** `paint` returns
  early when `size.isEmpty`, *before* the assert that reports — so a
  zero-height overflowing `Row` overflows and says nothing. Cost one false
  negative while verifying `audit`, and would have been read as "overflow
  detection does not work".
- **The doc was wrong about output.** It said "text rather than JSON by
  default". `fw` prints JSON for every structured result on purpose
  (`cli.dart:411`): the framework cannot invent a table, and JSON is the one
  rendering that is always honest and always pipes into `jq`. Left alone; each
  node carries a `depth` instead, so a flat list still reads as a tree.

## Open questions

1. **Where does the walker live** — `lib/src/inspect/` shared with devbar, or
   inside `CatalogGuest`? Recommended shared, argued above, not decided.
2. **Node id stability under structural change.** A path-derived id is stable
   only while the tree is. Is a type mismatch at a path a warning, an error, or
   a re-resolution? Needs a real editing loop to answer.
3. **Does `audit` belong to the catalog plugin or above it?** It is a
   whole-repo question asked of one plugin. Probably the catalog until a second
   plugin wants the same shape — the same standard the doc applies to
   `read <address>`.
4. **Semantics needs a held handle.** Holding `ensureSemantics()` changes what
   the app does. Held only for the duration of the call, or for the session when
   the panel is open? The first is safer; the second is what a GUI toggle wants.

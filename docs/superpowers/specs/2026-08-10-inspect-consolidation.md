# Inspect — one surface, three hosts

**Date:** 2026-08-10
**Status:** Part 1 **built** (this change) — `InspectNode.offstage` marked by
the guest walk, skipped by `nodeAtPoint`, folded by `ElementsView` and by the
`inspect` action's `tree` (boundary node reported, `--node` is the way in).
The route-oracle spike resolved *with* part 1: `visitChildrenForSemantics`
held on every probe case first try (`test/inspect/guest_inspect_offstage_test.dart`),
so candidate 1's fragile theater-recognition was never needed — the edge test
plus the four-type exemption list is the whole detector. Parts 2–4 remain a
plan. Originally written to answer "the inspect reports are duplicated at
three places; should we consolidate, and can we hide offstage content
everywhere at once?"
**Lineage:** `2026-07-31-sl3-inspect-surface-findings.md` (what the VM service
can and cannot give the run cockpit), `2026-08-10-scenarios-semantics-tab.md`
(the semantics leg, currently scenarios-only).

## The map — what the three surfaces actually share today

| | Previews (catalog) | Scenarios (step page) | Run (cockpit) |
|---|---|---|---|
| subject | live in-process guest | snapshot on disk | live external app |
| tree source | `GuestInspector` over `ext.flutterware.tree` | same walker, written to `.tree.json` | `RunInspector` over `ext.flutter.inspector.*` |
| layout rects | yes, plus live per-frame box (`WatchBox`) | yes (as of capture) | **none** — the VM surface carries no position |
| semantics | no | `.semantics.json` + Semantics tab | no — no service extension exists for it |
| texts | no | Texts tab | no |
| picker | exact (guest runs real `hitTest`) | approximate (`nodeAtPoint` over rects) | no |
| highlight painter | own `_HighlightPainter` (live-box aware) | `NodeHighlightPainter` | none |
| chrome | `InspectDock`: Controls · Elements · Problems · Console | `InspectDock`: Elements · Semantics · Texts | `InspectTabStrip`: Screen · Logs |

**Already consolidated** — more than the question assumes:

- The wire model is one: `InspectNode`/`InspectTree`/`InspectLayout`
  (`lib/src/inspect/node.dart`), shape-derived ids, same JSON whichever side
  produced it.
- The tree-plus-detail view is one: `ElementsView`, shared verbatim by all
  three hosts — **including the node detail pane**. The detail page is already
  uniform; improving `_Detail` improves all three at once. That half of the
  question is settled by pointing at it.
- The chrome is one: `InspectDock` / `InspectTabStrip` / `InspectSplitGrip`.
- The differing tab sets are justified by data, not drift: run has no rects to
  highlight and no semantics to show, previews has live-only tabs (Controls,
  Console) a snapshot cannot honestly serve.

**Still duplicated:**

- Two tree converters — `GuestInspector._convert` and
  `RunInspector.convertNode`. Kept separate deliberately (only one side can
  touch a live `Element`), with a stay-in-step comment on both. Leave them.
- Two highlight painters — the catalog's `_HighlightPainter`
  (`catalog_view.dart`) and `NodeHighlightPainter`, which was generalized for
  exactly this merge and not yet used by the catalog.
- Two copies of the picker grammar — arm → sweep → esc → one-pick-per-arming —
  in `catalog_view._pickerInput` and `step_page._ScreenOverlay`.
- Semantics capture and view live under `scenarios/` though nothing about them
  is scenario-specific.

## Finding — there is no "Offstage" node; the problem is worse (measured 2026-08-10)

Probe on the shop app, after `push`ing DrinkScreen over MenuScreen:

- The **whole previous route stays in the captured tree, unmarked** — 91
  MenuScreen nodes fully expanded beside DrinkScreen, indistinguishable from
  visible content. The framework's hiding machinery (`_RenderTheater`'s
  skip, `Offstage`) is not project-local code, so the summary filter drops the
  *marker* and keeps the local *content* under it. There is nothing that says
  "Offstage" for the reader to even fold away.
- Those nodes keep their last-laid-out **rects, which overlap the current
  screen**. `InspectTree.nodeAtPoint` takes the deepest box, so **the step
  page's picker can select a widget from the previous screen** through the
  current screenshot. This is a bug today, not a cosmetic wish.
- The **semantics tree is already clean** — the theater excludes covered
  entries from the semantics walk, so the Semantics tab shows the current
  route only (14 nodes vs the widget tree's 124). Nothing to do there.

## Part 1 — offstage marked at capture, hidden at presentation (built)

One flag in the shared model, so every host and every consumer inherits it:

- `InspectNode.offstage`, serialized sparsely (`'offstage': true`). Set by the
  guest walker, which serves previews' live tree and scenarios' `.tree.json`
  from the same `_convert` — one fix, two surfaces.
- **Detection (as built): one oracle, not two cases.** For every render edge
  between a summary node and its nearest converted ancestor, ask the parent
  whether it visits the child in `visitChildrenForSemantics` — the same
  mechanism that keeps a covered route out of a screen reader. The SDK's
  overrides were enumerated rather than guessed, and every one that skips a
  child is a child that is not painted — `_RenderTheater` (covered routes),
  `RenderOffstage`, `RenderIndexedStack`, `Render(Sliver)Opacity` at alpha 0,
  sliver keep-alive buckets — **except four public types that skip while
  painting**, exempted by type check: `RenderExcludeSemantics`,
  `RenderIgnorePointer`, `RenderAbsorbPointer` (both with the deprecated
  `ignoringSemantics`), `RenderSliverIgnorePointer`, plus
  `SemanticsAnnotationsMixin` (`Semantics(excludeSemantics: true)`). No
  private-name matching, no route accounting. Verified against the real
  framework: pushed-under route flagged, screen under a dialog not (a
  dialog's entry is not opaque, so the theater keeps visiting), `Offstage` /
  `Visibility(visible: false)` / hidden `IndexedStack` child flagged,
  semantics-excluded content not. Whole subtrees carry the flag, so a
  consumer of one node needs no ancestor walk.
- `InspectTree.nodeAtPoint` skips offstage nodes — the picker bug fix.
- `ElementsView` collapses an offstage subtree to one dim row —
  `MenuScreen — offstage` — expandable in place. Shared view, so previews,
  scenarios and run (once its trees carry the flag) all change at once.
- CLI/agent surface: a scenario step's `.tree.json` keeps everything, every
  node flagged. The `inspect` action's `tree` folds an offstage subtree to
  its top node (`offstage: true` on the wire); no separate include-flag —
  passing that node's id to `--node` is the way in, and `find` matches
  everywhere so a hit inside hidden content is reported with the flag as a
  warning rather than suppressed.
- **Run stays gapped**: the VM-service tree gives the host no render objects
  to interrogate, so its trees keep showing previous routes unmarked until
  the guest/devbar runtime lands. Say so in the view rather than pretending.

## Part 2 — one highlight, one picker

- Fold the catalog's `_HighlightPainter` into `NodeHighlightPainter`: the
  catalog computes the rect (live `WatchBox` wins over the tree's, as now)
  and the label, and passes both. Deletes a near-copy that was written before
  the shared painter existed.
- Extract the picker interaction into one overlay widget — the esc-focus, the
  sweep-hover, the one-pick-per-arming — parameterized by two resolvers:
  hover (sync, rect-walk on both hosts) and commit (async guest `hitTest` for
  the catalog, the same rect-walk for a snapshot). `_ScreenOverlay` and
  `_pickerInput` become thin wrappers. Run gets a picker for free the day it
  has rects, and not before.

## Part 3 — semantics grows legs

- Move the semantics pieces out of `scenarios/` into the inspect kit:
  `lib/src/scenarios/semantics_capture.dart` → `lib/src/inspect/`, and split
  `SemanticsSnapshotNode` (model) from `SemanticsView` (view) on the app
  side. Rename nothing else; the `.semantics.json` format is already
  host-neutral.
- **Previews gains a live Semantics tab nearly free**: the guest registers
  `ext.flutterware.semantics` beside `ext.flutterware.tree`, serving the same
  capture the harness writes; the panel adds the tab with the same view and
  the same overlay highlight. The 211µs capture cost is noise at
  refresh-on-demand cadence.
- **Run cannot follow yet** — the framework exposes no semantics over the VM
  service. Another entry on the guest-runtime ledger, beside global rects.

## Part 4 — the node detail pane, one pane growing richer

- The pane is already shared (`_Detail` in `elements_view.dart`); there is no
  uniformisation to do, only enrichment that lands on all three surfaces.
- Worth adding, in likely order of value: the widget's own diagnostics
  properties (filtered — `getProperties` is noisy), and for a selected node
  on a *live* host, fetched on selection (run: `getDetailsSubtree`; previews:
  a guest call) so snapshots pay nothing. If snapshot steps should carry
  properties too, **measure `.tree.json` growth first** — same posture as the
  semantics capture: measure, then promise.
- Give `SemanticsView` the same tree-beside-detail split, with *local*
  selection (the address stays elements-only, per the semantics-tab spec).
  Today's rows elide flags and actions; a detail pane is where a node's full
  reading — every flag, every action, text direction, the rect — fits without
  crowding the row.

## Order of work

1. **Part 1 minus the route oracle**: `RenderOffstage` marking, `nodeAtPoint`
   skip, hidden-by-default rows, CLI default — plus the route-oracle spike as
   its own probe. Most of the value and the actual bug fix live here.
2. **Part 2**: small, deletes code, no behavior questions.
3. **Part 3**: previews Semantics tab.
4. **Part 4**: detail enrichment, behind its measurement.

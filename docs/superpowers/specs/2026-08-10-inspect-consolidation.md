# Inspect — one surface, three hosts

**Date:** 2026-08-10
**Status:** Part 1 **built** (this change) — `InspectNode.offstage` marked by
the guest walk, skipped by `nodeAtPoint`, folded by `ElementsView` and by the
`inspect` action's `tree` (boundary node reported, `--node` is the way in).
The route-oracle spike resolved *with* part 1: `visitChildrenForSemantics`
held on every probe case first try (`test/inspect/guest_inspect_offstage_test.dart`),
so candidate 1's fragile theater-recognition was never needed — the edge test
plus the four-type exemption list is the whole detector. Part 2 **built**: the
catalog's `_HighlightPainter` is deleted (the host now picks live-box-over-
tree-rect and hands `NodeHighlightPainter` a plain rect + label), and the
picker grammar lives once in `InspectPickRegion`
(`app/lib/src/inspect/pick_region.dart`) — the catalog and the step page pass
resolvers, and disarm-after-pick moved into the region so an async commit
cannot leave the mode armed. Part 3 **built**: semantics moved into
the inspect kit (`lib/src/inspect/semantics_capture.dart`, pure wire model
`semantics.dart`, app-side `semantics_node.dart` + `semantics_view.dart`) and
the catalog grew a live Semantics tab over `ext.flutterware.semantics` — with
one discovery the plan missed: a **live app has semantics off** (unlike
`testWidgets`), so the extension holds a `SemanticsHandle` only while the tab
is open, and withholds the entry id until the enabling frame has built a tree
so the client's settling poll rides it out. Part 4 **built**: the guest walk
captures filtered widget diagnostics per node (`InspectNode.properties`,
measured before keeping: +168µs on the shop tree's 1.5ms read, +6KB on its
37KB JSON), the shared detail pane renders them on all three surfaces, and
`SemanticsView` gained the tree-beside-detail split with local selection.
**All four parts built.** Originally written to answer "the inspect reports
are duplicated at three places; should we consolidate, and can we hide
offstage content everywhere at once?"
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

## Part 2 — one highlight, one picker (built)

- The catalog's `_HighlightPainter` folded into `NodeHighlightPainter`: the
  catalog computes the rect (live `WatchBox` wins over the tree's, as before)
  and the label, and passes both. The near-copy predating the shared painter
  is deleted.
- The picker interaction lives once, in `InspectPickRegion`
  (`app/lib/src/inspect/pick_region.dart`) — the esc-focus, the sweep-hover,
  the one-pick-per-arming — parameterized by resolvers: sweep (rect-walk on
  both hosts) and pick (async guest `hitTest` for the catalog, the same
  rect-walk for a snapshot). `_ScreenOverlay` and `_pickerInput` are thin
  wrappers; disarm-after-pick moved from the catalog's async commit into the
  region, so the mode cannot hang armed while a guest answers. Run gets a
  picker for free the day it has rects, and not before. Grammar tested once
  in `app/test/inspect/pick_region_test.dart`.

## Part 3 — semantics grows legs (built)

- The semantics pieces moved out of `scenarios/` into the inspect kit:
  `lib/src/inspect/semantics_capture.dart` (capture),
  `lib/src/inspect/semantics.dart` (pure wire model `InspectSemantics` —
  `fw` links the client, so the typed node stays app-side), and
  `app/lib/src/inspect/semantics_node.dart` + `semantics_view.dart`. The
  `.semantics.json` format is unchanged; the view serves a step's snapshot
  and the live read without knowing which.
- **Previews' live Semantics tab**, over `ext.flutterware.semantics` in
  `GuestInspector.registerExtensions` — no generator change. What the plan
  missed and the build settled: a **live app has semantics off** until
  something holds a `SemanticsHandle` (`testWidgets` holds one by default,
  which is why scenarios never noticed). So the extension takes `on` — the
  session enables while the tab is open and releases on leaving, the guest
  pays per-frame semantics only while somebody looks — and the read
  **withholds the entry id until a tree exists**, because enabling takes a
  frame and `InspectClient._settle` polls on the id: an absence with a name
  would settle as the answer. Re-reads ride the same signals as the tree
  (structure pushes, scroll/resize settling, knob pushes, entry switches);
  the overlay draws the hovered row's rect with the elements highlight
  winning, as on the step page.
- **Run cannot follow yet** — the framework exposes no semantics over the VM
  service. Another entry on the guest-runtime ledger, beside global rects.

## Part 4 — the node detail pane, one pane growing richer (built)

- The pane was already shared (`_Detail` in `elements_view.dart`); the work
  was enrichment, landing on all three surfaces at once.
- **Properties ride the node, not a fetch-on-selection.** The plan leaned
  toward lazy fetching (run: `getDetailsSubtree`; previews: a guest call) so
  snapshots pay nothing — but that is two mechanisms and an async detail
  pane, and the measurement dissolved the reason for either: capturing
  filtered widget diagnostics for *every* node of the shop tree costs
  **+168µs on a 1.5ms read and +6KB on 37KB of JSON**. So the guest walk
  fills `InspectNode.properties` (level ≥ `info`, values elided past 96
  chars, twelve per node, `inherit` dropped by name — it is the resting
  state of every `TextStyle` and distinguishes nothing) and one mechanism
  serves the live tree, the `.tree.json`, the detail pane, and agents
  reading either. The yield is real: `padding: EdgeInsets.all(14.0)`,
  `maxLines: 1`, `data: "Cappuccino"`, colors. Run's trees stay without —
  the VM path cannot read widgets; noted beside `layout` on the
  guest-runtime ledger.
- `SemanticsView` has the same tree-beside-detail split as `ElementsView`,
  with **local** selection (the address stays elements-only, per the
  semantics-tab spec; the previews panel memoizes its JSON parse by identity
  so a session notify does not silently clear the selection). The detail is
  the node's full reading — label/value/hint/tooltip, identifier, text
  direction, every flag, every action, the rect — everything the row elides.

## Order of work

1. **Part 1 minus the route oracle**: `RenderOffstage` marking, `nodeAtPoint`
   skip, hidden-by-default rows, CLI default — plus the route-oracle spike as
   its own probe. Most of the value and the actual bug fix live here.
2. **Part 2**: small, deletes code, no behavior questions.
3. **Part 3**: previews Semantics tab.
4. **Part 4**: detail enrichment, behind its measurement.

# Scenarios — reach, discovery, and the semantics leg

**Date:** 2026-08-10
**Status:** Parts 1–3 **built** (this change) — part 3 as planned below, minus
the guideline audits, which stay a follow-on behind their two measurements.
As built: `lib/src/scenarios/semantics_capture.dart` (capture),
`app/lib/src/scenarios/semantics_view.dart` (tab),
`NodeHighlightPainter` generalized to a rect + label so both trees feed one
overlay.
**Lineage:** `2026-07-30-scenarios-design.md` (the design), 
`2026-07-31-scenarios-api-gaps.md` (the authoring surface as reviewed and
patched one day in). This picks up three gaps that review did not cover:
where discovery looks, what a verb does when its target is out of reach, and
the projection none of the captured legs shows — what a screen reader gets.

## Part 1 — discovery walks `test/` (built)

`test/scenarios` was the scan root, the creation default, and the display
prefix, all through one `directoryFor`. The fence bought nothing: a scenario
is an ordinary widget test, `flutter test` does not care which folder a test
sits in, and the scanner's substring prefilter (`'scenario('` before any
parse) makes the wider walk cost bytes, not parses. The harness side was
already indifferent — per-file `flutter_test_config.dart` resolution mirrors
`flutter_tools` exactly, and `scenarioDeclarationSink` already separates
scenarios from `testWidgets` sharing a file.

So the one question split into the two it always was:

- **Where do we look** — `ScenariosCore.scanRootFor`: the configured
  `directory`, else `test`.
- **Where does the next file go** — `ScenariosCore.newScenarioDirectoryFor`:
  the configured `directory`, else `test/scenarios`. The convention survives
  as the answer to authoring, not as a fence on discovery.

Declaring `directory:` in `tool/flutterware.dart` narrows both, which is the
fence back for a project that wants it.

**Display follows the files, not the config.** The list pane strips
`commonScenarioDirectory(files)` — the deepest directory every found file
shares — so a conventional suite renders exactly as before, and a spread one
shows the part that differs (`scenarios/checkout_test.dart` vs
`widgets/menu_test.dart` under a header saying `test`). Computed, so it
self-tunes as files move; the tooltip keeps the whole path and the address
always carries it, so links never depend on the prefix.

**Watch in the first real project:** a root `test/flutter_test_config.dart`
(fonts, golden setup) now governs scenarios placed outside `test/scenarios` —
which is precisely what bare `flutter test` does for those files, so it is
alignment, but it is the one behavior a project could notice.

## Part 2 — actionability: a verb reaches its target (built)

What `flutter_test` does with a tap on a found-but-off-screen widget: prints
a console warning and dispatches the tap anyway, into whatever is at that
point. The flow silently diverges and fails steps later, unattributed — the
one failure mode a screenshot-per-step tool must not have.

Every pointer verb (`tap`, `longPress`, `enterText`, `drag`) now checks, in
`_resolve` after the exactly-one check:

1. Would a pointer at the target's center reach it? The same test the SDK's
   `warnIfMissed` makes (`isRenderObjectAncestorOfTarget` over the hit path),
   as a boolean instead of a console line.
2. If not: `tester.ensureVisible` — `Scrollable.ensureVisible`, a no-op
   without a scrollable ancestor — then one pump, then re-check. This is what
   keeps one scenario honest across a device matrix: a button under the fold
   of the iPhone SE is above it on the tablet, and neither run should have to
   say so.
3. Still unreachable → `ScenarioTargetError`, split by whether the center is
   inside the view: *covered* (another widget, `IgnorePointer`/
   `AbsorbPointer`) or *off screen with nothing scrolling to it*. A tap
   through a dialog barrier is now a loud failure instead of a no-op.

The underlying verbs get `warnIfMissed: false` — reachability is decided
before the action, once. The nothing-matches error gained the sentence that
routes the lazy-list case: an unbuilt child matches nothing, and `s.scrollTo`
is the verb that walks to it. `s.tester` remains the escape hatch, and
`strayFrames` already reports what it does.

The scroll happens inside the step, so the capture shows the screen the
pointer actually landed on — no honesty field needed.

Verified: `test/scenarios/actionability_test.dart` (below-the-fold tap and
enterText, covered target, off-screen target, lazy-list hint), the existing
verb suite unchanged, the app's runner suite against a real `flutter_tester`.

## Part 3 — the Semantics tab (plan)

The step triple is pixels + texts + widget tree. None of them shows what a
screen reader gets: labels, merge order, actions. That projection is
invisible in a screenshot *by nature*, which makes it exactly what a per-step
snapshot should carry — and it is the authoring surface for `Target.label`,
the way the Texts tab feeds `tap('NEXT')`.

### Capture — `.semantics.json` beside `.tree.json`

In the harness's step listener (`harness.dart`, where `.tree.json` is
written), read the semantics tree and write `$base.semantics.json`; add
`'semantics': path` to the step record. Semantics are already on —
`testWidgets` defaults `semanticsEnabled: true`, and `ensureSemantics` holds
a handle when a `Target.label` asked — so this is capture, not a behavior
change. When the owner is absent (`semanticsOwner == null`), write nothing
and omit the key: the tab says "not captured", never invents.

Per node, from `getSemanticsData()` (which folds merging into the node):

- `rect` in **screen logical coordinates** — compose `node.transform` down
  from the root, the same space the tree's layout boxes and the overlay paint
  in. That is what makes hover-highlight free.
- `label`, `value`, `hint`, `tooltip`, `textDirection` when set.
- `flags` and `actions` as name lists, not bitmasks — the JSON is read by
  the GUI, agents, and humans, in that order of frequency but the reverse
  order of patience.
- `children` in **traversal order** (`DebugSemanticsDumpOrder.traversalOrder`)
  — reading order is half of what the tab exists to show. Nodes merged into
  their parent are folded, not listed: the merged tree is the one assistive
  tech consumes.

**Measured 2026-08-10**, probe on the shop app's menu screen under bare
`flutter test` (serialize + `jsonEncode`, 200 rounds): **19 nodes, 2.2KB,
211µs per capture** — against the 11.5ms (raw) / 56ms (PNG) the image side of
a step already costs, noise. The probe also settled two access details the
plan had wrong or vague:

- The root node hangs off the **render view's own pipeline owner** —
  `tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode`
  — not `rootPipelineOwner.semanticsOwner`, whose owner exists but owns no
  tree (multi-view split). Same `renderViews.single` the screenshot capture
  already reads.
- The root node's rect is **physical** pixels (the DPR transform sits at the
  root, exactly as it does in the layer tree), so composing transforms from
  the root yields physical coordinates; normalize by `devicePixelRatio` to
  land in the logical space the overlay paints in.
- Traversal order is `debugListChildrenInOrder(DebugSemanticsDumpOrder
  .traversalOrder)` — public, debug-named, and the harness only ever runs
  where asserts are on, the same posture as the widget-inspector read.
- The claim "semantics are already on" held: the owner and tree exist in a
  plain `testWidgets` with no `ensureSemantics` handle, so capture changes
  nothing about what runs.

The probe earned its keep immediately: the shop app's own drink tiles carry
the label `☕` — an emoji a screen reader reads as "hot beverage" — which is
precisely the class of finding the tab exists to make visible.

### Wire and GUI

- `ScenarioRunStep` gains a nullable `semantics` path
  (`scenarios_results.dart` + build_runner). Null for old artifacts — the tab
  states it, no migration.
- Third `InspectDockTab` in `step_page.dart`: id `semantics`, label
  **Semantics** — the Flutter vocabulary the codebase already speaks, and
  distinct from the *Accessibility axes* (bold text, contrast), which are the
  pixel half of a11y where this tab is the structural half.
- Rows render like `ElementsView`: indent by depth; the row's headline is the
  label in quotes when there is one, else a flags summary (`button`,
  `textField`, `header` as badges); actions muted at the end.
- Hover highlights the node's rect on the screenshot. The overlay currently
  paints an `InspectNode`; generalize `NodeHighlightPainter` (or its call
  site) to take a plain `Rect` so both trees feed one highlight.
- **V1 has no semantics selection in the address** and the picker stays bound
  to Elements. The id spaces differ, and a picker that answers from two trees
  needs a decision about which wins; defer until wanted.

### Follow-on — guideline audits (not v1)

`flutter_test` ships `AccessibilityGuideline`s: `labeledTapTargetGuideline`,
`androidTapTargetGuideline` (48dp), `iOSTapTargetGuideline` (44dp),
`textContrastGuideline`. Run per step in the harness, record violations on
the step, badge the step in the flow — that turns the tab from a viewer into
an audit. Two things to settle first, both by measurement:

- `textContrastGuideline` reads rendered pixels; its cost under the capture
  path is unknown. Measure before promising, as with capture scale.
- Which tap-target guideline applies is the platform axis's business — run
  the one the assignment's platform names, both when it names none.

### Order of work

1. Harness capture + step field (guest side, root package).
2. Results model + tab UI with hover highlight (app side).
3. Audits, after the two measurements.

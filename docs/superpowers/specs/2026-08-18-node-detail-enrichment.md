# What else a node detail could carry — previews, run, scenarios

**Date:** 2026-08-18
**Question:** clicking a node in the Elements pane shows its source location and
its box. Could it show the text style, the colours, the properties, the
constraints — the things DevTools shows? How would it work, and what does each
cost?
**Answer:** most of it is already in hand and thrown away, one piece of it is
*wrong today* rather than missing, and the flagship feature — "what is this
style, really, after every merge and apply" — is a single getter, cheap enough
to ride the walk (see §2 for the number, and for the first version of that
number being noise), and not reachable from outside the app at all.

Everything below is measured on the `.fvmrc` pin (Flutter 3.47.0-0.1.pre),
in `flutter test` on this machine. The probes were throwaway and are deleted;
each measurement says how to reproduce it.

## Status: A, B, C, A′ and F are built. D, E, G, H, I are not.

The resolved text style ships — `InspectNode.textStyle`, read in
`GuestInspector._textStyleOf`, so previews, scenarios and drive all carry it.
With it: the provenance line, the authored-vs-resolved diff in the detail pane
(`set here`), the correction to `InspectTree.styles()`, and
`ScreenRead.describe`'s one-line `style` on every `find` and `at` hit.

Two things the build changed about the plan, both found by looking rather than
reasoning:

- **The paragraph is found by following only-children, not by a depth bound.**
  A depth bound was written first and was wrong in *both* directions — render
  depth is not widget depth, so "two levels" let a `Scaffold` adopt a `Text`
  two `Column`s inside it while an `Icon`'s three plumbing render objects still
  came back empty. See `_paragraphOf`.
- **Three fields are cut at capture** — `baseline`, `leadingDistribution`, and
  a `decoration` that decorates nothing. Every resolved style in a Material app
  carries all three, so they were a row each on every text node. Seen in the
  pane, not predicted.

**F shipped by the other route, and the route mattered.** §5 below costs out
filling the cockpit's detail pane through `getDetailsSubtree` — a `valueId`
side map, a round trip per selection, and a pane that has boxes on selection
and none in the walk. None of that was built, because a run launched through
flutterware already contains a reader that has all of it: the guest registers
`ext.flutterware.tree`, and it answers with the same walk previews and
scenarios are answered from. `RunInspector.read(preferGuest: true)` asks it
first and falls back to the service extension, so the cockpit's Screen tab
draws boxes, constraints, the widget's own properties, the resolved style, the
merge card — the whole pane, identical to the other two surfaces — on a run it
launched, and goes on saying *"structure and source only"* on one it merely
attached to. `InspectRead.fromGuest` is what the pane's `readsWidgets` reads.

Measured on the studio inspecting its own 835-node tree, ten reads a run,
three runs:

```
tree only        service 123–149ms     guest 253–303ms
tree + picture   service 424–464ms     guest 576–614ms
```

So the guest walk costs about twice the service tree, and a refresh costs about
30% more than it did. Two things about that number are worth keeping:

- **The picture is what makes it affordable.** A screenshot is ~300ms of the
  read either way, so the walk's extra ~150ms lands on a total that was never
  going to feel instant. This is a button, not a mirror.
- **It would have been ~730ms without `_rootId`.** The screenshot RPC takes an
  inspector id, so the first version paid for the whole service summary tree
  purely to read one field off it and throw the rest away. `getRootWidget`
  serializes the root node alone — **2.7ms against 122ms** — and that one call
  is the difference between +30% and +60%. Note its argument is `objectGroup`,
  not `groupName`; the wrong spelling answers `(-32000) Server error: Null
  check operator used on a null value`, which reads like a broken app.

What F did *not* take from §5: `parentRenderElement` — which ancestor actually
laid this node out — is in `getLayoutExplorerNode` and in no guest field, so it
stays an open item on either route.

Deliberately not extended to the `inspect` action. Its whole selling point is
answering about an app that never heard of flutterware, and a caller that wants
the richer tree already has `act`.

Everything from §4 down — render-object properties, the constraint chain — is
still analysis.

---

## Where a node detail comes from today

Four consumers, **one walk and one exception**:

| surface | reader | properties | layout | offstage |
|---|---|---|---|---|
| Previews (`lib/previews_guest.dart`) | `GuestInspector` | yes | yes | yes |
| Scenarios (`lib/src/scenarios/harness.dart:100`) | `GuestInspector` | yes | yes | yes |
| Run **drive** (`lib/src/drive/run_guest.dart:43`) | `GuestInspector` | yes | yes | yes |
| Run **cockpit** Elements tab (`app/lib/src/run/inspect.dart`) | `RunInspector` over the VM service | **none** | **none** | **none** |

So a change to `GuestInspector._propertiesOf`
([guest_inspect.dart:420](lib/src/inspect/guest_inspect.dart:420)) lands on
three of the four at once, and the cockpit is its own problem with its own
answer (§5).

What one node carries now ([node.dart:315](lib/src/inspect/node.dart:315)):
id, type, description, source, `local`, `offstage`, `properties` (≤12 entries,
`DiagnosticLevel.info` and up, each value ≤96 chars), `layout` (x/y/w/h,
constraints, repaint boundary, flex, flexFactor/flexFit), `label`, `selected`.

**Constraints are therefore already there** on three surfaces, and the detail
pane already prints them (`given: w 0..900, h 0..∞`). The gap the question
describes is narrower and sharper than "geometry and that's it".

---

## 1. The properties we show are the *authored* widget, not the rendered result

`Text.debugFillProperties` does `style?.debugFillProperties(properties)` —
the widget's **own** style, which is usually null.

Measured, a `Text` under an ordinary `MaterialApp`:

```
===== plain body =====
-- widget diagnostics (what we report today):
   data = "plain body"
-- resolved style (RenderParagraph.text.style):
   debugLabel = (englishLike bodyMedium 2021).merge((blackMountainView bodyMedium).apply)
   color = #1D1B20   family = Roboto   size = 14.0   weight = 400
   letterSpacing = 0.3   baseline = alphabetic   height = 1.4x
   leadingDistribution = even   decoration = #1D1B20 TextDecoration.none
```

One property against ten. And the one is the words.

### This is a live defect, not only a missing feature

[`InspectTree.styles()`](lib/src/inspect/node.dart:994) — the `styles: true`
flag, the `design` lens, "the type ramp and the palette as one small table,
the cheapest question in the drill-down" — buckets on
`properties['size']` and `properties['color']`. Those keys exist **only when
the author wrote an inline `style:`**. In a themed app that is a minority of
the text on the screen, and every un-styled `Text` is silently absent from the
ramp rather than counted in it.

The doc comment promises it settles "are these two greys the same grey". It
cannot see either grey unless both were written by hand.

Reproduce: pump `Text('x')` inside a `MaterialApp`, print
`element.widget.toDiagnosticsNode().getProperties()`.

---

## 2. The resolved style is one getter away, and it is free

`Text.build` merges `DefaultTextStyle.of(context).style` with the widget's
`style`, then folds in `MediaQuery.boldTextOf` and the line-height /
letter-spacing / word-spacing overrides, and hands the result to a `TextSpan`.
That span reaches `RenderParagraph`, where it is public:

```dart
// rendering/paragraph.dart:420
InlineSpan get text => _textPainter.text!;
```

So `(element.renderObject as RenderParagraph).text.style` **is** the style the
glyphs were painted with — every inherit, merge, apply and accessibility
override already applied.

### Cost, measured — **and the first number here was wrong**

984 elements (a `ListView` of 30 Material cards, 72 of them `RenderParagraph`),
warmed, 20 runs:

| pass | per full walk | delta |
|---|---|---|
| widget properties (today's rule) | 2367µs | — |
| + resolved text style | 2414µs | +47µs |
| + render object properties, every node | 3662µs | +1295µs (+55%) |

**The +47µs is noise, not a measurement, and it was published as "+2%".** It is
a delta between two 2400µs numbers over 20 runs, which is well inside the
run-to-run spread. Measured properly later — the style pass timed on its own,
1368 elements and 112 paragraphs, 40 runs after warming every path — it is
**288µs**, or about **2.6µs per paragraph** rather than the 0.65µs the delta
implied. Four times larger.

It is still small in absolute terms, and the conclusion (keep it, it rides the
walk) does not change. What changes is the reason to trust it: a delta between
two large numbers cannot measure a small one, and the honest way to size a pass
is to time that pass.

The number to quote now is better than either, because the style descriptions
are memoised across the walk (see `_describeStyle`): a screen has far fewer
styles than texts — 112 paragraphs, **three distinct resolved styles** — so the
resolved pass is **135µs** and adding the ambient style for the merge popover
costs a further **84µs**. Both together are less than the resolved pass alone
was costing before the memo.

The render-object row stands as measured; it is a delta of the same shape but
+1295µs is far outside the noise.

It also lights up **`Icon` for nothing**: an `Icon` is a `RichText` over an
icon font, so its size and colour arrive by the same route.

**Caveat.** `Element.renderObject` descends to the first descendant render
object. Under a `SelectionContainer` a `Text` builds a
`_SelectableTextContainer` first, so the robust version is a bounded descend
(≤6 levels), the same shape `_labelOf` already uses.

---

## 3. `debugLabel` is the provenance chain, already computed

`TextStyle` keeps a `debugLabel` and every `merge`, `apply`, `copyWith` and
`lerp` extends it (`painting/text_style.dart:899, 1007, 1085, 1151`). Material's
`Typography` seeds it per slot. Measured:

| written as | debugLabel |
|---|---|
| `Text('x')` | `(englishLike bodyMedium 2021).merge((blackMountainView bodyMedium).apply)` |
| `Text('x', style: theme.textTheme.titleLarge)` | `(englishLike titleLarge 2021).merge((blackMountainView titleLarge).apply)` |
| `Text('x', style: TextStyle(fontSize: 30, …))` | `((englishLike bodyMedium 2021).merge((blackMountainView bodyMedium).apply)).merge(unknown)` |
| under a bare `DefaultTextStyle(style: TextStyle(…))` | **null** |

It names the theme slot (`bodyMedium`), the geometry set (`englishLike … 2021`),
the colour set (`blackMountainView`, i.e. the light-theme black), and each step.
That is most of "what is this style" in one string, and it costs nothing —
it is a field on an object we already hold.

The two honest gaps: a hand-written `TextStyle` literal has no label and reads
`unknown`, and a style that never came from a labelled ancestor has no label at
all. Both are *absences of authorship*, not failures of the read, and should be
rendered as such.

### What "what is this style, really" should show

Both halves are in hand at the same moment, so the answer is a **diff**, not a
dump:

```
style          14 / w400 / #1D1B20 / Roboto      ← what it renders as
from           bodyMedium · englishLike 2021 · blackMountainView.apply
set here       size 14 → 30, color → #F44336     ← the widget's own style:, diffed
inherited      family, weight, letterSpacing, height, baseline, decoration
```

`set here` is the widget's own `properties` (already collected) intersected
with the resolved map; `inherited` is the remainder. Pure host-side arithmetic
over two maps — no new read, no new RPC.

---

## 4. For everything that is not text: the render object's own diagnostics

The second half of the "colours and properties" question. A `Container`'s
widget diagnostics give the readable `BoxDecoration(color: …, borderRadius: …)`;
its render object gives what was *computed*:

```
RenderDecoratedBox
   parentData  = offset=Offset(371.0, 281.0) (can use size)
   constraints = BoxConstraints(0.0<=w<=800.0, 0.0<=h<=600.0)
   size        = Size(58.0, 38.0)
   decoration  = BoxDecoration          ← collapsed to the type name
```

**They are complements, not substitutes.** The render object collapses a
`Decoration` to its type; the widget spells it out. Anything that shows one
should keep showing the other.

What it adds that nothing else has: `RenderOpacity.opacity`,
`RenderTransform`'s matrix, `RenderClipRRect.borderRadius`,
`RenderPhysicalShape`'s elevation and shadow colour, a `RenderFlex`'s
*resolved* `textDirection` where the widget's was null.

At +55% of the property pass it is the one thing here that should **not** run on
every node of every walk. It wants to be on-selection — and the door already
exists: `GuestInspector.renderObjectFor(id)`
([guest_inspect.dart:185](lib/src/inspect/guest_inspect.dart:185)), which
`GuestWatch` already calls exactly that way.

Two more things worth doing on-selection, which are wrong to do on a walk:

- **Do not truncate.** `shortenPropertyValue` cuts at 96 chars. A
  `DiagnosticsProperty` whose value is `Diagnosticable` answers `getProperties()`
  with its own fields — so a `BoxDecoration` can *expand* into
  `color`/`border`/`borderRadius` rows instead of ending in `…`. (This is
  exactly what the inspector's `expandPropertyValues` does over the wire;
  measured below.)
- **The constraint chain.** Walk `render.parent` up N levels reporting each
  ancestor's type, constraints and size. That answers the single most-asked
  Flutter layout question — *who made this unbounded, who squashed this* — and
  DevTools' Layout Explorer shows one level of it. Cheap, guest-only, no new
  transport.

---

## 5. The run cockpit can be filled without the guest — the SL3 note is narrower than it reads

> **Route not taken.** F shipped by preferring the guest's own walk (see the
> status section). Everything below stands as the answer for a run that has no
> guest in it — an app somebody else launched and the cockpit attached to —
> which is still the only way that pane will ever have a box in it.

`2026-07-31-sl3-inspect-surface-findings.md` says "**No offset, no global rect,
anywhere in the inspector surface**" and "`getDetailsSubtree` at depth 100
answers `(-32000) Server error`". Both are true. Read as "the cockpit's detail
pane cannot be filled", they are misleading — that is not what they measured.

Measured now, via the public entry point behind the same extension,
`subtreeDepth: 1` rather than 100:

```
getDetailsSubtree(id, group, subtreeDepth: 1)   →  0.66ms per node, in-process

Container: bg = BoxDecoration(color: …, borderRadius: BorderRadius.circular(7.0))
              ↳ color = MaterialColor(…)          ← nested, expanded
              ↳ borderRadius = BorderRadius.circular(7.0)
Row:       direction/mainAxisAlignment/crossAxisAlignment/spacing…
           renderObject = RenderFlex#0c2d9 relayoutBoundary=up2
              ↳ parentData  = offset=Offset(0.0, 282.0)
              ↳ constraints = BoxConstraints(0.0<=w<=800.0, 0.0<=h<=600.0)
              ↳ size        = Size(800.0, 36.0)
```

Widget properties **with nested expansion**, and for any node that owns a render
object, its offset, constraints and size. One call, on selection.

The offset is **parent-relative**, which is why a *global* rect — the thing
`annotateNodes` and cropping need — still requires the guest. SL3's conclusion
stands for what it was about. But a detail pane for one selected node is a
different question, and for that the answer is already on the wire.

`getLayoutExplorerNode` adds, from the same source read:
`flexFactor`, `flexFit`, `isBox`, an explicit `parentData: {offsetX, offsetY}`,
and `parentRenderElement` — *which ancestor actually laid this out*, which the
guest path does not report either. Note its `else if`: a **flex child gets
`flexFactor`/`flexFit` and no offset**.

### What it takes to wire

One real obstacle. `RunInspector.convertNode` derives `InspectNode.id` from the
tree's shape and **discards `valueId`**, deliberately — inspector ids are minted
per object group and die with it. But `getDetailsSubtree` takes a `valueId`. So
the cockpit must keep the read's group alive and hold a `path → valueId` side
map for as long as that tree is on screen, and drop both when it re-reads.
Small, but it is the design decision, not a detail.

Then `ElementsView`'s `readsWidgets: false` message —
*"Structure and source only — a tree read from outside the app carries no box
and no properties"* — becomes true of the *walk* and false of the *selection*,
and the pane can say so.

### What stays guest-only, measured

**The resolved TextStyle does not cross the wire.** `RichText`'s widget
diagnostics carry `text = text.toPlainText()` and no style; the render object
in `getLayoutExplorerNode` is serialized with `subtreeDepth: 0`, so
`RenderParagraph.debugDescribeChildren` — the one place the resolved span lives
— never leaves. Nothing in the inspector surface hands it out.

That makes §2/§3 a clean Layer-2 differentiator rather than a race with
DevTools, and it is worth stating plainly: **DevTools cannot show this either,
for the same reason.**

---

## The list, in cost order

| # | what | answers | surfaces | cost | complexity |
|---|---|---|---|---|---|
| A | ✅ resolved text style off `RenderParagraph.text.style` | *what size/colour/weight is this actually* | previews, scenarios, drive | 135µs / 112 paragraphs, memoised | **S** — one switch in `_propertiesOf`, one field on `InspectNode` |
| B | ✅ `debugLabel` provenance line | *where did this style come from* | same | free with A | **XS** |
| C | ✅ authored-vs-resolved diff | *what did this widget actually change* | same | free, host-side | **S** |
| A′ | ✅ fix `InspectTree.styles()` to bucket on the resolved style | the type ramp, correctly | same + every agent using `styles` | free with A | **XS**, but it changes a shipped answer |
| D | render-object properties **on selection** | opacity, transform, clip, elevation, computed flex | same | one guest round trip | **M** — new extension beside `renderObjectFor` |
| E | constraint chain (N ancestors: type, constraints, size) | *who made this unbounded* | same | walks `render.parent` | **M** |
| F | ✅ fill the cockpit detail pane — *from the guest, not `getDetailsSubtree`* | ends "structure and source only" on a run flutterware launched | run cockpit | +150ms a read, whole tree, no per-selection cost | **S** — `preferGuest` on one read, no `valueId` side map |
| G | expand nested property values instead of truncating | a `BoxDecoration` you can read | all four | on-selection only | **S** |
| H | effective paint chain (nearest painting ancestor, opacity, clip) | *what is this actually sitting on* | guest | walk | **M/L** — needs a rule for "which ancestor counts" |
| I | colour → theme role (`colorScheme.primary`) | *is this the brand blue or a literal* | guest | lookup | **L** — `guest_inspect.dart` deliberately imports `widgets` and not `material`; reaching `ThemeData` means a dynamic ancestor lookup or a second, optional guest file. `debugLabel` already gives the text half for free, so this is the least urgent of the lot. |

Not analysed, named so it is not mistaken for an omission: DevTools'
`setFlexFit` / `setFlexFactor` / `setFlexProperties` mutate the live app from
the pane. The RPCs exist and work. That is a different feature — inspection
that writes — and it belongs to its own decision.

## What it means for the surfaces above the data

Three things the enrichment does not get for free:

1. **`InspectNode.properties` is one flat map capped at twelve.** The resolved
   style alone is ten entries. Whatever lands has to be its own field, or the
   cap silently evicts the widget's own properties in favour of style rows.
2. **`_Detail` in `elements_view.dart` is a flat `ListView` of `_Pair`.** Ten
   more rows on every text node makes it unreadable; this wants sections
   (Layout / Style / Paint / Widget / Render) and expandable values.
3. **One screen grammar, three surfaces.** Per
   `2026-08-13-screen-handback-design.md`, whatever a node learns has to be
   answerable through `find`, `at` and `styles` as well as through the pane —
   and the per-call budget is why D, E, F and G are on-selection rather than in
   the walk.

## Reproducing

Two throwaway tests under `app/test/`, deleted after:

- **§1–§3** — pump a `MaterialApp` with four texts (bare, themed, inline-styled,
  under a `DefaultTextStyle`); for each, print
  `element.widget.toDiagnosticsNode().getProperties()` beside
  `(element.renderObject as RenderParagraph).text.style` and its
  `debugFillProperties`.
- **§2 cost** — 984-element tree, 30 warm-up walks over *all three* passes
  before timing any of them, then 20 timed runs each. Warm-up matters: without
  it the first pass carries the JIT and the deltas come out negative.
- **§5** — `WidgetInspectorService.instance.getRootWidgetSummaryTree(group)` for
  a `valueId`, then `getDetailsSubtree(id, group, subtreeDepth: 1)`. Public
  methods, so no VM service and no launched app are needed to read the shapes.
  `testExtension` is Flutter's own test harness and is **not** on the service —
  `getLayoutExplorerNode` has no public entry point and was read from the SDK
  source (`widgets/widget_inspector.dart:2277`) rather than measured.

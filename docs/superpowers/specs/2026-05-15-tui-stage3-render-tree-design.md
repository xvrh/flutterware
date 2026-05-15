# TUI Stage 3 — Render tree

**Status:** Draft
**Date:** 2026-05-15
**Scope:** Add the stage 3 "render tree" to the TUI framework — a cell-based
transcription of Flutter's render layer: `RenderObject`/`RenderBox`,
`BoxConstraints`, the layout protocol, intrinsic dimensions, dirty-tracking
via `PipelineOwner`, and a starter set of render objects (`RenderText`,
`RenderPadding`, `RenderConstrainedBox`, `RenderFlex`, `RenderDecoratedBox`).

**Extends:** [`2026-05-15-tui-stage2-paint-kit-design.md`](./2026-05-15-tui-stage2-paint-kit-design.md)

---

## Context

Stage 1 delivered the engine (`Terminal`, `CellBuffer`, diff-to-ANSI, key
parsing). Stage 2 delivered the paint kit: `CellOffset`/`CellSize`/`CellRect`
geometry and a functional `Painter` that paints into a shared `CellBuffer`
through a translation offset and a clip.

Stage 3 builds the layout engine on top. It transcribes Flutter's render layer
— the tree that takes constraints from a parent, computes sizes and child
positions, and paints — with the single substitution the roadmap established:
**cells instead of pixels**. Every coordinate, size, and constraint is an
integer count of terminal cells.

The render layer is deliberately built *before* the widget layer (stage 4).
After stage 3 the framework has a working, independently testable layout
engine; stage 4 adds the `Widget`/`Element` machinery that drives it
reactively.

## Goals

1. `BoxConstraints` — cell-based min/max width & height, and the constraint
   algebra (`tight`, `loose`, `constrain`, `deflate`, `enforce`, …).
2. `RenderObject` — tree structure (`parent`, `attach`/`detach`,
   `adoptChild`/`dropChild`, `depth`), the paint entry point, and
   dirty-tracking (`markNeedsLayout`, `markNeedsPaint`, relayout boundaries).
3. `RenderBox` — the box layout protocol: `layout(constraints,
   {parentUsesSize})`, `performLayout`/`performResize`/`sizedByParent`, `size`,
   and the four intrinsic-dimension methods.
4. `PipelineOwner` — owns dirty nodes and flushes layout (`flushLayout`) and
   paint (`flushPaint`).
5. `RenderTuiView` — the root render object, bridging the tree to
   `Terminal.draw`.
6. A starter set of render objects: `RenderText` (leaf), `RenderPadding`,
   `RenderConstrainedBox`, `RenderFlex` (the shared mechanism behind
   `Row`/`Column`), and `RenderDecoratedBox` (borders + background).
7. A demo (`render_tree_demo.dart`) showing a laid-out, multi-panel screen.

## Non-goals (for this round)

- **No widgets, elements, or `setState`.** That is stage 4. Stage 3 trees are
  constructed and mutated imperatively.
- **No dry layout.** Flutter's `computeDryLayout`/`getDryLayout` is a
  layout-twice optimization for `RenderFlex`; stage 3 lays children out
  directly. Intrinsics *are* in scope; dry layout is not.
- **No layers, hence no repaint boundaries.** Painting goes into one shared
  `CellBuffer`; there is no compositing tree. `markNeedsPaint` therefore sets
  an owner-wide flag and the whole tree repaints. Relayout *is* localized.
  See "Dirty-tracking" below.
- **No intrusive child linked-list.** Flutter's `ContainerRenderObjectMixin`
  uses a linked list so the Element tree can splice children in O(1). With no
  Element tree yet, multi-child render objects hold a plain `List<RenderBox>`.
  Revisit in stage 4.
- **No mouse, scrolling, hit-testing, or `RenderAlign`.** Out of scope;
  candidates for later stages.
- **No wide-character handling.** Every cell is one column, consistent with
  stages 1–2.
- **No changes to `CellBuffer`, `Cell`, or the stage 2 `Painter`.** The render
  tree sits entirely on top of the existing paint kit.

## Architecture

```
Painter (stage 2 — shared CellBuffer + origin + clip)
    ▲
    │  render objects paint through it
    │
RenderObject            tree node: parent, depth, attach, dirty-tracking
    └── RenderBox        box layout protocol: constraints → size, intrinsics
          ├── RenderTuiView          root; bridges to Terminal.draw
          ├── RenderText             leaf; wraps + draws text
          ├── RenderPadding          single child; insets by EdgeInsets
          ├── RenderConstrainedBox   single child; applies extra constraints
          ├── RenderDecoratedBox     single child; paints border + background
          └── RenderFlex             multi child; Row/Column mechanism

PipelineOwner   owns dirty nodes; flushLayout() / flushPaint()
```

New code lives under a new subdirectory `app/lib/src/tui/render/` — the tree is
nine files and would crowd the currently-flat `tui/` directory.

### The paint model

A render object's `paint` method receives a `Painter` **already translated to
that object's top-left corner**:

```dart
void paint(Painter painter);
```

This adapts Flutter's `paint(PaintingContext context, Offset offset)` to the
stage 2 paint kit. A parent paints a child by translating the painter by the
child's offset (stored in the child's `parentData`):

```dart
void paint(Painter painter) {
  // ...paint self...
  final childOffset = (child.parentData as BoxParentData).offset;
  child.paint(painter.translate(childOffset));
}
```

A parent that must clip an overflowing child paints it through
`painter.clip(rect)` first. Because the stage 2 `Painter` routes every write
through one clipped chokepoint, a child physically cannot paint outside the
region handed to it.

## `BoxConstraints` — `box_constraints.dart`

Immutable. All four fields are integer cell counts; `width` means columns and
`height` means rows, matching `CellRect` and Flutter's naming so the
transcription stays mechanical.

```dart
class BoxConstraints {
  final int minWidth;
  final int maxWidth;   // may be a large sentinel for "unbounded"
  final int minHeight;
  final int maxHeight;

  const BoxConstraints({
    this.minWidth = 0,
    this.maxWidth = unbounded,
    this.minHeight = 0,
    this.maxHeight = unbounded,
  });

  /// Sentinel for an unbounded axis. A large int rather than a real infinity
  /// because cell counts are integers.
  static const int unbounded = 1 << 30;

  const BoxConstraints.tight(CellSize size);          // min == max == size
  const BoxConstraints.tightFor({int? width, int? height});
  const BoxConstraints.loose(CellSize size);          // min 0, max == size
  const BoxConstraints.expand({int? width, int? height});

  bool get hasBoundedWidth  => maxWidth  < unbounded;
  bool get hasBoundedHeight => maxHeight < unbounded;
  bool get isTight => minWidth == maxWidth && minHeight == maxHeight;

  CellSize get biggest;   // (maxHeight, maxWidth) — clamped if unbounded
  CellSize get smallest;  // (minHeight, minWidth)

  int constrainWidth([int width = unbounded]);
  int constrainHeight([int height = unbounded]);
  CellSize constrain(CellSize size);

  BoxConstraints deflate(EdgeInsets insets);  // shrink max, clamp min ≥ 0
  BoxConstraints loosen();                    // min → 0
  BoxConstraints enforce(BoxConstraints parent); // clamp into parent's range
  BoxConstraints tighten({int? width, int? height});
}
```

`constrain` clamps a desired size into the allowed range — the call every
`performLayout` ends with. `deflate` is used by `RenderPadding`; `enforce` by
`RenderConstrainedBox`.

## `RenderObject` — `render_object.dart`

The tree node and dirty-tracking. Generic over child management; `RenderBox`
adds the box protocol.

```dart
abstract class RenderObject {
  RenderObject? get parent;
  ParentData? parentData;     // set by the parent via adoptChild
  int get depth;              // 0 at the root; used to order layout flushes
  PipelineOwner? get owner;

  bool get attached;
  void attach(PipelineOwner owner);
  void detach();

  // Subclasses call these when (un)installing a child.
  void adoptChild(RenderObject child);
  void dropChild(RenderObject child);
  void redepthChild(RenderObject child);
  void visitChildren(void Function(RenderObject child) visitor);

  // Dirty-tracking.
  void markNeedsLayout();
  void markNeedsPaint();
  void setupParentData(RenderObject child);  // installs the right ParentData

  void performLayout();   // overridden by subclasses
  // ...paint is declared on RenderBox (needs a Painter)...
}
```

`ParentData` is the per-child data a parent attaches:

```dart
class ParentData {}                          // base, empty
class BoxParentData extends ParentData {
  CellOffset offset = CellOffset.zero;        // child's top-left in parent space
}
class FlexParentData extends BoxParentData {
  int flex = 0;                               // 0 == inflexible
  FlexFit fit = FlexFit.loose;
}
```

### `PipelineOwner`

```dart
class PipelineOwner {
  final List<RenderObject> _nodesNeedingLayout = [];
  bool _needsPaint = false;

  void flushLayout();   // depth-sorted; each node still dirty runs layout
  void flushPaint();    // if _needsPaint, signals the view to repaint
}
```

`flushLayout` sorts dirty nodes shallowest-first and re-runs layout from each
(skipping nodes already cleaned by an ancestor's relayout). Because layout
starts at a *relayout boundary*, the work is localized to that subtree.

## Dirty-tracking — relayout boundaries

`markNeedsLayout` walks up to the nearest **relayout boundary** and enqueues
*that* node, not the dirtied leaf. A node is its own relayout boundary when
re-laying it out cannot change its parent's layout — i.e. when any of:

- the constraints it received are tight (`constraints.isTight`), or
- it is `sizedByParent`, or
- its parent did not pass `parentUsesSize: true`, or
- it is the root (`RenderTuiView`).

`_relayoutBoundary` is computed and cached in `layout()`. `markNeedsLayout`
sets `_needsLayout`, and if `this` is not itself the boundary, recurses into
the parent; the boundary node is the one enqueued on the owner.

**Repaint has no equivalent.** Flutter localizes repaints with layers and
repaint boundaries; stage 3 has neither (it paints into one shared buffer).
`markNeedsPaint` therefore sets `PipelineOwner._needsPaint`, and the next frame
repaints the whole tree from `RenderTuiView`. This is an accepted stage 3
limitation, lifted in stage 4 when a compositing/layer model arrives. Relayout
*is* localized — that is the expensive part and the part the boundary logic
protects.

## `RenderBox` — `render_box.dart`

```dart
abstract class RenderBox extends RenderObject {
  BoxConstraints get constraints;   // the constraints from the last layout
  CellSize get size;                // set by performLayout/performResize

  /// The non-overridable layout entry point. Stores the relayout boundary,
  /// runs performResize (if sizedByParent) then performLayout, records size,
  /// clears the dirty flag.
  void layout(BoxConstraints constraints, {bool parentUsesSize = false});

  bool get sizedByParent => false;  // override → size depends only on constraints
  void performResize();             // override when sizedByParent
  @override
  void performLayout();             // every box overrides this

  // Intrinsic dimensions. Public getters memo-check then call the compute*.
  int getMinIntrinsicWidth(int height);
  int getMaxIntrinsicWidth(int height);
  int getMinIntrinsicHeight(int width);
  int getMaxIntrinsicHeight(int width);

  int computeMinIntrinsicWidth(int height) => 0;   // overridden by subclasses
  int computeMaxIntrinsicWidth(int height) => 0;
  int computeMinIntrinsicHeight(int width) => 0;
  int computeMaxIntrinsicHeight(int width) => 0;

  void paint(Painter painter);      // painter is translated to this box's origin
}
```

`BoxParentData` carries the child's `offset`. A parent's `performLayout`:

1. calls `child.layout(childConstraints, parentUsesSize: true)`,
2. reads `child.size`,
3. writes `(child.parentData as BoxParentData).offset`,
4. sets its own `size` via `constraints.constrain(...)`.

## Render objects

### `RenderText` — `render_text.dart`

The leaf. Wraps text to the incoming width constraint and paints it with the
stage 2 `Painter.drawText`.

- Fields: `text` (setter calls `markNeedsLayout`), `fg`, `bg`, `style`,
  `hAlign`, `vAlign`, `wrap` (setters that affect layout call
  `markNeedsLayout`; paint-only setters call `markNeedsPaint`).
- `performLayout`: if `wrap` and `constraints.hasBoundedWidth`, lay out as
  `wrapText(text, constraints.maxWidth)`; else split on `\n` only. Size is
  `constraints.constrain(CellSize(lineCount, longestLineLength))`.
- Intrinsics: `computeMaxIntrinsicWidth` = longest line unwrapped;
  `computeMinIntrinsicWidth` = longest single word; `computeMin/MaxIntrinsic
  Height(width)` = `wrapText(text, width).length`.
- `paint`: `painter.drawText(CellRect.fromOffsetSize(zero, size), text, …)`.

### `RenderPadding` — `render_padding.dart`

Single child; insets it by an `EdgeInsets`.

```dart
class EdgeInsets {
  final int left, top, right, bottom;
  const EdgeInsets.all(int v);
  const EdgeInsets.symmetric({int horizontal, int vertical});
  const EdgeInsets.only({int left, int top, int right, int bottom});
  int get horizontal => left + right;
  int get vertical => top + bottom;
}
```

- `performLayout`: `child.layout(constraints.deflate(padding),
  parentUsesSize: true)`; child offset = `CellOffset(padding.top,
  padding.left)`; size = `constraints.constrain(CellSize(child.size.rows +
  padding.vertical, child.size.cols + padding.horizontal))`. With no child,
  size is the padding alone, constrained.
- Intrinsics: child intrinsic + the corresponding padding.
- `paint`: paint the child through `painter.translate(childOffset)`.

### `RenderConstrainedBox` — `render_constrained_box.dart`

Single child; imposes `additionalConstraints` on top of what it receives.

- `performLayout`: `child.layout(additionalConstraints.enforce(constraints),
  parentUsesSize: true)`; size = `child.size`. With no child, size =
  `additionalConstraints.enforce(constraints).constrain(CellSize.zero)`.
- Underpins stage 4's `SizedBox` and `ConstrainedBox`, and fixed-extent
  regions (a fixed-height header is `RenderConstrainedBox` with a tight
  height).
- Intrinsics: clamp the child's intrinsics into `additionalConstraints`.

### `RenderDecoratedBox` — `render_decorated_box.dart`

Single child; paints a `BoxDecoration` (background fill and/or border) and
then the child. Faithful to Flutter: the decoration does **not** affect layout
— a bordered panel is `RenderDecoratedBox` wrapping `RenderPadding(1, …)` so
content clears the 1-cell border.

```dart
class BoxBorder {
  final BorderChars chars;     // reuses the stage 2 BorderChars
  final Color fg;
  const BoxBorder({this.chars = const BorderChars.single(),
                   this.fg = Color.defaultFg});
}
class BoxDecoration {
  final Cell? fill;            // background; null → transparent
  final BoxBorder? border;
}
```

- `performLayout`: pass constraints straight through to the child; size =
  `child.size` (or `constraints.smallest` with no child).
- `paint`: if `fill != null`, `painter.fill(fill)`; paint the child at offset
  zero; if `border != null`, `painter.drawBorder(bounds, …)` last so the
  border sits on top.
- Intrinsics: delegate to the child unchanged.

### `RenderFlex` — `render_flex.dart`

The multi-child workhorse behind `Row` and `Column`. Children held in a plain
`List<RenderBox>`; each child's `parentData` is a `FlexParentData`.

```dart
enum Axis { horizontal, vertical }
enum MainAxisAlignment { start, end, center,
                         spaceBetween, spaceAround, spaceEvenly }
enum CrossAxisAlignment { start, end, center, stretch }
enum MainAxisSize { min, max }
enum FlexFit { tight, loose }

class RenderFlex extends RenderBox {
  Axis direction;
  MainAxisAlignment mainAxisAlignment;
  CrossAxisAlignment crossAxisAlignment;
  MainAxisSize mainAxisSize;
  // child list mutators: add / insert / remove → adoptChild/dropChild
}
```

`performLayout` (two-pass, transcribed from Flutter's `RenderFlex`):

1. **Inflexible pass.** Lay out every child with `flex == 0`. Main axis:
   unbounded (`0..unbounded`). Cross axis: `0..maxCross` normally, or tight
   `maxCross` when `crossAxisAlignment == stretch`. Accumulate
   `allocatedMain` (sum) and `crossExtent` (max).
2. **Flex distribution.** `freeMain = maxMain - allocatedMain` (clamped ≥ 0);
   `totalFlex = Σ flex`. Each flex child gets a main extent proportional to
   its flex factor. `FlexFit.tight` → tight main; `FlexFit.loose` →
   `0..extent`.
3. **Own size.** Main extent = `maxMain` when `mainAxisSize == max`, else
   `allocatedMain + distributed`. Cross extent = `crossExtent`. Run both
   through `constraints.constrain`.
4. **Positioning.** Compute leading and between-child gaps from
   `mainAxisAlignment`; place each child's main offset; place its cross offset
   per `crossAxisAlignment` (`stretch` already sized it to fill).

**Integer space distribution.** Flutter splits free space and alignment gaps
with doubles; cells are integers. Both the flex distribution (step 2) and the
`spaceBetween`/`spaceAround`/`spaceEvenly` gaps (step 4) use a Bresenham-style
split: floor the per-unit amount, accumulate the remainder, and hand out one
extra cell front-to-back until the remainder is exhausted. This guarantees the
children exactly tile the parent — no dropped or doubled cell — and the result
is deterministic.

Intrinsics: along the main axis, sum inflexible children's main intrinsics and
scale flex children by the largest per-flex intrinsic; along the cross axis,
take the max. (Transcribed from Flutter's `_getIntrinsicSize`.)

## `RenderTuiView` — `render_view.dart`

The root. It is a `RenderObject` (not a `RenderBox`) holding one `RenderBox`
child, a `configuration` (the terminal `CellSize`), and the `PipelineOwner`
attachment point.

```dart
class RenderTuiView extends RenderObject {
  RenderTuiView(CellSize configuration);
  CellSize get configuration;
  set configuration(CellSize value);   // → markNeedsLayout
  RenderBox? get child;
  set child(RenderBox? value);         // → adoptChild/dropChild

  void performLayout();                // child.layout(tight full-screen)
  void compositeFrame(Painter painter);// flush layout, paint child from origin
}
```

`performLayout` lays the child out with
`BoxConstraints.tight(configuration)`. `compositeFrame` runs
`owner.flushLayout()` then paints the child through the supplied `Painter`.
The view is always a relayout boundary (it has no parent).

### Driving a frame

```dart
final view = RenderTuiView(CellSize(rows, cols))..child = root;
final owner = PipelineOwner();
view.attach(owner);

terminal.draw((buffer) {
  owner.flushLayout();
  view.compositeFrame(Painter(buffer));
});
```

- **Resize:** `view.configuration = newSize;` (the setter marks needs-layout)
  then request a redraw.
- **Content change:** mutate a render object (e.g. `someText.text = '…'`);
  its setter calls `markNeedsLayout`, which enqueues the nearest relayout
  boundary; the next `flushLayout` re-lays only that subtree.

## Files touched

- **Create** `app/lib/src/tui/render/box_constraints.dart`
- **Create** `app/lib/src/tui/render/render_object.dart` — `RenderObject`,
  `ParentData`, `BoxParentData`, `FlexParentData`, `PipelineOwner`
- **Create** `app/lib/src/tui/render/render_box.dart`
- **Create** `app/lib/src/tui/render/render_view.dart`
- **Create** `app/lib/src/tui/render/render_text.dart`
- **Create** `app/lib/src/tui/render/render_padding.dart` — `RenderPadding`,
  `EdgeInsets`
- **Create** `app/lib/src/tui/render/render_constrained_box.dart`
- **Create** `app/lib/src/tui/render/render_decorated_box.dart` —
  `RenderDecoratedBox`, `BoxDecoration`, `BoxBorder`
- **Create** `app/lib/src/tui/render/render_flex.dart` — `RenderFlex`,
  `FlexParentData`, axis/alignment enums
- **Create** `app/examples/tui/render_tree_demo.dart` — the demo
- **Modify** `app/lib/src/tui/tui.dart` — export the new public types
- **Modify** `app/lib/src/tui/README.md` — note stage 3 is done, update the
  file table and limitations
- **Create** `app/test/tui/render/box_constraints_test.dart`
- **Create** `app/test/tui/render/render_object_test.dart` — attach/detach,
  depth, relayout-boundary localization
- **Create** `app/test/tui/render/render_box_test.dart` — layout protocol,
  intrinsics
- **Create** `app/test/tui/render/render_text_test.dart`
- **Create** `app/test/tui/render/render_padding_test.dart`
- **Create** `app/test/tui/render/render_constrained_box_test.dart`
- **Create** `app/test/tui/render/render_decorated_box_test.dart`
- **Create** `app/test/tui/render/render_flex_test.dart`
- **Create** `app/test/tui/render/render_view_test.dart`
- **Modify** `docs/superpowers/tui-roadmap.md` — mark stage 3 done, link this
  spec

## Testing strategy

The whole render layer is testable without a tty: build a tree, call
`layout(constraints)`, and assert `size` and each child's
`parentData.offset`; for paint, construct a `CellBuffer`, wrap it in a
`Painter`, call `paint`, and read cells back with `CellBuffer.get`. No
`Terminal`, no ANSI, no golden files.

Key cases:

- **`BoxConstraints`** — `constrain` clamps; `deflate`/`enforce`/`loosen`;
  unbounded-axis handling; `isTight`.
- **`RenderObject`** — `attach`/`detach` propagates to children; `depth` is
  correct after `redepthChildren`; `markNeedsLayout` on a deep node enqueues
  the right relayout boundary and does **not** dirty siblings (the headline
  dirty-tracking test).
- **`RenderBox`** — `layout` records `size` and clears the dirty flag;
  `sizedByParent` routes through `performResize`; intrinsics return expected
  values.
- **`RenderText`** — wrap vs. no-wrap sizing; alignment in paint; intrinsics
  (longest word / longest line / wrapped height).
- **`RenderPadding`** — size = child + insets; child offset; empty-child case.
- **`RenderConstrainedBox`** — `additionalConstraints` enforced within
  incoming constraints; empty-child case.
- **`RenderDecoratedBox`** — size delegates to child; paint draws fill then
  child then border; border-on-top ordering.
- **`RenderFlex`** — main/cross sizing; all `MainAxisAlignment` and
  `CrossAxisAlignment` values; flex factors with `tight`/`loose` fit;
  `MainAxisSize.min` vs `max`; **integer distribution exactly tiles the parent
  with no dropped or doubled cell** (dedicated test).
- **`RenderTuiView`** — lays the child out tight to `configuration`;
  `compositeFrame` paints; resize re-lays out.

The only thing requiring a real terminal is the demo, covered by manual smoke.

## Success criteria

1. All existing tests still pass; `flutter analyze` is clean.
2. Every new `app/test/tui/render/` suite passes.
3. `dart tool/prepare_submit.dart` produces no diff.
4. `render_tree_demo.dart` runs in a real terminal:
   - A multi-panel screen renders: a fixed-height header, a row of two
     bordered panels (left `flex: 1`, right `flex: 2`), and a footer.
   - Panel borders, backgrounds, and wrapped text are laid out correctly and
     do not bleed across panels.
   - Pressing a key mutates one panel's text; only that subtree re-lays out
     (the sibling panel, a relayout boundary, is untouched), and the screen
     updates correctly.
   - Resizing the terminal re-lays out the whole screen to the new size.
   - Pressing `q` exits cleanly; the terminal is restored.

## Open questions deferred

- **Repaint boundaries / layers.** Localized repaint needs a compositing
  model; deferred to stage 4 alongside the Element tree.
- **Intrusive child linked-list** (`ContainerRenderObjectMixin`). A plain
  `List` suffices until the Element tree needs O(1) child splicing — revisit
  in stage 4.
- **`RenderAlign` / `RenderStack` / `RenderConstrainedOverflowBox`** and other
  render objects — add as stage 4 widgets demand them.
- **Dry layout** for `RenderFlex` — a layout-twice optimization; add only if
  profiling shows flex layout is hot.
- **Hit-testing and mouse input** — needed once interactive widgets arrive.

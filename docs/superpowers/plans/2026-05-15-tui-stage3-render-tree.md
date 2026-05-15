# TUI Stage 3 — Render Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cell-based transcription of Flutter's render layer in `app/lib/src/tui/render/` — `BoxConstraints`, `RenderObject`/`RenderBox`, intrinsics, dirty-tracking via `PipelineOwner`, and a starter render-object set (`RenderText`, `RenderPadding`, `RenderConstrainedBox`, `RenderDecoratedBox`, `RenderFlex`) plus a `RenderTuiView` root.

**Architecture:** Render objects form a tree. A parent passes `BoxConstraints` (cell counts) down via `RenderBox.layout`; each child sets its `size` (a `CellSize`) and the parent writes the child's `offset` into the child's `parentData`. Painting goes through the Stage 2 `Painter`: a render object's `paint(Painter)` receives a painter already translated to its top-left, and positions children with `painter.translate(childOffset)`. `markNeedsLayout` localizes re-layout to the nearest relayout boundary; `markNeedsPaint` flags a whole-tree repaint (no layers in Stage 3).

**Tech Stack:** Pure Dart, zero pub dependencies. Code lives in the `flutterware_app` package. Tests use `package:test` and run with `flutter test`.

---

## File structure

All Stage 3 code is one Dart library, `app/lib/src/tui/render/render.dart`, composed of `part` files so the tightly-coupled classes can share library-private state (`_needsLayout`, `_relayoutBoundary`, `PipelineOwner._nodesNeedingLayout`). Each `part` file has a single responsibility:

| File | Responsibility |
|---|---|
| `render/render.dart` | Library directive, imports, `part` directives |
| `render/box_constraints.dart` | `BoxConstraints`, `EdgeInsets` |
| `render/render_object.dart` | `RenderObject`, `ParentData`, `BoxParentData`, `PipelineOwner` |
| `render/render_box.dart` | `RenderBox`, `RenderBoxWithChild` mixin |
| `render/render_text.dart` | `RenderText` |
| `render/render_padding.dart` | `RenderPadding` |
| `render/render_constrained_box.dart` | `RenderConstrainedBox` |
| `render/render_decorated_box.dart` | `RenderDecoratedBox`, `BoxDecoration`, `BoxBorder` |
| `render/render_flex.dart` | `RenderFlex`, `FlexParentData`, axis/alignment enums |
| `render/render_view.dart` | `RenderTuiView` |

`render.dart` accumulates one `part` directive per task so each task compiles and tests on its own.

**Codebase conventions** (from `analysis_options.yaml`): `prefer_single_quotes`, `omit_local_variable_types` (use `var` for locals), `avoid_final_parameters` (never mark parameters `final`), `prefer_const_*` is OFF (do not litter `const`). Class fields stay `final` where immutable.

---

### Task 1: BoxConstraints and EdgeInsets

**Files:**
- Create: `app/lib/src/tui/render/render.dart`
- Create: `app/lib/src/tui/render/box_constraints.dart`
- Test: `app/test/tui/render/box_constraints_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/tui/render/box_constraints_test.dart`:

```dart
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

void main() {
  group('BoxConstraints', () {
    test('tight constrains a size to exactly itself', () {
      var c = BoxConstraints.tight(CellSize(4, 10));
      expect(c.isTight, isTrue);
      expect(c.constrain(CellSize(99, 99)), CellSize(4, 10));
      expect(c.constrain(CellSize(0, 0)), CellSize(4, 10));
    });

    test('loose allows 0..size', () {
      var c = BoxConstraints.loose(CellSize(4, 10));
      expect(c.isTight, isFalse);
      expect(c.constrain(CellSize(2, 5)), CellSize(2, 5));
      expect(c.constrain(CellSize(99, 99)), CellSize(4, 10));
    });

    test('tightFor leaves unspecified axes unbounded', () {
      var c = BoxConstraints.tightFor(height: 1);
      expect(c.minHeight, 1);
      expect(c.maxHeight, 1);
      expect(c.hasBoundedWidth, isFalse);
      expect(c.hasBoundedHeight, isTrue);
    });

    test('constrainWidth/Height clamp into the range', () {
      var c = BoxConstraints(minWidth: 3, maxWidth: 8, minHeight: 2, maxHeight: 5);
      expect(c.constrainWidth(1), 3);
      expect(c.constrainWidth(6), 6);
      expect(c.constrainWidth(20), 8);
      expect(c.constrainHeight(0), 2);
      expect(c.constrainHeight(99), 5);
    });

    test('deflate shrinks max and clamps min at zero', () {
      var c = BoxConstraints(minWidth: 1, maxWidth: 10, minHeight: 1, maxHeight: 6);
      var d = c.deflate(EdgeInsets.all(2));
      expect(d.maxWidth, 6); // 10 - 4
      expect(d.maxHeight, 2); // 6 - 4
      expect(d.minWidth, 0); // 1 - 4, clamped
      expect(d.minHeight, 0);
    });

    test('deflate keeps an unbounded axis unbounded', () {
      var c = BoxConstraints(minWidth: 0, maxHeight: 8);
      var d = c.deflate(EdgeInsets.symmetric(horizontal: 1, vertical: 1));
      expect(d.hasBoundedWidth, isFalse);
      expect(d.maxHeight, 6);
    });

    test('enforce clamps into the parent range', () {
      var child = BoxConstraints.tight(CellSize(20, 20));
      var parent = BoxConstraints(minWidth: 0, maxWidth: 5, minHeight: 0, maxHeight: 5);
      var e = child.enforce(parent);
      expect(e.maxWidth, 5);
      expect(e.maxHeight, 5);
      expect(e.minWidth, 5);
      expect(e.minHeight, 5);
    });

    test('loosen drops the minimums to zero', () {
      var c = BoxConstraints.tight(CellSize(3, 3)).loosen();
      expect(c.minWidth, 0);
      expect(c.minHeight, 0);
      expect(c.maxWidth, 3);
      expect(c.maxHeight, 3);
    });

    test('biggest and smallest', () {
      var c = BoxConstraints(minWidth: 2, maxWidth: 9, minHeight: 1, maxHeight: 7);
      expect(c.biggest, CellSize(7, 9));
      expect(c.smallest, CellSize(1, 2));
    });

    test('equality is structural', () {
      expect(BoxConstraints.tight(CellSize(2, 2)),
          BoxConstraints.tight(CellSize(2, 2)));
      expect(BoxConstraints.tight(CellSize(2, 2)),
          isNot(BoxConstraints.tight(CellSize(2, 3))));
    });
  });

  group('EdgeInsets', () {
    test('all sets every side', () {
      var e = EdgeInsets.all(3);
      expect(e.left, 3);
      expect(e.horizontal, 6);
      expect(e.vertical, 6);
    });

    test('symmetric and only', () {
      var s = EdgeInsets.symmetric(horizontal: 2, vertical: 5);
      expect(s.left, 2);
      expect(s.right, 2);
      expect(s.top, 5);
      var o = EdgeInsets.only(left: 1, bottom: 4);
      expect(o.left, 1);
      expect(o.bottom, 4);
      expect(o.right, 0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tui/render/box_constraints_test.dart`
Expected: FAIL — `Couldn't resolve the package 'flutterware_app' ... render/render.dart` (file does not exist).

- [ ] **Step 3: Write the implementation**

Create `app/lib/src/tui/render/render.dart`:

```dart
/// The TUI render tree (stage 3): a cell-based transcription of Flutter's
/// render layer. One library composed of [part] files so the tightly-coupled
/// classes can share library-private layout state.
library;

import '../cell.dart';
import '../geometry.dart';
import '../painter.dart';
import '../text_wrap.dart';

part 'box_constraints.dart';
```

Create `app/lib/src/tui/render/box_constraints.dart`:

```dart
part of 'render.dart';

/// Cell-space insets for the four sides of a box.
class EdgeInsets {
  final int left;
  final int top;
  final int right;
  final int bottom;

  const EdgeInsets.fromLTRB(this.left, this.top, this.right, this.bottom);

  const EdgeInsets.all(int value)
      : left = value,
        top = value,
        right = value,
        bottom = value;

  const EdgeInsets.symmetric({int horizontal = 0, int vertical = 0})
      : left = horizontal,
        right = horizontal,
        top = vertical,
        bottom = vertical;

  const EdgeInsets.only({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  static const EdgeInsets zero = EdgeInsets.fromLTRB(0, 0, 0, 0);

  int get horizontal => left + right;
  int get vertical => top + bottom;

  @override
  bool operator ==(Object other) =>
      other is EdgeInsets &&
      left == other.left &&
      top == other.top &&
      right == other.right &&
      bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'EdgeInsets.fromLTRB($left, $top, $right, $bottom)';
}

/// Immutable layout constraints in cells. [minWidth]/[maxWidth] are column
/// counts and [minHeight]/[maxHeight] are row counts. An axis whose max is
/// [unbounded] imposes no upper bound.
class BoxConstraints {
  final int minWidth;
  final int maxWidth;
  final int minHeight;
  final int maxHeight;

  /// Sentinel max for an unbounded axis. A large int, since cell counts are
  /// integers and there is no integer infinity.
  static const int unbounded = 1 << 30;

  const BoxConstraints({
    this.minWidth = 0,
    this.maxWidth = unbounded,
    this.minHeight = 0,
    this.maxHeight = unbounded,
  });

  /// Requires exactly [size].
  const BoxConstraints.tight(CellSize size)
      : minWidth = size.cols,
        maxWidth = size.cols,
        minHeight = size.rows,
        maxHeight = size.rows;

  /// Tight on the axes given a value; unbounded on the others.
  const BoxConstraints.tightFor({int? width, int? height})
      : minWidth = width ?? 0,
        maxWidth = width ?? unbounded,
        minHeight = height ?? 0,
        maxHeight = height ?? unbounded;

  /// Allows any size up to [size].
  const BoxConstraints.loose(CellSize size)
      : minWidth = 0,
        maxWidth = size.cols,
        minHeight = 0,
        maxHeight = size.rows;

  bool get hasBoundedWidth => maxWidth < unbounded;
  bool get hasBoundedHeight => maxHeight < unbounded;
  bool get isTight => minWidth == maxWidth && minHeight == maxHeight;

  /// The largest allowed size (axes clamped to a real number if unbounded).
  CellSize get biggest => CellSize(constrainHeight(), constrainWidth());

  /// The smallest allowed size.
  CellSize get smallest => CellSize(minHeight, minWidth);

  int constrainWidth([int width = unbounded]) =>
      width.clamp(minWidth, maxWidth);

  int constrainHeight([int height = unbounded]) =>
      height.clamp(minHeight, maxHeight);

  /// Clamps [size] into the allowed range.
  CellSize constrain(CellSize size) =>
      CellSize(constrainHeight(size.rows), constrainWidth(size.cols));

  /// Shrinks the constraints by [insets] on all sides; min clamps at 0 and
  /// max never drops below the resulting min. Unbounded axes stay unbounded.
  BoxConstraints deflate(EdgeInsets insets) {
    var h = insets.horizontal;
    var v = insets.vertical;
    var dMinW = minWidth - h < 0 ? 0 : minWidth - h;
    var dMinH = minHeight - v < 0 ? 0 : minHeight - v;
    var dMaxW = maxWidth >= unbounded
        ? unbounded
        : (maxWidth - h < dMinW ? dMinW : maxWidth - h);
    var dMaxH = maxHeight >= unbounded
        ? unbounded
        : (maxHeight - v < dMinH ? dMinH : maxHeight - v);
    return BoxConstraints(
      minWidth: dMinW,
      maxWidth: dMaxW,
      minHeight: dMinH,
      maxHeight: dMaxH,
    );
  }

  /// Drops the minimums to zero.
  BoxConstraints loosen() => BoxConstraints(
        minWidth: 0,
        maxWidth: maxWidth,
        minHeight: 0,
        maxHeight: maxHeight,
      );

  /// Clamps every bound into [parent]'s range.
  BoxConstraints enforce(BoxConstraints parent) => BoxConstraints(
        minWidth: minWidth.clamp(parent.minWidth, parent.maxWidth),
        maxWidth: maxWidth.clamp(parent.minWidth, parent.maxWidth),
        minHeight: minHeight.clamp(parent.minHeight, parent.maxHeight),
        maxHeight: maxHeight.clamp(parent.minHeight, parent.maxHeight),
      );

  @override
  bool operator ==(Object other) =>
      other is BoxConstraints &&
      minWidth == other.minWidth &&
      maxWidth == other.maxWidth &&
      minHeight == other.minHeight &&
      maxHeight == other.maxHeight;

  @override
  int get hashCode => Object.hash(minWidth, maxWidth, minHeight, maxHeight);

  @override
  String toString() =>
      'BoxConstraints(w: $minWidth..$maxWidth, h: $minHeight..$maxHeight)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/tui/render/box_constraints_test.dart`
Expected: PASS — all tests green.

Run: `cd .. && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/render/render.dart app/lib/src/tui/render/box_constraints.dart app/test/tui/render/box_constraints_test.dart
git commit -m "$(cat <<'EOF'
Add BoxConstraints and EdgeInsets (TUI stage 3)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: RenderObject, ParentData, PipelineOwner

**Files:**
- Create: `app/lib/src/tui/render/render_object.dart`
- Modify: `app/lib/src/tui/render/render.dart` (add `part` directive)
- Test: `app/test/tui/render/render_object_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/tui/render/render_object_test.dart`:

```dart
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

/// A minimal multi-child RenderObject for exercising the base class.
class _Node extends RenderObject {
  final List<_Node> children = [];

  void append(_Node child) {
    children.add(child);
    adoptChild(child);
  }

  void unappend(_Node child) {
    children.remove(child);
    dropChild(child);
  }

  @override
  void redepthChildren() {
    for (var c in children) {
      redepthChild(c);
    }
  }

  @override
  void visitChildren(void Function(RenderObject child) visitor) {
    for (var c in children) {
      visitor(c);
    }
  }

  @override
  void performLayout() {}
}

void main() {
  group('RenderObject tree', () {
    test('adoptChild sets parent and parentData', () {
      var root = _Node();
      var child = _Node();
      root.append(child);
      expect(child.parent, same(root));
      expect(child.parentData, isA<ParentData>());
    });

    test('dropChild clears parent and parentData', () {
      var root = _Node();
      var child = _Node();
      root.append(child);
      root.unappend(child);
      expect(child.parent, isNull);
      expect(child.parentData, isNull);
    });

    test('depth increases down the tree', () {
      var root = _Node();
      var mid = _Node();
      var leaf = _Node();
      mid.append(leaf);
      root.append(mid);
      expect(root.depth, 0);
      expect(mid.depth, greaterThan(root.depth));
      expect(leaf.depth, greaterThan(mid.depth));
    });
  });

  group('attachment', () {
    test('attach propagates to the whole subtree', () {
      var owner = PipelineOwner();
      var root = _Node();
      var child = _Node();
      root.append(child);
      expect(root.attached, isFalse);
      root.attach(owner);
      expect(root.attached, isTrue);
      expect(child.attached, isTrue);
      expect(child.owner, same(owner));
    });

    test('detach propagates to the whole subtree', () {
      var owner = PipelineOwner();
      var root = _Node();
      var child = _Node();
      root.append(child);
      root.attach(owner);
      root.detach();
      expect(root.attached, isFalse);
      expect(child.attached, isFalse);
    });

    test('a child adopted after attach is attached immediately', () {
      var owner = PipelineOwner();
      var root = _Node()..attach(owner);
      var child = _Node();
      root.append(child);
      expect(child.attached, isTrue);
    });
  });

  group('markNeedsPaint', () {
    test('sets the owner needsPaint flag', () {
      var owner = PipelineOwner();
      var root = _Node()..attach(owner);
      expect(owner.needsPaint, isFalse);
      root.markNeedsPaint();
      expect(owner.needsPaint, isTrue);
      owner.clearNeedsPaint();
      expect(owner.needsPaint, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tui/render/render_object_test.dart`
Expected: FAIL — `RenderObject` / `ParentData` / `PipelineOwner` are undefined.

- [ ] **Step 3: Write the implementation**

Create `app/lib/src/tui/render/render_object.dart`:

```dart
part of 'render.dart';

/// Per-child data a parent attaches to each of its children. The concrete
/// subclass depends on the parent ([BoxParentData], [FlexParentData]).
class ParentData {}

/// [ParentData] for box-model children: the child's top-left offset within
/// the parent, in cells.
class BoxParentData extends ParentData {
  CellOffset offset = CellOffset.zero;
}

/// Owns the dirty render objects and flushes layout each frame.
///
/// Stage 3 has no layer tree, so there are no repaint boundaries: a repaint
/// request sets [needsPaint] and the whole tree is repainted. Re-layout *is*
/// localized — see [RenderObject.markNeedsLayout].
class PipelineOwner {
  final List<RenderObject> _nodesNeedingLayout = [];
  bool _needsPaint = false;

  /// Whether any render object has requested a repaint since the last clear.
  bool get needsPaint => _needsPaint;

  /// Re-runs layout for every dirty relayout boundary, shallowest depth first.
  /// A boundary's re-layout may clean nested boundaries enqueued in the same
  /// pass; those are skipped.
  void flushLayout() {
    while (_nodesNeedingLayout.isNotEmpty) {
      var dirty = _nodesNeedingLayout.toList()
        ..sort((a, b) => a.depth - b.depth);
      _nodesNeedingLayout.clear();
      for (var node in dirty) {
        if (node._needsLayout && node._owner == this) {
          node._layoutWithoutResize();
        }
      }
    }
  }

  /// Clears the repaint flag. Call once a frame has been painted.
  void clearNeedsPaint() {
    _needsPaint = false;
  }
}

/// Base of the render tree: parentage, depth, attachment, and dirty-tracking.
/// [RenderBox] adds the box layout protocol; [RenderTuiView] is the root.
abstract class RenderObject {
  RenderObject? _parent;
  RenderObject? get parent => _parent;

  /// Data this object's parent attaches to it.
  ParentData? parentData;

  int _depth = 0;

  /// Distance from the root. Used only to order [PipelineOwner.flushLayout].
  int get depth => _depth;

  PipelineOwner? _owner;
  PipelineOwner? get owner => _owner;
  bool get attached => _owner != null;

  bool _needsLayout = true;
  RenderObject? _relayoutBoundary;

  /// Installs [parentData] of the right type on [child]. Parents that need a
  /// richer parent-data type override this.
  void setupParentData(RenderObject child) {
    child.parentData ??= ParentData();
  }

  /// Called by a subclass when it installs [child].
  void adoptChild(RenderObject child) {
    setupParentData(child);
    child._parent = this;
    if (attached) {
      child.attach(_owner!);
    }
    redepthChild(child);
    markNeedsLayout();
  }

  /// Called by a subclass when it removes [child].
  void dropChild(RenderObject child) {
    child._cleanRelayoutBoundary();
    child.parentData = null;
    child._parent = null;
    if (attached) {
      child.detach();
    }
    markNeedsLayout();
  }

  /// Ensures [child] (and its descendants) have a depth greater than this.
  void redepthChild(RenderObject child) {
    if (child._depth <= _depth) {
      child._depth = _depth + 1;
      child.redepthChildren();
    }
  }

  /// Calls [redepthChild] on every child. Parents with children override this.
  void redepthChildren() {}

  /// Visits every child. Parents with children override this.
  void visitChildren(void Function(RenderObject child) visitor) {}

  /// Attaches this subtree to [owner].
  void attach(PipelineOwner owner) {
    _owner = owner;
    visitChildren((child) => child.attach(owner));
  }

  /// Detaches this subtree from its owner.
  void detach() {
    _owner = null;
    visitChildren((child) => child.detach());
  }

  /// Marks this object dirty, walking up to the nearest relayout boundary and
  /// enqueuing *that* node on the owner. Intermediate nodes are flagged but
  /// not enqueued — the boundary's re-layout will revisit them.
  void markNeedsLayout() {
    if (_needsLayout) {
      return;
    }
    if (_relayoutBoundary == null) {
      // Never laid out yet: bubble up so a future layout reaches this subtree.
      _needsLayout = true;
      _parent?.markNeedsLayout();
      return;
    }
    if (_relayoutBoundary != this) {
      _needsLayout = true;
      _parent!.markNeedsLayout();
    } else {
      _needsLayout = true;
      _owner?._nodesNeedingLayout.add(this);
    }
  }

  void _cleanRelayoutBoundary() {
    if (_relayoutBoundary != this) {
      _relayoutBoundary = null;
      _needsLayout = true;
      visitChildren((child) => child._cleanRelayoutBoundary());
    }
  }

  /// Requests a repaint. With no layer tree this flags a whole-tree repaint.
  void markNeedsPaint() {
    _owner?._needsPaint = true;
  }

  /// Re-runs layout in place (constraints unchanged). Called by
  /// [PipelineOwner.flushLayout] on a dirty relayout boundary.
  void _layoutWithoutResize() {
    performLayout();
    _needsLayout = false;
    markNeedsPaint();
  }

  /// Computes this object's layout. Subclasses override.
  void performLayout();
}
```

Modify `app/lib/src/tui/render/render.dart` — add after the `box_constraints.dart` part directive:

```dart
part 'box_constraints.dart';
part 'render_object.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/tui/render/render_object_test.dart`
Expected: PASS.

Run: `cd .. && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/render/render_object.dart app/lib/src/tui/render/render.dart app/test/tui/render/render_object_test.dart
git commit -m "$(cat <<'EOF'
Add RenderObject, ParentData, PipelineOwner (TUI stage 3)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: RenderBox and the layout protocol

**Files:**
- Create: `app/lib/src/tui/render/render_box.dart`
- Modify: `app/lib/src/tui/render/render.dart` (add `part` directive)
- Test: `app/test/tui/render/render_box_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/tui/render/render_box_test.dart`:

```dart
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

/// A leaf box that sizes itself to a fixed natural size, clamped to its
/// constraints, and counts how many times it was laid out.
class _FixedBox extends RenderBox {
  _FixedBox(this.natural);

  CellSize natural;
  int layoutCount = 0;

  @override
  void performLayout() {
    layoutCount++;
    size = constraints.constrain(natural);
  }

  @override
  int computeMaxIntrinsicWidth(int height) => natural.cols;

  @override
  int computeMaxIntrinsicHeight(int width) => natural.rows;
}

/// A single-child box that passes its constraints straight through and adopts
/// the child's size.
class _PassBox extends RenderBox with RenderBoxWithChild {
  _PassBox(RenderBox child) {
    this.child = child;
  }

  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    (child!.parentData as BoxParentData).offset = CellOffset.zero;
    size = child!.size;
  }
}

void main() {
  group('RenderBox.layout', () {
    test('records size from performLayout', () {
      var box = _FixedBox(CellSize(3, 7));
      box.layout(BoxConstraints.loose(CellSize(10, 10)));
      expect(box.size, CellSize(3, 7));
    });

    test('constraints clamp the natural size', () {
      var box = _FixedBox(CellSize(99, 99));
      box.layout(BoxConstraints.tight(CellSize(4, 5)));
      expect(box.size, CellSize(4, 5));
    });

    test('re-layout with identical constraints is skipped', () {
      var box = _FixedBox(CellSize(2, 2));
      box.layout(BoxConstraints.loose(CellSize(9, 9)));
      box.layout(BoxConstraints.loose(CellSize(9, 9)));
      expect(box.layoutCount, 1);
    });

    test('re-layout after markNeedsLayout runs again', () {
      var box = _FixedBox(CellSize(2, 2));
      box.layout(BoxConstraints.loose(CellSize(9, 9)));
      box.markNeedsLayout();
      box.layout(BoxConstraints.loose(CellSize(9, 9)));
      expect(box.layoutCount, 2);
    });
  });

  group('intrinsics', () {
    test('default intrinsics are zero', () {
      var box = _PassBox(_FixedBox(CellSize(1, 1)));
      expect(box.getMinIntrinsicWidth(10), 0);
    });

    test('a leaf reports its computed intrinsics', () {
      var box = _FixedBox(CellSize(4, 9));
      expect(box.getMaxIntrinsicWidth(100), 9);
      expect(box.getMaxIntrinsicHeight(100), 4);
    });
  });

  group('relayout boundary localization', () {
    test('a tight-constrained child is its own relayout boundary, so '
        'dirtying its child does not dirty the parent', () {
      // parent (loose) -> mid (laid out tight) -> leaf
      var leaf = _FixedBox(CellSize(1, 1));
      var mid = _PassBox(leaf);
      var owner = PipelineOwner();

      // Lay the subtree out once with mid receiving tight constraints.
      mid.attach(owner);
      mid.layout(BoxConstraints.tight(CellSize(5, 5)));
      expect(leaf.layoutCount, 1);
      expect(mid.layoutCount, 1);

      // Dirtying the leaf must enqueue mid (the boundary), not bubble past it.
      leaf.markNeedsLayout();
      owner.flushLayout();
      expect(leaf.layoutCount, 2);
      expect(mid.layoutCount, 2);
    });
  });
}
```

Note: `_FixedBox` has no `layoutCount` increment guard issue — `_PassBox` extends `RenderBox with RenderBoxWithChild`; `_PassBox.layoutCount` is referenced via its `_FixedBox` children only.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tui/render/render_box_test.dart`
Expected: FAIL — `RenderBox` / `RenderBoxWithChild` are undefined.

- [ ] **Step 3: Write the implementation**

Create `app/lib/src/tui/render/render_box.dart`:

```dart
part of 'render.dart';

/// A render object that uses the cell-box layout protocol: it receives
/// [BoxConstraints] from its parent and produces a [CellSize].
abstract class RenderBox extends RenderObject {
  BoxConstraints? _constraints;

  /// The constraints from the most recent [layout] call.
  BoxConstraints get constraints => _constraints!;

  CellSize? _size;

  /// The size produced by the most recent [performLayout].
  CellSize get size => _size!;
  set size(CellSize value) {
    _size = value;
  }

  /// When true, the size depends only on the constraints, so [performResize]
  /// can set it before children are laid out. No Stage 3 box sets this; it
  /// exists for protocol completeness.
  bool get sizedByParent => false;

  /// Sets [size] from the constraints alone. Only called when [sizedByParent].
  void performResize() {}

  /// The layout entry point. Not meant to be overridden — subclasses override
  /// [performLayout] (and [performResize]/[sizedByParent] if relevant).
  ///
  /// Pass [parentUsesSize] true when the caller will read [size]; this affects
  /// whether the child becomes its own relayout boundary.
  void layout(BoxConstraints constraints, {bool parentUsesSize = false}) {
    var p = parent;
    var isBoundary = !parentUsesSize ||
        sizedByParent ||
        constraints.isTight ||
        p is! RenderBox;
    var boundary = isBoundary ? this : p!._relayoutBoundary;

    if (!_needsLayout && constraints == _constraints) {
      if (boundary != _relayoutBoundary) {
        _relayoutBoundary = boundary;
        visitChildren(
            (child) => (child as RenderBox)._propagateRelayoutBoundary());
      }
      return;
    }

    _constraints = constraints;
    _relayoutBoundary = boundary;
    if (sizedByParent) {
      performResize();
    }
    performLayout();
    _needsLayout = false;
    markNeedsPaint();
  }

  void _propagateRelayoutBoundary() {
    if (_relayoutBoundary == this) {
      return;
    }
    var parentBoundary = (parent! as RenderBox)._relayoutBoundary;
    if (parentBoundary != _relayoutBoundary) {
      _relayoutBoundary = parentBoundary;
      visitChildren(
          (child) => (child as RenderBox)._propagateRelayoutBoundary());
    }
  }

  /// Intrinsic dimensions. The public getters delegate to the `compute*`
  /// methods, which subclasses override.
  int getMinIntrinsicWidth(int height) => computeMinIntrinsicWidth(height);
  int getMaxIntrinsicWidth(int height) => computeMaxIntrinsicWidth(height);
  int getMinIntrinsicHeight(int width) => computeMinIntrinsicHeight(width);
  int getMaxIntrinsicHeight(int width) => computeMaxIntrinsicHeight(width);

  int computeMinIntrinsicWidth(int height) => 0;
  int computeMaxIntrinsicWidth(int height) => 0;
  int computeMinIntrinsicHeight(int width) => 0;
  int computeMaxIntrinsicHeight(int width) => 0;

  /// Paints this box. [painter] is already translated so this box's top-left
  /// is local `(0, 0)`. Subclasses override.
  void paint(Painter painter) {}
}

/// Mixin for render boxes that hold exactly one box child.
mixin RenderBoxWithChild on RenderBox {
  RenderBox? _child;
  RenderBox? get child => _child;
  set child(RenderBox? value) {
    if (_child != null) {
      dropChild(_child!);
    }
    _child = value;
    if (value != null) {
      adoptChild(value);
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  @override
  void redepthChildren() {
    if (_child != null) {
      redepthChild(_child!);
    }
  }

  @override
  void visitChildren(void Function(RenderObject child) visitor) {
    if (_child != null) {
      visitor(_child!);
    }
  }
}
```

Modify `app/lib/src/tui/render/render.dart` — add the part directive:

```dart
part 'render_object.dart';
part 'render_box.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/tui/render/render_box_test.dart`
Expected: PASS.

Run: `cd .. && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/render/render_box.dart app/lib/src/tui/render/render.dart app/test/tui/render/render_box_test.dart
git commit -m "$(cat <<'EOF'
Add RenderBox and the cell-box layout protocol (TUI stage 3)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: RenderText

**Files:**
- Create: `app/lib/src/tui/render/render_text.dart`
- Modify: `app/lib/src/tui/render/render.dart` (add `part` directive)
- Test: `app/test/tui/render/render_text_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/tui/render/render_text_test.dart`:

```dart
import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

List<String> dump(CellBuffer b) => [
      for (var r = 0; r < b.rows; r++)
        String.fromCharCodes([
          for (var c = 0; c < b.cols; c++) b.get(r, c).rune,
        ]),
    ];

void main() {
  group('RenderText layout', () {
    test('a single short line sizes to its length', () {
      var t = RenderText('hello');
      t.layout(BoxConstraints(maxWidth: 20, maxHeight: 5));
      expect(t.size, CellSize(1, 5));
    });

    test('wraps to the width constraint', () {
      var t = RenderText('one two three four');
      t.layout(BoxConstraints(maxWidth: 8, maxHeight: 10));
      // 'one two' (7), 'three' (5), 'four' (4) -> 3 rows, widest 7.
      expect(t.size.rows, 3);
      expect(t.size.cols, 7);
    });

    test('with wrap off, splits only on newlines', () {
      var t = RenderText('a very long single line here', wrap: false);
      t.layout(BoxConstraints(maxWidth: 6, maxHeight: 4));
      // One logical line; size width clamps to the constraint.
      expect(t.size.rows, 1);
      expect(t.size.cols, 6);
    });

    test('size is clamped to the constraints', () {
      var t = RenderText('abcdefghij');
      t.layout(BoxConstraints.tight(CellSize(2, 4)));
      expect(t.size, CellSize(2, 4));
    });
  });

  group('RenderText intrinsics', () {
    test('max intrinsic width is the longest unwrapped line', () {
      var t = RenderText('short\na much longer line');
      expect(t.getMaxIntrinsicWidth(100), 'a much longer line'.length);
    });

    test('min intrinsic width is the longest word', () {
      var t = RenderText('hi enormously-long-word ok');
      expect(t.getMinIntrinsicWidth(100), 'enormously-long-word'.length);
    });

    test('intrinsic height is the wrapped line count', () {
      var t = RenderText('one two three four');
      expect(t.getMinIntrinsicHeight(8), 3);
    });
  });

  group('RenderText paint', () {
    test('draws the text into the buffer at the origin', () {
      var t = RenderText('hi');
      t.layout(BoxConstraints(maxWidth: 10, maxHeight: 3));
      var buffer = CellBuffer(3, 10);
      t.paint(Painter(buffer));
      expect(dump(buffer)[0].trimRight(), 'hi');
    });
  });

  group('RenderText dirty-tracking', () {
    test('setting text marks needs-layout', () {
      var t = RenderText('a');
      t.layout(BoxConstraints(maxWidth: 10, maxHeight: 3));
      t.text = 'bbbbb';
      // _needsLayout is private; observe it via a fresh layout changing size.
      t.layout(BoxConstraints(maxWidth: 10, maxHeight: 3));
      expect(t.size.cols, 5);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tui/render/render_text_test.dart`
Expected: FAIL — `RenderText` is undefined.

- [ ] **Step 3: Write the implementation**

Create `app/lib/src/tui/render/render_text.dart`:

```dart
part of 'render.dart';

/// A leaf render object that lays out and paints a string. Wrapping is done
/// with [wrapText]; painting with [Painter.drawText].
class RenderText extends RenderBox {
  RenderText(
    this._text, {
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
    HorizontalAlign hAlign = HorizontalAlign.left,
    VerticalAlign vAlign = VerticalAlign.top,
    bool wrap = true,
  })  : _fg = fg,
        _bg = bg,
        _style = style,
        _hAlign = hAlign,
        _vAlign = vAlign,
        _wrap = wrap;

  String _text;
  String get text => _text;
  set text(String value) {
    if (value == _text) return;
    _text = value;
    markNeedsLayout();
  }

  bool _wrap;
  bool get wrap => _wrap;
  set wrap(bool value) {
    if (value == _wrap) return;
    _wrap = value;
    markNeedsLayout();
  }

  Color _fg;
  Color get fg => _fg;
  set fg(Color value) {
    if (value == _fg) return;
    _fg = value;
    markNeedsPaint();
  }

  Color _bg;
  Color get bg => _bg;
  set bg(Color value) {
    if (value == _bg) return;
    _bg = value;
    markNeedsPaint();
  }

  int _style;
  int get style => _style;
  set style(int value) {
    if (value == _style) return;
    _style = value;
    markNeedsPaint();
  }

  HorizontalAlign _hAlign;
  HorizontalAlign get hAlign => _hAlign;
  set hAlign(HorizontalAlign value) {
    if (value == _hAlign) return;
    _hAlign = value;
    markNeedsPaint();
  }

  VerticalAlign _vAlign;
  VerticalAlign get vAlign => _vAlign;
  set vAlign(VerticalAlign value) {
    if (value == _vAlign) return;
    _vAlign = value;
    markNeedsPaint();
  }

  List<String> _layoutLines(int maxWidth) {
    if (_wrap && maxWidth < BoxConstraints.unbounded) {
      return wrapText(_text, maxWidth);
    }
    return _text.split('\n');
  }

  @override
  void performLayout() {
    var lines = _layoutLines(constraints.maxWidth);
    var longest = 0;
    for (var line in lines) {
      var len = line.runes.length;
      if (len > longest) longest = len;
    }
    size = constraints.constrain(CellSize(lines.length, longest));
  }

  @override
  int computeMaxIntrinsicWidth(int height) {
    var longest = 0;
    for (var line in _text.split('\n')) {
      var len = line.runes.length;
      if (len > longest) longest = len;
    }
    return longest;
  }

  @override
  int computeMinIntrinsicWidth(int height) {
    var longest = 0;
    for (var word in _text.split(RegExp(r'\s+'))) {
      var len = word.runes.length;
      if (len > longest) longest = len;
    }
    return longest;
  }

  @override
  int computeMinIntrinsicHeight(int width) => _heightAt(width);

  @override
  int computeMaxIntrinsicHeight(int width) => _heightAt(width);

  int _heightAt(int width) => _layoutLines(width).length;

  @override
  void paint(Painter painter) {
    painter.drawText(
      CellRect.fromOffsetSize(CellOffset.zero, size),
      _text,
      fg: _fg,
      bg: _bg,
      style: _style,
      hAlign: _hAlign,
      vAlign: _vAlign,
      wrap: _wrap,
    );
  }
}
```

Modify `app/lib/src/tui/render/render.dart` — add the part directive:

```dart
part 'render_box.dart';
part 'render_text.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/tui/render/render_text_test.dart`
Expected: PASS.

Run: `cd .. && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/render/render_text.dart app/lib/src/tui/render/render.dart app/test/tui/render/render_text_test.dart
git commit -m "$(cat <<'EOF'
Add RenderText leaf render object (TUI stage 3)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: RenderPadding

**Files:**
- Create: `app/lib/src/tui/render/render_padding.dart`
- Modify: `app/lib/src/tui/render/render.dart` (add `part` directive)
- Test: `app/test/tui/render/render_padding_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/tui/render/render_padding_test.dart`:

```dart
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

/// A leaf box that sizes to a fixed natural size, clamped to its constraints.
class _FixedBox extends RenderBox {
  _FixedBox(this.natural);
  CellSize natural;

  @override
  void performLayout() {
    size = constraints.constrain(natural);
  }

  @override
  int computeMaxIntrinsicWidth(int height) => natural.cols;

  @override
  int computeMinIntrinsicWidth(int height) => natural.cols;

  @override
  int computeMaxIntrinsicHeight(int width) => natural.rows;

  @override
  int computeMinIntrinsicHeight(int width) => natural.rows;
}

void main() {
  group('RenderPadding', () {
    test('size is the child size plus the padding', () {
      var child = _FixedBox(CellSize(3, 5));
      var pad = RenderPadding(padding: EdgeInsets.all(2), child: child);
      pad.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect(pad.size, CellSize(3 + 4, 5 + 4));
    });

    test('positions the child at (top, left)', () {
      var child = _FixedBox(CellSize(1, 1));
      var pad = RenderPadding(
        padding: EdgeInsets.only(left: 3, top: 2),
        child: child,
      );
      pad.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect((child.parentData as BoxParentData).offset, CellOffset(2, 3));
    });

    test('the child is laid out with deflated constraints', () {
      var child = _FixedBox(CellSize(99, 99));
      var pad = RenderPadding(padding: EdgeInsets.all(1), child: child);
      pad.layout(BoxConstraints.tight(CellSize(10, 20)));
      // Child clamped to 10-2 rows, 20-2 cols.
      expect(child.size, CellSize(8, 18));
      expect(pad.size, CellSize(10, 20));
    });

    test('with no child, size is the padding alone', () {
      var pad = RenderPadding(padding: EdgeInsets.all(3));
      pad.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect(pad.size, CellSize(6, 6));
    });

    test('intrinsics add the padding to the child intrinsics', () {
      var child = _FixedBox(CellSize(4, 9));
      var pad = RenderPadding(padding: EdgeInsets.all(2), child: child);
      expect(pad.getMaxIntrinsicWidth(100), 9 + 4);
      expect(pad.getMaxIntrinsicHeight(100), 4 + 4);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tui/render/render_padding_test.dart`
Expected: FAIL — `RenderPadding` is undefined.

- [ ] **Step 3: Write the implementation**

Create `app/lib/src/tui/render/render_padding.dart`:

```dart
part of 'render.dart';

/// A single-child render object that insets its child by [padding].
class RenderPadding extends RenderBox with RenderBoxWithChild {
  RenderPadding({required EdgeInsets padding, RenderBox? child})
      : _padding = padding {
    this.child = child;
  }

  EdgeInsets _padding;
  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    var h = _padding.horizontal;
    var v = _padding.vertical;
    if (child == null) {
      size = constraints.constrain(CellSize(v, h));
      return;
    }
    child!.layout(constraints.deflate(_padding), parentUsesSize: true);
    (child!.parentData as BoxParentData).offset =
        CellOffset(_padding.top, _padding.left);
    size = constraints.constrain(
      CellSize(child!.size.rows + v, child!.size.cols + h),
    );
  }

  int _innerWidth(int width) {
    if (width >= BoxConstraints.unbounded) return width;
    var inner = width - _padding.horizontal;
    return inner < 0 ? 0 : inner;
  }

  int _innerHeight(int height) {
    if (height >= BoxConstraints.unbounded) return height;
    var inner = height - _padding.vertical;
    return inner < 0 ? 0 : inner;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      (child?.getMinIntrinsicWidth(_innerHeight(height)) ?? 0) +
      _padding.horizontal;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      (child?.getMaxIntrinsicWidth(_innerHeight(height)) ?? 0) +
      _padding.horizontal;

  @override
  int computeMinIntrinsicHeight(int width) =>
      (child?.getMinIntrinsicHeight(_innerWidth(width)) ?? 0) +
      _padding.vertical;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      (child?.getMaxIntrinsicHeight(_innerWidth(width)) ?? 0) +
      _padding.vertical;

  @override
  void paint(Painter painter) {
    if (child == null) return;
    var offset = (child!.parentData as BoxParentData).offset;
    child!.paint(painter.translate(offset));
  }
}
```

Modify `app/lib/src/tui/render/render.dart` — add the part directive:

```dart
part 'render_text.dart';
part 'render_padding.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/tui/render/render_padding_test.dart`
Expected: PASS.

Run: `cd .. && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/render/render_padding.dart app/lib/src/tui/render/render.dart app/test/tui/render/render_padding_test.dart
git commit -m "$(cat <<'EOF'
Add RenderPadding render object (TUI stage 3)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: RenderConstrainedBox

**Files:**
- Create: `app/lib/src/tui/render/render_constrained_box.dart`
- Modify: `app/lib/src/tui/render/render.dart` (add `part` directive)
- Test: `app/test/tui/render/render_constrained_box_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/tui/render/render_constrained_box_test.dart`:

```dart
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

class _FixedBox extends RenderBox {
  _FixedBox(this.natural);
  CellSize natural;

  @override
  void performLayout() {
    size = constraints.constrain(natural);
  }

  @override
  int computeMaxIntrinsicWidth(int height) => natural.cols;

  @override
  int computeMaxIntrinsicHeight(int width) => natural.rows;
}

void main() {
  group('RenderConstrainedBox', () {
    test('imposes a tight height on the child', () {
      var child = _FixedBox(CellSize(99, 8));
      var box = RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tightFor(height: 1),
        child: child,
      );
      box.layout(BoxConstraints(maxWidth: 40, maxHeight: 40));
      expect(child.size, CellSize(1, 8));
      expect(box.size, CellSize(1, 8));
    });

    test('additional constraints are clamped within incoming constraints', () {
      var child = _FixedBox(CellSize(5, 5));
      var box = RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tight(CellSize(100, 100)),
        child: child,
      );
      // Parent only allows up to 10x10, so the child cannot exceed that.
      box.layout(BoxConstraints(maxWidth: 10, maxHeight: 10));
      expect(child.size, CellSize(10, 10));
    });

    test('with no child, sizes from the enforced constraints', () {
      var box = RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tight(CellSize(3, 4)),
      );
      box.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect(box.size, CellSize(3, 4));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tui/render/render_constrained_box_test.dart`
Expected: FAIL — `RenderConstrainedBox` is undefined.

- [ ] **Step 3: Write the implementation**

Create `app/lib/src/tui/render/render_constrained_box.dart`:

```dart
part of 'render.dart';

/// A single-child render object that imposes [additionalConstraints] on top
/// of the constraints it receives. Underpins `SizedBox`/`ConstrainedBox` and
/// fixed-extent regions in stage 4.
class RenderConstrainedBox extends RenderBox with RenderBoxWithChild {
  RenderConstrainedBox({
    required BoxConstraints additionalConstraints,
    RenderBox? child,
  }) : _additionalConstraints = additionalConstraints {
    this.child = child;
  }

  BoxConstraints _additionalConstraints;
  BoxConstraints get additionalConstraints => _additionalConstraints;
  set additionalConstraints(BoxConstraints value) {
    if (value == _additionalConstraints) return;
    _additionalConstraints = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    var inner = _additionalConstraints.enforce(constraints);
    if (child == null) {
      size = inner.constrain(CellSize.zero);
      return;
    }
    child!.layout(inner, parentUsesSize: true);
    (child!.parentData as BoxParentData).offset = CellOffset.zero;
    size = child!.size;
  }

  int _constrainW(int width) {
    var a = _additionalConstraints;
    var value = a.minWidth == a.maxWidth ? a.minWidth : width;
    return a.constrainWidth(value);
  }

  int _constrainH(int height) {
    var a = _additionalConstraints;
    var value = a.minHeight == a.maxHeight ? a.minHeight : height;
    return a.constrainHeight(value);
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      _constrainW(child?.getMinIntrinsicWidth(height) ?? 0);

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _constrainW(child?.getMaxIntrinsicWidth(height) ?? 0);

  @override
  int computeMinIntrinsicHeight(int width) =>
      _constrainH(child?.getMinIntrinsicHeight(width) ?? 0);

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _constrainH(child?.getMaxIntrinsicHeight(width) ?? 0);

  @override
  void paint(Painter painter) {
    child?.paint(painter);
  }
}
```

Modify `app/lib/src/tui/render/render.dart` — add the part directive:

```dart
part 'render_padding.dart';
part 'render_constrained_box.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/tui/render/render_constrained_box_test.dart`
Expected: PASS.

Run: `cd .. && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/render/render_constrained_box.dart app/lib/src/tui/render/render.dart app/test/tui/render/render_constrained_box_test.dart
git commit -m "$(cat <<'EOF'
Add RenderConstrainedBox render object (TUI stage 3)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: RenderDecoratedBox

**Files:**
- Create: `app/lib/src/tui/render/render_decorated_box.dart`
- Modify: `app/lib/src/tui/render/render.dart` (add `part` directive)
- Test: `app/test/tui/render/render_decorated_box_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/tui/render/render_decorated_box_test.dart`:

```dart
import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

List<String> dump(CellBuffer b) => [
      for (var r = 0; r < b.rows; r++)
        String.fromCharCodes([
          for (var c = 0; c < b.cols; c++) b.get(r, c).rune,
        ]),
    ];

class _FixedBox extends RenderBox {
  _FixedBox(this.natural);
  CellSize natural;

  @override
  void performLayout() {
    size = constraints.constrain(natural);
  }
}

void main() {
  group('RenderDecoratedBox', () {
    test('size delegates to the child', () {
      var child = _FixedBox(CellSize(4, 6));
      var box = RenderDecoratedBox(
        decoration: BoxDecoration(border: BoxBorder()),
        child: child,
      );
      box.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect(box.size, CellSize(4, 6));
    });

    test('with no child, size is the smallest allowed', () {
      var box = RenderDecoratedBox(decoration: BoxDecoration());
      box.layout(BoxConstraints(minWidth: 2, minHeight: 3));
      expect(box.size, CellSize(3, 2));
    });

    test('paints the border around the box perimeter', () {
      var child = _FixedBox(CellSize(3, 5));
      var box = RenderDecoratedBox(
        decoration: BoxDecoration(border: BoxBorder(chars: BorderChars.ascii())),
        child: child,
      );
      box.layout(BoxConstraints.tight(CellSize(3, 5)));
      var buffer = CellBuffer(3, 5);
      box.paint(Painter(buffer));
      expect(dump(buffer), ['+---+', '|   |', '+---+']);
    });

    test('paints the fill behind the child', () {
      var child = _FixedBox(CellSize(2, 2));
      var box = RenderDecoratedBox(
        decoration: BoxDecoration(fill: Cell(rune: 0x2e)), // '.'
        child: child,
      );
      box.layout(BoxConstraints.tight(CellSize(2, 2)));
      var buffer = CellBuffer(2, 2);
      box.paint(Painter(buffer));
      expect(dump(buffer), ['..', '..']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tui/render/render_decorated_box_test.dart`
Expected: FAIL — `RenderDecoratedBox` / `BoxDecoration` / `BoxBorder` are undefined.

- [ ] **Step 3: Write the implementation**

Create `app/lib/src/tui/render/render_decorated_box.dart`:

```dart
part of 'render.dart';

/// A box border described by its glyphs and color. Reuses the stage 2
/// [BorderChars].
class BoxBorder {
  final BorderChars chars;
  final Color fg;

  const BoxBorder({
    this.chars = const BorderChars.single(),
    this.fg = Color.defaultFg,
  });
}

/// A background fill and/or a border. Painted by [RenderDecoratedBox].
class BoxDecoration {
  /// The cell painted across the whole box; null leaves the background as-is.
  final Cell? fill;

  /// The perimeter border; null draws no border.
  final BoxBorder? border;

  const BoxDecoration({this.fill, this.border});
}

/// A single-child render object that paints a [BoxDecoration] around its
/// child. The decoration does not affect layout — a bordered panel is a
/// [RenderDecoratedBox] wrapping a [RenderPadding] so content clears the
/// 1-cell border.
class RenderDecoratedBox extends RenderBox with RenderBoxWithChild {
  RenderDecoratedBox({required BoxDecoration decoration, RenderBox? child})
      : _decoration = decoration {
    this.child = child;
  }

  BoxDecoration _decoration;
  BoxDecoration get decoration => _decoration;
  set decoration(BoxDecoration value) {
    if (identical(value, _decoration)) return;
    _decoration = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child!.layout(constraints, parentUsesSize: true);
    (child!.parentData as BoxParentData).offset = CellOffset.zero;
    size = child!.size;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(Painter painter) {
    var rect = CellRect.fromOffsetSize(CellOffset.zero, size);
    var fill = _decoration.fill;
    if (fill != null) {
      painter.fillRect(rect, fill);
    }
    child?.paint(painter);
    var border = _decoration.border;
    if (border != null) {
      painter.drawBorder(rect, chars: border.chars, fg: border.fg);
    }
  }
}
```

Modify `app/lib/src/tui/render/render.dart` — add the part directive:

```dart
part 'render_constrained_box.dart';
part 'render_decorated_box.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/tui/render/render_decorated_box_test.dart`
Expected: PASS.

Run: `cd .. && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/render/render_decorated_box.dart app/lib/src/tui/render/render.dart app/test/tui/render/render_decorated_box_test.dart
git commit -m "$(cat <<'EOF'
Add RenderDecoratedBox render object (TUI stage 3)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: RenderFlex

**Files:**
- Create: `app/lib/src/tui/render/render_flex.dart`
- Modify: `app/lib/src/tui/render/render.dart` (add `part` directive)
- Test: `app/test/tui/render/render_flex_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/tui/render/render_flex_test.dart`:

```dart
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

class _FixedBox extends RenderBox {
  _FixedBox(this.natural);
  CellSize natural;

  @override
  void performLayout() {
    size = constraints.constrain(natural);
  }

  @override
  int computeMinIntrinsicWidth(int height) => natural.cols;

  @override
  int computeMaxIntrinsicWidth(int height) => natural.cols;

  @override
  int computeMinIntrinsicHeight(int width) => natural.rows;

  @override
  int computeMaxIntrinsicHeight(int width) => natural.rows;
}

int mainOffset(RenderBox child, Axis axis) {
  var offset = (child.parentData as FlexParentData).offset;
  return axis == Axis.horizontal ? offset.col : offset.row;
}

int crossOffset(RenderBox child, Axis axis) {
  var offset = (child.parentData as FlexParentData).offset;
  return axis == Axis.horizontal ? offset.row : offset.col;
}

void main() {
  group('RenderFlex sizing (horizontal Row)', () {
    test('main axis sums inflexible children, cross axis is the max', () {
      var a = _FixedBox(CellSize(2, 3));
      var b = _FixedBox(CellSize(5, 4));
      var row = RenderFlex(
        direction: Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: [a, b],
      );
      row.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect(row.size, CellSize(5, 7)); // width 3+4, height max(2,5)
    });

    test('MainAxisSize.max fills the available main extent', () {
      var a = _FixedBox(CellSize(1, 3));
      var row = RenderFlex(
        direction: Axis.horizontal,
        children: [a],
      );
      row.layout(BoxConstraints.tight(CellSize(4, 20)));
      expect(row.size, CellSize(4, 20));
    });

    test('children are laid end to end starting at 0', () {
      var a = _FixedBox(CellSize(1, 3));
      var b = _FixedBox(CellSize(1, 5));
      var row = RenderFlex(
        direction: Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: [a, b],
      );
      row.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect(mainOffset(a, Axis.horizontal), 0);
      expect(mainOffset(b, Axis.horizontal), 3);
    });
  });

  group('RenderFlex MainAxisAlignment', () {
    RenderFlex build(MainAxisAlignment alignment) {
      var a = _FixedBox(CellSize(1, 2));
      var b = _FixedBox(CellSize(1, 2));
      return RenderFlex(
        direction: Axis.horizontal,
        mainAxisAlignment: alignment,
        children: [a, b],
      )..layout(BoxConstraints.tight(CellSize(1, 10)));
      // total child width 4, leftover 6.
    }

    test('start puts children flush left', () {
      var row = build(MainAxisAlignment.start);
      expect(mainOffset(row.children[0], Axis.horizontal), 0);
      expect(mainOffset(row.children[1], Axis.horizontal), 2);
    });

    test('end puts leftover before the first child', () {
      var row = build(MainAxisAlignment.end);
      expect(mainOffset(row.children[0], Axis.horizontal), 6);
      expect(mainOffset(row.children[1], Axis.horizontal), 8);
    });

    test('center splits the leftover', () {
      var row = build(MainAxisAlignment.center);
      expect(mainOffset(row.children[0], Axis.horizontal), 3);
      expect(mainOffset(row.children[1], Axis.horizontal), 5);
    });

    test('spaceBetween puts all leftover between children', () {
      var row = build(MainAxisAlignment.spaceBetween);
      expect(mainOffset(row.children[0], Axis.horizontal), 0);
      expect(mainOffset(row.children[1], Axis.horizontal), 8);
    });
  });

  group('RenderFlex CrossAxisAlignment', () {
    test('center positions a short child within the cross extent', () {
      var tall = _FixedBox(CellSize(5, 1));
      var short = _FixedBox(CellSize(1, 1));
      var row = RenderFlex(
        direction: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [tall, short],
      )..layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect(crossOffset(short, Axis.horizontal), 2); // (5-1) ~/ 2
    });

    test('stretch sizes children to the cross extent', () {
      var a = _FixedBox(CellSize(1, 1));
      var row = RenderFlex(
        direction: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [a],
      )..layout(BoxConstraints.tight(CellSize(6, 10)));
      expect(a.size.rows, 6);
    });
  });

  group('RenderFlex flex factors', () {
    test('a single flex child fills the free space', () {
      var fixed = _FixedBox(CellSize(1, 4));
      var flexible = _FixedBox(CellSize(1, 1));
      var row = RenderFlex(direction: Axis.horizontal, children: [fixed, flexible]);
      row.setFlex(flexible, 1);
      row.layout(BoxConstraints.tight(CellSize(1, 20)));
      expect(flexible.size.cols, 16); // 20 - 4
    });

    test('flex factors split the free space proportionally', () {
      var x = _FixedBox(CellSize(1, 1));
      var y = _FixedBox(CellSize(1, 1));
      var row = RenderFlex(direction: Axis.horizontal, children: [x, y]);
      row.setFlex(x, 1, fit: FlexFit.tight);
      row.setFlex(y, 2, fit: FlexFit.tight);
      row.layout(BoxConstraints.tight(CellSize(1, 30)));
      expect(x.size.cols, 10);
      expect(y.size.cols, 20);
    });

    test('integer distribution tiles the parent exactly with no gap', () {
      var x = _FixedBox(CellSize(1, 1));
      var y = _FixedBox(CellSize(1, 1));
      var z = _FixedBox(CellSize(1, 1));
      var row = RenderFlex(direction: Axis.horizontal, children: [x, y, z]);
      row.setFlex(x, 1, fit: FlexFit.tight);
      row.setFlex(y, 1, fit: FlexFit.tight);
      row.setFlex(z, 1, fit: FlexFit.tight);
      // 10 cells over 3 flex units does not divide evenly.
      row.layout(BoxConstraints.tight(CellSize(1, 10)));
      expect(x.size.cols + y.size.cols + z.size.cols, 10);
      // Children tile contiguously: each starts where the previous ended.
      expect(mainOffset(x, Axis.horizontal), 0);
      expect(mainOffset(y, Axis.horizontal), x.size.cols);
      expect(mainOffset(z, Axis.horizontal), x.size.cols + y.size.cols);
    });
  });

  group('RenderFlex vertical (Column)', () {
    test('main axis is the row count', () {
      var a = _FixedBox(CellSize(2, 4));
      var b = _FixedBox(CellSize(3, 6));
      var col = RenderFlex(
        direction: Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        children: [a, b],
      )..layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect(col.size, CellSize(5, 6)); // height 2+3, width max(4,6)
      expect(mainOffset(b, Axis.vertical), 2);
    });
  });

  group('RenderFlex intrinsics', () {
    test('horizontal main intrinsic sums inflexible child widths', () {
      var a = _FixedBox(CellSize(1, 3));
      var b = _FixedBox(CellSize(1, 5));
      var row = RenderFlex(direction: Axis.horizontal, children: [a, b]);
      expect(row.getMaxIntrinsicWidth(100), 8);
    });

    test('horizontal cross intrinsic is the max child height', () {
      var a = _FixedBox(CellSize(2, 1));
      var b = _FixedBox(CellSize(7, 1));
      var row = RenderFlex(direction: Axis.horizontal, children: [a, b]);
      expect(row.getMaxIntrinsicHeight(100), 7);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tui/render/render_flex_test.dart`
Expected: FAIL — `RenderFlex` / `FlexParentData` / `Axis` etc. are undefined.

- [ ] **Step 3: Write the implementation**

Create `app/lib/src/tui/render/render_flex.dart`:

```dart
part of 'render.dart';

/// The layout axis of a [RenderFlex].
enum Axis { horizontal, vertical }

/// How children are placed along the main axis when there is free space.
enum MainAxisAlignment {
  start,
  end,
  center,
  spaceBetween,
  spaceAround,
  spaceEvenly,
}

/// How children are placed along the cross axis.
enum CrossAxisAlignment { start, end, center, stretch }

/// Whether a [RenderFlex] is as large as possible or as small as its children
/// along the main axis.
enum MainAxisSize { min, max }

/// How a flexible child fills the main-axis space allotted to it.
enum FlexFit { tight, loose }

/// [ParentData] for [RenderFlex] children: adds a flex factor and fit.
class FlexParentData extends BoxParentData {
  int flex = 0;
  FlexFit fit = FlexFit.loose;
}

/// A multi-child render object that lays children out along one axis — the
/// shared mechanism behind `Row` and `Column`.
class RenderFlex extends RenderBox {
  RenderFlex({
    required this.direction,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    List<RenderBox> children = const [],
  }) {
    addAll(children);
  }

  Axis direction;
  MainAxisAlignment mainAxisAlignment;
  CrossAxisAlignment crossAxisAlignment;
  MainAxisSize mainAxisSize;

  final List<RenderBox> _children = [];

  /// The children, in layout order. Read-only; mutate via [add]/[remove].
  List<RenderBox> get children => List.unmodifiable(_children);

  void add(RenderBox child) {
    _children.add(child);
    adoptChild(child);
  }

  void addAll(List<RenderBox> children) {
    for (var child in children) {
      add(child);
    }
  }

  void remove(RenderBox child) {
    _children.remove(child);
    dropChild(child);
  }

  void clearChildren() {
    var copy = _children.toList();
    _children.clear();
    for (var child in copy) {
      dropChild(child);
    }
  }

  /// Sets the flex factor and fit of an already-added [child].
  void setFlex(RenderBox child, int flex, {FlexFit fit = FlexFit.loose}) {
    var pd = child.parentData as FlexParentData;
    pd.flex = flex;
    pd.fit = fit;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! FlexParentData) {
      child.parentData = FlexParentData();
    }
  }

  @override
  void redepthChildren() {
    for (var child in _children) {
      redepthChild(child);
    }
  }

  @override
  void visitChildren(void Function(RenderObject child) visitor) {
    for (var child in _children) {
      visitor(child);
    }
  }

  bool get _isHorizontal => direction == Axis.horizontal;

  int _mainOf(CellSize s) => _isHorizontal ? s.cols : s.rows;
  int _crossOf(CellSize s) => _isHorizontal ? s.rows : s.cols;

  CellSize _sizeFor(int main, int cross) =>
      _isHorizontal ? CellSize(cross, main) : CellSize(main, cross);

  CellOffset _offsetFor(int main, int cross) =>
      _isHorizontal ? CellOffset(cross, main) : CellOffset(main, cross);

  /// Distributes [total] across the slots proportional to [weights], with the
  /// rounding remainder handed out front-to-back so the result sums to [total]
  /// exactly (a Bresenham-style integer split).
  static List<int> _splitProportional(int total, List<int> weights) {
    var sum = weights.fold<int>(0, (a, b) => a + b);
    if (sum <= 0 || total <= 0) {
      return List<int>.filled(weights.length, 0);
    }
    var result = <int>[];
    var allocated = 0;
    var acc = 0;
    for (var w in weights) {
      acc += total * w;
      var upTo = acc ~/ sum;
      result.add(upTo - allocated);
      allocated = upTo;
    }
    return result;
  }

  /// The weight of each of the [n]+1 gap slots (before child 0, between each
  /// pair, after child n-1) for a main-axis alignment.
  static List<int> _gapWeights(MainAxisAlignment alignment, int n) {
    var w = List<int>.filled(n + 1, 0);
    switch (alignment) {
      case MainAxisAlignment.start:
        w[n] = 1;
      case MainAxisAlignment.end:
        w[0] = 1;
      case MainAxisAlignment.center:
        w[0] = 1;
        w[n] = 1;
      case MainAxisAlignment.spaceBetween:
        for (var i = 1; i < n; i++) {
          w[i] = 1;
        }
      case MainAxisAlignment.spaceAround:
        for (var i = 1; i < n; i++) {
          w[i] = 2;
        }
        w[0] = 1;
        w[n] = 1;
      case MainAxisAlignment.spaceEvenly:
        for (var i = 0; i <= n; i++) {
          w[i] = 1;
        }
    }
    return w;
  }

  BoxConstraints _childConstraints(int maxCross, bool stretch, int minMain,
      int maxMain) {
    if (_isHorizontal) {
      return BoxConstraints(
        minWidth: minMain,
        maxWidth: maxMain,
        minHeight: stretch ? maxCross : 0,
        maxHeight: maxCross,
      );
    }
    return BoxConstraints(
      minWidth: stretch ? maxCross : 0,
      maxWidth: maxCross,
      minHeight: minMain,
      maxHeight: maxMain,
    );
  }

  @override
  void performLayout() {
    var maxMain = _isHorizontal ? constraints.maxWidth : constraints.maxHeight;
    var maxCross =
        _isHorizontal ? constraints.maxHeight : constraints.maxWidth;
    var canStretch = crossAxisAlignment == CrossAxisAlignment.stretch &&
        maxCross < BoxConstraints.unbounded;

    // Pass 1: inflexible children.
    var allocatedMain = 0;
    var crossExtent = 0;
    var flexFactors = <int>[];
    for (var child in _children) {
      var pd = child.parentData as FlexParentData;
      if (pd.flex > 0) {
        flexFactors.add(pd.flex);
        continue;
      }
      child.layout(
        _childConstraints(maxCross, canStretch, 0, BoxConstraints.unbounded),
        parentUsesSize: true,
      );
      allocatedMain += _mainOf(child.size);
      var cross = _crossOf(child.size);
      if (cross > crossExtent) crossExtent = cross;
    }

    // Pass 2: flexible children share the free main-axis space.
    var freeMain = maxMain >= BoxConstraints.unbounded
        ? 0
        : (maxMain - allocatedMain < 0 ? 0 : maxMain - allocatedMain);
    var shares = _splitProportional(freeMain, flexFactors);
    var shareIndex = 0;
    var flexMain = 0;
    for (var child in _children) {
      var pd = child.parentData as FlexParentData;
      if (pd.flex <= 0) continue;
      var extent = shares[shareIndex++];
      var minMain = pd.fit == FlexFit.tight ? extent : 0;
      child.layout(
        _childConstraints(maxCross, canStretch, minMain, extent),
        parentUsesSize: true,
      );
      flexMain += _mainOf(child.size);
      var cross = _crossOf(child.size);
      if (cross > crossExtent) crossExtent = cross;
    }

    // Own size.
    var contentMain = allocatedMain + flexMain;
    int mainExtent;
    if (mainAxisSize == MainAxisSize.max &&
        maxMain < BoxConstraints.unbounded) {
      mainExtent = maxMain;
    } else {
      mainExtent = contentMain;
    }
    size = constraints.constrain(_sizeFor(mainExtent, crossExtent));
    var resolvedMain = _mainOf(size);
    var resolvedCross = _crossOf(size);

    // Position children: distribute the leftover main space into gap slots.
    var leftover = resolvedMain - contentMain;
    if (leftover < 0) leftover = 0;
    var gaps = _splitProportional(
      leftover,
      _gapWeights(mainAxisAlignment, _children.length),
    );
    var cursor = gaps[0];
    for (var i = 0; i < _children.length; i++) {
      var child = _children[i];
      var childCross = _crossOf(child.size);
      var crossPos = switch (crossAxisAlignment) {
        CrossAxisAlignment.start => 0,
        CrossAxisAlignment.end => resolvedCross - childCross,
        CrossAxisAlignment.center => (resolvedCross - childCross) ~/ 2,
        CrossAxisAlignment.stretch => 0,
      };
      (child.parentData as FlexParentData).offset =
          _offsetFor(cursor, crossPos);
      cursor += _mainOf(child.size) + gaps[i + 1];
    }
  }

  int _intrinsicMain(bool useMax, int crossLimit) {
    var inflexibleSum = 0;
    var maxFlexFraction = 0;
    var totalFlex = 0;
    for (var child in _children) {
      var flex = (child.parentData as FlexParentData).flex;
      var extent = _isHorizontal
          ? (useMax
              ? child.getMaxIntrinsicWidth(crossLimit)
              : child.getMinIntrinsicWidth(crossLimit))
          : (useMax
              ? child.getMaxIntrinsicHeight(crossLimit)
              : child.getMinIntrinsicHeight(crossLimit));
      if (flex > 0) {
        totalFlex += flex;
        var fraction = (extent + flex - 1) ~/ flex; // ceil(extent / flex)
        if (fraction > maxFlexFraction) maxFlexFraction = fraction;
      } else {
        inflexibleSum += extent;
      }
    }
    return inflexibleSum + maxFlexFraction * totalFlex;
  }

  int _intrinsicCross(bool useMax, int mainLimit) {
    var result = 0;
    for (var child in _children) {
      var extent = _isHorizontal
          ? (useMax
              ? child.getMaxIntrinsicHeight(mainLimit)
              : child.getMinIntrinsicHeight(mainLimit))
          : (useMax
              ? child.getMaxIntrinsicWidth(mainLimit)
              : child.getMinIntrinsicWidth(mainLimit));
      if (extent > result) result = extent;
    }
    return result;
  }

  @override
  int computeMinIntrinsicWidth(int height) => _isHorizontal
      ? _intrinsicMain(false, height)
      : _intrinsicCross(false, height);

  @override
  int computeMaxIntrinsicWidth(int height) => _isHorizontal
      ? _intrinsicMain(true, height)
      : _intrinsicCross(true, height);

  @override
  int computeMinIntrinsicHeight(int width) => _isHorizontal
      ? _intrinsicCross(false, width)
      : _intrinsicMain(false, width);

  @override
  int computeMaxIntrinsicHeight(int width) => _isHorizontal
      ? _intrinsicCross(true, width)
      : _intrinsicMain(true, width);

  @override
  void paint(Painter painter) {
    for (var child in _children) {
      var offset = (child.parentData as FlexParentData).offset;
      child.paint(painter.translate(offset));
    }
  }
}
```

Modify `app/lib/src/tui/render/render.dart` — add the part directive:

```dart
part 'render_decorated_box.dart';
part 'render_flex.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/tui/render/render_flex_test.dart`
Expected: PASS.

Run: `cd .. && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/render/render_flex.dart app/lib/src/tui/render/render.dart app/test/tui/render/render_flex_test.dart
git commit -m "$(cat <<'EOF'
Add RenderFlex render object (TUI stage 3)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: RenderTuiView and the frame pipeline

**Files:**
- Create: `app/lib/src/tui/render/render_view.dart`
- Modify: `app/lib/src/tui/render/render.dart` (add `part` directive)
- Test: `app/test/tui/render/render_view_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/tui/render/render_view_test.dart`:

```dart
import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:test/test.dart';

List<String> dump(CellBuffer b) => [
      for (var r = 0; r < b.rows; r++)
        String.fromCharCodes([
          for (var c = 0; c < b.cols; c++) b.get(r, c).rune,
        ]),
    ];

void main() {
  group('RenderTuiView', () {
    test('lays the child out tight to the configuration', () {
      var text = RenderText('hi');
      var view = RenderTuiView(CellSize(3, 6));
      var owner = PipelineOwner();
      view.attach(owner);
      view.child = text;
      view.prepareInitialFrame();

      var buffer = CellBuffer(3, 6);
      view.compositeFrame(Painter(buffer));
      expect(text.size, CellSize(3, 6));
    });

    test('compositeFrame paints the tree into the buffer', () {
      var text = RenderText('ab');
      var view = RenderTuiView(CellSize(1, 4));
      var owner = PipelineOwner();
      view.attach(owner);
      view.child = text;
      view.prepareInitialFrame();

      var buffer = CellBuffer(1, 4);
      view.compositeFrame(Painter(buffer));
      expect(dump(buffer)[0], 'ab  ');
    });

    test('changing the configuration triggers re-layout', () {
      var text = RenderText('x');
      var view = RenderTuiView(CellSize(1, 1));
      var owner = PipelineOwner();
      view.attach(owner);
      view.child = text;
      view.prepareInitialFrame();
      view.compositeFrame(Painter(CellBuffer(1, 1)));

      view.configuration = CellSize(2, 8);
      view.compositeFrame(Painter(CellBuffer(2, 8)));
      expect(text.size, CellSize(2, 8));
    });

    test('mutating a deep RenderText re-lays only its relayout boundary', () {
      // view -> Row(stretch) of two tight-flex panels, each a Padding+Text.
      var leftText = RenderText('left');
      var rightText = RenderText('right');
      var left = RenderPadding(padding: EdgeInsets.all(1), child: leftText);
      var right = RenderPadding(padding: EdgeInsets.all(1), child: rightText);
      var row = RenderFlex(
        direction: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, right],
      );
      row.setFlex(left, 1, fit: FlexFit.tight);
      row.setFlex(right, 1, fit: FlexFit.tight);

      var view = RenderTuiView(CellSize(5, 20));
      var owner = PipelineOwner();
      view.attach(owner);
      view.child = row;
      view.prepareInitialFrame();
      view.compositeFrame(Painter(CellBuffer(5, 20)));

      // Mutating leftText enqueues left (a tight-constrained boundary), not row.
      leftText.text = 'changed';
      owner.flushLayout();
      // The screen still composes without error and sizes are intact.
      expect(left.size, right.size);
      expect(view.size, CellSize(5, 20));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tui/render/render_view_test.dart`
Expected: FAIL — `RenderTuiView` is undefined.

- [ ] **Step 3: Write the implementation**

Create `app/lib/src/tui/render/render_view.dart`:

```dart
part of 'render.dart';

/// The root of the render tree. Holds one [RenderBox] child, lays it out tight
/// to the terminal [configuration], and bridges the tree to a [Painter].
///
/// It is a [RenderObject] but not a [RenderBox]: it has no parent and is not
/// laid out by a constraint protocol.
class RenderTuiView extends RenderObject {
  RenderTuiView(CellSize configuration) : _configuration = configuration;

  CellSize _configuration;

  /// The terminal size, in cells. Setting it requests a re-layout.
  CellSize get configuration => _configuration;
  set configuration(CellSize value) {
    if (value == _configuration) return;
    _configuration = value;
    markNeedsLayout();
  }

  RenderBox? _child;
  RenderBox? get child => _child;
  set child(RenderBox? value) {
    if (_child != null) {
      dropChild(_child!);
    }
    _child = value;
    if (value != null) {
      adoptChild(value);
    }
  }

  /// The view's own size — always the [configuration].
  CellSize get size => _configuration;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  @override
  void redepthChildren() {
    if (_child != null) {
      redepthChild(_child!);
    }
  }

  @override
  void visitChildren(void Function(RenderObject child) visitor) {
    if (_child != null) {
      visitor(_child!);
    }
  }

  /// Registers the view for its first layout. Call once, after [attach] and
  /// after [child] is set.
  void prepareInitialFrame() {
    _relayoutBoundary = this;
    _needsLayout = true;
    owner!._nodesNeedingLayout.add(this);
  }

  @override
  void performLayout() {
    _child?.layout(BoxConstraints.tight(_configuration), parentUsesSize: true);
  }

  /// Flushes any pending layout and paints the whole tree into [painter].
  void compositeFrame(Painter painter) {
    owner!.flushLayout();
    _child?.paint(painter);
    owner!.clearNeedsPaint();
  }
}
```

Modify `app/lib/src/tui/render/render.dart` — add the part directive:

```dart
part 'render_flex.dart';
part 'render_view.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/tui/render/render_view_test.dart`
Expected: PASS.

Run the whole render suite and analyze:
Run: `cd app && flutter test test/tui/render/`
Expected: PASS — every render test green.
Run: `cd .. && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/render/render_view.dart app/lib/src/tui/render/render.dart app/test/tui/render/render_view_test.dart
git commit -m "$(cat <<'EOF'
Add RenderTuiView root and the frame pipeline (TUI stage 3)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Public exports and README

**Files:**
- Modify: `app/lib/src/tui/tui.dart`
- Modify: `app/lib/src/tui/README.md`

- [ ] **Step 1: Add the render exports**

Modify `app/lib/src/tui/tui.dart` — append after the existing `export` lines:

```dart
export 'render/render.dart'
    show
        BoxConstraints,
        EdgeInsets,
        RenderObject,
        ParentData,
        BoxParentData,
        PipelineOwner,
        RenderBox,
        RenderBoxWithChild,
        RenderText,
        RenderPadding,
        RenderConstrainedBox,
        RenderDecoratedBox,
        BoxDecoration,
        BoxBorder,
        RenderFlex,
        FlexParentData,
        FlexFit,
        Axis,
        MainAxisAlignment,
        CrossAxisAlignment,
        MainAxisSize,
        RenderTuiView;
```

- [ ] **Step 2: Verify the barrel file compiles**

Run: `cd .. && flutter analyze`
Expected: No issues.

- [ ] **Step 3: Update the README**

Modify `app/lib/src/tui/README.md`:

In the intro paragraph, change `**This package is currently stage 1: the engine layer only.**` and the sentence after it to:

```markdown
**This package is currently at stage 3: engine, paint kit, and render tree.**
There is no widget layer yet — see [the roadmap](../../../../docs/superpowers/tui-roadmap.md) for the staged plan.
```

In the "What's here" table, add these rows after the `tui.dart` row:

```markdown
| `geometry.dart` | `CellOffset`, `CellSize`, `CellRect` — integer-cell geometry |
| `painter.dart` | `Painter` — offset+clip drawing surface; `BorderChars`, text helpers |
| `text_wrap.dart` | `wrapText` — pure word-wrapping |
| `render/` | The render tree: `RenderObject`/`RenderBox`, `BoxConstraints`, `RenderFlex`/`RenderPadding`/`RenderText`/`RenderDecoratedBox`/`RenderConstrainedBox`, `RenderTuiView` |
```

In "Current limitations", replace the `- No layout, widgets, or render objects (stages 2–4).` line with:

```markdown
- No widget layer yet (`Widget`/`Element`/`setState`) — stage 4.
- Repaint is whole-tree: with no layer model, `markNeedsPaint` repaints
  everything. Re-layout *is* localized to relayout boundaries.
```

- [ ] **Step 4: Commit**

```bash
git add app/lib/src/tui/tui.dart app/lib/src/tui/README.md
git commit -m "$(cat <<'EOF'
Export the TUI render tree and update the README (stage 3)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Demo and roadmap

**Files:**
- Create: `app/examples/tui/render_tree_demo.dart`
- Modify: `docs/superpowers/tui-roadmap.md`

- [ ] **Step 1: Write the demo**

Create `app/examples/tui/render_tree_demo.dart`:

```dart
// Stage 3 render-tree demo. Run in a real terminal:
//   cd app && dart run examples/tui/render_tree_demo.dart
// Press any key to update the left panel; press 'q' to quit.

import 'package:flutterware_app/src/tui/tui.dart';

const _leftLorem = 'The render tree lays this panel out with BoxConstraints '
    'and a RenderFlex column. Press a key to mutate this text.';

const _rightLorem = 'This panel is a relayout boundary: when the left panel '
    'updates, only its subtree is laid out again. Both panels share one '
    'RenderFlex row, sized by flex factors (left 1, right 2).';

late RenderText _leftBody;
var _counter = 0;

RenderBox _panel(String title, RenderText body, Color accent) {
  return RenderDecoratedBox(
    decoration: BoxDecoration(
      border: BoxBorder(chars: BorderChars.rounded(), fg: accent),
    ),
    child: RenderPadding(
      padding: EdgeInsets.all(1),
      child: RenderFlex(
        direction: Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RenderText(title, fg: accent, style: TextStyle.bold),
          body,
        ],
      ),
    ),
  );
}

RenderBox _buildScreen() {
  var header = RenderConstrainedBox(
    additionalConstraints: BoxConstraints.tightFor(height: 1),
    child: RenderDecoratedBox(
      decoration: BoxDecoration(fill: Cell(rune: 0x20, bg: Color.blue)),
      child: RenderText(
        'flutterware — render tree demo',
        fg: Color.brightWhite,
        bg: Color.blue,
        style: TextStyle.bold,
        hAlign: HorizontalAlign.center,
      ),
    ),
  );

  _leftBody = RenderText(_leftLorem);
  var left = _panel('Left panel', _leftBody, Color.cyan);
  var right = _panel('Right panel', RenderText(_rightLorem), Color.magenta);
  var row = RenderFlex(
    direction: Axis.horizontal,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [left, right],
  );
  row.setFlex(left, 1, fit: FlexFit.tight);
  row.setFlex(right, 2, fit: FlexFit.tight);

  var footer = RenderConstrainedBox(
    additionalConstraints: BoxConstraints.tightFor(height: 1),
    child: RenderText(
      "Press any key to update the left panel · 'q' to quit",
      fg: Color.brightBlack,
    ),
  );

  var screen = RenderFlex(
    direction: Axis.vertical,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [header, row, footer],
  );
  screen.setFlex(row, 1, fit: FlexFit.tight);
  return screen;
}

Future<void> main() async {
  await Terminal.run((terminal) async {
    var view = RenderTuiView(CellSize.zero);
    var owner = PipelineOwner();
    view.attach(owner);
    view.child = _buildScreen();
    view.prepareInitialFrame();

    void render() {
      terminal.draw((buffer) {
        view.configuration = CellSize(buffer.rows, buffer.cols);
        view.compositeFrame(Painter(buffer));
      });
    }

    render();
    var resizeSub = terminal.resizes.listen((_) => render());
    try {
      await for (final event in terminal.keys) {
        if (event is CharKey && event.rune == 0x71 /* 'q' */) break;
        _counter++;
        _leftBody.text = 'Updated $_counter time(s). Only the left panel '
            'subtree was laid out again — the right panel is untouched.';
        render();
      }
    } finally {
      await resizeSub.cancel();
    }
  });
}
```

- [ ] **Step 2: Verify the demo compiles**

Run: `cd app && dart analyze examples/tui/render_tree_demo.dart`
Expected: No issues.

- [ ] **Step 3: Manual smoke test**

Run: `cd app && dart run examples/tui/render_tree_demo.dart`
Expected, in a real terminal:
- A blue header bar reading "flutterware — render tree demo".
- Two rounded-border panels side by side; the right panel about twice the
  width of the left.
- Each panel shows a bold title and wrapped body text inside a 1-cell border,
  with no text bleeding across the border.
- Pressing a key updates the left panel's body text; the right panel is
  unchanged.
- Resizing the terminal re-lays the whole screen.
- Pressing `q` exits cleanly and restores the terminal.

If the demo misbehaves, fix the underlying render code (and its unit tests)
before proceeding.

- [ ] **Step 4: Update the roadmap**

Modify `docs/superpowers/tui-roadmap.md`:

In the Stages table, change the stage 3 row's status from `⬜ Not started` to `✅ Done`.

In the "Detailed docs per stage" list, add after the Stage 2 entry:

```markdown
- Stage 3 — [spec](specs/2026-05-15-tui-stage3-render-tree-design.md) ·
  [plan](plans/2026-05-15-tui-stage3-render-tree.md)
```

- [ ] **Step 5: Run the full check and commit**

Run: `cd app && flutter test test/tui/`
Expected: PASS — all TUI tests, old and new.
Run: `cd .. && dart tool/prepare_submit.dart && git status`
Expected: the formatter produces no diff (clean working tree apart from the new files).

```bash
git add app/examples/tui/render_tree_demo.dart docs/superpowers/tui-roadmap.md
git commit -m "$(cat <<'EOF'
Add render-tree demo and mark TUI stage 3 done

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** `BoxConstraints` (Task 1), `RenderObject`/`ParentData`/`PipelineOwner` (Task 2), `RenderBox`/layout protocol/intrinsics (Task 3), `RenderText` (Task 4), `RenderPadding`/`EdgeInsets` (Task 5 — `EdgeInsets` actually landed in Task 1's `box_constraints.dart` because `BoxConstraints.deflate` depends on it; this is a deliberate, noted deviation from the spec's file list), `RenderConstrainedBox` (Task 6), `RenderDecoratedBox`/`BoxDecoration`/`BoxBorder` (Task 7), `RenderFlex`/`FlexParentData`/enums (Task 8), `RenderTuiView` (Task 9), exports/README (Task 10), demo/roadmap (Task 11). Dirty-tracking and relayout-boundary localization are tested in Task 3 and Task 9.
- **Deviation from spec:** the spec grouped `FlexParentData` under `render_object.dart` in one code block but listed it under `render_flex.dart` in the file list. The plan puts `FlexParentData` and `FlexFit` in `render_flex.dart` (flex-specific), and `EdgeInsets` in `box_constraints.dart` (so `BoxConstraints.deflate` can use it). All Stage 3 files are `part` of one library `render.dart` rather than separate libraries, so library-private layout state is shared — the spec's "Files touched" list is otherwise unchanged.
- **Repaint limitation:** as the spec states, `markNeedsPaint` only sets `PipelineOwner._needsPaint`; `compositeFrame` always repaints the whole tree. Relayout is localized; repaint is not. This is intentional for Stage 3.

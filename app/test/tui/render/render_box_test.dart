import 'package:flutterware_app/src/tui/geometry.dart';
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

  int layoutCount = 0;

  @override
  void performLayout() {
    layoutCount++;
    child!.layout(constraints, parentUsesSize: true);
    (child!.parentData! as BoxParentData).offset = CellOffset.zero;
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
    test(
        'a tight-constrained child is its own relayout boundary, so '
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

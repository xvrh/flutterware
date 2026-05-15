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
    test('a box receiving tight constraints is its own relayout boundary', () {
      // mid is laid out tight and passes those tight constraints straight to
      // leaf, so leaf is also its own boundary. Dirtying leaf re-lays only
      // leaf — the dirty does not bubble up to mid.
      var leaf = _FixedBox(CellSize(1, 1));
      var mid = _PassBox(leaf);
      var owner = PipelineOwner();

      mid.attach(owner);
      mid.layout(BoxConstraints.tight(CellSize(5, 5)));
      expect(leaf.layoutCount, 1);
      expect(mid.layoutCount, 1);

      leaf.markNeedsLayout();
      owner.flushLayout();
      expect(leaf.layoutCount, 2);
      expect(mid.layoutCount, 1); // mid untouched — leaf is its own boundary
    });

    test(
        'a box receiving non-tight constraints bubbles dirty to its parent '
        'boundary', () {
      // mid is laid out with loose (non-tight) constraints and passes them to
      // leaf, so leaf is NOT its own boundary — its boundary is mid. Dirtying
      // leaf enqueues mid, and the flush re-lays the whole mid subtree.
      var leaf = _FixedBox(CellSize(1, 1));
      var mid = _PassBox(leaf);
      var owner = PipelineOwner();

      mid.attach(owner);
      mid.layout(BoxConstraints.loose(CellSize(5, 5)));
      expect(leaf.layoutCount, 1);
      expect(mid.layoutCount, 1);

      leaf.markNeedsLayout();
      owner.flushLayout();
      expect(mid.layoutCount, 2); // mid (the relayout boundary) re-laid out
      expect(leaf.layoutCount, 2); // and its child with it
    });
  });
}

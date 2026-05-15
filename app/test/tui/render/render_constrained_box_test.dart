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

    test('tight additional-constraint axis overrides the child intrinsic', () {
      // additionalConstraints fixes width to 7; child reports intrinsic width 20.
      // CellSize(rows, cols) — so cols=20 means width=20.
      var child = _FixedBox(CellSize(10, 20));
      var box = RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tightFor(width: 7),
        child: child,
      );
      // The tight axis (min == max == 7) must win over the child's 20.
      expect(box.getMaxIntrinsicWidth(100), 7);
    });

    test('non-tight axis passes child intrinsic through, clamped to max', () {
      // Child intrinsic width 12 falls inside [0, 30] → returned as-is.
      // CellSize(rows, cols) — cols=12 means width=12.
      var child = _FixedBox(CellSize(10, 12));
      var box = RenderConstrainedBox(
        additionalConstraints: BoxConstraints(minWidth: 0, maxWidth: 30),
        child: child,
      );
      expect(box.getMaxIntrinsicWidth(100), 12);

      // Child intrinsic width 50 exceeds maxWidth 30 → clamped to 30.
      var wideChild = _FixedBox(CellSize(10, 50));
      var clampingBox = RenderConstrainedBox(
        additionalConstraints: BoxConstraints(minWidth: 0, maxWidth: 30),
        child: wideChild,
      );
      expect(clampingBox.getMaxIntrinsicWidth(100), 30);
    });
  });
}

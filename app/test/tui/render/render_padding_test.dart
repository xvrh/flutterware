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
      expect((child.parentData! as BoxParentData).offset, CellOffset(2, 3));
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

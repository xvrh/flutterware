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

/// A leaf box that sizes to a fixed natural size and fills itself with '*'.
class _FillBox extends RenderBox {
  _FillBox(this.natural);
  CellSize natural;

  @override
  void performLayout() {
    size = constraints.constrain(natural);
  }

  @override
  void paint(Painter painter) {
    painter.fillRect(
      CellRect.fromOffsetSize(CellOffset.zero, size),
      Cell(rune: 0x2a /* '*' */),
    );
  }
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

    test('paint places the child at the padded offset', () {
      var pad = RenderPadding(
        padding: EdgeInsets.all(1),
        child: _FillBox(CellSize(1, 2)),
      );
      pad.layout(BoxConstraints.tight(CellSize(3, 4)));
      var buffer = CellBuffer(3, 4);
      pad.paint(Painter(buffer));
      // '*' cells appear only at row 1, cols 1-2; everything else is space.
      expect(dump(buffer), ['    ', ' ** ', '    ']);
    });

    test('asymmetric padding applies each side to the correct axis', () {
      var child = _FixedBox(CellSize(2, 5));
      var pad = RenderPadding(
        padding: EdgeInsets.only(left: 2, top: 1, right: 4, bottom: 3),
        child: child,
      );
      pad.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      // Child offset: row = top = 1, col = left = 2.
      expect((child.parentData! as BoxParentData).offset, CellOffset(1, 2));
      // Padding size: rows = child.rows + top + bottom = 2+1+3 = 6,
      //               cols = child.cols + left + right = 5+2+4 = 11.
      expect(pad.size, CellSize(6, 11));
    });

    test('the padding setter triggers re-layout', () {
      var child = _FixedBox(CellSize(2, 2));
      var pad = RenderPadding(padding: EdgeInsets.all(1), child: child);
      var owner = PipelineOwner();
      pad.attach(owner);
      pad.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      // Initial size: child 2×2 + padding 2 each axis = 4×4.
      expect(pad.size, CellSize(4, 4));

      pad.padding = EdgeInsets.all(3);
      pad.layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      // New size: child 2×2 + padding 6 each axis = 8×8.
      expect(pad.size, CellSize(8, 8));
    });
  });
}

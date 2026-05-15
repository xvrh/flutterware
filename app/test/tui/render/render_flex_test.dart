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
  var offset = (child.parentData! as FlexParentData).offset;
  return axis == Axis.horizontal ? offset.col : offset.row;
}

int crossOffset(RenderBox child, Axis axis) {
  var offset = (child.parentData! as FlexParentData).offset;
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
      RenderFlex(
        direction: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [tall, short],
      ).layout(BoxConstraints(maxWidth: 99, maxHeight: 99));
      expect(crossOffset(short, Axis.horizontal), 2); // (5-1) ~/ 2
    });

    test('stretch sizes children to the cross extent', () {
      var a = _FixedBox(CellSize(1, 1));
      RenderFlex(
        direction: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [a],
      ).layout(BoxConstraints.tight(CellSize(6, 10)));
      expect(a.size.rows, 6);
    });
  });

  group('RenderFlex flex factors', () {
    test('a single flex child fills the free space', () {
      var fixed = _FixedBox(CellSize(1, 4));
      var flexible = _FixedBox(CellSize(1, 1));
      var row =
          RenderFlex(direction: Axis.horizontal, children: [fixed, flexible]);
      row.setFlex(flexible, 1, fit: FlexFit.tight);
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

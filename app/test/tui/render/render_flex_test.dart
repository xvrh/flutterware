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

    test('spaceAround distributes leftover with half-size edge gaps', () {
      // 2 children, leftover 6: _gapWeights → [1,2,1], sum=4.
      // _splitProportional(6,[1,2,1]) → [1,3,2].
      // child0 at 1, child1 at 1+2+3=6.
      var row = build(MainAxisAlignment.spaceAround);
      expect(mainOffset(row.children[0], Axis.horizontal), 1);
      expect(mainOffset(row.children[1], Axis.horizontal), 6);
    });

    test('spaceEvenly distributes leftover across n+1 equal gaps', () {
      // 2 children, leftover 6: _gapWeights → [1,1,1], sum=3.
      // _splitProportional(6,[1,1,1]) → [2,2,2].
      // child0 at 2, child1 at 2+2+2=6.
      var row = build(MainAxisAlignment.spaceEvenly);
      expect(mainOffset(row.children[0], Axis.horizontal), 2);
      expect(mainOffset(row.children[1], Axis.horizontal), 6);
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

    test('a loose flex child may stay smaller than its allotment', () {
      var fixed = _FixedBox(CellSize(1, 4));
      var flexible = _FixedBox(CellSize(1, 1));
      var row =
          RenderFlex(direction: Axis.horizontal, children: [fixed, flexible]);
      // Default fit is FlexFit.loose — do not pass fit:.
      row.setFlex(flexible, 1);
      row.layout(BoxConstraints.tight(CellSize(1, 20)));
      // Allotted 16 cells (20-4) but, being loose, keeps its natural width 1.
      expect(flexible.size.cols, 1);
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

    test('main intrinsic accounts for flex children', () {
      // inflexible child: width=4; flex child: width=6, flex=2.
      // fraction = ceil(6/2) = 3; result = 4 + 3*2 = 10.
      var inflexible = _FixedBox(CellSize(1, 4));
      var flexChild = _FixedBox(CellSize(1, 6));
      var row = RenderFlex(
        direction: Axis.horizontal,
        children: [inflexible, flexChild],
      );
      row.setFlex(flexChild, 2);
      expect(row.getMaxIntrinsicWidth(100), 10);
    });
  });

  group('insert / move', () {
    test('insert after null places child first', () {
      var a = RenderText('a');
      var b = RenderText('b');
      var flex = RenderFlex(direction: Axis.vertical, children: [a]);
      flex.insert(b, after: null);
      expect(flex.children, [b, a]);
    });

    test('insert after a child places it immediately following', () {
      var a = RenderText('a');
      var b = RenderText('b');
      var c = RenderText('c');
      var flex = RenderFlex(direction: Axis.vertical, children: [a, b]);
      flex.insert(c, after: a);
      expect(flex.children, [a, c, b]);
    });

    test('insert after the last child appends it', () {
      var a = RenderText('a');
      var b = RenderText('b');
      var c = RenderText('c');
      var flex = RenderFlex(direction: Axis.vertical, children: [a, b]);
      flex.insert(c, after: b);
      expect(flex.children, [a, b, c]);
    });

    test('move relocates an existing child without re-adopting', () {
      var a = RenderText('a');
      var b = RenderText('b');
      var c = RenderText('c');
      var flex = RenderFlex(direction: Axis.vertical, children: [a, b, c]);
      flex.move(c, after: null);
      expect(flex.children, [c, a, b]);
      expect(c.parent, flex);
    });

    test('move with explicit after relocates correctly', () {
      var a = RenderText('a');
      var b = RenderText('b');
      var c = RenderText('c');
      var flex = RenderFlex(direction: Axis.vertical, children: [a, b, c]);
      flex.move(a, after: b);
      expect(flex.children, [b, a, c]);
    });
  });
}

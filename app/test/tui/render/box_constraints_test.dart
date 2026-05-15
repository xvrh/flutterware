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
      var c =
          BoxConstraints(minWidth: 3, maxWidth: 8, minHeight: 2, maxHeight: 5);
      expect(c.constrainWidth(1), 3);
      expect(c.constrainWidth(6), 6);
      expect(c.constrainWidth(20), 8);
      expect(c.constrainHeight(0), 2);
      expect(c.constrainHeight(99), 5);
    });

    test('deflate shrinks max and clamps min at zero', () {
      var c =
          BoxConstraints(minWidth: 1, maxWidth: 10, minHeight: 1, maxHeight: 6);
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
      var parent =
          BoxConstraints(minWidth: 0, maxWidth: 5, minHeight: 0, maxHeight: 5);
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
      var c =
          BoxConstraints(minWidth: 2, maxWidth: 9, minHeight: 1, maxHeight: 7);
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

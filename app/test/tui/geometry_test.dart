import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:test/test.dart';

void main() {
  group('CellOffset', () {
    test('addition and subtraction', () {
      expect(CellOffset(1, 2) + CellOffset(3, 4), CellOffset(4, 6));
      expect(CellOffset(5, 5) - CellOffset(1, 2), CellOffset(4, 3));
    });

    test('zero constant', () {
      expect(CellOffset.zero, CellOffset(0, 0));
    });

    test('structural equality', () {
      expect(CellOffset(2, 3), CellOffset(2, 3));
      expect(CellOffset(2, 3) == CellOffset(3, 2), isFalse);
    });
  });

  group('CellSize', () {
    test('isEmpty when a dimension is non-positive', () {
      expect(CellSize(0, 5).isEmpty, isTrue);
      expect(CellSize(5, 0).isEmpty, isTrue);
      expect(CellSize(-1, 5).isEmpty, isTrue);
      expect(CellSize(3, 4).isEmpty, isFalse);
    });

    test('structural equality', () {
      expect(CellSize(3, 4), CellSize(3, 4));
      expect(CellSize(3, 4) == CellSize(4, 3), isFalse);
    });
  });

  group('CellRect', () {
    test('derived edges and accessors', () {
      var r = CellRect.fromTLWH(2, 3, 10, 5); // top,left,width,height
      expect(r.top, 2);
      expect(r.left, 3);
      expect(r.width, 10);
      expect(r.height, 5);
      expect(r.bottom, 7);
      expect(r.right, 13);
      expect(r.offset, CellOffset(2, 3));
      expect(r.size, CellSize(5, 10));
    });

    test('fromOffsetSize', () {
      var r = CellRect.fromOffsetSize(CellOffset(2, 3), CellSize(5, 10));
      expect(r, CellRect.fromTLWH(2, 3, 10, 5));
    });

    test('contains uses the half-open convention', () {
      var r = CellRect.fromTLWH(0, 0, 3, 3); // covers rows/cols 0..2
      expect(r.contains(CellOffset(0, 0)), isTrue);
      expect(r.contains(CellOffset(2, 2)), isTrue);
      expect(r.contains(CellOffset(3, 0)), isFalse);
      expect(r.contains(CellOffset(0, 3)), isFalse);
      expect(r.contains(CellOffset(-1, 0)), isFalse);
    });

    test('isEmpty', () {
      expect(CellRect.fromTLWH(0, 0, 0, 5).isEmpty, isTrue);
      expect(CellRect.fromTLWH(0, 0, 5, 0).isEmpty, isTrue);
      expect(CellRect.fromTLWH(0, 0, 5, 5).isEmpty, isFalse);
    });

    test('intersect of overlapping rects', () {
      var a = CellRect.fromTLWH(0, 0, 10, 10);
      var b = CellRect.fromTLWH(5, 5, 10, 10);
      expect(a.intersect(b), CellRect.fromTLWH(5, 5, 5, 5));
    });

    test('intersect of disjoint rects is empty', () {
      var a = CellRect.fromTLWH(0, 0, 2, 2);
      var b = CellRect.fromTLWH(10, 10, 2, 2);
      expect(a.intersect(b).isEmpty, isTrue);
    });

    test('shift translates the rect', () {
      var r = CellRect.fromTLWH(1, 1, 4, 4);
      expect(r.shift(CellOffset(2, 3)), CellRect.fromTLWH(3, 4, 4, 4));
    });

    test('deflate insets every side', () {
      var r = CellRect.fromTLWH(0, 0, 10, 8);
      expect(r.deflate(1), CellRect.fromTLWH(1, 1, 8, 6));
    });

    test('deflate past collapse yields an empty rect', () {
      var r = CellRect.fromTLWH(0, 0, 3, 3);
      expect(r.deflate(5).isEmpty, isTrue);
    });

    test('intersect of edge-adjacent rects is empty', () {
      var a = CellRect.fromTLWH(0, 0, 2, 2);
      var b = CellRect.fromTLWH(0, 2, 2, 2); // shares the right edge of a
      expect(a.intersect(b).isEmpty, isTrue);
    });
  });
}

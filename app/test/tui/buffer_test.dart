import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:test/test.dart';

void main() {
  group('CellBuffer', () {
    test('new buffer is filled with Cell.empty', () {
      final b = CellBuffer(3, 4);
      expect(b.rows, 3);
      expect(b.cols, 4);
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 4; c++) {
          expect(b.get(r, c), Cell.empty);
        }
      }
    });

    test('set and get round-trip', () {
      final b = CellBuffer(2, 2);
      final cell = Cell(rune: 0x41, fg: Color.red);
      b.set(0, 1, cell);
      expect(b.get(0, 1), cell);
      expect(b.get(0, 0), Cell.empty);
    });

    test('writeAt writes a string left-to-right', () {
      final b = CellBuffer(1, 10);
      b.writeAt(0, 2, 'Hi');
      expect(b.get(0, 0), Cell.empty);
      expect(b.get(0, 1), Cell.empty);
      expect(b.get(0, 2).rune, 0x48); // H
      expect(b.get(0, 3).rune, 0x69); // i
      expect(b.get(0, 4), Cell.empty);
    });

    test('writeAt applies fg/bg/style to all cells', () {
      final b = CellBuffer(1, 5);
      b.writeAt(0, 0, 'ab', fg: Color.red, style: TextStyle.bold);
      expect(b.get(0, 0).fg, Color.red);
      expect(b.get(0, 0).style, TextStyle.bold);
      expect(b.get(0, 1).fg, Color.red);
    });

    test('writeAt clips silently past right edge', () {
      final b = CellBuffer(1, 3);
      b.writeAt(0, 1, 'hello');
      expect(b.get(0, 0), Cell.empty);
      expect(b.get(0, 1).rune, 0x68); // h
      expect(b.get(0, 2).rune, 0x65); // e
      // 'llo' silently dropped
    });

    test('writeAt with negative col is partially clipped', () {
      final b = CellBuffer(1, 4);
      b.writeAt(0, -2, 'hello');
      // h,e at -2,-1 clipped; l,l,o at 0,1,2
      expect(b.get(0, 0).rune, 0x6c); // l
      expect(b.get(0, 1).rune, 0x6c); // l
      expect(b.get(0, 2).rune, 0x6f); // o
      expect(b.get(0, 3), Cell.empty);
    });

    test('set out of bounds is a no-op', () {
      final b = CellBuffer(2, 2);
      // Must not throw.
      b.set(-1, 0, Cell(rune: 0x41));
      b.set(0, 5, Cell(rune: 0x41));
      b.set(10, 10, Cell(rune: 0x41));
      expect(b.get(0, 0), Cell.empty);
    });

    test('get out of bounds returns Cell.empty', () {
      final b = CellBuffer(2, 2);
      expect(b.get(-1, 0), Cell.empty);
      expect(b.get(0, 5), Cell.empty);
    });

    test('fill replaces every cell', () {
      final b = CellBuffer(2, 2);
      final c = Cell(rune: 0x41, fg: Color.blue);
      b.fill(c);
      expect(b.get(0, 0), c);
      expect(b.get(1, 1), c);
    });

    test('fillRect fills only the given region', () {
      final b = CellBuffer(4, 4);
      final c = Cell(rune: 0x23); // #
      b.fillRect(1, 1, 2, 2, c);
      expect(b.get(0, 0), Cell.empty);
      expect(b.get(1, 1), c);
      expect(b.get(2, 2), c);
      expect(b.get(3, 3), Cell.empty);
    });

    test('fillRect clips to buffer bounds', () {
      final b = CellBuffer(2, 2);
      final c = Cell(rune: 0x23);
      b.fillRect(-1, -1, 5, 5, c); // overflows on all sides
      // Every in-bounds cell should be c.
      for (var r = 0; r < 2; r++) {
        for (var col = 0; col < 2; col++) {
          expect(b.get(r, col), c);
        }
      }
    });

    test('copyFrom copies all cells', () {
      final a = CellBuffer(2, 2);
      a.set(0, 0, Cell(rune: 0x41));
      a.set(1, 1, Cell(rune: 0x42));
      final b = CellBuffer(2, 2);
      b.copyFrom(a);
      expect(b.get(0, 0).rune, 0x41);
      expect(b.get(1, 1).rune, 0x42);
    });

    test('copyFrom throws on size mismatch', () {
      final a = CellBuffer(2, 2);
      final b = CellBuffer(3, 3);
      expect(() => b.copyFrom(a), throwsA(isA<ArgumentError>()));
    });

    test('inBounds', () {
      final b = CellBuffer(2, 3);
      expect(b.inBounds(0, 0), isTrue);
      expect(b.inBounds(1, 2), isTrue);
      expect(b.inBounds(-1, 0), isFalse);
      expect(b.inBounds(0, 3), isFalse);
      expect(b.inBounds(2, 0), isFalse);
    });
  });
}

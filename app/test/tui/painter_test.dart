import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:flutterware_app/src/tui/geometry.dart';
import 'package:flutterware_app/src/tui/painter.dart';
import 'package:test/test.dart';

/// Renders a buffer to a list of strings, one per row, for easy assertions.
List<String> dump(CellBuffer b) => [
      for (var r = 0; r < b.rows; r++)
        String.fromCharCodes([
          for (var c = 0; c < b.cols; c++) b.get(r, c).rune,
        ]),
    ];

void main() {
  var star = Cell(rune: 0x2a); // '*'

  group('Painter.fillRect', () {
    test('fills the given rect, leaving the rest blank', () {
      var b = CellBuffer(3, 5);
      Painter(b).fillRect(CellRect.fromTLWH(1, 1, 2, 1), star);
      expect(dump(b), ['     ', ' **  ', '     ']);
    });

    test('fill covers the whole buffer', () {
      var b = CellBuffer(2, 3);
      Painter(b).fill(star);
      expect(dump(b), ['***', '***']);
    });
  });

  group('Painter.translate', () {
    test('shifts painted content by the offset', () {
      var b = CellBuffer(4, 4);
      Painter(b)
          .translate(CellOffset(1, 2))
          .fillRect(CellRect.fromTLWH(0, 0, 1, 1), star);
      expect(b.get(1, 2).rune, 0x2a);
      expect(b.get(0, 0).rune, 0x20);
    });

    test('translates still fill the whole buffer via fill()', () {
      var b = CellBuffer(2, 2);
      Painter(b).translate(CellOffset(1, 1)).fill(star);
      expect(dump(b), ['**', '**']);
    });
  });

  group('Painter.clip', () {
    test('drops writes outside the clip', () {
      var b = CellBuffer(4, 4);
      Painter(b)
          .clip(CellRect.fromTLWH(0, 0, 2, 2))
          .fillRect(CellRect.fromTLWH(0, 0, 10, 10), star);
      expect(dump(b), ['**  ', '**  ', '    ', '    ']);
    });

    test('clip composes with a later translate', () {
      // Clip to the top-left 2x2, then translate by (1,1): only the cell
      // that lands back inside the clip is painted.
      var b = CellBuffer(4, 4);
      Painter(b)
          .clip(CellRect.fromTLWH(0, 0, 2, 2))
          .translate(CellOffset(1, 1))
          .fillRect(CellRect.fromTLWH(0, 0, 5, 5), star);
      expect(dump(b), ['    ', ' *  ', '    ', '    ']);
    });

    test('nested clips intersect', () {
      var b = CellBuffer(4, 4);
      Painter(b)
          .clip(CellRect.fromTLWH(0, 0, 3, 3))
          .clip(CellRect.fromTLWH(1, 1, 3, 3))
          .fill(star);
      expect(dump(b), ['    ', ' ** ', ' ** ', '    ']);
    });
  });

  group('Painter lines', () {
    test('drawHLine draws a horizontal run', () {
      var b = CellBuffer(1, 5);
      Painter(b).drawHLine(CellOffset(0, 1), 3, rune: 0x2a);
      expect(dump(b), [' *** ']);
    });

    test('drawVLine draws a vertical run', () {
      var b = CellBuffer(4, 1);
      Painter(b).drawVLine(CellOffset(1, 0), 2, rune: 0x2a);
      expect(dump(b), [' ', '*', '*', ' ']);
    });

    test('non-positive length draws nothing', () {
      var b = CellBuffer(1, 3);
      Painter(b).drawHLine(CellOffset(0, 0), 0, rune: 0x2a);
      expect(dump(b), ['   ']);
      Painter(b).drawVLine(CellOffset(0, 0), -2, rune: 0x2a);
      expect(dump(b), ['   ']);
    });
  });

  group('BorderChars', () {
    test('single preset has box-drawing corners', () {
      var c = BorderChars.single();
      expect(c.topLeft, '┌');
      expect(c.bottomRight, '┘');
    });

    test('ascii preset uses plain characters', () {
      var c = BorderChars.ascii();
      expect(c.topLeft, '+');
      expect(c.horizontal, '-');
      expect(c.vertical, '|');
    });
  });
}

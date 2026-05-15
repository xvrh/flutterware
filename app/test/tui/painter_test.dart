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

  group('Painter.drawBorder', () {
    test('draws an ascii box around the rect', () {
      var b = CellBuffer(3, 4);
      Painter(b).drawBorder(
        CellRect.fromTLWH(0, 0, 4, 3),
        chars: BorderChars.ascii(),
      );
      expect(dump(b), ['+--+', '|  |', '+--+']);
    });

    test('leaves the interior untouched', () {
      var b = CellBuffer(3, 3);
      Painter(b).drawBorder(
        CellRect.fromTLWH(0, 0, 3, 3),
        chars: BorderChars.ascii(),
      );
      expect(b.get(1, 1).rune, 0x20); // still blank
    });

    test('a 1-wide rect does not crash and draws vertical edges', () {
      var b = CellBuffer(4, 1);
      Painter(b).drawBorder(
        CellRect.fromTLWH(0, 0, 1, 4),
        chars: BorderChars.ascii(),
      );
      // Middle rows are vertical edges; no exception thrown.
      expect(b.get(1, 0).rune, '|'.runes.first);
      expect(b.get(2, 0).rune, '|'.runes.first);
    });

    test('a 1-tall rect does not crash and draws horizontal edges', () {
      var b = CellBuffer(1, 4);
      Painter(b).drawBorder(
        CellRect.fromTLWH(0, 0, 4, 1),
        chars: BorderChars.ascii(),
      );
      // No exception; the middle cells are horizontal edges.
      expect(b.get(0, 1).rune, '-'.runes.first);
      expect(b.get(0, 2).rune, '-'.runes.first);
    });

    test('an empty rect draws nothing', () {
      var b = CellBuffer(3, 3);
      Painter(b).drawBorder(
        CellRect.fromTLWH(0, 0, 0, 0),
        chars: BorderChars.ascii(),
      );
      expect(dump(b), ['   ', '   ', '   ']);
    });

    test('respects the clip', () {
      var b = CellBuffer(4, 4);
      Painter(b).clip(CellRect.fromTLWH(0, 0, 4, 2)).drawBorder(
            CellRect.fromTLWH(0, 0, 4, 4),
            chars: BorderChars.ascii(),
          );
      // Only the top two rows of the border survive the clip.
      expect(dump(b), ['+--+', '|  |', '    ', '    ']);
    });
  });

  group('Painter.drawText', () {
    test('left/top aligned single line', () {
      var b = CellBuffer(2, 8);
      Painter(b).drawText(CellRect.fromTLWH(0, 0, 8, 2), 'hi');
      expect(dump(b), ['hi      ', '        ']);
    });

    test('horizontal center alignment', () {
      var b = CellBuffer(1, 7);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 7, 1),
        'odd',
        hAlign: HorizontalAlign.center,
      );
      // 7 - 3 = 4 spare cols, 2 each side.
      expect(dump(b), ['  odd  ']);
    });

    test('horizontal right alignment', () {
      var b = CellBuffer(1, 6);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 6, 1),
        'abc',
        hAlign: HorizontalAlign.right,
      );
      expect(dump(b), ['   abc']);
    });

    test('vertical center alignment', () {
      var b = CellBuffer(3, 3);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 3, 3),
        'x',
        vAlign: VerticalAlign.center,
      );
      expect(dump(b), ['   ', 'x  ', '   ']);
    });

    test('vertical bottom alignment', () {
      var b = CellBuffer(3, 3);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 3, 3),
        'x',
        vAlign: VerticalAlign.bottom,
      );
      expect(dump(b), ['   ', '   ', 'x  ']);
    });

    test('wraps long text across rows', () {
      var b = CellBuffer(2, 7);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 7, 2),
        'one two three',
      );
      expect(dump(b), ['one two', 'three  ']);
    });

    test('drops wrapped rows that overflow the rect height', () {
      var b = CellBuffer(3, 7);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 7, 1), // only one row tall
        'one two three',
      );
      expect(dump(b), ['one two', '       ', '       ']);
    });

    test('unwrapped long line is clipped at the rect right edge', () {
      var b = CellBuffer(1, 8);
      Painter(b).drawText(
        CellRect.fromTLWH(0, 0, 4, 1),
        'abcdefgh',
        wrap: false,
      );
      expect(dump(b), ['abcd    ']);
    });

    test('text is offset by the rect position', () {
      var b = CellBuffer(3, 6);
      Painter(b).drawText(CellRect.fromTLWH(1, 2, 4, 1), 'ab');
      expect(dump(b), ['      ', '  ab  ', '      ']);
    });

    test('respects the clip; alignment stays relative to the logical rect', () {
      var b = CellBuffer(1, 8);
      // 'ab' right-aligned in an 8-wide rect lands on cols 6 and 7.
      // The clip cuts off col 7, so only 'a' (col 6) survives.
      Painter(b).clip(CellRect.fromTLWH(0, 0, 7, 1)).drawText(
            CellRect.fromTLWH(0, 0, 8, 1),
            'ab',
            hAlign: HorizontalAlign.right,
          );
      expect(dump(b), ['      a ']);
    });

    test('empty rect draws nothing', () {
      var b = CellBuffer(2, 2);
      Painter(b).drawText(CellRect.fromTLWH(0, 0, 0, 0), 'x');
      expect(dump(b), ['  ', '  ']);
    });
  });
}

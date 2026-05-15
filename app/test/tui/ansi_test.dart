import 'package:flutterware_app/src/tui/ansi.dart';
import 'package:flutterware_app/src/tui/buffer.dart';
import 'package:flutterware_app/src/tui/cell.dart';
import 'package:test/test.dart';

void main() {
  group('ansi constants', () {
    test('alt-screen sequences', () {
      expect(Ansi.enterAltScreen, '\x1b[?1049h');
      expect(Ansi.exitAltScreen, '\x1b[?1049l');
    });

    test('cursor visibility', () {
      expect(Ansi.hideCursor, '\x1b[?25l');
      expect(Ansi.showCursor, '\x1b[?25h');
    });

    test('moveTo is 1-indexed', () {
      // ANSI cursor positioning is 1-indexed; our API takes 0-indexed.
      expect(Ansi.moveTo(0, 0), '\x1b[1;1H');
      expect(Ansi.moveTo(4, 9), '\x1b[5;10H');
    });

    test('clearScreen', () {
      expect(Ansi.clearScreen, '\x1b[2J');
    });

    test('resetStyle', () {
      expect(Ansi.resetStyle, '\x1b[0m');
    });
  });

  group('sgrForeground', () {
    test('default fg', () {
      expect(Ansi.sgrForeground(Color.defaultFg), '39');
    });

    test('named ansi fg (0-7)', () {
      expect(Ansi.sgrForeground(Color.red), '31');
      expect(Ansi.sgrForeground(Color.white), '37');
    });

    test('bright named ansi fg (8-15)', () {
      expect(Ansi.sgrForeground(Color.brightRed), '91');
      expect(Ansi.sgrForeground(Color.brightWhite), '97');
    });

    test('rgb fg', () {
      expect(Ansi.sgrForeground(Color.rgb(10, 20, 30)), '38;2;10;20;30');
    });
  });

  group('sgrBackground', () {
    test('default bg', () {
      expect(Ansi.sgrBackground(Color.defaultBg), '49');
    });

    test('named ansi bg', () {
      expect(Ansi.sgrBackground(Color.blue), '44');
      expect(Ansi.sgrBackground(Color.brightCyan), '106');
    });

    test('rgb bg', () {
      expect(Ansi.sgrBackground(Color.rgb(255, 0, 128)), '48;2;255;0;128');
    });
  });

  group('sgrStyle', () {
    test('no style', () {
      expect(Ansi.sgrStyle(0), <String>[]);
    });

    test('bold', () {
      expect(Ansi.sgrStyle(TextStyle.bold), ['1']);
    });

    test('combined', () {
      final s = Ansi.sgrStyle(
          TextStyle.bold | TextStyle.underline | TextStyle.reverse);
      expect(s, containsAll(['1', '4', '7']));
      expect(s.length, 3);
    });
  });

  group('encodeDiff', () {
    test('no changes produces empty string', () {
      final front = CellBuffer(2, 2);
      final back = CellBuffer(2, 2);
      expect(encodeDiff(front, back), '');
    });

    test('single cell change emits move + SGR + rune', () {
      final front = CellBuffer(2, 4);
      final back = CellBuffer(2, 4);
      back.set(1, 2, Cell(rune: 0x41 /* A */));
      final out = encodeDiff(front, back);
      // Expected: move to (1,2) in 0-indexed = CSI 2;3H, default colors,
      // then "A".
      expect(out, contains('\x1b[2;3H'));
      expect(out, contains('A'));
    });

    test('two adjacent changes in same row skip second move', () {
      final front = CellBuffer(1, 5);
      final back = CellBuffer(1, 5);
      back.set(0, 1, Cell(rune: 0x41));
      back.set(0, 2, Cell(rune: 0x42));
      final out = encodeDiff(front, back);
      // First move to (0,1) = CSI 1;2H. After writing 'A', the cursor is at
      // (0,2), so the next 'B' should follow without another CSI move.
      // We expect: one CSI for move + at most SGR transitions. With both
      // cells default colored from empty state, SGR may or may not appear.
      // The number of move sequences (matching CSI <num>;<num>H) must be 1.
      final moveRegex = RegExp(r'\x1b\[\d+;\d+H');
      expect(moveRegex.allMatches(out).length, 1);
      expect(out, contains('AB'));
    });

    test('change at start of new row emits a move', () {
      final front = CellBuffer(2, 3);
      final back = CellBuffer(2, 3);
      back.set(0, 0, Cell(rune: 0x41));
      back.set(1, 0, Cell(rune: 0x42));
      final out = encodeDiff(front, back);
      final moveRegex = RegExp(r'\x1b\[\d+;\d+H');
      expect(moveRegex.allMatches(out).length, 2);
    });

    test('fg change emits SGR', () {
      final front = CellBuffer(1, 2);
      final back = CellBuffer(1, 2);
      back.set(0, 0, Cell(rune: 0x41, fg: Color.red));
      final out = encodeDiff(front, back);
      expect(out, contains('31'));
      expect(out, contains('A'));
    });

    test('consecutive cells with same color do not re-emit SGR', () {
      final front = CellBuffer(1, 3);
      final back = CellBuffer(1, 3);
      back.set(0, 0, Cell(rune: 0x41, fg: Color.red));
      back.set(0, 1, Cell(rune: 0x42, fg: Color.red));
      back.set(0, 2, Cell(rune: 0x43, fg: Color.red));
      final out = encodeDiff(front, back);
      // The red SGR (parameter "31") should appear exactly once.
      final redCount = '31'.allMatches(out).length;
      expect(redCount, 1);
      expect(out, contains('ABC'));
    });

    test('color reset emits default fg', () {
      // front: red 'A'; back: default 'A' (rune unchanged but color is)
      final front = CellBuffer(1, 1);
      front.set(0, 0, Cell(rune: 0x41, fg: Color.red));
      final back = CellBuffer(1, 1);
      back.set(0, 0, Cell(rune: 0x41 /* default */));
      // The cell is "different" (fg differs), so we emit something.
      final out = encodeDiff(front, back);
      expect(out, contains('39')); // default fg
      expect(out, contains('A'));
    });

    test('size mismatch throws', () {
      final front = CellBuffer(2, 2);
      final back = CellBuffer(3, 3);
      expect(() => encodeDiff(front, back), throwsA(isA<ArgumentError>()));
    });

    test('originRow shifts all cursor moves down', () {
      final front = CellBuffer(1, 2);
      final back = CellBuffer(1, 2);
      back.set(0, 0, Cell(rune: 0x41));
      back.set(0, 1, Cell(rune: 0x42));
      final out = encodeDiff(front, back, originRow: 5);
      // The single cursor move for the first cell should target row 5+0=5
      // (1-indexed: 6), col 0 (1-indexed: 1).
      expect(out, contains('\x1b[6;1H'));
      expect(out, contains('AB'));
    });

    test('originCol shifts all cursor moves right', () {
      final front = CellBuffer(1, 1);
      final back = CellBuffer(1, 1);
      back.set(0, 0, Cell(rune: 0x41));
      final out = encodeDiff(front, back, originCol: 10);
      // Move target: row 0+0=0 (1-indexed: 1), col 0+10=10 (1-indexed: 11).
      expect(out, contains('\x1b[1;11H'));
    });

    test('default origin (0, 0) preserves existing behavior', () {
      // Regression guard: omitting the new params must produce identical output
      // to the pre-extension version.
      final front = CellBuffer(1, 1);
      final back = CellBuffer(1, 1);
      back.set(0, 0, Cell(rune: 0x41));
      final withDefault = encodeDiff(front, back);
      final withExplicit = encodeDiff(front, back, originRow: 0, originCol: 0);
      expect(withDefault, withExplicit);
      expect(withDefault, contains('\x1b[1;1H'));
    });

    test('style-to-zero with unchanged color re-emits fg/bg after reset', () {
      // Two cells: first is bold red 'A'; second is plain red 'B'.
      // When the encoder prints 'A', lastStyle becomes TextStyle.bold.
      // When it then prints 'B' (style 0, same red fg), it must emit a reset
      // (0) followed by red fg again — otherwise the reset would clear the
      // color to terminal default.
      final front = CellBuffer(1, 2);
      final back = CellBuffer(1, 2);
      back.set(0, 0, Cell(rune: 0x41, fg: Color.red, style: TextStyle.bold));
      back.set(0, 1, Cell(rune: 0x42, fg: Color.red /* style: 0 */));
      final out = encodeDiff(front, back);
      // Must include a reset ('0') and re-apply red ('31') for the second cell.
      // Match a `0` SGR param surrounded by either CSI `[` or `;` on the left
      // and either `m` or `;` on the right — i.e. a real reset, not part of '31'.
      expect(out, matches(RegExp(r'(\x1b\[|;)0(;|m)')));
      expect(out, contains('31'));
      expect(out, contains('A'));
      expect(out, contains('B'));
    });

    test('non-zero style transitions to a different non-zero style', () {
      // Two cells: first is bold 'A'; second is italic 'B'. After printing 'A',
      // lastStyle becomes TextStyle.bold. For 'B' the style differs, so the
      // encoder must reset (emit '0') then apply italic ('3').
      final front = CellBuffer(1, 2);
      final back = CellBuffer(1, 2);
      back.set(0, 0, Cell(rune: 0x41, style: TextStyle.bold));
      back.set(0, 1, Cell(rune: 0x42, style: TextStyle.italic));
      final out = encodeDiff(front, back);
      // Reset is emitted before 'B'; italic param '3' appears; both runes present.
      // Match a `0` SGR param surrounded by either CSI `[` or `;` on the left
      // and either `m` or `;` on the right — i.e. a real reset, not part of '31'.
      expect(out, matches(RegExp(r'(\x1b\[|;)0(;|m)')));
      // Italic SGR param '3' similarly bounded.
      expect(out, matches(RegExp(r'(\x1b\[|;)3(;|m)')));
      expect(out, contains('A'));
      expect(out, contains('B'));
    });
  });

  group('encodeRow', () {
    test('empty row produces empty string', () {
      final buffer = CellBuffer(1, 5);
      expect(encodeRow(buffer), '');
    });

    test('plain row emits runes with no leading cursor move', () {
      final buffer = CellBuffer(1, 5);
      buffer.writeAt(0, 0, 'Hi');
      final out = encodeRow(buffer);
      expect(out, contains('Hi'));
      expect(out, isNot(matches(RegExp(r'\x1b\[\d+;\d+H'))));
    });

    test('trailing blank cells are dropped', () {
      final buffer = CellBuffer(1, 10);
      buffer.writeAt(0, 0, 'ab');
      // Row is "ab" followed by 8 blank cells; output must not pad them.
      final out = encodeRow(buffer);
      expect(out.endsWith('b'), isTrue);
    });

    test('rowIndex selects the row', () {
      final buffer = CellBuffer(3, 5);
      buffer.writeAt(2, 0, 'Xy');
      expect(encodeRow(buffer, rowIndex: 2), contains('Xy'));
      expect(encodeRow(buffer, rowIndex: 0), '');
    });

    test('foreground color emits SGR once per run', () {
      final buffer = CellBuffer(1, 3);
      buffer.writeAt(0, 0, 'RR', fg: Color.red);
      final out = encodeRow(buffer);
      expect('31'.allMatches(out).length, 1);
      expect(out, contains('RR'));
    });

    test('style transition resets and re-applies color', () {
      final buffer = CellBuffer(1, 2);
      buffer.set(0, 0, Cell(rune: 0x41, fg: Color.red, style: TextStyle.bold));
      buffer.set(0, 1, Cell(rune: 0x42, fg: Color.red));
      final out = encodeRow(buffer);
      expect(out, matches(RegExp(r'(\x1b\[|;)0(;|m)')));
      expect(out, contains('31'));
      expect(out, contains('A'));
      expect(out, contains('B'));
    });
  });
}

import 'package:flutterware_app/src/tui/ansi.dart';
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
      final s = Ansi.sgrStyle(TextStyle.bold | TextStyle.underline | TextStyle.reverse);
      expect(s, containsAll(['1', '4', '7']));
      expect(s.length, 3);
    });
  });
}

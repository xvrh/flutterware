import 'package:flutterware_app/src/tui/cell.dart';
import 'package:test/test.dart';

void main() {
  group('Color', () {
    test('named ANSI colors have stable indices', () {
      expect(Color.red.ansiIndex, 1);
      expect(Color.brightWhite.ansiIndex, 15);
    });

    test('rgb colors carry rgb values', () {
      final c = Color.rgb(10, 20, 30);
      expect(c.r, 10);
      expect(c.g, 20);
      expect(c.b, 30);
    });

    test('default colors are distinct from named black', () {
      expect(Color.defaultFg, isNot(equals(Color.black)));
      expect(Color.defaultBg, isNot(equals(Color.black)));
    });

    test('value equality', () {
      expect(Color.rgb(1, 2, 3), equals(Color.rgb(1, 2, 3)));
      expect(Color.red, equals(Color.red));
      expect(Color.red, isNot(equals(Color.blue)));
    });
  });

  group('Cell', () {
    test('empty cell is a space with default colors', () {
      expect(Cell.empty.rune, 0x20);
      expect(Cell.empty.fg, Color.defaultFg);
      expect(Cell.empty.bg, Color.defaultBg);
      expect(Cell.empty.style, 0);
      expect(Cell.empty.width, 1);
    });

    test('value equality', () {
      final a = Cell(
          rune: 0x41,
          fg: Color.red,
          bg: Color.defaultBg,
          style: TextStyle.bold);
      final b = Cell(
          rune: 0x41,
          fg: Color.red,
          bg: Color.defaultBg,
          style: TextStyle.bold);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('TextStyle bitfield combines', () {
      final combined = TextStyle.bold | TextStyle.underline;
      expect(combined & TextStyle.bold, isNot(0));
      expect(combined & TextStyle.underline, isNot(0));
      expect(combined & TextStyle.italic, 0);
    });
  });

  group('kind predicates', () {
    test('kind predicates', () {
      expect(Color.defaultFg.isDefault, isTrue);
      expect(Color.defaultBg.isDefault, isTrue);
      expect(Color.red.isAnsi, isTrue);
      expect(Color.rgb(1, 2, 3).isRgb, isTrue);

      expect(Color.defaultFg.isDefaultFg, isTrue);
      expect(Color.defaultFg.isDefaultBg, isFalse);
      expect(Color.defaultBg.isDefaultBg, isTrue);
      expect(Color.defaultBg.isDefaultFg, isFalse);

      // Cross checks: non-default isn't default
      expect(Color.red.isDefault, isFalse);
      expect(Color.rgb(0, 0, 0).isAnsi, isFalse);
    });
  });
}

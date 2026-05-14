import 'package:flutterware_app/src/tui/input.dart';
import 'package:test/test.dart';

void main() {
  group('KeyEvent types', () {
    test('CharKey holds rune and modifiers', () {
      const k = CharKey(rune: 0x41, modifiers: {});
      expect(k.rune, 0x41);
      expect(k.modifiers, isEmpty);
    });

    test('CharKey value equality', () {
      const a = CharKey(rune: 0x61, modifiers: {Modifier.ctrl});
      const b = CharKey(rune: 0x61, modifiers: {Modifier.ctrl});
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('SpecialKey for arrows', () {
      const k = SpecialKey(code: SpecialKeyCode.up, modifiers: {});
      expect(k.code, SpecialKeyCode.up);
    });

    test('SpecialKey value equality with modifier set', () {
      const a = SpecialKey(code: SpecialKeyCode.left, modifiers: {Modifier.shift});
      const b = SpecialKey(code: SpecialKeyCode.left, modifiers: {Modifier.shift});
      expect(a, equals(b));
    });

    test('different special keys are unequal', () {
      const a = SpecialKey(code: SpecialKeyCode.up, modifiers: {});
      const b = SpecialKey(code: SpecialKeyCode.down, modifiers: {});
      expect(a, isNot(equals(b)));
    });
  });
}

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
      const a =
          SpecialKey(code: SpecialKeyCode.left, modifiers: {Modifier.shift});
      const b =
          SpecialKey(code: SpecialKeyCode.left, modifiers: {Modifier.shift});
      expect(a, equals(b));
    });

    test('different special keys are unequal', () {
      const a = SpecialKey(code: SpecialKeyCode.up, modifiers: {});
      const b = SpecialKey(code: SpecialKeyCode.down, modifiers: {});
      expect(a, isNot(equals(b)));
    });
  });

  group('parseKeyEvents', () {
    Future<List<KeyEvent>> parse(List<List<int>> chunks) async {
      final stream = Stream<List<int>>.fromIterable(chunks);
      return parseKeyEvents(stream).toList();
    }

    test('ASCII printable becomes CharKey', () async {
      final events = await parse([
        [0x41, 0x42]
      ]); // 'A', 'B'
      expect(events, [
        const CharKey(rune: 0x41, modifiers: {}),
        const CharKey(rune: 0x42, modifiers: {}),
      ]);
    });

    test('ctrl-A through ctrl-Z become CharKey with ctrl modifier', () async {
      final events = await parse([
        [0x01, 0x03, 0x1a]
      ]); // ctrl-A, ctrl-C, ctrl-Z
      expect(events.length, 3);
      expect(events[0], CharKey(rune: 0x61, modifiers: {Modifier.ctrl})); // 'a'
      expect(events[1], CharKey(rune: 0x63, modifiers: {Modifier.ctrl})); // 'c'
      expect(events[2], CharKey(rune: 0x7a, modifiers: {Modifier.ctrl})); // 'z'
    });

    test('enter, tab, backspace', () async {
      final events = await parse([
        [0x0d, 0x09, 0x7f]
      ]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.enter, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.tab, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.backspace, modifiers: {}),
      ]);
    });

    test('newline (LF) is also enter', () async {
      final events = await parse([
        [0x0a]
      ]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.enter, modifiers: {}),
      ]);
    });

    test('CSI arrows', () async {
      // ESC [ A/B/C/D
      final events = await parse([
        [0x1b, 0x5b, 0x41],
        [0x1b, 0x5b, 0x42],
        [0x1b, 0x5b, 0x43],
        [0x1b, 0x5b, 0x44],
      ]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.up, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.down, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.right, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.left, modifiers: {}),
      ]);
    });

    test('SS3 arrows (ESC O A)', () async {
      final events = await parse([
        [0x1b, 0x4f, 0x41]
      ]); // ESC O A
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.up, modifiers: {}),
      ]);
    });

    test('CSI with modifier (ctrl-up = ESC [1;5A)', () async {
      final events = await parse([
        [0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x41]
      ]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.up, modifiers: {Modifier.ctrl}),
      ]);
    });

    test('CSI shift-arrow (ESC [1;2A)', () async {
      final events = await parse([
        [0x1b, 0x5b, 0x31, 0x3b, 0x32, 0x41]
      ]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.up, modifiers: {Modifier.shift}),
      ]);
    });

    test('CSI Home/End/PgUp/PgDn (ESC [H, [F, [5~, [6~)', () async {
      final events = await parse([
        [0x1b, 0x5b, 0x48], // home
        [0x1b, 0x5b, 0x46], // end
        [0x1b, 0x5b, 0x35, 0x7e], // pgUp
        [0x1b, 0x5b, 0x36, 0x7e], // pgDn
      ]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.home, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.end, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.pageUp, modifiers: {}),
        const SpecialKey(code: SpecialKeyCode.pageDown, modifiers: {}),
      ]);
    });

    test('bare escape (no follow-up bytes) emits escape', () async {
      // A single chunk containing ONLY ESC, followed by stream end.
      final events = await parse([
        [0x1b]
      ]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.escape, modifiers: {}),
      ]);
    });

    test('UTF-8 multi-byte rune', () async {
      // U+00E9 (é) in UTF-8 = C3 A9
      final events = await parse([
        [0xc3, 0xa9]
      ]);
      expect(events, [
        const CharKey(rune: 0x00e9, modifiers: {}),
      ]);
    });

    test('UTF-8 split across chunks', () async {
      final events = await parse([
        [0xc3],
        [0xa9]
      ]);
      expect(events, [
        const CharKey(rune: 0x00e9, modifiers: {}),
      ]);
    });

    test('CSI split across chunks', () async {
      final events = await parse([
        [0x1b],
        [0x5b],
        [0x41]
      ]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.up, modifiers: {}),
      ]);
    });

    test('incomplete SS3 at stream close drains both ESC and O', () async {
      // Only ESC and O delivered; stream then closes. Implementation must drain
      // both bytes and emit escape — NOT escape + CharKey('O').
      final events = await parse([
        [0x1b, 0x4f]
      ]);
      expect(events, [
        const SpecialKey(code: SpecialKeyCode.escape, modifiers: {}),
      ]);
    });

    test('incomplete UTF-8 at stream close yields replacement character',
        () async {
      // A 2-byte UTF-8 leading byte arrives but the second byte never does.
      // Stream closes. Implementation must emit U+FFFD.
      final events = await parse([
        [0xc3]
      ]);
      expect(events, [
        const CharKey(rune: 0xFFFD, modifiers: {}),
      ]);
    });
  });
}

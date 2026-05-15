import 'package:flutterware_app/src/tui/text_wrap.dart';
import 'package:test/test.dart';

void main() {
  group('wrapText', () {
    test('short text fits on one line', () {
      expect(wrapText('hello', 20), ['hello']);
    });

    test('wraps on spaces at the width boundary', () {
      expect(wrapText('one two three', 7), ['one two', 'three']);
    });

    test('preserves explicit newlines', () {
      expect(wrapText('a\nb', 20), ['a', 'b']);
    });

    test('preserves blank lines from consecutive newlines', () {
      expect(wrapText('a\n\nb', 20), ['a', '', 'b']);
    });

    test('hard-breaks a word longer than width', () {
      expect(wrapText('abcdefg', 3), ['abc', 'def', 'g']);
    });

    test('hard-break flushes the pending line first', () {
      expect(wrapText('hi abcdefg', 3), ['hi', 'abc', 'def', 'g']);
    });

    test('width <= 0 splits only on newlines', () {
      expect(wrapText('one two\nthree', 0), ['one two', 'three']);
    });

    test('empty string yields one empty line', () {
      expect(wrapText('', 10), ['']);
    });
  });
}

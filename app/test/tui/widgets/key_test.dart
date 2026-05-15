import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

void main() {
  group('ValueKey', () {
    test('equal when value and type match', () {
      expect(ValueKey('a'), ValueKey('a'));
      expect(ValueKey('a').hashCode, ValueKey('a').hashCode);
    });
    test('unequal across values', () {
      expect(ValueKey('a') == ValueKey('b'), isFalse);
    });
    test('unequal across value types', () {
      expect(ValueKey<Object>(1) == ValueKey<Object>('1'), isFalse);
    });
  });

  group('ObjectKey', () {
    test('equal only for identical objects', () {
      var o = Object();
      expect(ObjectKey(o), ObjectKey(o));
      expect(ObjectKey(Object()) == ObjectKey(Object()), isFalse);
    });
  });

  group('UniqueKey', () {
    test('never equal to another UniqueKey', () {
      expect(UniqueKey() == UniqueKey(), isFalse);
      var k = UniqueKey();
      expect(k, k);
    });
  });

  test('Key factory builds a ValueKey<String>', () {
    expect(Key('x'), ValueKey<String>('x'));
  });
}

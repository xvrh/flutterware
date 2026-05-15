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

  group('Widget.canUpdate', () {
    test('true for same type and key', () {
      expect(Widget.canUpdate(_W(key: Key('a')), _W(key: Key('a'))), isTrue);
    });
    test('false for different key', () {
      expect(Widget.canUpdate(_W(key: Key('a')), _W(key: Key('b'))), isFalse);
    });
    test('false for different runtimeType', () {
      expect(Widget.canUpdate(_W(), _W2()), isFalse);
    });
    test('true for same type, both keyless', () {
      expect(Widget.canUpdate(_W(), _W()), isTrue);
    });
  });
}

class _W extends StatelessWidget {
  const _W({super.key});
  @override
  Widget build(BuildContext context) => this;
}

class _W2 extends StatelessWidget {
  const _W2();
  @override
  Widget build(BuildContext context) => this;
}

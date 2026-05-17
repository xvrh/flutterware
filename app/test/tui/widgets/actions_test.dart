import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/tui/tui.dart';

import 'harness.dart';

class _IntentA extends Intent {
  const _IntentA();
}

class _IntentB extends Intent {
  const _IntentB();
}

/// An action that records that it was found, tagged so tests can tell
/// instances apart.
class _TaggedAction extends Action<Intent> {
  _TaggedAction(this.tag);
  final String tag;
  @override
  Object? invoke(Intent intent) => tag;
}

void main() {
  test('maybeFind returns the action registered for the intent type', () {
    Action<Intent>? found;
    pump(Actions(
      actions: {_IntentA: _TaggedAction('a')},
      child: Builder(builder: (context) {
        found = Actions.maybeFind(context, const _IntentA());
        return SizedBox();
      }),
    ));
    expect(found, isA<_TaggedAction>());
    expect((found! as _TaggedAction).tag, 'a');
  });

  test('maybeFind is null for an unregistered intent type', () {
    Action<Intent>? found;
    var sentinel = _TaggedAction('present');
    pump(Actions(
      actions: {_IntentA: sentinel},
      child: Builder(builder: (context) {
        found = Actions.maybeFind(context, const _IntentB());
        return SizedBox();
      }),
    ));
    expect(found, isNull);
  });

  test('maybeFind is null when there is no enclosing Actions', () {
    Action<Intent>? found;
    pump(Builder(builder: (context) {
      found = Actions.maybeFind(context, const _IntentA());
      return SizedBox();
    }));
    expect(found, isNull);
  });

  test('lookup falls through to an enclosing Actions', () {
    Action<Intent>? found;
    pump(Actions(
      actions: {_IntentA: _TaggedAction('outer-a')},
      child: Actions(
        actions: {_IntentB: _TaggedAction('inner-b')},
        child: Builder(builder: (context) {
          found = Actions.maybeFind(context, const _IntentA());
          return SizedBox();
        }),
      ),
    ));
    expect((found! as _TaggedAction).tag, 'outer-a');
  });

  test('an inner Actions shadows an outer one for the same intent type', () {
    Action<Intent>? found;
    pump(Actions(
      actions: {_IntentA: _TaggedAction('outer')},
      child: Actions(
        actions: {_IntentA: _TaggedAction('inner')},
        child: Builder(builder: (context) {
          found = Actions.maybeFind(context, const _IntentA());
          return SizedBox();
        }),
      ),
    ));
    expect((found! as _TaggedAction).tag, 'inner');
  });
}

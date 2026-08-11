import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/drive/guest_drive.dart';
import 'package:flutterware/src/scenarios/target.dart';

/// The wire spelling of a target, as `ext.flutterware.act` receives it.
void main() {
  test('bare text, quoted or not', () {
    expect(wireTarget('"Pay"'), 'Pay');
    // Never valid JSON, still a target: an agent typing `target=Pay` should
    // not need quoting rules to tap a button.
    expect(wireTarget('Pay'), 'Pay');
    expect(wireTarget('{"text": "Pay"}'), 'Pay');
  });

  test('keys and the Target grammar', () {
    expect(wireTarget('{"key": "shop.next"}'), const ValueKey('shop.next'));
    expect(
      '${wireTarget('{"label": "Add to cart"}')}',
      '${Target.label('Add to cart')}',
    );
    expect(
      '${wireTarget('{"tooltip": "Delete"}')}',
      '${Target.tooltip('Delete')}',
    );
    expect(
      '${wireTarget('{"containing": "Pay"}')}',
      '${Target.containing('Pay')}',
    );
  });

  test('within and nth compose, recursively', () {
    var within = wireTarget(
      '{"within": {"scope": {"key": "card"}, "child": "Buy"}}',
    );
    expect('$within', '${Target.within(ValueKey('card'), 'Buy')}');

    var nth = wireTarget(
      '{"nth": {"target": {"containing": "Buy"}, "index": 1}}',
    );
    expect('$nth', '${Target.nth(Target.containing('Buy'), 1)}');
  });

  test('anything else is refused with the grammar in the message', () {
    expect(
      () => wireTarget('{"node": "0/1/2"}'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('{"within": {"scope", "child"}}'),
        ),
      ),
    );
  });
}

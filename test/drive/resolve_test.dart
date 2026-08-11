import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/drive/resolve.dart';

/// The shared actionability ladder in its live flavor — no `s.` prefix, no
/// `s.tester` escape hatch, and a [TargetFailure] kind on every refusal so a
/// live driver can decide what is transient. The scenario flavor of the same
/// ladder is covered by test/scenarios/actionability_test.dart.
void main() {
  testWidgets('a covered target is refused with the covered kind', (
    tester,
  ) async {
    await tester.pumpWidget(_covered());
    var resolver = TargetResolver(tester);

    var error = await _refusal(() => resolver.resolve('Buy', 'tap'));

    expect(error.failure, TargetFailure.covered);
    expect('$error', contains('`tap` at its center'));
    expect('$error', isNot(contains('s.')));
    expect('$error', isNot(contains('tester')));
  });

  testWidgets('nothing matching is refused with the notFound kind and the '
      'screen description when one is wired', (tester) async {
    await tester.pumpWidget(_covered());
    var resolver = TargetResolver(
      tester,
      describeScreen: () => visibleTextsOf(tester).join(', '),
    );

    var error = await _refusal(() => resolver.resolve('Pay', 'tap'));

    expect(error.failure, TargetFailure.notFound);
    expect('$error', contains('nothing matches "Pay"'));
    expect('$error', contains('`scrollTo` walks to it'));
    expect('$error', contains('Visible text: Buy'));
  });

  testWidgets('several matches are refused with the multiple kind', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(children: [for (var i = 0; i < 2; i++) const Text('Buy')]),
      ),
    );
    var resolver = TargetResolver(tester);

    var error = await _refusal(() => resolver.resolve('Buy', 'tap'));

    expect(error.failure, TargetFailure.multiple);
    expect('$error', contains('2 widgets match "Buy"'));
  });

  testWidgets('below the fold resolves after the ladder scrolls to it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 2000),
                TextButton(onPressed: () {}, child: const Text('Buy')),
              ],
            ),
          ),
        ),
      ),
    );
    var resolver = TargetResolver(tester);

    var finder = await resolver.resolve('Buy', 'tap');

    await tester.tap(finder, warnIfMissed: true);
  });
}

Widget _covered() => MaterialApp(
  home: Stack(
    children: [
      Center(
        child: TextButton(onPressed: () {}, child: const Text('Buy')),
      ),
      Positioned.fill(
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}),
      ),
    ],
  ),
);

Future<TargetError> _refusal(Future<Object?> Function() act) async {
  try {
    await act();
  } on TargetError catch (error) {
    return error;
  }
  fail('expected a TargetError');
}

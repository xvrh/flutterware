import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/drive/human_actions.dart';

/// The guest-side recorder: real pointer events in, named `actor: human`
/// records out. Injected agent gestures arrive on the same global route, so
/// the suppression flag is load-bearing — without it every drive tap would
/// journal twice.
void main() {
  testWidgets('a tap is recorded with the nearest nameable widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TextButton(onPressed: () {}, child: const Text('Pay')),
        ),
      ),
    );
    var actions = HumanActions()..install();

    await tester.tap(find.text('Pay'));

    var taken = actions.take();
    expect(taken, hasLength(1));
    expect(taken.single['verb'], 'tap');
    expect(taken.single['target'], '"Pay"');
    expect(actions.take(), isEmpty, reason: 'a take clears the buffer');
  });

  testWidgets('a keyed but textless control is named by its key', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: IconButton(
            key: const ValueKey('cart'),
            onPressed: () {},
            icon: const Icon(Icons.shopping_cart),
          ),
        ),
      ),
    );
    var actions = HumanActions()..install();

    await tester.tap(find.byKey(const ValueKey('cart')));

    expect(actions.take().single['target'], "key 'cart'");
  });

  testWidgets('a drag is not a tap, and records nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(children: [for (var i = 0; i < 50; i++) Text('Row $i')]),
      ),
    );
    var actions = HumanActions()..install();

    await tester.drag(find.text('Row 3'), const Offset(0, -200));

    expect(actions.take(), isEmpty);
  });

  testWidgets('suppressed events — an agent verb in flight — are dropped', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TextButton(onPressed: () {}, child: const Text('Pay')),
        ),
      ),
    );
    var actions = HumanActions()..install();

    actions.suppress = true;
    await tester.tap(find.text('Pay'));
    actions.suppress = false;

    expect(actions.take(), isEmpty);
  });

  testWidgets('past the cap, the drop is visible rather than silent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TextButton(onPressed: () {}, child: const Text('Pay')),
        ),
      ),
    );
    var actions = HumanActions(cap: 2)..install();

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Pay'));
    }

    var taken = actions.take();
    expect(taken, hasLength(3));
    expect(taken.last['verb'], 'dropped');
    expect(taken.last['target'], contains('2 more'));
    expect(actions.take(), isEmpty, reason: 'the drop count resets too');
  });

  testWidgets('nothing nameable falls back to the position', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ColoredBox(color: Colors.white)),
    );
    var actions = HumanActions()..install();

    await tester.tapAt(const Offset(11, 22));

    expect(actions.take().single['target'], 'at (11, 22)');
  });

  testWidgets('a held press is a longPress', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TextButton(onPressed: () {}, child: const Text('Pay')),
        ),
      ),
    );
    var actions = HumanActions()..install();

    // Explicit timestamps: the recorder reads the engine's event clock, and
    // test-injected events default to zero.
    var gesture = await tester.startGesture(tester.getCenter(find.text('Pay')));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.up(
      timeStamp: kLongPressTimeout + const Duration(milliseconds: 100),
    );

    expect(actions.take().single['verb'], 'longPress');
  });
}

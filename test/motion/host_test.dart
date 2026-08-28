import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/motion.dart';

Duration ms(int value) => Duration(milliseconds: value);

final _values = MotionValues(
  targets: {
    'first': {
      'opacity': [Seg<double>(start: ms(0), end: ms(400), from: 0, to: 1)],
    },
  },
);

const _stage = MotionStage(
  width: 200,
  height: 200,
  elements: [
    StageElement(target: 'first', x: 10, y: 10, width: 100, height: 40),
    // On the stage and nowhere else. Whether the guest reports it is exactly
    // the question "does the draft create targets", and the answer has to
    // change with the host.
    StageElement(target: 'draft_only', x: 10, y: 70, width: 100, height: 40),
  ],
);

MotionScopeState _stateOf(WidgetTester tester) =>
    tester.state<MotionScopeState>(find.byType(MotionScope).first);

Widget _both() => MaterialApp(
  home: MotionScope(
    motion: _values,
    stage: _stage,
    controller: MotionController(autoplay: false),
    builder: (m) => MotionBox(
      m.target('first'),
      child: const Text('real', textDirection: TextDirection.ltr),
    ),
  ),
);

Set<String> _targetNames() {
  var scopes = MotionRegistry.instance.describe()['scopes']! as List<Object?>;
  var scope = scopes.single! as Map<String, Object?>;
  return {
    for (var target in scope['targets']! as List<Object?>)
      '${(target as Map<String, Object?>)['name']}',
  };
}

void main() {
  group('the host', () {
    testWidgets('is real when there is a real body', (tester) async {
      await tester.pumpWidget(_both());

      expect(_stateOf(tester).host, MotionHost.real);
      expect(_stateOf(tester).hosts, [MotionHost.real, MotionHost.draft]);
      expect(find.text('real'), findsOneWidget);
    });

    testWidgets('is draft when the stage is the only body', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MotionScope(
            motion: _values,
            stage: _stage,
            controller: MotionController(autoplay: false),
          ),
        ),
      );

      expect(_stateOf(tester).host, MotionHost.draft);
      expect(_stateOf(tester).hosts, [MotionHost.draft]);
      // The placeholder wears its name, which is the whole draft affordance.
      expect(find.text('draft_only'), findsOneWidget);
    });

    testWidgets('swaps the body and keeps the playhead', (tester) async {
      await tester.pumpWidget(_both());
      var state = _stateOf(tester);
      state.controller.progress = 0.5;
      await tester.pump();

      state.host = MotionHost.draft;
      await tester.pump();

      expect(find.text('real'), findsNothing);
      expect(find.text('draft_only'), findsOneWidget);
      // One scope, so one playhead — the flip is a choice of body, not a
      // teardown.
      expect(state.controller.progress, 0.5);
    });

    testWidgets('changes which targets the guest reports', (tester) async {
      await tester.pumpWidget(_both());
      var state = _stateOf(tester);

      expect(_targetNames(), {'first'});

      state.host = MotionHost.draft;
      await tester.pump();

      expect(_targetNames(), {'first', 'draft_only'});
    });

    testWidgets('ignores a host it does not have', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MotionScope(
            motion: _values,
            controller: MotionController(autoplay: false),
            builder: (m) =>
                const Text('real', textDirection: TextDirection.ltr),
          ),
        ),
      );

      _stateOf(tester).host = MotionHost.draft;
      await tester.pump();

      expect(_stateOf(tester).host, MotionHost.real);
      expect(find.text('real'), findsOneWidget);
    });
  });
}

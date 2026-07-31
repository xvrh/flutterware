import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/motion.dart';

Duration ms(int value) => Duration(milliseconds: value);

final _values = MotionValues(
  targets: {
    'title': {
      'opacity': [Seg<double>(start: ms(0), end: ms(400), from: 0, to: 1)],
      'translateY': [Seg<double>(start: ms(0), end: ms(400), from: 40, to: 0)],
    },
  },
);

MotionScopeState _stateOf(WidgetTester tester) =>
    tester.state<MotionScopeState>(find.byType(MotionScope).first);

Widget _scope({
  MotionController? controller,
  MotionValues? values,
  Widget Function(MotionTarget title)? child,
}) => MotionScope(
  motion: values ?? _values,
  controller: controller,
  builder: (m) {
    var title = m.target('title');
    return (child ?? (a) => MotionBox(a, child: const SizedBox(width: 10)))(
      title,
    );
  },
);

void main() {
  group('the scope', () {
    testWidgets('autoplays with no controller and no code', (tester) async {
      await tester.pumpWidget(_scope());
      expect(_stateOf(tester).controller.progress, 0);

      await tester.pump(ms(200));
      expect(_stateOf(tester).controller.progress, closeTo(0.5, 0.01));

      await tester.pump(ms(200));
      expect(_stateOf(tester).controller.progress, 1);
    });

    testWidgets('takes its duration from the last segment', (tester) async {
      await tester.pumpWidget(_scope());
      expect(_stateOf(tester).controller.position, Duration.zero);
      await tester.pump(ms(400));
      expect(_stateOf(tester).controller.position, ms(400));
    });

    testWidgets('records what the last build read at a call site', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scope(child: (title) => SizedBox(width: 10, height: title.opacity)),
      );
      var state = _stateOf(tester);
      expect(state.reads, {'title.opacity'});
      expect(state.targetsNamed, {'title'});
    });

    testWidgets("MotionBox's sweep is offered, not read", (tester) async {
      // Eight properties swept by one widget are not eight wired properties.
      // A panel showing a lane per read would otherwise be all noise.
      await tester.pumpWidget(_scope());
      var state = _stateOf(tester);
      expect(state.reads, isEmpty);
      expect(
        state.offered,
        containsAll(['title.opacity', 'title.translateY', 'title.blur']),
      );
    });

    testWidgets('an explicit read beside a MotionBox still counts as read', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scope(
          child: (title) => Opacity(
            opacity: title.opacity,
            child: MotionBox(title, child: const SizedBox(width: 10)),
          ),
        ),
      );
      var state = _stateOf(tester);
      expect(state.reads, {'title.opacity'});
      expect(state.offered, contains('title.translateY'));
    });

    testWidgets('an unread target is still reported as named', (tester) async {
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          builder: (m) {
            m.target('ghost');
            return const SizedBox();
          },
        ),
      );
      var state = _stateOf(tester);
      expect(state.targetsNamed, {'ghost'});
      expect(state.reads, isEmpty);
    });

    testWidgets('two scopes keep separate playheads', (tester) async {
      var slow = MotionController(autoplay: false);
      await tester.pumpWidget(
        Row(
          textDirection: TextDirection.ltr,
          children: [
            _scope(),
            _scope(controller: slow),
          ],
        ),
      );
      await tester.pump(ms(400));

      var states = tester.stateList<MotionScopeState>(find.byType(MotionScope));
      expect(states.first.controller.progress, 1);
      expect(states.last.controller.progress, 0);
      slow.dispose();
    });

    testWidgets('swapping the values keeps the playhead', (tester) async {
      await tester.pumpWidget(_scope());
      await tester.pump(ms(200));
      var before = _stateOf(tester).controller.progress;

      await tester.pumpWidget(
        _scope(
          values: MotionValues(
            targets: {
              'title': {
                'opacity': [
                  Seg<double>(start: ms(0), end: ms(400), from: 1, to: 0),
                ],
              },
            },
          ),
        ),
      );
      // A hot reload of the values file must not snap you back to zero.
      expect(_stateOf(tester).controller.progress, before);
      await tester.pump(ms(200));
    });
  });

  group('the controller', () {
    testWidgets('buffers transport called before the scope mounts', (
      tester,
    ) async {
      // The trap this removes: `myMotion.play()` in initState runs before the
      // scope below it exists.
      var controller = MotionController(autoplay: false)..play();
      expect(controller.isAttached, isFalse);

      await tester.pumpWidget(_scope(controller: controller));
      await tester.pump(ms(400));
      expect(controller.progress, 1);
      controller.dispose();
    });

    testWidgets('seeks while detached, and the scope adopts the position', (
      tester,
    ) async {
      var controller = MotionController(autoplay: false)..progress = 0.25;
      await tester.pumpWidget(_scope(controller: controller));
      expect(controller.progress, 0.25);
      expect(_stateOf(tester).controller.position, ms(100));
      controller.dispose();
    });

    testWidgets('reverse runs back to zero', (tester) async {
      var controller = MotionController();
      await tester.pumpWidget(_scope(controller: controller));
      await tester.pump(ms(400));
      expect(controller.progress, 1);

      controller.reverse();
      await tester.pump();
      await tester.pump(ms(400));
      expect(controller.progress, 0);
      controller.dispose();
    });

    testWidgets("a driven controller follows somebody else's animation", (
      tester,
    ) async {
      var source = AnimationController(vsync: const TestVSync(), value: 0.3);
      var controller = MotionController.driven(source);
      await tester.pumpWidget(_scope(controller: controller));
      expect(controller.progress, closeTo(0.3, 1e-9));

      source.value = 0.8;
      await tester.pump();
      expect(controller.progress, closeTo(0.8, 1e-9));

      controller.dispose();
      source.dispose();
    });

    testWidgets('the scope disposes only the controller it made', (
      tester,
    ) async {
      var mine = MotionController(autoplay: false);
      await tester.pumpWidget(_scope(controller: mine));
      await tester.pumpWidget(const SizedBox());
      // Still usable: if the scope had disposed it, this would throw.
      expect(() => mine.progress = 0.5, returnsNormally);
      mine.dispose();
    });
  });

  group('MotionBox', () {
    testWidgets('adds no layers when everything is at rest', (tester) async {
      await tester.pumpWidget(
        MotionScope(
          motion: MotionValues.empty,
          builder: (m) =>
              MotionBox(m.target('title'), child: const SizedBox(width: 10)),
        ),
      );
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(Transform), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('adds opacity and transform while they are not at rest', (
      tester,
    ) async {
      await tester.pumpWidget(_scope());
      await tester.pump(ms(200));
      expect(find.byType(Opacity), findsOneWidget);
      expect(find.byType(Transform), findsOneWidget);
      // Nothing tuned blur, so no filter — the expensive layer stays off.
      expect(find.byType(ImageFiltered), findsNothing);
      await tester.pump(ms(200));
    });

    testWidgets('only blur brings in the image filter', (tester) async {
      await tester.pumpWidget(
        MotionScope(
          motion: MotionValues(
            targets: {
              'title': {
                'blur': [
                  Seg<double>(start: ms(0), end: ms(100), from: 8, to: 0),
                ],
              },
            },
          ),
          controller: MotionController(autoplay: false),
          builder: (m) =>
              MotionBox(m.target('title'), child: const SizedBox(width: 10)),
        ),
      );
      expect(find.byType(ImageFiltered), findsOneWidget);
    });
  });
}

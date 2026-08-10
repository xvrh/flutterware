import 'package:flutter/widgets.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/motion.dart';

Duration ms(int value) => Duration(milliseconds: value);

final _values = MotionValues(
  targets: {
    'title': {
      'opacity': [Seg<double>(start: ms(0), end: ms(400), from: 0, to: 1)],
      'color': [
        Seg<Color>(
          start: ms(0),
          end: ms(400),
          from: Color(0xFF000000),
          to: Color(0xFFFFFFFF),
        ),
      ],
    },
  },
);

Widget _scope({MotionController? controller}) => MotionScope(
  motion: _values,
  controller: controller ?? MotionController(autoplay: false),
  builder: (m) =>
      Opacity(opacity: m.target('title').opacity, child: const SizedBox()),
);

void main() {
  group('driving a motion from a test', () {
    testWidgets('seek parks the playhead and the tree follows', (tester) async {
      await tester.pumpWidget(_scope());
      await tester.seekMotion(0.5);
      expect(tester.motionValue('title', 'opacity'), closeTo(0.5, 1e-9));

      await tester.seekMotionTo(ms(100));
      expect(tester.motionValue('title', 'opacity'), closeTo(0.25, 1e-9));
    });

    testWidgets('the duration is readable, so stops need no hard-coding', (
      tester,
    ) async {
      await tester.pumpWidget(_scope());
      expect(tester.motionDuration(), ms(400));
    });

    testWidgets('a colour comes back as a Color', (tester) async {
      await tester.pumpWidget(_scope());
      await tester.seekMotion(1);
      expect(tester.motionValue('title', 'color'), const Color(0xFFFFFFFF));
    });

    testWidgets('reading a value is not a read', (tester) async {
      // The panel's three states must not change because a test looked.
      await tester.pumpWidget(_scope());
      tester.motionValue('title', 'color');
      var state = tester.state<MotionScopeState>(find.byType(MotionScope));
      expect(state.reads, {'title.opacity'});
    });

    testWidgets('nothing mounted says so, rather than throwing a null', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      expect(
        () => tester.seekMotion(0.5),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('No MotionScope is mounted'),
          ),
        ),
      );
    });

    testWidgets('two mounted asks which, and names them', (tester) async {
      await tester.pumpWidget(
        Row(textDirection: TextDirection.ltr, children: [_scope(), _scope()]),
      );
      expect(
        () => tester.seekMotion(0.5),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('2 MotionScopes'), contains('scope:')),
          ),
        ),
      );
    });
  });
}

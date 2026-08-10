import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/motion.dart';

Duration ms(int value) => Duration(milliseconds: value);

/// A motion that has moved and grown by the time it is done, so the rect a
/// `MotionBox` reports can be checked against something other than layout.
final _values = MotionValues(
  targets: {
    'card': {
      'translateX': [Seg<double>(start: ms(0), end: ms(400), from: 0, to: 100)],
      'scale': [Seg<double>(start: ms(0), end: ms(400), from: 1, to: 2)],
    },
  },
);

/// Mounts [build] inside a scope parked at [t], and hands back the `Motion` so
/// a test can ask it where things are.
Future<Motion> pumpScope(
  WidgetTester tester,
  Widget Function(Motion m) build, {
  double t = 0,
  MotionValues? values,
}) async {
  late Motion motion;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: MotionScope(
          motion: values ?? _values,
          controller: MotionController(progress: t, autoplay: false),
          builder: (m) {
            motion = m;
            return build(m);
          },
        ),
      ),
    ),
  );
  return motion;
}

void main() {
  testWidgets('nothing points at a target, so it has nowhere to be', (
    tester,
  ) async {
    // The ordinary case, and not an error: `card.translateX` could be read onto
    // a Transform and `card.scale` onto another, and neither is a widget that
    // *is* `card`.
    var motion = await pumpScope(
      tester,
      (m) => SizedBox(width: 10 + m.target('card').translateX),
    );
    expect(motion.extentOf('card'), isNull);
    expect(motion.extents, isEmpty);
  });

  testWidgets('MotionExtent says where a target is, and applies nothing', (
    tester,
  ) async {
    var motion = await pumpScope(
      tester,
      (m) => MotionExtent(
        m.target('card'),
        child: const SizedBox(width: 40, height: 20),
      ),
    );
    expect(motion.extents, {'card'});
    expect(motion.extentOf('card'), const Rect.fromLTWH(0, 0, 40, 20));
  });

  testWidgets('MotionBox registers on its own', (tester) async {
    var motion = await pumpScope(
      tester,
      (m) => MotionBox(
        m.target('card'),
        child: const SizedBox(width: 40, height: 20),
      ),
    );
    expect(motion.extents, {'card'});
  });

  testWidgets('the rect is where the box moved it, not where it laid out', (
    tester,
  ) async {
    // The whole point. At t=1 the box has translated 100 and scaled 2 about its
    // centre, so a rect taken from the layout box would sit at the origin at
    // its original size and the ring would not follow the animation at all.
    var motion = await pumpScope(
      tester,
      (m) => MotionBox(
        m.target('card'),
        child: const SizedBox(width: 40, height: 20),
      ),
      t: 1,
    );
    var rect = motion.extentOf('card')!;
    expect(rect.width, 80);
    expect(rect.height, 40);
    expect(rect.center.dx, closeTo(120, 0.01));
    expect(rect.center.dy, closeTo(10, 0.01));
  });

  testWidgets('two widgets naming one target report the box holding both', (
    tester,
  ) async {
    var motion = await pumpScope(tester, (m) {
      var card = m.target('card');
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MotionExtent(card, child: const SizedBox(width: 30, height: 20)),
          MotionExtent(card, child: const SizedBox(width: 30, height: 50)),
        ],
      );
    });
    expect(motion.extentOf('card'), const Rect.fromLTWH(0, 0, 60, 50));
  });

  testWidgets('a target stops having a place when its widget goes', (
    tester,
  ) async {
    late Motion motion;
    Widget build(bool showing) => Directionality(
      textDirection: TextDirection.ltr,
      child: MotionScope(
        motion: _values,
        controller: MotionController(autoplay: false),
        builder: (m) {
          motion = m;
          return showing
              ? MotionExtent(m.target('card'), child: const SizedBox(width: 10))
              : const SizedBox(width: 10);
        },
      ),
    );

    await tester.pumpWidget(build(true));
    expect(motion.extents, {'card'});

    // Not merely unresolvable — gone. A registration that lingered would have
    // the panel ringing the last place something used to be.
    await tester.pumpWidget(build(false));
    expect(motion.extents, isEmpty);
    expect(motion.extentOf('card'), isNull);
  });

  testWidgets('the same element handed a new target re-keys', (tester) async {
    // What a reordered list does. Keyed on the old name, the ring would point
    // at whatever used to be in this row.
    late Motion motion;
    Widget build(String name) => Directionality(
      textDirection: TextDirection.ltr,
      child: MotionScope(
        motion: _values,
        controller: MotionController(autoplay: false),
        builder: (m) {
          motion = m;
          return MotionExtent(
            m.target(name),
            child: const SizedBox(width: 10, height: 10),
          );
        },
      ),
    );

    await tester.pumpWidget(build('card'));
    expect(motion.extents, {'card'});

    await tester.pumpWidget(build('other'));
    expect(motion.extents, {'other'});
    expect(motion.extentOf('card'), isNull);
  });

  testWidgets("the guest reports it, in the guest's own coordinates", (
    tester,
  ) async {
    await pumpScope(
      tester,
      (m) => MotionBox(
        m.target('card'),
        child: const SizedBox(width: 40, height: 20),
      ),
    );
    var surface = MotionRegistry.instance.resolve(
      MotionRegistry.instance.ids.single,
    )!;
    expect(surface.extentOf('card'), const Rect.fromLTWH(0, 0, 40, 20));
    expect(surface.extentOf('nobody'), isNull);
  });
}

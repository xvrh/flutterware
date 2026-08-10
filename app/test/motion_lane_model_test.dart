import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/motion/lane_model.dart';

/// One target's worth of `ext.flutterware.motion.list`, spelled the way the
/// guest spells it — see `_describeTarget` in `lib/src/motion/guest.dart`.
Map<String, dynamic> target(
  String name, {
  bool named = true,
  List<String> offered = const [],
  List<Map<String, dynamic>> properties = const [],
}) => {
  'name': name,
  'named': named,
  'offered': offered,
  'properties': properties,
};

Map<String, dynamic> property(
  String name, {
  String state = 'wired',
  Object? value,
  List<Map<String, dynamic>> segments = const [],
}) => {'name': name, 'state': state, 'value': value, 'segments': segments};

Map<String, dynamic> segment({
  int startMs = 0,
  int endMs = 100,
  Object? from = 0,
  Object? to = 1,
  String? curve,
}) => {
  'startMs': startMs,
  'endMs': endMs,
  'from': from,
  'to': to,
  'curve': curve,
};

Map<String, dynamic> scope(List<Map<String, dynamic>> targets) => {
  'id': 'demo',
  'durationMs': 620,
  'ms': 210,
  'progress': 0.34,
  'playing': false,
  'targets': targets,
};

void main() {
  group('parsing', () {
    test('reads a scope the way the guest writes one', () {
      var parsed = MotionScopeView.parse(
        scope([
          target(
            'title',
            properties: [
              property(
                'opacity',
                value: 0.5,
                segments: [segment(startMs: 60, endMs: 520, curve: 'easeOut')],
              ),
            ],
          ),
        ]),
      )!;

      expect(parsed.id, 'demo');
      expect(parsed.durationMs, 620);
      expect(parsed.positionMs, 210);
      expect(parsed.progress, closeTo(0.34, 1e-9));
      expect(parsed.playing, isFalse);

      var opacity = parsed.property('title', 'opacity')!;
      expect(opacity.state, MotionLaneState.wired);
      expect(opacity.value, const MotionNumberView(0.5));
      expect(opacity.segments.single.startMs, 60);
      expect(opacity.segments.single.durationMs, 460);
      expect(opacity.segments.single.curve, 'easeOut');
    });

    test('null is no scope rather than an empty one', () {
      expect(MotionScopeView.parse(null), isNull);
    });

    test('the two value kinds, and nothing else', () {
      expect(MotionValueView.parse(3), const MotionNumberView(3));
      expect(
        MotionValueView.parse({'color': 0xFF102030}),
        const MotionColorView(0xFF102030),
      );
      expect(MotionValueView.parse(null), isNull);
      expect(MotionValueView.parse('easeOut'), isNull);
    });

    test('a colour prints as the file spells one', () {
      expect(const MotionColorView(0xFF1A1F26).label, '#FF1A1F26');
      // Leading zeroes survive: 0x0A is not 0xA0.
      expect(const MotionColorView(0x0A0B0C0D).label, '#0A0B0C0D');
    });

    test('an unknown state is wired, not a crash', () {
      // The panel draws whatever the guest says. A runtime that grew a fourth
      // state should show the lane, not lose it.
      expect(MotionLaneState.parse('something-new'), MotionLaneState.wired);
      expect(MotionLaneState.parse(null), MotionLaneState.wired);
    });
  });

  group('a target', () {
    test('is worth what its best property is worth', () {
      var wired = MotionTargetView.parse(
        target(
          't',
          properties: [
            property('a', state: 'untuned'),
            property('b', state: 'wired'),
          ],
        ),
      );
      expect(wired.state, MotionLaneState.wired);

      var dead = MotionTargetView.parse(
        target(
          't',
          properties: [
            property('a', state: 'untuned'),
            property('b', state: 'dead'),
          ],
        ),
      );
      expect(dead.state, MotionLaneState.dead);

      var untuned = MotionTargetView.parse(
        target('t', properties: [property('a', state: 'untuned')]),
      );
      expect(untuned.state, MotionLaneState.untuned);
    });

    test('never named outranks every property below it', () {
      // The build did not ask for this target, so nothing under it is applied
      // no matter what the individual lanes say.
      var orphan = MotionTargetView.parse(
        target('t', named: false, properties: [property('a', state: 'wired')]),
      );
      expect(orphan.state, MotionLaneState.dead);
    });

    test('offers only what no lane already covers', () {
      // A MotionBox sweeps its whole frozen set every build, so the offer list
      // includes the property that already has a lane.
      var box = MotionTargetView.parse(
        target(
          't',
          offered: ['opacity', 'scale', 'rotate'],
          properties: [property('opacity')],
        ),
      );
      expect(box.addable, ['scale', 'rotate']);
    });

    test('spans from its earliest start to its latest end', () {
      var spread = MotionTargetView.parse(
        target(
          't',
          properties: [
            property('a', segments: [segment(startMs: 300, endMs: 560)]),
            property(
              'b',
              segments: [
                segment(startMs: 80, endMs: 200),
                segment(startMs: 400, endMs: 620),
              ],
            ),
          ],
        ),
      );
      expect(spread.span, (80, 620));
    });

    test('has no span when nothing under it is tuned', () {
      var bare = MotionTargetView.parse(
        target('t', properties: [property('a', state: 'untuned')]),
      );
      expect(bare.span, isNull);
    });
  });

  group('selection', () {
    var parsed = MotionScopeView.parse(
      scope([
        target(
          'title',
          properties: [
            property(
              'opacity',
              segments: [
                segment(startMs: 0, endMs: 100),
                segment(startMs: 200, endMs: 300),
              ],
            ),
          ],
        ),
      ]),
    )!;

    test('resolves to the segment it addresses', () {
      var second = parsed.resolve(const MotionSelection('title', 'opacity', 1));
      expect(second?.startMs, 200);
    });

    test('stops resolving once the thing is gone', () {
      // The poll rebuilds the model every second. An address that no longer
      // lands has to say so, or the inspector shows numbers for a span that
      // was deleted under it.
      expect(
        parsed.resolve(const MotionSelection('title', 'opacity', 7)),
        isNull,
      );
      expect(
        parsed.resolve(const MotionSelection('title', 'scale', 0)),
        isNull,
      );
      expect(
        parsed.resolve(const MotionSelection('gone', 'opacity', 0)),
        isNull,
      );
    });

    test('is equal by address, so a refresh keeps it', () {
      expect(
        const MotionSelection('a', 'b', 0),
        const MotionSelection('a', 'b', 0),
      );
      expect(
        const MotionSelection('a', 'b', 0),
        isNot(const MotionSelection('a', 'b', 1)),
      );
    });
  });
}

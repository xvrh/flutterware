import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/run_listener.dart';

/// What `tap(target)` cannot say: **where** on a widget the finger goes down.
///
/// A map, a chart, an SVG: the regions are painted rather than built, so they
/// share one widget and one box, and every finder verb comes back to that
/// box's centre. Reported by a consumer aiming at an SVG's hit-test regions,
/// who had `dragFrom(point, Offset.zero)` as the only spelling — the right
/// gesture arrived at sideways, and a report that says `dragFrom` about a tap.
void main() {
  var captures = <ScenarioStepCapture>[];
  setUp(() {
    captures = [];
    scenarioRunListener = captures.add;
  });
  tearDown(() => scenarioRunListener = null);

  group('tapAt', () {
    scenario('presses the point, not the widget under it', (s) async {
      var canvas = _Regions();
      await s.pumpWidget(_Map(canvas));

      await s.tapAt(const Offset(200, 500));
      expect(canvas.pressed, const Offset(200, 500));

      // The distinction this verb exists for. `Target.at` resolves the widget
      // *under* the point and the press still lands on that widget's centre —
      // right for a button, useless for the canvas that fills the screen
      // behind it.
      canvas.reset();
      await s.tap(const Target.at(200, 500));
      expect(canvas.pressed, isNot(const Offset(200, 500)));
    });
    tearDown(() {
      // The step says what the author meant. It is a tap, spelled as a tap,
      // and the report reads it as one.
      expect(captures[1].verb, 'tapAt');
      expect(captures[1].target, '200,500');

      // The mark is the point itself: a box of no size, as on `dragFrom`.
      // Inventing a box would draw a ring around whatever happens to lie
      // under the finger, as though the verb had resolved it.
      var aim = captures[1].aim!;
      expect((aim.x, aim.y), (200.0, 500.0));
      expect((aim.width, aim.height), (0.0, 0.0));
      expect((aim.dx, aim.dy), (null, null));
    });
  });
}

/// Where the finger went down on the canvas.
class _Regions {
  Offset? pressed;

  void reset() => pressed = null;
}

class _Map extends StatelessWidget {
  const _Map(this.regions);

  final _Regions regions;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: GestureDetector(
        onTapDown: (details) => regions.pressed = details.globalPosition,
        child: Container(color: const Color(0xFF202020)),
      ),
    ),
  );
}

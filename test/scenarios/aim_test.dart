import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/run_listener.dart';

/// Where the finger went.
///
/// A scenario runs with no cursor on screen, so nothing in a picture says
/// which of six drinks was tapped. The verbs measure the box they resolved,
/// on the frame they were about to act on, and it rides the step they
/// produce.
void main() {
  var captures = <ScenarioStepCapture>[];
  setUp(() {
    captures = [];
    scenarioRunListener = captures.add;
  });
  tearDown(() => scenarioRunListener = null);

  group('a tap records the box it resolved', () {
    scenario('measured before the tap, on the screen it acted on', (s) async {
      await s.pumpWidget(const _App());
      // Two identical buttons, 200 logical pixels apart: a rect that came from
      // the wrong one is a failure this test can see.
      await s.tap('Second');
    });
    tearDown(() {
      var aim = captures.last.aim!;
      // **The finder's box, not the button's.** `tap('Second')` resolves the
      // `Text`, and the tap lands at its centre — so the box is the word's,
      // sitting inside the 40-high target that handles the gesture. That is
      // the truth of what the verb aimed at, and it is why a viewer marks the
      // point as well as the box.
      expect(aim.y, greaterThan(300), reason: 'inside the second button');
      expect(aim.y + aim.height, lessThan(340));
      expect(aim.height, lessThan(40), reason: 'the word, not the button');
      expect(aim.point, (aim.x + aim.width / 2, aim.y + aim.height / 2));
      expect(aim.dx, isNull, reason: 'a tap does not travel');
    });
  });

  group('a verb with nothing to point at records nothing', () {
    scenario('and does not inherit the last verb that had one', (s) async {
      await s.pumpWidget(const _App());
      await s.tap('Second');
      await s.wait(const Duration(milliseconds: 10));
    });
    tearDown(() {
      expect(captures[captures.length - 2].aim, isNotNull, reason: 'the tap');
      expect(captures.last.aim, isNull, reason: 'the wait after it');
    });
  });

  group('a drag records where it went and how far', () {
    scenario("the offset is the verb's own", (s) async {
      await s.pumpWidget(const _App());
      await s.drag('Second', const Offset(0, -80));
    });
    tearDown(() {
      var aim = captures.last.aim!;
      expect((aim.dx, aim.dy), (0.0, -80.0));
      expect(aim.y, greaterThan(300), reason: 'where it started, not ended');
      expect(aim.y, lessThan(340));
    });
  });

  group('a long press aims like a tap', () {
    scenario('same box, no travel', (s) async {
      await s.pumpWidget(const _App());
      await s.longPress('First');
    });
    tearDown(() {
      var aim = captures.last.aim!;
      expect(aim.y, greaterThan(100), reason: 'inside the first button');
      expect(aim.y, lessThan(140));
      expect(aim.dx, isNull);
    });
  });

  group('the aim survives the report', () {
    scenario('written and read back as the same box', (s) async {
      await s.pumpWidget(const _App());
      await s.tap('Second');
    });
    tearDown(() {
      var aim = captures.last.aim!;
      var read = ScenarioAim.fromJson(aim.toJson())!;
      expect(
        (read.x, read.y, read.width, read.height),
        (aim.x, aim.y, aim.width, aim.height),
      );
      // A report written before any of this simply has no aim, and a viewer
      // draws nothing rather than guessing.
      expect(ScenarioAim.fromJson(null), isNull);
    });
  });
}

/// Two buttons at known heights, so a wrong box is a wrong number.
class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          for (var (top, label) in [(100.0, 'First'), (300.0, 'Second')])
            Positioned(
              top: top,
              left: 20,
              child: SizedBox(
                height: 40,
                width: 120,
                child: GestureDetector(
                  onTap: () {},
                  onLongPress: () {},
                  child: Center(child: Text(label)),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

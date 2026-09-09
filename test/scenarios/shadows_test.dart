import 'package:flutter/rendering.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/run_args.dart';
import 'package:flutterware/src/scenarios/run_listener.dart';

import 'shadow_fixture.dart';

/// Real shadows, which is what a scenario renders and what no other
/// `flutter_test` does.
///
/// `AutomatedTestWidgetsFlutterBinding` sets `debugDisableShadows` in its
/// constructor and asserts at the end of every body that nobody left it moved.
/// That default is right for a golden — shadow rasterisation is not promised
/// stable across engine versions — and wrong for every picture this harness
/// takes, all of which are looked at. `runScenarios(shadows: false)` is how a
/// folder asks for upstream's back.
void main() {
  var captures = <ScenarioStepCapture>[];
  setUp(() {
    captures = [];
    scenarioRunListener = captures.add;
  });
  tearDown(() {
    scenarioRunListener = null;
    scenarioRunArgs = null;
  });

  group('the flag belongs to the run', () {
    scenario('which is what a body sees', (s) async {
      await s.pumpWidget(const ShadowFixture());
      expect(debugDisableShadows, isFalse);
    });
    // Put back on the way out, and it has to be: the binding checks its own
    // painting variables at the end of the body, before any tearDown runs, and
    // fails the scenario over one it did not set.
    tearDown(() => expect(debugDisableShadows, isTrue));
  });

  group('a blur reaches the pixels', () {
    // Encoded bytes say nothing about a ramp without being decoded back.
    setUp(() => scenarioRunArgs = const ScenarioRunArgs(captureRaw: true));

    scenario('as a ramp rather than a step', (s) async {
      await s.pumpWidget(const ShadowFixture());
    });
    tearDown(() {
      expect(greyLevels(captures.single.bytes!), greaterThan(8));
    });
  });
}

import 'package:flutter/rendering.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/run_args.dart';
import 'package:flutterware/src/scenarios/run_listener.dart';

import '../shadow_fixture.dart';

/// The folder's shadow policy, end to end: nothing here says anything, and
/// every scenario in it renders the way a bare `flutter test` would.
void main() {
  var captures = <ScenarioStepCapture>[];
  setUp(() {
    captures = [];
    scenarioRunListener = captures.add;
    scenarioRunArgs = const ScenarioRunArgs(captureRaw: true);
  });
  tearDown(() {
    scenarioRunListener = null;
    scenarioRunArgs = null;
  });

  scenario('takes the folder policy', (s) async {
    await s.pumpWidget(const ShadowFixture());
    expect(debugDisableShadows, isTrue);
  });
  tearDown(() {
    // The two the fixture painted itself, and nothing between them: the mask
    // filter is gone, so the shadow is a flat fill of the shape.
    expect(greyLevels(captures.single.bytes!), lessThan(4));
  });
}

import 'dart:async';

import 'package:flutterware/flutter_test.dart';

/// The web demo is a window; its scenarios are framed as one, under the
/// harness and under `flutter test` alike.
const demo = ScenarioProfile('demo', devices: [Devices.window]);

Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, profile: demo);

import 'dart:async';

import 'package:flutterware/flutter_test.dart';

/// A folder whose scenarios are worth pointing at something real — said once,
/// instead of on every `scenario()` in it.
Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, network: ScenarioNetwork.live);

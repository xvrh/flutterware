import 'dart:async';

import 'package:flutterware/flutter_test.dart';

import '../profiles.dart';

/// A folder whose screens load their data over http, answered from the
/// recording committed at `test/scenarios/network/`.
///
/// Said here rather than on every scenario, and rather than on the project:
/// the rest of this project's scenarios make no requests at all, and a folder
/// is the altitude where "these ones talk to an API" is true. A project that
/// is *all* API screens says it once in `tool/flutterware.dart` with
/// `fw.network(ScenarioNetwork.replay)` instead — with the one caveat that a
/// bare `flutter test` reads no manifest, so it would need `FW_NETWORK=replay`
/// on the command line where this needs nothing.
Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, profile: phones, network: ScenarioNetwork.replay);

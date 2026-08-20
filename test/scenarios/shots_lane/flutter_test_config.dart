import 'dart:async';

import 'package:flutterware/flutter_test.dart';

/// A folder that captures only what it names — the shape a folder whose
/// pictures feed a document generator wants, said once instead of on every
/// `scenario()` in it.
Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, shots: Shots.manual);

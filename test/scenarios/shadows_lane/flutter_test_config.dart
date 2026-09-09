import 'dart:async';

import 'package:flutterware/flutter_test.dart';

/// A folder that keeps `flutter_test`'s own shadows — the shape a suite gating
/// on pictures across a Flutter bump wants, said once for the folder.
Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, shadows: false);

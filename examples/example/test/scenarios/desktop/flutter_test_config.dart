import 'dart:async';

import 'package:flutterware/flutter_test.dart';

import '../profiles.dart';

/// The same hook as `../mobile/`, naming the other profile — which is the
/// whole per-folder story: opening a scenario from this folder frames a
/// window, opening one from that folder frames a phone, and no scenario says
/// a word about devices.
Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, profile: desktop);

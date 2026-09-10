import 'dart:async';

import 'package:flutterware/flutter_test.dart';

/// The studio's own scenarios are framed as a window: the harness runs them
/// at this device, and so does `flutter test`, which would otherwise pump
/// the shell into an 800×600 surface and overflow the address bar on a deep
/// address. One profile, and no scenario says a word about devices.
const studio = ScenarioProfile(
  'studio',
  devices: [Devices.window, Devices.wideWindow],
);

Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, profile: studio);

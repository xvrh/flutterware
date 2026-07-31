import 'dart:async';

import 'package:flutterware/flutter_test.dart';

import '../profiles.dart';

/// The hook `flutter test` already looks for, found by walking up from each
/// test file — so this folder says what it is for, and the folder next to it
/// says something else, without either knowing the other exists.
///
/// One line does three jobs: `flutter test` runs these scenarios on an iPhone
/// 16 in English (the head of each list), the GUI offers the whole pool, and
/// CI overrides it with a list of its own:
///
/// ```sh
/// flutter test test/scenarios/mobile \
///   --dart-define=fw.devices=iphone-se,android-tall \
///   --dart-define=fw.languages=en,fr
/// ```
Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, profile: phones);

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class ScenarioBinding extends AutomatedTestWidgetsFlutterBinding {
  final void Function()? onReloaded;

  ScenarioBinding({this.onReloaded});

  @override
  bool get overrideHttpClient => false;

  @override
  Future<void> performReassemble() {
    // In order for Hot reload to work, we need to schedule a test
    Timer.run(_afterHotReload);
    return super.performReassemble();
  }

  void _afterHotReload() async {
    await runTest(() async {}, () {});
    postTest();
    onReloaded?.call();
  }

  @override
  void scheduleWarmUpFrame() {
    if (inTest) {
      super.scheduleWarmUpFrame();
    } else {
      // A hot reload schedule a frame, if we are not running a test, this
      // will create an error.
    }
  }
}

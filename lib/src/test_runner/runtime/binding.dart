import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class ScenarioBinding extends AutomatedTestWidgetsFlutterBinding {
  final void Function()? onReloaded;

  ScenarioBinding({this.onReloaded});

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  /// The current [AutomatedTestWidgetsFlutterBinding], if one has been created.
  ///
  /// The binding must be initialized before using this getter. If you
  /// need the binding to be constructed before calling [testWidgets],
  /// you can ensure a binding has been constructed by calling the
  /// [TestWidgetsFlutterBinding.ensureInitialized] function.
  static ScenarioBinding get instance => BindingBase.checkInstance(_instance);
  static ScenarioBinding? _instance;

  static ScenarioBinding ensureInitialized() {
    if (ScenarioBinding._instance == null) ScenarioBinding();
    return ScenarioBinding.instance;
  }

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

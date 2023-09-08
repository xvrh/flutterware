import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class TestBinding extends AutomatedTestWidgetsFlutterBinding {
  final void Function()? onReloaded;

  TestBinding({this.onReloaded});

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  static TestBinding get instance => BindingBase.checkInstance(_instance);
  static TestBinding? _instance;

  static TestBinding ensureInitialized() {
    if (TestBinding._instance == null) TestBinding();
    return TestBinding.instance;
  }

  @override
  bool get overrideHttpClient => false;

  @override
  bool get disableShadows => false;

  @override
  Timeout get defaultTestTimeout => const Timeout(Duration(seconds: 60));

  @override
  Future<void> performReassemble() {
    // In order for Hot reload to work, we need to schedule a test
    Timer.run(_afterHotReload);
    return super.performReassemble();
  }

  void _afterHotReload() async {
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

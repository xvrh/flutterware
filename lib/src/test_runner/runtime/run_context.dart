import 'dart:async';
import 'dart:ui';
import 'package:flutterware/src/test_runner/protocol/model/locale.dart';

import '../../../flutter_test.dart';
import '../protocol/models.dart';
import 'path_tracker.dart';

class RunContext {
  final RunArgs args;
  final void Function(NewScreen newScreen) addScreen;
  final pathTracker = PathTracker();
  int screenIndex = 0;
  String? currentSplitName;
  String? previousId;
  final previousScreens = <String>{};
  Rect? previousTap;

  RunContext(this.args, {required this.addScreen});

  static void apply(RunContext context, void Function() callback) {
    return runZoned(callback, zoneValues: {#runContext: context});
  }
}

extension WidgetTesterContextExtension on WidgetTester {
  static final _testRunContexts = Expando<RunContext>();

  RunContext get runContext {
    var runContext = Zone.current[#runContext] as RunContext?;
    if (runContext != null) {
      return runContext;
    }

    return _testRunContexts[this] ??= _createDefaultContextForTest();
  }

  set runContext(RunContext context) {
    _testRunContexts[this] = context;
  }

  RunContext _createDefaultContextForTest() {
    return RunContext(
        RunArgs(['test'],
            device: DeviceInfo.iPhoneX,
            accessibility: AccessibilityConfig(),
            locale: SerializableLocale('en'),
            imageRatio: 1),
        addScreen: (_) {});
  }
}

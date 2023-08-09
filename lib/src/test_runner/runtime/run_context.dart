import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import '../../../flutter_test.dart';
import '../protocol/models.dart';
import 'path_tracker.dart';
import 'package:path/path.dart' as p;

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
    Directory? screenshotDirectory;
    var i = 0;

    String? screenshotPath = const String.fromEnvironment(
        'screenshots-destination',
        defaultValue: '');
    if (screenshotPath.isEmpty) {
      screenshotPath = Platform.environment['SCREENSHOTS_DESTINATION'];
    }
    if (screenshotPath != null) {
      screenshotDirectory = Directory(screenshotPath)
        ..createSync(recursive: true);
    }

    return RunContext(
      RunArgs(['test'],
          device: DeviceInfo.iPhoneX,
          accessibility: AccessibilityConfig(),
          locale: SerializableLocale('en'),
          imageRatio: 1),
      addScreen: (screen) {
        var image = screen.imageBase64;
        if (image != null && screenshotDirectory != null) {
          File(p.join(screenshotDirectory.path, '${++i}.png'))
              .writeAsBytesSync(base64Decode(image));
        }
      },
    );
  }
}

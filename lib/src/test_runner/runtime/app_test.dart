import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../api.dart';
import 'extract_text.dart';
import 'phone_status_bar.dart';

abstract class AppTest {
  Future<void> setUp() async {}
  Future<void> tearDown() async {}
  Future<void> run();

  AppWidgetTester? _tester;
  AppWidgetTester get tester {
    var tester = _tester;
    if (tester == null) {
      throw Exception('tester is only available when the test is run');
    }
    return tester;
  }

  /// A flag to control whether every calls to [pumpWidget], [tap], [enterText]...
  /// will automatically create a screenshot.
  /// If the flag is false, the [screenshot] method need to be called manually at
  /// each relevant steps.
  ///
  /// Whatever the value of this flag, most of the methods in this class expose
  /// a parameter [screenshot] allowing to control the screenshot of the step.
  /// ie:
  /// ```dart
  ///     Future<void> run() async {
  ///       autoScreenshot = true;
  ///
  ///       // Disable the screenshot for this step although [autoScreenshot] is true
  ///       await tap('Pay', screenshot: Screenshot.none);
  ///
  ///       // Specify some parameter for the screenshot of this step
  ///       await tap('37', screenshot: Screenshot(name: 'Paywall')));
  ///     }
  /// ```
  ///
  ///  When the flag is `false`,
  //  ```dart
  //      Future<void> run() async {
  //        autoScreenshot = false;
  //
  //        await tap('Pay');
  //
  //        // Manual screenshot is required since autoScreenshot is false
  //        await screenshot(name: 'Checkout');
  //
  //        // If you specify, the [screenshot] parameter, a screenshot is also taken
  //        await tap('37', screenshot: Screenshot(name: 'Paywall')));
  //      }
  //  ```
  bool autoScreenshot = true;

  Future<void> call(AppWidgetTester tester) async {
    _tester = tester;
    try {
      await setUp();
      await run();
    } finally {
      await tearDown();
      _tester = null;
    }
  }

  Future<void> pumpWidget(
    Widget widget, {
    Screenshot? screenshot,
  }) async {
    // widget = PhoneStatusBar(
    //   leftText: '09:42',
    //   key: _statusBarKey,
    //   viewPadding: args.device.safeArea.toEdgeInsets(),
    //   child: widget,
    // );
    //
    // widget = wrapWidget(widget);
    //
    //  await tester.pumpWidget(
    //    DefaultAssetBundle(
    //      bundle: _bundle,
    //      child: widget,
    //    ),
    //  );
    await tester.pumpWidget(widget);
    await _screenshot(screenshot);
  }

  Finder _targetToFinder(dynamic target) {
    if (target is Finder) {
      return target;
    } else if (target is String) {
      return TextFinder(target);
    } else if (target is Key) {
      return find.byKey(target);
    } else if (target is Type) {
      return find.byType(target);
    } else {
      throw StateError('Unsupported target ${target.runtimeType}');
    }
  }

  Future<void> enterText(
    dynamic target,
    String text,
    Screenshot? screenshot,
  ) async {
    var finder = _targetToFinder(target);
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
    await _screenshot(screenshot);
  }

  Future<void> tap(
    dynamic target, {
    bool pumpFrames = true,
    Screenshot? screenshot,
  }) async {
    var finder = _targetToFinder(target);

    await tester.tap(finder);
    if (pumpFrames) {
      await tester.pumpAndSettle();
    }
    await _screenshot(screenshot);
  }

  Future<void> _screenshot(Screenshot? screenshot, {String? autoName}) async {
    if (screenshot == null && autoScreenshot) {
      screenshot = Screenshot(name: autoName);
    }
    if (screenshot != null) {
      await tester.screenshot();
    }
  }

  Future<void> screenshot({String? name, List<String>? tags}) {
    return _screenshot(Screenshot(name: name, tags: tags));
  }
}

class Screenshot {
  static final none = Screenshot();
  final String? name;
  final List<String> tags;

  Screenshot({this.name, List<String>? tags}) : tags = tags ?? const [];
}

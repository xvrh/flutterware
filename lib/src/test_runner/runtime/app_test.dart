import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../api.dart';
import 'extract_text.dart';
import 'widget_tester.dart';

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

  Future<void> pumpWidget(Widget widget) async {
    //widget = PhoneStatusBar(
    //  leftText: '09:42',
    //  key: _statusBarKey,
    //  viewPadding: args.device.safeArea.toEdgeInsets(),
    //  child: widget,
    //);

    //widget = wrapWidget(widget);

    // await tester.pumpWidget(
    //   DefaultAssetBundle(
    //     bundle: _bundle,
    //     child: widget,
    //   ),
    // );
    await tester.pumpWidget(widget);
    await tester.pump(Duration(seconds: 10));
    await tester.pumpAndSettle();
    await tester.pump(Duration(seconds: 10));
    await tester.screenshot();
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

  Future<void> enterText(dynamic target, String text) async {
    var finder = _targetToFinder(target);
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
    await tester.screenshot();
  }

  Future<void> tap(dynamic target, {bool pumpFrames = true}) async {
    var finder = _targetToFinder(target);

    await tester.tap(finder);
    if (pumpFrames) {
      await tester.pumpAndSettle();
    }
    await tester.screenshot();
  }
}

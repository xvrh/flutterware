import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../flutter_test.dart';
import '../protocol/models.dart';
import 'run_context.dart';

Future<void> Function(WidgetTester) withTestValues(
    Future<void> Function(WidgetTester) body) {
  return (tester) async {
    var runContext = tester.runContext;
    var args = runContext.args;
    var device = args.device;
    var binding = AutomatedTestWidgetsFlutterBinding.instance;
    var platformDispatcher = binding.platformDispatcher;

    var pixelRatio = device.pixelRatio;
    tester.view.physicalSize =
        Size(device.width * pixelRatio, device.height * pixelRatio);
    tester.view.devicePixelRatio = pixelRatio;
    tester.view.padding = FakeViewPadding(
      left: device.safeArea.left * pixelRatio,
      top: device.safeArea.top * pixelRatio,
      right: device.safeArea.right * pixelRatio,
      bottom: device.safeArea.bottom * pixelRatio,
    );
    platformDispatcher.textScaleFactorTestValue = args.accessibility.textScale;
    platformDispatcher.accessibilityFeaturesTestValue =
        _FakeAccessibilityFeatures(args.accessibility);
    var platformBrightness = args.platformBrightness;
    if (platformBrightness != null) {
      platformDispatcher.platformBrightnessTestValue =
          ui.Brightness.values[platformBrightness];
    }

    var locale = args.locale;
    if (locale != null) {
      platformDispatcher.localesTestValue = [
        Locale(locale.language, locale.country)
      ];
    }
    debugDefaultTargetPlatformOverride = device.platform.toTargetPlatform();

    try {
      await body(tester);
    } catch (e) {
      // Take a screenshot of the error
      //TODO(xha): remove this and put it in Runner and get the value though the
      // binding.renderView
      await tester.screenshot(name: 'After error');
      await tester.pumpWidget(ErrorWidget('$e'));
      await tester.screenshot(name: 'Error');
      rethrow;
    } finally {
      tester.platformDispatcher.clearAllTestValues();
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    }
  };
}

class _FakeAccessibilityFeatures implements ui.AccessibilityFeatures {
  final AccessibilityConfig config;

  _FakeAccessibilityFeatures(this.config);

  @override
  bool get accessibleNavigation => config.accessibleNavigation;

  @override
  bool get boldText => config.boldText;

  @override
  bool get disableAnimations => config.disableAnimations;

  @override
  bool get highContrast => config.highContrast;

  @override
  bool get invertColors => config.invertColors;

  @override
  bool get reduceMotion => config.reduceMotion;

  @override
  bool get onOffSwitchLabels => config.onOffSwitchLabels;

  @override
  bool get announce => false;
}

/// Putting a widget test on a device, for a test that is not a scenario.
///
/// The machinery is a scenario's own — a device becomes a size, a ratio, a
/// notch and a target platform, applied through the binding's test values
/// exactly as a hand-written widget test would set them. This is that, minus
/// the scenario: a plain `testWidgets` that walks a catalog and pumps every
/// entry needs the same fact, and has nowhere to get it from.
///
/// **Why a project needs this at all.** A catalog holding two form factors has
/// to pump a desktop entry on a desktop-sized surface or it reports overflows
/// that are not real — the same fact `PreviewCanvas` carries for the tool. The
/// canvas list is pure Dart and lives in the project's own package, so the
/// config and the test read one list and cannot disagree:
///
/// ```dart
/// // demo/test/catalog_test.dart
/// import 'package:flutterware/flutter_test.dart';
/// import 'package:demo/canvases.dart';
///
/// for (var entry in catalog) {
///   testWidgets(entry.name, (tester) async {
///     var reset = tester.applyCanvas(canvasFor(canvases, entry.path));
///     await tester.pumpWidget(entry.build());
///     reset();
///   });
/// }
/// ```
library;

import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../canvases.dart';
import '../devices.dart';
import 'run_args.dart';

/// Staging a widget test on a device, for tests that are not scenarios.
///
/// A scenario gets this from its axes and needs none of it. This is for the
/// other lane: an ordinary `testWidgets` that has to render as something in
/// particular.
extension DeviceStaging on WidgetTester {
  /// Renders as [device] until the returned callback is run.
  ///
  /// **Run the reset inside the test body — a `tearDown` is too late.** The
  /// binding verifies its foundation debug variables at the end of the body,
  /// `debugDefaultTargetPlatformOverride` among them, and tearDowns run after
  /// that. So a reset filed as a tearDown fails the test it was meant to clean
  /// up. Forgetting it entirely fails loudly for the same reason, which is the
  /// one thing to be grateful for here.
  ///
  /// A null [device] is the plain surface and a reset that does nothing, so a
  /// caller looking a device up per entry needs no branch around this.
  VoidCallback applyDevice(Device? device, {ScreenOrientation? orientation}) {
    if (device == null) return () {};
    return applyScenarioRunArgs(
      this,
      const ScenarioRunArgs().withDevice(device, orientation: orientation),
    );
  }

  /// [applyDevice] with the head of [canvas] — what that list means everywhere
  /// else, so a test written against it agrees with the panel and with
  /// `previews screenshot` by construction rather than by care.
  ///
  /// **No canvas and a canvas that stages nothing are different answers.** No
  /// canvas leaves the surface exactly as the test had it, which is the whole
  /// of the old behaviour and stays the rule. A canvas that resolves to no
  /// device has *said something* — it is a subtree of windows, and a declared
  /// window is offered rather than staged (see [PreviewCanvas.defaultDevice]) —
  /// so it gets the same rectangle the panel opens it on rather than
  /// `flutter_test`'s 800×600, which is the arbitrary surface
  /// [previewPanelWidth] exists to keep entries off.
  VoidCallback applyCanvas(PreviewCanvas? canvas) {
    if (canvas == null) return () {};
    if (canvas.defaultDevice case var device?) {
      return applyDevice(device, orientation: canvas.defaultOrientation);
    }
    return applyScenarioRunArgs(
      this,
      ScenarioRunArgs(
        size: Size(previewPanelWidth.toDouble(), previewPanelHeight.toDouble()),
        // At 1, like the rectangle everywhere else: it is a size the layout
        // meets, not a screen with a scale of its own.
        pixelRatio: 1,
      ),
    );
  }
}

/// Applies [args] through the binding's own test values, exactly as a
/// hand-written widget test would — so a scenario under an axis, and a test
/// that sets `tester.view.physicalSize` itself, are the same machinery.
///
/// Returns the reset. See [DeviceStaging.applyDevice] for why the caller has to
/// run it inside the test body.
VoidCallback applyScenarioRunArgs(WidgetTester tester, ScenarioRunArgs args) {
  var view = tester.view;
  var dispatcher = tester.platformDispatcher;

  var ratio = args.pixelRatio ?? view.devicePixelRatio;
  if (args.pixelRatio != null) view.devicePixelRatio = ratio;
  if (args.size case var size?) view.physicalSize = size * ratio;
  if (args.padding case var padding?) {
    // FakeViewPadding speaks physical pixels; the args speak logical, like
    // the device table they come from.
    var fake = FakeViewPadding(
      left: padding.left * ratio,
      top: padding.top * ratio,
      right: padding.right * ratio,
      bottom: padding.bottom * ratio,
    );
    view.padding = fake;
    view.viewPadding = fake;
  }
  if (args.platform case var platform?) {
    debugDefaultTargetPlatformOverride = platform;
  }
  if (args.locale case var locale?) {
    dispatcher.localeTestValue = locale;
    dispatcher.localesTestValue = [locale];
  }
  if (args.textScale case var scale?) {
    dispatcher.textScaleFactorTestValue = scale;
  }
  if (args.brightness case var brightness?) {
    dispatcher.platformBrightnessTestValue = brightness;
  }
  if (!args.accessibility.isDefault) {
    dispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      boldText: args.accessibility.boldText,
      highContrast: args.accessibility.highContrast,
      invertColors: args.accessibility.invertColors,
    );
  }

  return () {
    debugDefaultTargetPlatformOverride = null;
    view.reset();
    dispatcher.clearAllTestValues();
  };
}

import 'package:flutter/widgets.dart';

/// One run's axis assignment — device geometry, locale, text scale,
/// brightness — as the substrate applies it.
///
/// Every field is optional and null means "the test default": a scenario run
/// with no axes is byte-identical to what a bare `flutter test` produces.
class ScenarioRunArgs {
  const ScenarioRunArgs({
    this.size,
    this.pixelRatio,
    this.padding,
    this.platform,
    this.locale,
    this.textScale,
    this.brightness,
    this.accessibility = const ScenarioRunAccessibility(),
    this.captureScale,
    this.captureRaw = false,
  });

  final ScenarioRunAccessibility accessibility;

  /// The screen in **logical** pixels — what the layout reads from
  /// `MediaQuery`.
  final Size? size;

  final double? pixelRatio;

  /// Safe areas in logical pixels — the notch, without which an `AppBar`
  /// renders under the cutout and a capture misses the exact thing a phone
  /// frame exists to catch.
  final EdgeInsets? padding;

  final TargetPlatform? platform;
  final Locale? locale;
  final double? textScale;
  final Brightness? brightness;

  /// Output pixels per **logical** pixel in captured screenshots, or null for
  /// the device's own ratio (a real screenshot's resolution). Not an axis —
  /// it changes the artifact, never what the app sees.
  final double? captureScale;

  /// Capture raw rgba8888 instead of PNG. PNG *encoding* is ~80% of a 1×
  /// capture's cost (and ~96% at 3×); a host that can display raw pixels —
  /// the GUI can — skips it entirely.
  final bool captureRaw;
}

/// The accessibility features a run can turn on — the platform switches a
/// real user flips, applied through the binding's
/// `accessibilityFeaturesTestValue`.
class ScenarioRunAccessibility {
  const ScenarioRunAccessibility({
    this.boldText = false,
    this.highContrast = false,
    this.invertColors = false,
  });

  final bool boldText;
  final bool highContrast;
  final bool invertColors;

  bool get isDefault => !boldText && !highContrast && !invertColors;
}

/// Set by the flutterware harness for the duration of one run request; null
/// under a bare `flutter test`, where every scenario runs at the test
/// defaults.
///
/// Deliberately not exported from `package:flutterware/flutter_test.dart` —
/// like `scenarioRunListener`, it is the seam between the authoring API and
/// the runner, not part of the authoring API.
ScenarioRunArgs? scenarioRunArgs;

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
  });

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
}

/// Set by the flutterware harness for the duration of one run request; null
/// under a bare `flutter test`, where every scenario runs at the test
/// defaults.
///
/// Deliberately not exported from `package:flutterware/flutter_test.dart` —
/// like `scenarioRunListener`, it is the seam between the authoring API and
/// the runner, not part of the authoring API.
ScenarioRunArgs? scenarioRunArgs;

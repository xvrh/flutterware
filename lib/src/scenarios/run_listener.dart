import 'dart:typed_data';

/// One captured step, handed from [ScenarioTester]'s capture to whoever is
/// listening — the harness, when a scenario runs under the flutterware
/// runner.
class ScenarioStepCapture {
  ScenarioStepCapture({
    required this.index,
    required this.name,
    required this.tags,
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
    required this.texts,
    required this.statusBrightness,
    required this.navBrightness,
  });

  /// 1-based position in the scenario's capture sequence.
  final int index;

  /// The [Shot]'s name, or null for an automatic capture.
  final String? name;

  final List<String> tags;

  /// The image, in [format]: `png`, or `raw` — bare rgba8888 rows,
  /// [width]×[height]×4 bytes. Raw exists because PNG *encoding* is ~80% of
  /// a capture's cost; a host that can display raw pixels asks for them.
  final Uint8List bytes;

  final String format;
  final int width;
  final int height;

  /// The visible `Text` widgets, in tree order — the text projection.
  final List<String> texts;

  /// The app's declared `SystemUiOverlayStyle` icon brightness at capture
  /// time (`light`/`dark`), or null when it never declared one. What the
  /// GUI's fake status bar and home indicator tint themselves with — wrong
  /// status-bar brightness is a shipped bug a screenshot exists to catch.
  final String? statusBrightness;
  final String? navBrightness;
}

/// Set by the flutterware harness for the duration of one scenario run; null
/// under a bare `flutter test`, where captures go to
/// `SCREENSHOTS_DESTINATION` instead (or nowhere).
///
/// Deliberately not exported from `package:flutterware/flutter_test.dart` —
/// it is the seam between the authoring API and the runner, not part of the
/// authoring API.
void Function(ScenarioStepCapture capture)? scenarioRunListener;

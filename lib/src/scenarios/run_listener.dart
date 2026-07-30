import 'dart:typed_data';

/// One captured step, handed from [ScenarioTester]'s capture to whoever is
/// listening — the harness, when a scenario runs under the flutterware runner.
class ScenarioStepCapture {
  ScenarioStepCapture({
    required this.index,
    required this.name,
    required this.tags,
    required this.png,
    required this.texts,
  });

  /// 1-based position in the scenario's capture sequence.
  final int index;

  /// The [Shot]'s name, or null for an automatic capture.
  final String? name;

  final List<String> tags;
  final Uint8List png;

  /// The visible `Text` widgets, in tree order — the text projection.
  final List<String> texts;
}

/// Set by the flutterware harness for the duration of one scenario run; null
/// under a bare `flutter test`, where captures go to
/// `SCREENSHOTS_DESTINATION` instead (or nowhere).
///
/// Deliberately not exported from `package:flutterware/flutter_test.dart` —
/// it is the seam between the authoring API and the runner, not part of the
/// authoring API.
void Function(ScenarioStepCapture capture)? scenarioRunListener;

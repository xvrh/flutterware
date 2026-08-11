import 'dart:typed_data';

import 'events.dart';

/// One captured step, handed from [ScenarioTester]'s capture to whoever is
/// listening — the harness, when a scenario runs under the flutterware
/// runner.
class ScenarioStepCapture {
  ScenarioStepCapture({
    required this.index,
    required this.parent,
    required this.branch,
    required this.name,
    required this.tags,
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
    required this.texts,
    required this.statusBrightness,
    required this.navBrightness,
    this.verb,
    this.target,
    this.events = const [],
    this.eventsDropped = 0,
    this.settled = true,
    this.strayFrames = 0,
    this.failure,
  });

  /// 1-based position in the scenario's capture sequence.
  final int index;

  /// The [index] of the step this one follows, or null for the first. A
  /// linear scenario chains; a `split` gives one parent several children —
  /// the flow graph's edges, exactly.
  final int? parent;

  /// The `split` branch label when this is a branch's first capture; null
  /// everywhere else.
  final String? branch;

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

  /// The verb that produced this step (`tap`, `enterText`, `screen`, …) and
  /// what it was aimed at, when it was aimed at anything. Together they say
  /// what the transition *into* this step was, which is what turns an edge in
  /// the flow from an arrow into a sentence.
  final String? verb;
  final String? target;

  /// What the app did on the way here: everything recorded between the
  /// previous capture and this one, in the order it happened.
  final List<ScenarioEvent> events;

  /// Events dropped to stay inside the per-step or per-run cap. Reported
  /// rather than swallowed — silence would read as "the app did nothing".
  final int eventsDropped;

  /// The app's declared `SystemUiOverlayStyle` icon brightness at capture
  /// time (`light`/`dark`), or null when it never declared one. What the
  /// GUI's fake status bar and home indicator tint themselves with — wrong
  /// status-bar brightness is a shipped bug a screenshot exists to catch.
  final String? statusBrightness;
  final String? navBrightness;

  /// False when the verb's settle policy gave up with frames still scheduled
  /// — an indefinite animation on screen, which is worth seeing rather than
  /// failing on.
  final bool settled;

  /// Frames drawn between the previous step and this one that no verb drew —
  /// so they came from the raw `tester`, and whatever they showed is missing
  /// from the flow. Zero in a scenario written in verbs alone.
  final int strayFrames;

  /// Set on the one step a scenario captures when it breaks: the error, with
  /// its split branch. The frame is the state at the failure.
  final String? failure;
}

/// Set by the flutterware harness for the duration of one scenario run; null
/// under a bare `flutter test`, where captures go to
/// `SCREENSHOTS_DESTINATION` instead (or nowhere).
///
/// Deliberately not exported from `package:flutterware/flutter_test.dart` —
/// it is the seam between the authoring API and the runner, not part of the
/// authoring API.
void Function(ScenarioStepCapture capture)? scenarioRunListener;

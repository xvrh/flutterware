import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../plugins/native/scenarios_results.dart';
import '../utils/raw_image_provider.dart';

/// Where a step's captured artifacts are read from.
///
/// The harness writes five things per step — the frame, the widget tree, the
/// semantics tree, the events, and the texts (which ride in the report). Four
/// of them are files, and *whose* files they are is the only thing that
/// differs between the two places these widgets run: the panel opens a
/// worktree off disk, the exported page fetches them from the server it was
/// loaded from. Everything above this interface is the same code.
///
/// Absence is a null, never an exception. A run whose artifacts have been
/// moved or deleted must still open — the step page says the file is gone,
/// which is a better answer than a red screen.
abstract class ScenarioArtifacts {
  const ScenarioArtifacts();

  /// The bytes at [path], as the report spells it, or null when there is
  /// nothing there.
  Future<Uint8List?> readBytes(String path);

  /// The text at [path], or null when there is nothing there.
  Future<String?> readString(String path);

  /// Where [path] lives, for handing to whatever opens files here: the
  /// desktop's own file association in the panel, a download in an exported
  /// page. Both are `launchUrl`'s job; only the scheme differs.
  ///
  /// The one artifact this is for is a document step's payload — a step's
  /// other files are read and rendered in place, where a PDF or a payload is a
  /// thing you open elsewhere.
  Uri uriOf(String path);

  /// A provider for an already-encoded image — the PNG case, where the
  /// framework's own decoding and caching are worth going through rather than
  /// around.
  ImageProvider encodedImage(String path);

  /// The step's captured frame, decoded according to its format.
  ///
  /// `raw` captures are rgba8888 rows with no header, so they carry their
  /// dimensions from the report and skip decoding entirely — the fast lane the
  /// runner offers hosts that can display pixels directly.
  ///
  /// For a [ScenarioStepKind.screen] only. A step of any other kind has no
  /// frame of its own; resolve it through [scenarioFrameFor] first, which is
  /// what every caller here does.
  ImageProvider imageOf(ScenarioRunStep step) =>
      _decoded(step.image!, step.format!, step.width!, step.height!);

  /// One frame of a step's recorded transition.
  ///
  /// Its own size, not the step's: a recording runs at half scale and the shot
  /// beside it does not.
  ImageProvider frameImageOf(ScenarioRunStep step, String path) => _decoded(
    path,
    step.format ?? 'png',
    step.frameWidth ?? 0,
    step.frameHeight ?? 0,
  );

  ImageProvider _decoded(String path, String format, int width, int height) =>
      format == 'raw'
      ? RawImageProvider(
          RawImageData(
            path,
            () async => await readBytes(path) ?? Uint8List(0),
            width,
            height,
          ),
        )
      : encodedImage(path);
}

/// The source the widgets below read through.
///
/// Required rather than defaulted: the two implementations differ in which
/// `dart:` library they need, and a widget that guessed would be a widget that
/// compiles for the web and then reaches for a filesystem at run time.
class ScenarioArtifactsScope extends InheritedWidget {
  const ScenarioArtifactsScope({
    super.key,
    required this.artifacts,
    required super.child,
  });

  final ScenarioArtifacts artifacts;

  static ScenarioArtifacts of(BuildContext context) {
    var scope = context
        .dependOnInheritedWidgetOfExactType<ScenarioArtifactsScope>();
    assert(
      scope != null,
      'No ScenarioArtifactsScope above this widget. The panel installs a '
      'file-backed one and the exported page an HTTP-backed one; a scenario '
      'view outside both has no way to read a step.',
    );
    return scope!.artifacts;
  }

  @override
  bool updateShouldNotify(ScenarioArtifactsScope oldWidget) =>
      oldWidget.artifacts != artifacts;
}

/// The frame a step is drawn on.
///
/// Itself for a screen. For a beat that has none — a document, a notification —
/// the nearest screen before it, which is what was on the device when it
/// happened: a banner goes over the screen it landed on, and a document sheet
/// is drawn on that screen's canvas so it scales with the shots beside it.
///
/// Null when nothing has been drawn yet, which a viewer shows as a locked
/// phone rather than inventing a screen.
ScenarioRunStep? scenarioFrameFor(
  List<ScenarioRunStep> steps,
  ScenarioRunStep step,
) {
  if (step.image != null) return step;
  // Backwards along the chain the run recorded, and by list order where it
  // recorded no parents — the same pair of answers every walk over these has.
  var byIndex = {for (var candidate in steps) candidate.index: candidate};
  var current = step;
  while (true) {
    var parent = current.parent;
    var next = parent == null ? null : byIndex[parent];
    if (next == null) break;
    if (next.image != null) return next;
    current = next;
  }
  if (steps.any((s) => s.parent != null)) return null;
  for (var i = steps.indexOf(step) - 1; i >= 0; i--) {
    if (steps[i].image != null) return steps[i];
  }
  return null;
}

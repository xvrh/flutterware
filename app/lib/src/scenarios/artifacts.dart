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
  /// The one artifact this is for is an attachment — a step's other files are
  /// read and rendered in place, where a PDF or a payload is a thing you open
  /// elsewhere.
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
  ImageProvider imageOf(ScenarioRunStep step) =>
      _decoded(step.image, step.format, step.width, step.height);

  /// One frame of a step's recorded transition.
  ///
  /// Its own size, not the step's: a recording runs at half scale and the shot
  /// beside it does not.
  ImageProvider frameImageOf(ScenarioRunStep step, String path) =>
      _decoded(path, step.format, step.frameWidth ?? 0, step.frameHeight ?? 0);

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

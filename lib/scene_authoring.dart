/// The scene/motion authoring core — the vocabulary a generated `.scene.dart`
/// is built from, plus the pure document models and the motion runtime that
/// evaluates them.
///
/// This library is pure Dart by decision (see
/// `docs/superpowers/specs/2026-09-01-scene-graduation-plan.md`): a plain
/// `dart` process — the `fw` CLI, the MCP server, a codemod — can import it
/// and parse, edit, emit and evaluate without a Flutter engine. A test
/// guards the import graph. The Flutter half (players, widget bridges)
/// lives in `package:flutterware/scene.dart`.
///
/// Spike-grade surface: graduated from the canvas-toy spike 2026-09-01 and
/// still moving with the editor; not yet a supported consumer API.
library;

export 'src/scene/core/curves.dart';
export 'src/scene/core/json.dart';
export 'src/scene/core/kind.dart';
export 'src/scene/core/listenable.dart';
export 'src/scene/core/model.dart';
export 'src/scene/core/motion_model.dart';
export 'src/scene/core/motion_runtime.dart';
export 'src/scene/core/props.dart';
export 'src/scene/core/stops.dart';
export 'src/scene/core/values.dart';
export 'src/scene/core/view3d.dart';

/// The Flutter half of the scene system: motion playback and the bridges
/// between the pure authoring core (`package:flutterware/scene_authoring.dart`)
/// and Flutter's types.
///
/// By decision (2026-09-01-scene-graduation-plan.md) this user-facing
/// library will never export the authoring vocabulary — a file that imports
/// it next to `material.dart` must never collide.
///
/// Spike-grade surface: graduated from the canvas-toy spike 2026-09-01 and
/// still moving with the editor; not yet a supported consumer API.
library;

export 'src/scene/flutter_bridge.dart';
export 'src/scene/host.dart';
export 'src/scene/layered_text.dart';
export 'src/scene/player.dart';
export 'src/scene/view.dart';

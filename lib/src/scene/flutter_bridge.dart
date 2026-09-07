// Where the pure scene core meets Flutter: value conversions, listenable
// adapters, and the frame-aligned fx flush. Every enum conversion is by
// index, and `scene_bridge_test.dart` (app package) pins each core order to
// Flutter's so a reorder on either side fails a test instead of a render.
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'core/listenable.dart';
import 'core/values.dart';

extension SceneColorToFlutter on SceneColor {
  Color get flutter => Color(argb);
}

extension FlutterColorToScene on Color {
  SceneColor get scene => SceneColor(toARGB32());
}

extension SceneFontWeightToFlutter on SceneFontWeight {
  FontWeight get flutter => FontWeight.values[index];
}

/// The app's colour as the scene core spells it — what the generated
/// `SceneTokens` getter for a `Color` export returns, and what the guest
/// puts on a property bound to one.
SceneColor sceneColorOf(Color color) => color.scene;

/// The properties of the app's text style the table knows — size, weight
/// and colour. The rest (family, letter spacing, height) is the app's to
/// draw: the guest renders with the app's own `TextStyle` underneath, so
/// nothing is lost on the canvas, only unnamed in the editor.
SceneTextStyle sceneTextStyleOf(TextStyle style) => SceneTextStyle(
  fontSize: style.fontSize,
  weight: style.fontWeight == null
      ? null
      : SceneFontWeight.values[FontWeight.values.indexOf(style.fontWeight!)],
  color: style.color?.scene,
);

extension SceneTextAlignToFlutter on SceneTextAlign {
  TextAlign get flutter => TextAlign.values[index];
}

extension SceneEdgesToFlutter on SceneEdges {
  EdgeInsets get flutter => EdgeInsets.fromLTRB(left, top, right, bottom);
}

extension SceneCornersToFlutter on SceneCorners {
  BorderRadius get flutter => BorderRadius.only(
    topLeft: Radius.circular(topLeft),
    topRight: Radius.circular(topRight),
    bottomRight: Radius.circular(bottomRight),
    bottomLeft: Radius.circular(bottomLeft),
  );
}

extension SceneCrossAxisAlignmentToFlutter on SceneCrossAxisAlignment {
  CrossAxisAlignment get flutter => CrossAxisAlignment.values[index];
}

extension SceneMainAxisAlignmentToFlutter on SceneMainAxisAlignment {
  MainAxisAlignment get flutter => MainAxisAlignment.values[index];
}

extension SceneRectToFlutter on SceneRect {
  Rect get flutter => Rect.fromLTWH(left, top, width, height);
}

extension FlutterRectToScene on Rect {
  SceneRect get scene => SceneRect(left, top, width, height);
}

/// Route the core's coalesced fx flush through the frame: post-frame
/// callback + ensureVisualUpdate, the probed 500-writes-to-1-rebuild shape
/// that also wakes a hidden or idle window. Idempotent; every Flutter
/// process that hosts scene documents installs it once at startup.
void installSceneFrameFlush() {
  sceneFlushScheduler = (flush) {
    SchedulerBinding.instance.addPostFrameCallback((_) => flush());
    SchedulerBinding.instance.ensureVisualUpdate();
  };
}

final _adapters = Expando<_SceneListenableAdapter>();

extension SceneListenableToFlutter on SceneListenable {
  /// A Flutter [Listenable] view of this core listenable, cached per
  /// instance — hand it to AnimatedBuilder and friends.
  Listenable get listenable =>
      _adapters[this] ??= _SceneListenableAdapter(this);
}

class _SceneListenableAdapter extends ChangeNotifier {
  _SceneListenableAdapter(SceneListenable source) {
    source.addListener(notifyListeners);
  }
}

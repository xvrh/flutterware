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

extension SceneTextAlignToFlutter on SceneTextAlign {
  TextAlign get flutter => TextAlign.values[index];
}

extension SceneEdgesToFlutter on SceneEdges {
  EdgeInsets get flutter => EdgeInsets.fromLTRB(left, top, right, bottom);
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

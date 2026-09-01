// The core's own change notification — ~15 lines where Flutter's
// ChangeNotifier would drag dart:ui into the pure import graph. The Flutter
// bridge adapts these to real Listenables for AnimatedBuilder and friends.
import 'dart:async';

class SceneListenable {
  final _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void notifyListeners() {
    for (var listener in List.of(_listeners)) {
      listener();
    }
  }
}

class SceneValue<T> extends SceneListenable {
  SceneValue(this._value);

  T _value;

  T get value => _value;

  set value(T next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }
}

/// How a batch of fx writes schedules its coalesced flush. The default
/// coalesces on a microtask — right for a headless process, where nothing
/// frames. A Flutter process installs the frame-aligned one (post-frame
/// callback + ensureVisualUpdate, the probed 500-writes-to-1-rebuild shape)
/// via the bridge's [installSceneFrameFlush].
void Function(void Function() flush) sceneFlushScheduler = (flush) {
  scheduleMicrotask(flush);
};

// The Flutter half of the motion runtime: the applicator with a clock.
// Everything time-shaped is in the pure core (seek is `apply(t)`); this
// file owns only the Ticker.
import 'package:flutter/scheduler.dart';

import 'core/motion_runtime.dart';

enum MotionPlayerStatus { idle, playing, paused, completed }

/// The applicator with a clock: seek is pure (`apply(t)`, any direction),
/// play owns a ticker (a raw one anywhere, a vsync-muted one when a
/// [TickerProvider] is given), pause keeps the picture, stop is cancel —
/// the fx drops and the authored values were never touched. A non-looping
/// player stops itself at the end, so a completed player holds no frame
/// callbacks and forgetting to dispose it is harmless; dispose matters
/// exactly while it might still be playing.
class MotionPlayer {
  MotionPlayer(this.playable, {TickerProvider? vsync}) {
    _ticker = vsync?.createTicker(_tick) ?? Ticker(_tick);
  }

  final Playable playable;
  late final Ticker _ticker;

  var status = MotionPlayerStatus.idle;
  var _position = Duration.zero;
  var _lastElapsed = Duration.zero;

  /// Tempo lives here, never in the file. Takes effect from the next tick.
  double rate = 1;

  Duration get position => _position;

  void play() {
    if (status == MotionPlayerStatus.playing) return;
    playable.claimDriver(this);
    if (_position >= playable.duration) _position = Duration.zero;
    _lastElapsed = Duration.zero;
    status = MotionPlayerStatus.playing;
    _ticker.start();
  }

  void pause() {
    if (status != MotionPlayerStatus.playing) return;
    _ticker.stop();
    status = MotionPlayerStatus.paused;
  }

  /// Pure: always legal, any direction, any state. Does not start a clock.
  void seek(Duration t) {
    _position = t < Duration.zero
        ? Duration.zero
        : (t > playable.duration ? playable.duration : t);
    playable.apply(_position);
  }

  /// Cancel: the fx drops, the base was never touched.
  void stop() {
    _ticker.stop();
    playable.clearFx();
    playable.releaseDriver(this);
    _position = Duration.zero;
    status = MotionPlayerStatus.idle;
  }

  void dispose() {
    stop();
    _ticker.dispose();
  }

  void _tick(Duration elapsed) {
    var delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    _position += delta * rate;
    if (_position >= playable.duration) {
      _position = playable.duration;
      playable.apply(_position);
      _ticker.stop();
      playable.releaseDriver(this);
      status = MotionPlayerStatus.completed;
      return;
    }
    playable.apply(_position);
  }
}

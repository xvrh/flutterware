// The Flutter half of the motion runtime: the applicator with a clock.
// Everything time-shaped is in the pure core (a seek is `apply(t)`); this
// file owns only the Ticker, and the vocabulary is the one every comparable
// player already uses — AnimationController's, the Web Animations API's.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'core/motion_model.dart';
import 'core/motion_runtime.dart';

enum MotionPlayerStatus { idle, playing, paused, completed }

/// A motion, with a clock.
///
/// Seeking is pure and always legal — assign [position] or [progress], in
/// any direction, from any state, without starting anything. Playing owns a
/// ticker: [play] runs to the end, [reverse] runs back to zero, [repeat]
/// keeps going. [pause] keeps the picture, [finish] jumps to the end pose
/// and holds it, and [stop] is cancel — the fx drops, the authored values
/// were never touched, and scene time is back at zero.
///
/// A [ChangeNotifier], so `AnimatedBuilder(animation: player)` redraws a
/// scrubber or a play button. The SCENE needs none of that: applying a frame
/// writes into the document, which notifies whatever is drawing it.
///
/// A player that reached its end holds no frame callbacks, so forgetting to
/// dispose one is harmless; dispose matters exactly while it might still be
/// playing.
class MotionPlayer with ChangeNotifier {
  /// Plays a motion an app COMPILED — `MotionPlayer(BannerIntro(scene),
  /// vsync: this)`, which is the whole of starting one.
  MotionPlayer(SceneMotion motion, {required TickerProvider? vsync})
    : this.bound(motion.playable, vsync: vsync);

  /// Plays a motion already bound to its scene — the [BoundMotion] the
  /// editor makes from a file it read, or any playable tree.
  ///
  /// [vsync] is required and nullable, which is the point: passing null
  /// gives a ticker that runs whether or not anything is on screen, and
  /// that is a decision (a test, a headless walk) rather than something to
  /// leave out by accident. An app passes one — a player still ticking
  /// behind a pushed route is what a [TickerProvider] is for.
  MotionPlayer.bound(this.playable, {required TickerProvider? vsync}) {
    _ticker = vsync?.createTicker(_tick) ?? Ticker(_tick);
  }

  /// What plays. Replaced by [retarget] when the scene it animates is
  /// rebuilt under it — a theme flipped while an intro plays.
  Playable playable;

  /// Continues this playback on [next] — the same motion bound to a fresh
  /// instance of the scene, which is what a token set that changed calls
  /// for: `late final` read its tokens once, so a mode is a new instance,
  /// and the intro that was halfway through should be halfway through on
  /// the new one too. The playhead keeps its place and its direction; the
  /// old playable is released and left at the pose it had.
  void retarget(Playable next) {
    if (identical(next, playable)) return;
    var old = playable;
    old.releaseDriver(this);
    playable = next;
    if (isPlaying) next.claimDriver(this);
    next.apply(_position);
    notifyListeners();
  }

  late final Ticker _ticker;

  Duration get duration => playable.duration;

  MotionPlayerStatus _status = MotionPlayerStatus.idle;

  MotionPlayerStatus get status => _status;

  bool get isPlaying => _status == MotionPlayerStatus.playing;

  var _position = Duration.zero;
  var _lastElapsed = Duration.zero;

  /// Which way the clock runs. Direction is a VERB here ([play], [reverse])
  /// and never a sign on [rate]: a negative tempo used to run the playhead
  /// past zero into negative time and tick there forever, because the end
  /// it watched for was only the far one.
  var _forward = true;

  /// Traversals left, or null for as long as nobody stops it.
  int? _remaining = 0;
  var _yoyo = false;

  Completer<void>? _finished;

  double _rate = 1;

  /// Tempo. Takes effect from the next tick.
  double get rate => _rate;

  set rate(double value) {
    assert(
      value > 0,
      'rate is tempo, not direction — reverse() runs backwards',
    );
    _rate = value.abs();
    notifyListeners();
  }

  /// Where the playhead is. Assigning parks it there and draws that moment:
  /// pure, any state, any direction, and it starts no clock. Past the end is
  /// legal and holds the end pose — an editor needs the playhead beyond the
  /// last key to put the next one there.
  Duration get position => _position;

  set position(Duration t) {
    _position = t < Duration.zero ? Duration.zero : t;
    playable.apply(_position);
    notifyListeners();
  }

  /// The same, as a fraction of [duration] — what a scrubber binds to.
  double get progress {
    var total = duration.inMicroseconds;
    return total == 0 ? 0 : (_position.inMicroseconds / total).clamp(0.0, 1.0);
  }

  set progress(double value) => position = duration * value.clamp(0.0, 1.0);

  /// Completes when the current playback ends, HOWEVER it ends — running out
  /// of timeline, [finish], or [stop]. Ask [status] which.
  ///
  /// A property rather than something [play] returns, so several things can
  /// await one playback, and so awaiting a player that is not playing is
  /// simply an answer rather than a hang.
  Future<void> get finished => isPlaying || _status == MotionPlayerStatus.paused
      ? (_finished ??= Completer<void>()).future
      : Future.value();

  /// Runs forward to the end. Resumes instead when paused, so a repeat
  /// survives a pause.
  void play() {
    if (_status == MotionPlayerStatus.paused) return resume();
    _run(forward: true);
  }

  /// Runs backward to zero, from wherever the playhead is.
  void reverse() => _run(forward: false);

  /// Runs [times] traversals of the timeline, or forever when null.
  ///
  /// [yoyo] turns around at each end instead of jumping back, so a there-
  /// and-back is `repeat(times: 2, yoyo: true)`. A traversal is one crossing
  /// of the timeline, which is what makes those two numbers the same number.
  void repeat({int? times, bool yoyo = false}) =>
      _run(forward: true, times: times, yoyo: yoyo);

  void _run({required bool forward, int? times = 1, bool yoyo = false}) {
    if (isPlaying &&
        _forward == forward &&
        _remaining == times &&
        _yoyo == yoyo) {
      return;
    }
    playable.claimDriver(this);
    _forward = forward;
    _remaining = times;
    _yoyo = yoyo;
    // Sitting at the far end already means there is nothing to play, so a
    // fresh run rewinds to the end it is travelling from.
    if (forward && _position >= duration) _position = Duration.zero;
    if (!forward && _position <= Duration.zero) _position = duration;
    _lastElapsed = Duration.zero;
    _status = MotionPlayerStatus.playing;
    // The pose it is about to play FROM, now rather than on the first tick.
    // A ticker's first callback is a frame away, so a motion that opens on
    // opacity 0 used to draw one frame of the authored scene first — the
    // flash of a finished thing before it starts.
    playable.apply(_position);
    _ticker.start();
    notifyListeners();
  }

  void pause() {
    if (!isPlaying) return;
    _ticker.stop();
    _status = MotionPlayerStatus.paused;
    notifyListeners();
  }

  void resume() {
    if (_status != MotionPlayerStatus.paused) return;
    _lastElapsed = Duration.zero;
    _status = MotionPlayerStatus.playing;
    _ticker.start();
    notifyListeners();
  }

  /// Jump to the end pose and hold it — what [stop] is not: the fx stays.
  void finish() {
    _position = _forward ? duration : Duration.zero;
    playable.apply(_position);
    _end(MotionPlayerStatus.completed);
  }

  /// Cancel: the fx drops, the base was never touched, and the clock is at
  /// zero again — nothing plays, so a shader pass drawn by the clock shows
  /// the authored moment too.
  void stop() {
    playable
      ..clearFx()
      ..clock.value = Duration.zero;
    _position = Duration.zero;
    _remaining = 0;
    _end(MotionPlayerStatus.idle);
  }

  @override
  void dispose() {
    _ticker
      ..stop()
      ..dispose();
    playable
      ..clearFx()
      ..clock.value = Duration.zero
      ..releaseDriver(this);
    _status = MotionPlayerStatus.idle;
    var pending = _finished;
    _finished = null;
    pending?.complete();
    super.dispose();
  }

  void _end(MotionPlayerStatus to) {
    _ticker.stop();
    playable.releaseDriver(this);
    _status = to;
    var pending = _finished;
    _finished = null;
    pending?.complete();
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    var delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    _position += delta * _rate * (_forward ? 1 : -1);

    var arrived = _forward ? _position >= duration : _position <= Duration.zero;
    if (!arrived) {
      playable.apply(_position);
      notifyListeners();
      return;
    }
    _position = _forward ? duration : Duration.zero;

    var left = _remaining == null ? null : _remaining! - 1;
    if (left != null && left <= 0) {
      _remaining = 0;
      playable.apply(_position);
      _end(MotionPlayerStatus.completed);
      return;
    }
    _remaining = left;
    if (_yoyo) {
      _forward = !_forward;
    } else {
      _position = _forward ? Duration.zero : duration;
    }
    playable.apply(_position);
    notifyListeners();
  }
}

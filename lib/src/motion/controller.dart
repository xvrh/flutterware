import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Where a motion's progress comes from.
enum MotionSource {
  /// A ticker the scope owns. `play`, `reverse` and `repeat` mean something.
  ticker,

  /// Somebody else's `Animation<double>` — a route transition, a scroll
  /// position, a drag. Transport is not ours to command.
  driven,
}

/// The playhead, and the only control input `MotionScope` takes.
///
/// Optional, and shaped like `TextEditingController`: pass one when you need to
/// drive the motion yourself, and the scope makes and disposes its own when you
/// do not. Progress lives here rather than in the scope's state so it is always
/// well defined — a controller you are holding never has to be asked whether it
/// is attached before it can be read.
///
/// The **scope owns the ticker**, not this. That keeps a controller free of
/// `vsync:` ceremony, and it is what makes `TickerMode` work — a motion on a
/// route that is no longer current stops costing frames without anybody
/// remembering to arrange it. The cost is that transport called before the
/// scope mounts has nothing to tick; that is buffered rather than thrown, which
/// removes the `initState`-ordering trap the ceremony-free version would
/// otherwise have.
class MotionController extends ChangeNotifier {
  MotionController({double progress = 0, this.autoplay = true})
    : source = MotionSource.ticker,
      _driver = null,
      _progress = progress.clamp(0.0, 1.0);

  /// Progress comes from [progress]. Transport methods are no-ops, because the
  /// thing driving this is not ours to command.
  MotionController.driven(Animation<double> progress)
    : source = MotionSource.driven,
      autoplay = false,
      _driver = progress,
      _progress = progress.value.clamp(0.0, 1.0);

  final MotionSource source;

  /// Whether the scope starts playing as soon as it mounts. The common case is
  /// an entrance, so this is on.
  final bool autoplay;

  final Animation<double>? _driver;

  double _progress;
  AnimationController? _inner;
  _Pending? _pending;
  var _disposed = false;

  /// 0 at the start of the motion, 1 at its end.
  double get progress => _progress;

  set progress(double value) {
    var next = value.clamp(0.0, 1.0);
    if (_inner != null) {
      _inner!.value = next;
      return; // The listener writes `_progress` and notifies.
    }
    if (next == _progress) return;
    _progress = next;
    notifyListeners();
  }

  /// The playhead as a duration, once the scope has told us how long the
  /// motion is. Zero before then.
  Duration get position => _duration * _progress;
  set position(Duration value) {
    var total = _duration.inMicroseconds;
    progress = total == 0 ? 0 : value.inMicroseconds / total;
  }

  Duration _duration = Duration.zero;

  AnimationStatus get status => _inner?.status ?? AnimationStatus.dismissed;

  bool get isAnimating => _inner?.isAnimating ?? false;

  /// Whether a scope is mounted and ticking this.
  bool get isAttached => _inner != null;

  void play({bool restart = false}) => _transport(_Pending.forward(restart));

  void reverse() => _transport(const _Pending(_Verb.reverse));

  void repeat({bool reverse = false}) =>
      _transport(_Pending(_Verb.repeat, reverse: reverse));

  void stop() => _transport(const _Pending(_Verb.stop));

  void _transport(_Pending intent) {
    if (source == MotionSource.driven) {
      assert(() {
        throw FlutterError(
          'A MotionController.driven takes its progress from an '
          'Animation<double>. Command that animation instead.',
        );
      }());
      return;
    }
    var inner = _inner;
    if (inner == null) {
      // Buffered rather than thrown: `myMotion.play()` in `initState` runs
      // before the scope below it mounts, and that ordering should not be
      // something anybody has to know about.
      _pending = intent;
      return;
    }
    intent.applyTo(inner);
  }

  // --- what MotionScope drives. Not public API. ---

  void attach(TickerProvider vsync, Duration duration) {
    assert(
      _inner == null,
      'This MotionController is already attached to a '
      'MotionScope. One controller drives one scope.',
    );
    _duration = duration;
    if (source == MotionSource.driven) {
      _driver!.addListener(_readDriver);
      _readDriver();
      return;
    }
    var inner = _inner = AnimationController(
      vsync: vsync,
      duration: duration,
      value: _progress,
    )..addListener(_readInner);
    var pending = _pending;
    _pending = null;
    if (pending != null) {
      pending.applyTo(inner);
    } else if (autoplay) {
      inner.forward();
    }
  }

  void updateDuration(Duration duration) {
    _duration = duration;
    _inner?.duration = duration;
  }

  void detach() {
    if (source == MotionSource.driven) {
      _driver!.removeListener(_readDriver);
      return;
    }
    var inner = _inner;
    _inner = null;
    inner?.removeListener(_readInner);
    inner?.dispose();
  }

  void _readInner() {
    _progress = _inner!.value;
    if (!_disposed) notifyListeners();
  }

  void _readDriver() {
    var next = _driver!.value.clamp(0.0, 1.0);
    if (next == _progress) return;
    _progress = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    detach();
    super.dispose();
  }
}

enum _Verb { forward, reverse, repeat, stop }

class _Pending {
  const _Pending(this.verb, {this.reverse = false}) : restart = false;

  const _Pending.forward(this.restart) : verb = _Verb.forward, reverse = false;

  final _Verb verb;
  final bool reverse;
  final bool restart;

  void applyTo(AnimationController inner) {
    switch (verb) {
      case _Verb.forward:
        inner.forward(from: restart || inner.value >= 1 ? 0 : null);
      case _Verb.reverse:
        inner.reverse();
      case _Verb.repeat:
        inner.repeat(reverse: reverse);
      case _Verb.stop:
        inner.stop();
    }
  }
}

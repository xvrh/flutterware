import 'package:flutter_test/flutter_test.dart';

import 'motion.dart';

/// The interval `pumpAndSettle` itself advances the clock by, kept the same so
/// a scenario's frames land where a hand-written test's would.
const _frameInterval = Duration(milliseconds: 100);

/// How a scenario verb waits for the app to be done before it captures.
///
/// Every verb — `pumpWidget`, `tap`, `enterText`, `screen` — applies the same
/// policy, because which verb settles and which does not is exactly the
/// knowledge the high-level API exists to remove. Set it per scenario
/// (`scenario('…', settle: …)`) and override it per call
/// (`s.tap(target, settle: Settle.none)`).
///
/// The default is [Settle.standard], and it is *bounded* on purpose:
/// `pumpAndSettle` never converges on a screen holding an indefinite animation
/// — a spinner, a shimmer, a looping Lottie — and throws
/// `pumpAndSettle timed out` when its ten fake minutes run out. A loading
/// spinner is the first thing most apps show, so the default must survive one:
/// it gives up quietly, captures the frame, and records `settled: false` on
/// the step. Use [Settle.full] where a screen that never settles should be an
/// error.
///
/// This is also the one place a run records **motion**: a policy that owns its
/// pump loop hands every frame to the [ScenarioMotionRecorder] a run passes,
/// and pumps at that recorder's finer interval while it does. One seam, and
/// no verb had to learn anything.
sealed class Settle {
  const Settle();

  /// The default: pump until nothing more is scheduled or five seconds of the
  /// fake clock are spent, whichever comes first. Fifty frames, instant in
  /// wall time.
  static const standard = Settle.upTo(Duration(seconds: 5));

  /// Pump until nothing more is scheduled or [budget] of the fake clock is
  /// spent. Running out is not a failure — it is recorded on the step.
  const factory Settle.upTo(Duration budget) = _Budgeted;

  /// One frame, no clock advance — for a capture that must show the app
  /// mid-transition, or after work the scenario already pumped itself.
  static const none = _None();

  /// [count] frames of [interval] each, whatever is still scheduled at the
  /// end — how to capture a fixed way into an animation.
  const factory Settle.frames(int count, {Duration interval}) = _Frames;

  /// `pumpAndSettle`'s own semantics, ten-minute timeout and throw included.
  ///
  /// The one policy that records no motion: `pumpAndSettle` is the SDK's loop
  /// and offers no per-frame hook, and reimplementing it here to get one would
  /// be trading the exact semantics this policy exists to provide for a
  /// nicety.
  static const full = _Full();

  /// Applies the policy. False when the app was still scheduling frames when
  /// the policy gave up — the step is captured either way.
  ///
  /// [record], when a run is recording, receives the frame after every pump —
  /// and, where the policy chooses its own interval, dictates it.
  Future<bool> apply(WidgetTester tester, {ScenarioMotionRecorder? record});
}

class _Budgeted extends Settle {
  const _Budgeted(this.budget);

  final Duration budget;

  @override
  Future<bool> apply(
    WidgetTester tester, {
    ScenarioMotionRecorder? record,
  }) async {
    // Our own loop rather than `pumpAndSettle(timeout:)`: the SDK's version
    // *throws* when the budget runs out, and the whole point here is to carry
    // on and capture what the screen looks like.
    //
    // A recording subdivides the step — 30fps instead of 10 — and the budget
    // stays in fake *time*, so both cadences give up at the same instant and
    // land on the same settled frame. Measured byte-identical; that is what
    // lets a recorded run be diffed against one captured without recording.
    var interval = record?.interval ?? _frameInterval;
    var elapsed = Duration.zero;
    do {
      await tester.pump(interval);
      elapsed += interval;
      record?.capture(tester);
    } while (tester.binding.hasScheduledFrame && elapsed < budget);
    return !tester.binding.hasScheduledFrame;
  }
}

class _None extends Settle {
  const _None();

  @override
  Future<bool> apply(
    WidgetTester tester, {
    ScenarioMotionRecorder? record,
  }) async {
    await tester.pump();
    record?.capture(tester);
    return !tester.binding.hasScheduledFrame;
  }
}

class _Frames extends Settle {
  const _Frames(this.count, {this.interval = _frameInterval});

  final int count;
  final Duration interval;

  @override
  Future<bool> apply(
    WidgetTester tester, {
    ScenarioMotionRecorder? record,
  }) async {
    // [interval] is the author's, not the recorder's: `Settle.frames(3)` says
    // where in the animation to land, and a recording may not move it.
    for (var i = 0; i < count; i++) {
      await tester.pump(interval);
      record?.capture(tester);
    }
    return !tester.binding.hasScheduledFrame;
  }
}

class _Full extends Settle {
  const _Full();

  @override
  Future<bool> apply(
    WidgetTester tester, {
    ScenarioMotionRecorder? record,
  }) async {
    await tester.pumpAndSettle();
    return true;
  }
}

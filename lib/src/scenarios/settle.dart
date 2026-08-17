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
/// **Frames are all a policy can follow, and a scenario needs one more thing.**
/// Work that resolves on the *real* event loop — an asset read from the engine,
/// and the `vector_graphics`, Lottie or `ImageProvider` decode on the other end
/// of it — schedules no frame while it is in flight, so no policy here can wait
/// for it: `upTo` and `frames` see a quiet tree and `elapse` advances a clock
/// that real work does not read. Landing that work is a separate step a verb
/// takes after this one, deliberately not a policy: it is not a choice an
/// author makes, and a policy applied by hand through [apply] — as a plain
/// widget test does — should keep meaning exactly what it says.
///
/// This is also the one place a run records **motion**: a policy that owns its
/// pump loop hands every frame to the [ScenarioMotionRecorder] a run passes,
/// and pumps at that recorder's finer interval while it does. One seam, and
/// no verb had to learn anything.
sealed class Settle {
  const Settle();

  /// The default: pump while the app keeps asking for frames, up to five
  /// seconds of the fake clock. Fifty frames at the ceiling, instant in wall
  /// time.
  static const standard = Settle.upTo(Duration(seconds: 5));

  /// Pump while the app keeps asking for frames, stopping at the first frame
  /// it does not — or when [budget] of the fake clock is spent, whichever
  /// comes first. Running out is not a failure — it is recorded on the step.
  ///
  /// **The budget is a ceiling, not a wait.** Frames are the only thing this
  /// loop follows, and work waiting on a timer schedules none: a screen whose
  /// `Future.delayed(Duration(seconds: 1))` has not completed looks exactly
  /// like a screen that is finished, so the loop returns at the first quiet
  /// frame — 100ms in — with the second still on the clock, and the tree is
  /// disposed under it. That is `pumpAndSettle`'s contract too, and a caller
  /// that means to wait for a timer has to say so: [Settle.elapse], or a
  /// [Settle.frames] count that covers it.
  const factory Settle.upTo(Duration budget) = _Budgeted;

  /// Spend the whole of [budget] on the fake clock, whatever the frame loop is
  /// doing — the policy for work that waits on a timer rather than on frames.
  ///
  /// Where [Settle.upTo] asks the app whether to keep going, this one does not
  /// ask: it advances the clock, so a timer due inside [budget] fires and
  /// whatever it wakes gets its frames. Pumping past a quiet screen is close to
  /// free — a pump with nothing due builds nothing — so the cost is not the
  /// frames.
  ///
  /// The cost is that the clock really does move. A snackbar that
  /// auto-dismisses at four seconds is gone by the end of a five-second
  /// budget, and a screen captured after this policy is the screen as it stands
  /// at `budget`, not as it stood when it stopped changing. Which is why it is
  /// not the default: reach for it where the question is *does this work at
  /// all* rather than *what does it look like now*.
  const factory Settle.elapse(Duration budget) = _Elapsed;

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
  /// True says that and only that: no frame was scheduled. It is not a claim
  /// that the app has nothing left to do, because a pending timer is invisible
  /// from here — as it is to `pumpAndSettle`.
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

class _Elapsed extends Settle {
  const _Elapsed(this.budget);

  final Duration budget;

  @override
  Future<bool> apply(
    WidgetTester tester, {
    ScenarioMotionRecorder? record,
  }) async {
    // [_Budgeted]'s loop kept in the same shape on purpose — same interval,
    // same recorder cadence, same one guaranteed pump — so the only thing that
    // differs between the two policies is when they are allowed to stop.
    var interval = record?.interval ?? _frameInterval;
    var elapsed = Duration.zero;
    do {
      await tester.pump(interval);
      elapsed += interval;
      record?.capture(tester);
    } while (elapsed < budget);
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

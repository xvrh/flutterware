import 'dart:async';

import 'package:flutter/scheduler.dart';

import 'settle.dart';

/// How long a single frame may take before the wait stops believing one is
/// coming.
///
/// Not a frame budget — a stall detector. Anything on the far side of this is
/// not a slow frame, it is a window the platform has stopped driving. Two
/// seconds because the cost of being wrong is one extra pass round a loop that
/// is already waiting minutes, and the cost of being trigger-happy would be a
/// spin.
///
/// Overridable per call so a test can watch the loop survive a window that
/// never draws without waiting two real seconds per iteration to see it.
const _frameGrace = Duration(seconds: 2);

/// Waits until nothing in [registry] has been busy for [quiet], or [timeout]
/// elapses.
///
/// **A quiet period rather than a single idle reading.** The catalog goes
/// briefly idle between compiling an entry and reloading it into the guest, and
/// a capture that fired in that gap would photograph the previous entry with
/// every appearance of success. [quiet] has to outlast that hand-off; it does
/// not have to outlast a human.
///
/// Frames are pumped throughout, and that is not incidental: a settled tree
/// still has to *paint* before `toImage` has anything to copy, and an app
/// nobody is interacting with is not scheduling frames on its own. This is the
/// half of settling that needs Flutter, which is why it is not on
/// [SettleRegistry] itself — see the note there.
///
/// **[timeout] is enforced against the clock, not against the frame loop.** It
/// used to be checked only between iterations, while each iteration ended in a
/// bare `await endOfFrame` — which completes in a post-frame callback and
/// therefore never completes at all when the platform stops delivering vsync.
/// macOS stops delivering it for a window that is minimised or fully occluded,
/// so a capture behind another window did not time out after three minutes: it
/// waited for a frame that was never going to arrive, and `fw capture` waited
/// on it, and the deadline this function takes could not be consulted because
/// the `while` that consults it was never reached. A screenshot tool that hangs
/// when nobody is looking at the screen is the one failure mode it cannot have.
Future<SettleOutcome> waitForSettle(
  SettleRegistry registry, {
  Duration quiet = const Duration(milliseconds: 250),
  Duration timeout = const Duration(minutes: 3),
  Duration frameGrace = _frameGrace,
  void Function(List<String> waiting)? onWaiting,
}) async {
  var deadline = Stopwatch()..start();
  var quietFor = Stopwatch();
  while (deadline.elapsed < timeout) {
    if (registry.isIdle) {
      if (!quietFor.isRunning) quietFor.start();
      if (quietFor.elapsed >= quiet) {
        return (settled: true, waitingOn: <String>[]);
      }
    } else {
      onWaiting?.call(registry.waitingOn);
      quietFor
        ..stop()
        ..reset();
    }
    var remaining = timeout - deadline.elapsed;
    if (remaining <= Duration.zero) break;
    await _frame(remaining < frameGrace ? remaining : frameGrace);
  }
  return (settled: false, waitingOn: registry.waitingOn);
}

/// One frame, or [grace], whichever comes first.
///
/// Returning on the grace is not an error and says nothing about the frame: a
/// stalled window and a window that simply had nothing to draw look identical
/// from here. The caller re-checks its deadline either way, which is the whole
/// contract — this must never be the thing that waits forever.
Future<void> _frame(Duration grace) {
  var binding = SchedulerBinding.instance;
  binding.scheduleFrame();
  var stalled = Completer<void>();
  var timer = Timer(grace, () {
    if (!stalled.isCompleted) stalled.complete();
  });
  return Future.any([
    binding.endOfFrame,
    stalled.future,
  ]).whenComplete(timer.cancel);
}

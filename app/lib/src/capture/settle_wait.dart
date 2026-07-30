import 'package:flutter/scheduler.dart';

import 'settle.dart';

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
Future<SettleOutcome> waitForSettle(
  SettleRegistry registry, {
  Duration quiet = const Duration(milliseconds: 250),
  Duration timeout = const Duration(minutes: 3),
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
      quietFor
        ..stop()
        ..reset();
    }
    SchedulerBinding.instance.scheduleFrame();
    await SchedulerBinding.instance.endOfFrame;
  }
  return (settled: false, waitingOn: registry.waitingOn);
}

import 'package:flutter_test/flutter_test.dart';

import 'motion.dart';
import 'settle.dart';

/// How many turns of the real event loop a caller gives work that is still
/// landing — see [landRealWork].
///
/// Every turn nothing needs is paid for in full, because "nothing has landed
/// yet" and "nothing is coming" are the same observation. That is what sets the
/// number, and it was measured rather than picked: on the example scenario
/// suite a turn costs ~56µs, so the 41 of 48 steps with nothing pending paid
/// **678µs** each — against the ~48ms their capture costs — and the whole suite
/// paid **57ms of 2.29s**, 2.5%.
///
/// The other seven steps are what the ceiling is for. The deepest of them
/// needed **seven** turns before its frame appeared — an engine asset read is
/// the slow link, and `vector_graphics` then decodes, lays out and paints on
/// top of it — and none of the 48 left the loop with a frame still scheduled.
/// Twelve is that measured seven with room, at a cost of 280µs over eight.
const realWorkTurns = 12;

/// Lets work that resolves on the **real** event loop land, and be drawn,
/// before a tree under fake time is judged or photographed.
///
/// A [Settle] policy follows frames, and that is all any of them can do —
/// `upTo` stops at the first frame the app does not ask for, `frames` counts
/// them, `elapse` advances a clock that real work does not read. So a decode
/// running on the real event loop is invisible to every one of them: it
/// schedules no frame while it is in flight, the tree looks finished, and
/// whatever reads it next reads a frame the tree is about to replace.
/// `vector_graphics` is how this was found — a scenario's artwork appeared one
/// step late in every flow that photographs each screen as it arrives — but
/// nothing about it is specific to SVG. Lottie, a PDF or thumbnail renderer, an
/// `ImageProvider` decoding off the fake clock and a `FutureBuilder` on a real
/// future are the same shape, and none of them is in `ImageCache` for the
/// framework's own bookkeeping to notice.
///
/// **A turn of the real loop is the only detector there is.** Nothing exposes
/// "is real work pending", so this takes the turn and reads what it did: a
/// frame scheduled on a tree that was quiet before it can only have been
/// scheduled by work that just landed. Then it draws that frame with the
/// caller's own policy and looks again, because a decode arrives in links — a
/// read completes, the app builds, the build starts the next read — and only a
/// pump between turns lets the chain walk. `tester.runAsync` flushes the fake
/// microtask queue as it closes, which is why the continuation has run by the
/// time `hasScheduledFrame` is read here and has *not* run when it is read from
/// inside the turn.
///
/// Bounded by turns rather than by wall time on purpose: a count of event-loop
/// turns is the same number on a slow machine and a fast one, where a
/// millisecond budget is not. What it does not buy is work that needs real
/// *time* — an http call, a `Future.delayed` on the real clock — which no
/// number of turns reaches and which `s.runAsync` is the verb for.
///
/// Does nothing when [settled] is false: a screen holding an indefinite
/// animation has a frame scheduled for its own reasons, the detector cannot
/// tell that apart from work arriving, and settling it again per turn would
/// multiply the cost of exactly the screens that already cost the most. Such a
/// step is already marked `settled: false` — the same flag that says the
/// capture is of a moving picture now also says it may be of an unfinished one.
Future<bool> landRealWork(
  WidgetTester tester,
  Settle policy, {
  required bool settled,
  ScenarioMotionRecorder? record,
}) async {
  if (!settled) return false;
  for (var turn = 0; turn < realWorkTurns; turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    if (!tester.binding.hasScheduledFrame) continue;
    settled = await policy.apply(tester, record: record);
    if (!settled) return false;
  }
  return settled;
}

import 'dart:async';

import 'package:flutter/widgets.dart';

/// What a bounded wall-clock settle observed.
class LiveSettleResult {
  LiveSettleResult({
    required this.settled,
    required this.frames,
    required this.forcedFrames,
    required this.framesEnabled,
    required this.elapsed,
  });

  /// False means the budget ran out with work still pending — an infinite
  /// animation, a spinner. Reported, never thrown: the caller always gets its
  /// observation back.
  ///
  /// **It answers "is the app painting", which is not "is the screen ready".**
  /// The only things it can see are the ones below: a scheduled frame, a
  /// running ticker, an image being decoded. A `Future` waiting on the
  /// network, a file or an isolate schedules none of them, so a screen that
  /// has drawn its empty state and is still fetching settles immediately and
  /// truthfully — the app really has stopped painting. Whoever reads this
  /// wanting "the screen is done" has to read the texts as well.
  final bool settled;

  final int frames;

  /// Frames this settle had to force because the window was hidden.
  final int forcedFrames;

  /// Whether the platform was granting frames when the settle ended. False
  /// explains otherwise-mystifying behavior to whoever reads the step: the
  /// window is hidden or occluded, and every frame here was forced.
  final bool framesEnabled;

  final Duration elapsed;

  Map<String, Object?> toJson() => {
    'settled': settled,
    'frames': frames,
    'forcedFrames': forcedFrames,
    'framesEnabled': framesEnabled,
    'elapsedMs': elapsed.inMilliseconds,
  };
}

/// Pumps the live app until nothing is pending or [budget] runs out, and
/// never hangs.
///
/// A hidden window is the case that shapes everything here (measured —
/// `2026-08-11-run-drive-spike-findings.md`): the platform disables frames,
/// `scheduleFrame` no-ops, transitions wedge mid-flight with their
/// `IgnorePointer` up, and `hasScheduledFrame` reads false while tickers are
/// still waiting. So:
///
/// - Pending is `hasScheduledFrame || transientCallbackCount > 0 || images
///   still decoding` — tickers are the honest "something animates" probe when
///   frames are disabled, and [ImageCache.pendingImageCount] is the window a
///   capture must not fire in.
/// - When frames are disabled, one frame is forced unconditionally first: a
///   dirty element is invisible to every probe, and without the flush an
///   observation after `enterText` reads the tree from before the text.
/// - Each `endOfFrame` wait is capped, so an engine that refuses even forced
///   frames makes this late, not stuck.
Future<LiveSettleResult> settleLive({
  Duration budget = const Duration(milliseconds: 800),
  Duration frameTimeout = const Duration(milliseconds: 250),
}) async {
  var binding = WidgetsBinding.instance;
  var watch = Stopwatch()..start();
  var frames = 0;
  var forced = 0;

  bool pending() =>
      binding.hasScheduledFrame ||
      binding.transientCallbackCount > 0 ||
      PaintingBinding.instance.imageCache.pendingImageCount > 0;

  Future<void> awaitFrame() async {
    if (!binding.framesEnabled) {
      binding.scheduleForcedFrame();
      forced++;
    }
    await Future.any([binding.endOfFrame, Future<void>.delayed(frameTimeout)]);
    frames++;
  }

  if (!binding.framesEnabled) await awaitFrame();
  while (watch.elapsed < budget) {
    if (!pending()) {
      // Give microtasks and just-completed futures one beat to schedule work
      // before calling it settled.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!pending()) break;
      continue;
    }
    await awaitFrame();
  }

  return LiveSettleResult(
    settled: !pending(),
    frames: frames,
    forcedFrames: forced,
    framesEnabled: binding.framesEnabled,
    elapsed: watch.elapsed,
  );
}

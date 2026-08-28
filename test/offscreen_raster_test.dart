import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/offscreen_raster.dart';

/// The notice that keeps an external texture out of a `toImage`.
///
/// Every case here is about *when the frame happens*, because that is the whole
/// of what this class does: raising a flag is trivial, and raising it late is
/// the crash it exists to prevent — `toImage` rasterises the tree the previous
/// frame left behind, so a raster that runs in the same turn as the flag
/// photographs the texture anyway.
void main() {
  testWidgets('a raster runs a frame after the notice went up', (tester) async {
    var seen = <bool>[];
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: OffscreenRaster.notice,
        builder: (context, rastering, _) {
          seen.add(rastering);
          return const SizedBox();
        },
      ),
    );
    expect(seen, [false]);

    // What the raster sees is what the *last painted frame* held, which is
    // exactly what this records.
    var duringRaster = <bool>[];
    var done = OffscreenRaster.around(() async {
      duringRaster.addAll(seen);
      return 'picture';
    });

    await tester.pump();
    expect(await done, 'picture');
    expect(
      duringRaster.last,
      isTrue,
      reason: 'the notice was up for the frame the raster photographed',
    );
    expect(OffscreenRaster.notice.value, isFalse, reason: 'lowered after');
  });

  testWidgets('nothing watching costs no frame at all', (tester) async {
    await tester.pumpWidget(const SizedBox());
    // No pump between the call and the answer: an app with no external texture
    // must not pay a frame per screenshot for a hazard it does not have.
    expect(await OffscreenRaster.around(() async => 7), 7);
  });

  testWidgets('a raster that throws still lowers the notice', (tester) async {
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: OffscreenRaster.notice,
        builder: (context, _, _) => const SizedBox(),
      ),
    );
    var failed = OffscreenRaster.around<void>(
      () async => throw StateError('no context'),
    );
    // Claimed before the pump that lets it run: an error with no handler yet
    // reaches the test framework as an uncaught one instead of this matcher.
    var raised = expectLater(failed, throwsStateError);
    await tester.pump();
    await raised;
    expect(OffscreenRaster.notice.value, isFalse);
  });

  testWidgets('a hidden window still gets its frame', (tester) async {
    var painted = <bool>[];
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: OffscreenRaster.notice,
        builder: (context, rastering, _) {
          painted.add(rastering);
          return const SizedBox();
        },
      ),
    );

    // The state a studio is in for the whole of an agent's drive session, and
    // the reason `scheduleForcedFrame` is in `_oneFrame` at all: with frames
    // disabled a plain `scheduleFrame` is a no-op, so the notice would go up,
    // nothing would repaint, and the raster would read a tree that still holds
    // the texture — the crash, in the one configuration that matters most.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(WidgetsBinding.instance.framesEnabled, isFalse);
    expect(WidgetsBinding.instance.hasScheduledFrame, isFalse);

    var done = OffscreenRaster.around(() async => painted.last);
    expect(
      WidgetsBinding.instance.hasScheduledFrame,
      isTrue,
      reason: 'forced, because nothing else can schedule one here',
    );

    await tester.pump();
    expect(await done, isTrue);
  });

  testWidgets('two rasters at once, and the texture stays away for both', (
    tester,
  ) async {
    // Both live in the studio — the drive guest's per-step screenshot and
    // `WindowCapture` — with nothing serialising them. The inner one finishing
    // must not put the texture back under the outer one.
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: OffscreenRaster.notice,
        builder: (context, _, _) => const SizedBox(),
      ),
    );

    var innerDone = Completer<void>();
    var outerSawAfterInner = false;
    var outer = OffscreenRaster.around(() async {
      await innerDone.future;
      outerSawAfterInner = OffscreenRaster.notice.value;
    });
    var inner = OffscreenRaster.around(() async {});

    await tester.pump();
    await inner;
    innerDone.complete();
    await tester.pump();
    await outer;

    expect(
      outerSawAfterInner,
      isTrue,
      reason: 'the inner raster finishing left the outer one covered',
    );
    expect(OffscreenRaster.notice.value, isFalse, reason: 'and both are done');
  });
}

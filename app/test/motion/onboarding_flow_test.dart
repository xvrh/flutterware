import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/motion.dart';

import '../../tool/catalog/demos/onboarding.dart';

/// The flow's own playhead, and the two ways it was silently not one.
///
/// Both failures here were invisible to every check that existed: the end
/// frames were right, the panel listed the motion, a screenshot at `t = 0` and
/// one at `t = 1` looked exactly as intended. Only a frame from the middle
/// showed either of them, and nothing was taking one.
void main() {
  Widget flow() => wrapInDark(onboarding());

  /// The flow's scope is the outermost, and mount order is tree order — so it
  /// is the first id. Read rather than written, because the ids run on from
  /// whatever an earlier test mounted.
  String flowScope() => MotionRegistry.instance.ids.first;

  /// Where the flow actually sits, in pages.
  ///
  /// Read off the scroll position rather than from `find`, and that is the
  /// whole point of this test: a `PageView` builds its neighbours, so both
  /// headlines are in the tree whether or not either has moved. The first
  /// version of this test asserted `find.text` for two pages at once, passed
  /// with snapping deliberately turned back on, and would have pinned nothing.
  double pagesAcross(WidgetTester tester) {
    var position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(PageView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    return position.pixels / position.viewportDimension;
  }

  testWidgets('the playhead parks the flow between two pages', (tester) async {
    await tester.pumpWidget(flow());
    await tester.pump();
    expect(pagesAcross(tester), 0);

    // t = 0.3 is the middle of the first slide — 1050ms into a motion whose
    // first segment runs 700 to 1400 — so the flow belongs exactly half a page
    // across.
    await tester.seekMotion(0.3, scope: flowScope());
    await tester.pump();
    // Settled, with time on the clock. A snap is a `ScrollSpringSimulation`,
    // and a spring advances only as the clock does — so a `pump()` with no
    // duration leaves the position exactly where `forcePixels` put it and the
    // snap this pins is invisible. The renderer settles by waiting for frames
    // to stop, which is real time; so does this.
    await tester.pumpAndSettle();

    // Half a page, not a whole one. `PageView` layers `PageScrollPhysics` over
    // whatever physics it is handed while `pageSnapping` is true, and a
    // `jumpTo` ends in `goBallistic` — so a playhead parked between two pages
    // sprang back to one of them and every transition frame this tool exists
    // to show was structurally unrenderable. Passing `ClampingScrollPhysics`
    // does not stop it, and looked like it had.
    expect(pagesAcross(tester), closeTo(0.5, 0.02));
  });

  testWidgets('a seek is not undone by the next build', (tester) async {
    await tester.pumpWidget(flow());
    await tester.pump();

    var scope = flowScope();
    await tester.seekMotion(0.3, scope: scope);
    var parked = MotionRegistry.instance.resolve(scope)!.controller.progress;
    expect(parked, closeTo(0.3, 1e-9));

    // Several frames, because the failure this pins takes exactly one: a page
    // that writes its playhead from a prop on *every* build stamps the seek
    // out on the following frame, and every renderer, scrubber and `?t=` in
    // the tool moves the playhead by seeking it.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(
      MotionRegistry.instance.resolve(scope)!.controller.progress,
      closeTo(parked, 1e-9),
    );
  });

  testWidgets('the flow lands on the last page, form and all', (tester) async {
    await tester.pumpWidget(flow());
    await tester.pump();

    await tester.seekMotion(1, scope: flowScope());
    await tester.pump();
    await tester.pump();

    expect(find.text('Start your'), findsAtLeastNWidgets(1));
    expect(find.byType(TextFormField), findsOneWidget);
  });
}

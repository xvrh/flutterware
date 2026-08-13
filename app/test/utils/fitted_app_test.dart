import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/utils/fitted_app.dart';

/// The responsive policy in four assertions: above the minimum nothing happens,
/// below it the child still lays out at the minimum, the MediaQuery it reads
/// agrees with the box it is in, and it scales rather than overflowing.
void main() {
  const minimum = Size(1000, 800);

  /// Lays out a probe under [FittedApp] at a window of [window], and reports
  /// what the child saw.
  Future<({Size box, Size media})> mount(
    WidgetTester tester,
    Size window,
  ) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Size media;
    var probeKey = GlobalKey();
    await tester.pumpWidget(
      FittedApp(
        minimumSize: minimum,
        child: Builder(
          builder: (context) {
            media = MediaQuery.sizeOf(context);
            return SizedBox.expand(
              child: ColoredBox(color: const Color(0xFF000000), key: probeKey),
            );
          },
        ),
      ),
    );
    return (box: tester.getSize(find.byKey(probeKey)), media: media);
  }

  testWidgets('a window at the minimum is left alone', (tester) async {
    var r = await mount(tester, minimum);
    expect(r.box, minimum);
    expect(r.media, minimum);
    expect(
      find.byType(FittedBox),
      findsNothing,
      reason: 'no wrapper to pay for',
    );
  });

  testWidgets('a window above the minimum is left alone', (tester) async {
    var r = await mount(tester, const Size(1600, 1200));
    expect(r.box, const Size(1600, 1200));
    expect(r.media, const Size(1600, 1200));
    expect(find.byType(FittedBox), findsNothing);
  });

  testWidgets('a narrow window still lays out at the minimum width', (
    tester,
  ) async {
    // Width binds: 500/1000 = 0.5, against 600/800 = 0.75.
    var r = await mount(tester, const Size(500, 600));
    expect(r.box.width, minimum.width);
    // Taller than the minimum, because the window is proportionally taller —
    // the scale is uniform, so the extra height is real space, not letterbox.
    expect(r.box.height, 1200);
  });

  testWidgets('a short window still lays out at the minimum height', (
    tester,
  ) async {
    // Height binds: 400/800 = 0.5, against 1500/1000 = 1.5.
    var r = await mount(tester, const Size(1500, 400));
    expect(r.box.height, minimum.height);
    expect(r.box.width, 3000);
  });

  testWidgets('MediaQuery reports the size the child is actually laid out at', (
    tester,
  ) async {
    var r = await mount(tester, const Size(500, 600));
    expect(
      r.media,
      r.box,
      reason:
          'anything positioning itself against the viewport measures the box '
          'it is in, not the window behind the scale',
    );
  });

  testWidgets('scaling down does not overflow', (tester) async {
    await mount(tester, const Size(320, 240));
    expect(tester.takeException(), isNull);
  });
}

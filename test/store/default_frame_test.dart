import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware/store.dart';

/// Which frame a project that declared none gets, per set.
///
/// The rule matters more than it looks: it is what decides whether an App Store
/// screenshot is the app's own pixels or a composition around them, and it is
/// read at compose time for every shot of every set.
StoreShot _shot(StoreTarget target) => StoreShot(
  image: MemoryImage(_pixel),
  imageSize: Size(target.device.width, target.device.height),
  slug: 'home',
  index: 1,
  total: 1,
  locale: const Locale('en'),
  device: target.device,
  canvas: target.canvas,
);

/// A 1×1 PNG. The frame under test draws whatever it is handed; what matters
/// here is the chrome over it, so the cheapest decodable image will do.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
  'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  var appStore = const AppStoreListing(locales: {'en': 'en-US'});
  var play = const PlayListing(locales: {'en': 'en-US'});

  group('defaultStoreFrame', () {
    test('gives Apple a pane of glass, not a composition', () {
      for (var target in appStore.targets) {
        expect(
          defaultStoreFrame(_shot(target)),
          isA<PlainStoreFrame>(),
          reason:
              '${target.id} would gain an invented ground and device body, '
              'which is a marketing decision nobody asked for',
        );
      }
    });

    test("composes Play's phone, whose canvas is not its device", () {
      var targets = {for (var t in play.targets) t.id: t};
      expect(
        defaultStoreFrame(_shot(targets['phone']!)),
        isA<DefaultStoreFrame>(),
      );
      // 800×1280 at ratio 2 is Play's own recommended 10" size, so nothing is
      // forced here either.
      expect(
        defaultStoreFrame(_shot(targets['tablet-10']!)),
        isA<PlainStoreFrame>(),
      );
    });

    test('frames every set either way', () {
      // The change decision 7 did not originally draw: a status bar is not
      // marketing, so no set is handed over unframed any more. What varies is
      // which frame, never whether there is one.
      for (var target in [...appStore.targets, ...play.targets]) {
        expect(defaultStoreFrame(_shot(target)), isA<StoreFrame>());
      }
    });
  });

  group('PlainStoreFrame', () {
    testWidgets('draws the capture at its own size, chrome over it', (
      tester,
    ) async {
      var target = appStore.targets.first;
      var shot = _shot(target);
      await tester.pumpWidget(
        StoreFrameStage(shot: shot, child: PlainStoreFrame(shot)),
      );

      // Nothing resampled: an uncomposed canvas is its device's own output, so
      // the frame's scale is exactly one and the store receives the bytes the
      // app painted.
      expect(shot.canvas.logicalWidth, shot.imageSize.width);
      expect(find.byType(StatusChrome), findsOneWidget);
      expect(find.text('9:41'), findsOneWidget);
    });
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/splash/model/studio.dart';
import 'package:flutterware_app/src/splash/model/studio_render.dart';
import 'package:flutterware_app/src/splash/model/surface.dart';
import 'package:image/image.dart' as img;

/// The canvases, checked against the package's own documented numbers.
///
/// These are the four or five figures the whole studio exists to supply, so
/// getting one wrong would not produce a bug report — it would produce a
/// confidently exported file that is quietly the wrong size.
void main() {
  group('the Android 12 icon canvas', () {
    test('is 1152 with no icon background and 960 with one', () {
      var plain = splashStudioCanvas(
        target: SplashStudioTarget.android12Icon,
        sourceWidth: 512,
        sourceHeight: 512,
      );
      expect(plain.width, 1152);
      expect(plain.height, 1152);

      var withBackground = splashStudioCanvas(
        target: SplashStudioTarget.android12Icon,
        sourceWidth: 512,
        sourceHeight: 512,
        hasIconBackground: true,
      );
      expect(withBackground.width, 960);
    });

    test('keeps the inner two thirds — 768, and 640 with a background', () {
      expect(
        splashStudioCanvas(
          target: SplashStudioTarget.android12Icon,
          sourceWidth: 1,
          sourceHeight: 1,
        ).usableWidth.round(),
        768,
      );
      expect(
        splashStudioCanvas(
          target: SplashStudioTarget.android12Icon,
          sourceWidth: 1,
          sourceHeight: 1,
          hasIconBackground: true,
        ).usableWidth.round(),
        640,
      );
    });

    test('says the mask is circular, and says why the size is what it is', () {
      var canvas = splashStudioCanvas(
        target: SplashStudioTarget.android12Icon,
        sourceWidth: 1,
        sourceHeight: 1,
      );
      expect(canvas.circularMask, isTrue);
      // A canvas size with no reason attached is a number to mistrust.
      expect(canvas.explanation, contains('1152×1152'));
      expect(canvas.explanation, contains('768px circle'));
    });
  });

  test('the branding canvas is the fixed 800×320, all of it usable', () {
    var canvas = splashStudioCanvas(
      target: SplashStudioTarget.android12Branding,
      sourceWidth: 400,
      sourceHeight: 160,
    );
    expect((canvas.width, canvas.height), (800, 320));
    expect(canvas.usableWidth, 800);
    expect(canvas.usableHeight, 320);
    expect(canvas.circularMask, isFalse);
  });

  group('the legacy image canvas', () {
    test('is the asked-for width times the source density', () {
      // The question nobody thinks to ask, because the config has no field for
      // it — the answer is baked into the pixel size of the exported file.
      var canvas = splashStudioCanvas(
        target: SplashStudioTarget.image,
        sourceWidth: 1000,
        sourceHeight: 1000,
        logicalWidth: 160,
      );
      expect(canvas.width, 640);
      expect(canvas.height, 640);
    });

    test('follows the source aspect rather than imposing a square', () {
      var canvas = splashStudioCanvas(
        target: SplashStudioTarget.image,
        sourceWidth: 1000,
        sourceHeight: 500,
        logicalWidth: 200,
      );
      expect(canvas.width, 800);
      expect(canvas.height, 400);
    });

    test('defaults to a width that fits the narrowest phone', () {
      var canvas = splashStudioCanvas(
        target: SplashStudioTarget.image,
        sourceWidth: 100,
        sourceHeight: 100,
      );
      expect(canvas.width, (splashDefaultImageWidthDp * sourceDensity).round());
      expect(canvas.explanation, contains('quarter of its pixel size'));
    });
  });

  group('the background canvas', () {
    test('is as tall as the tallest screen and safe to the widest', () {
      var canvas = splashStudioCanvas(
        target: SplashStudioTarget.backgroundImage,
        sourceWidth: 100,
        sourceHeight: 100,
      );
      var extremes = splashBackgroundAspects();

      // Tall enough to cover the tallest device without letterboxing…
      expect(canvas.height / canvas.width, closeTo(extremes.tallest, 0.01));
      // …and the band every device shows is the widest aspect's.
      expect(
        canvas.usableHeight / canvas.usableWidth,
        closeTo(extremes.widest, 0.01),
      );
      expect(canvas.usableHeight, lessThan(canvas.height));
    });

    test('the extremes come off the device table, not a constant', () {
      var extremes = splashBackgroundAspects();
      expect(extremes.tallest, greaterThan(extremes.widest));
      expect(extremes.width, greaterThan(0));
    });
  });

  group('the default crop', () {
    test('fits the source inside the usable area, centred', () {
      var canvas = splashStudioCanvas(
        target: SplashStudioTarget.android12Icon,
        sourceWidth: 1536,
        sourceHeight: 1536,
      );
      var crop = splashFitCrop(
        canvas: canvas,
        sourceWidth: 1536,
        sourceHeight: 1536,
      );

      expect(crop.offsetX, 0);
      expect(crop.offsetY, 0);
      // 768 usable / 1536 source.
      expect(crop.scale, closeTo(0.5, 0.0001));
      expect(
        splashCropOverflow(
          canvas: canvas,
          crop: crop,
          sourceWidth: 1536,
          sourceHeight: 1536,
        ),
        0,
      );
    });

    test('fits the long side, so a wide source is not cropped', () {
      var canvas = splashStudioCanvas(
        target: SplashStudioTarget.android12Icon,
        sourceWidth: 2000,
        sourceHeight: 1000,
      );
      var crop = splashFitCrop(
        canvas: canvas,
        sourceWidth: 2000,
        sourceHeight: 1000,
      );
      expect(2000 * crop.scale, closeTo(768, 0.5));
      expect(1000 * crop.scale, closeTo(384, 0.5));
    });
  });

  group('what the crop is told about the mask', () {
    var canvas = splashStudioCanvas(
      target: SplashStudioTarget.android12Icon,
      sourceWidth: 1000,
      sourceHeight: 1000,
    );

    test('a square filling the usable box overhangs the circle', () {
      // This is *not* an error and the default fit deliberately produces it:
      // the package's own advice is a 768 image in a 1152 file, and a logo with
      // transparent corners is unaffected. Fitting to the circle instead would
      // shrink every icon by 30% to protect corners that are usually empty.
      var crop = splashFitCrop(
        canvas: canvas,
        sourceWidth: 1000,
        sourceHeight: 1000,
      );
      var overhang = splashCornerOverhang(
        canvas: canvas,
        crop: crop,
        sourceWidth: 1000,
        sourceHeight: 1000,
      );
      // Half-diagonal of a 768 square is 543; the radius is 384.
      expect(overhang, closeTo(543 - 384, 1));
      expect(
        splashCropOverflow(
          canvas: canvas,
          crop: crop,
          sourceWidth: 1000,
          sourceHeight: 1000,
        ),
        0,
      );
    });

    test(
      'a source small enough to sit inside the circle overhangs by none',
      () {
        var crop = const SplashCrop(scale: 0.5);
        expect(
          splashCornerOverhang(
            canvas: canvas,
            crop: crop,
            sourceWidth: 1000,
            sourceHeight: 1000,
          ),
          0,
        );
      },
    );

    test('no mask means no overhang to report', () {
      var branding = splashStudioCanvas(
        target: SplashStudioTarget.android12Branding,
        sourceWidth: 100,
        sourceHeight: 100,
      );
      expect(
        splashCornerOverhang(
          canvas: branding,
          crop: const SplashCrop(scale: 10),
          sourceWidth: 100,
          sourceHeight: 100,
        ),
        0,
      );
    });

    test('an offset counts towards the overflow', () {
      var crop = const SplashCrop(scale: 0.5, offsetX: 200);
      // 500 wide drawn, half = 250, plus 200 offset = 450 from centre; the
      // usable half-width is 384.
      expect(
        splashCropOverflow(
          canvas: canvas,
          crop: crop,
          sourceWidth: 1000,
          sourceHeight: 1000,
        ),
        closeTo(450 - 384, 1),
      );
    });
  });

  group('the key each target writes', () {
    test('is the section key for Android 12 and the bare one otherwise', () {
      expect(
        SplashStudioTarget.android12Icon.keyFor(SplashTheme.light),
        'android_12.image',
      );
      expect(
        SplashStudioTarget.android12Icon.keyFor(SplashTheme.dark),
        'android_12.image_dark',
      );
      expect(SplashStudioTarget.image.keyFor(SplashTheme.light), 'image');
      expect(
        SplashStudioTarget.backgroundImage.keyFor(SplashTheme.dark),
        'background_image_dark',
      );
    });
  });

  group('rendering', () {
    Uint8List png(int width, int height) => Uint8List.fromList(
      img.encodePng(img.Image(width: width, height: height, numChannels: 4)),
    );

    test('writes exactly the canvas size, whatever the source was', () {
      var canvas = splashStudioCanvas(
        target: SplashStudioTarget.android12Icon,
        sourceWidth: 300,
        sourceHeight: 300,
      );
      var bytes = renderSplashPng(
        sourceBytes: png(300, 300),
        canvas: canvas,
        crop: splashFitCrop(
          canvas: canvas,
          sourceWidth: 300,
          sourceHeight: 300,
        ),
      );

      var decoded = img.decodePng(bytes)!;
      // Which is the whole point: `validateSplash` has nothing to say about a
      // file this produced.
      expect((decoded.width, decoded.height), (1152, 1152));
    });

    test('leaves the canvas transparent where nothing was drawn', () {
      // Every one of these files is composited over something the config
      // decides. A baked-in background would appear as a white rectangle the
      // moment somebody set `color_dark`.
      var canvas = splashStudioCanvas(
        target: SplashStudioTarget.android12Icon,
        sourceWidth: 100,
        sourceHeight: 100,
      );
      var bytes = renderSplashPng(
        sourceBytes: png(100, 100),
        canvas: canvas,
        crop: const SplashCrop(scale: 1),
      );

      var decoded = img.decodePng(bytes)!;
      expect(decoded.getPixel(2, 2).a, 0);
    });

    test('measures a source without decoding it', () {
      var facts = measureSplashSource(png(1152, 640))!;
      expect((facts.width, facts.height), (1152, 640));
    });

    test('says so rather than throwing something unreadable', () {
      // `decodeImage` does not return null on rubbish — its PSD probe reads a
      // 32-bit header field off a three-byte buffer and throws `RangeError
      // (length): Not in inclusive range 0..2`. That is what somebody picking a
      // corrupt file would have been shown.
      expect(
        () => renderSplashPng(
          sourceBytes: Uint8List.fromList([1, 2, 3]),
          canvas: splashStudioCanvas(
            target: SplashStudioTarget.image,
            sourceWidth: 10,
            sourceHeight: 10,
          ),
          crop: const SplashCrop(scale: 1),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

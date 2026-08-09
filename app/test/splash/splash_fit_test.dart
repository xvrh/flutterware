import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/splash/model/composition.dart';
import 'package:flutterware_app/src/splash/model/fit_check.dart';
import 'package:flutterware_app/src/splash/model/surface.dart';

/// The device sweep, as arithmetic.
///
/// No rendering anywhere here, which is the point of the rule existing at all:
/// "is the logo clipped on a small phone" is a question about two numbers, and
/// answering it by drawing eighteen pictures and asking someone to look would be
/// answering a different, worse question.
void main() {
  SplashComposition composition({
    SplashSurface surface = SplashSurface.android,
    double? imageSize,
    SplashFit fit = SplashFit.none,
    bool branding = false,
    int brandingBottomPadding = 0,
  }) => SplashComposition(
    surface: surface,
    theme: SplashTheme.light,
    enabled: true,
    backgroundColor: 0xFFFFFFFF,
    image: imageSize == null
        ? null
        : SplashLayer(
            path: 'assets/logo.png',
            absolutePath: '/tmp/logo.png',
            fit: fit,
            alignment: SplashAlignment.center,
            naturalWidth: imageSize,
            naturalHeight: imageSize,
          ),
    branding: branding
        ? const SplashLayer(
            path: 'assets/branding.png',
            absolutePath: '/tmp/branding.png',
            fit: SplashFit.none,
            alignment: SplashAlignment.bottomCenter,
            naturalWidth: 200,
            naturalHeight: 80,
          )
        : null,
    brandingBottomPadding: brandingBottomPadding,
  );

  group('splashDrawnSize', () {
    test('none is the natural size, whatever the screen', () {
      expect(
        splashDrawnSize(
          fit: SplashFit.none,
          naturalWidth: 256,
          naturalHeight: 256,
          screenWidth: 412,
          screenHeight: 915,
        ),
        (256.0, 256.0),
      );
    });

    test('contain takes the smaller ratio, cover the larger', () {
      expect(
        splashDrawnSize(
          fit: SplashFit.contain,
          naturalWidth: 100,
          naturalHeight: 100,
          screenWidth: 400,
          screenHeight: 800,
        ),
        (400.0, 400.0),
      );
      expect(
        splashDrawnSize(
          fit: SplashFit.cover,
          naturalWidth: 100,
          naturalHeight: 100,
          screenWidth: 400,
          screenHeight: 800,
        ),
        (800.0, 800.0),
      );
    });

    test('a zero-sized source does not divide by zero', () {
      expect(
        splashDrawnSize(
          fit: SplashFit.contain,
          naturalWidth: 0,
          naturalHeight: 0,
          screenWidth: 400,
          screenHeight: 800,
        ),
        (0.0, 0.0),
      );
    });
  });

  group('the device sweep', () {
    test("only sweeps the surface's own platform", () {
      expect(
        splashDevicesFor(SplashSurface.ios).every((d) => d.id.contains('i')),
        isTrue,
      );
      expect(
        splashDevicesFor(SplashSurface.android).map((d) => d.id),
        contains('android-small'),
      );
      // The web splash is a browser viewport, not a handset.
      expect(splashDevicesFor(SplashSurface.web), isEmpty);
    });

    test('a 1024px source at 4x fits every Android phone', () {
      // 256dp on a 360dp screen — the ordinary, correct case, and the one that
      // has to stay quiet or the rule is wallpaper.
      expect(checkSplashFit(composition(imageSize: 256)), isEmpty);
    });

    test('a 2048px source is clipped, worst on the narrowest phone', () {
      var findings = checkSplashFit(composition(imageSize: 512));
      expect(findings, isNotEmpty);
      expect(
        findings.every((f) => f.issue == SplashFitIssue.imageClipped),
        isTrue,
      );

      // Sorted worst first, and the worst is the narrowest screen: 512 - 360.
      expect(findings.first.device.id, 'android-small');
      expect(findings.first.amount, closeTo(152, 0.001));
    });

    test('contain can never clip, however large the source', () {
      expect(
        checkSplashFit(composition(imageSize: 4096, fit: SplashFit.contain)),
        isEmpty,
      );
    });

    test('the Android 12 icon is exempt — it is a fixed slot', () {
      // The system draws it at 240dp and masks it, the same on every screen, so
      // there is no screen it can be too large for.
      expect(
        checkSplashFit(
          composition(surface: SplashSurface.android12, imageSize: 512),
        ),
        isEmpty,
      );
    });

    test('branding with no padding lands under the home indicator', () {
      var findings = checkSplashFit(
        composition(surface: SplashSurface.ios, branding: true),
      );
      var collisions = findings
          .where((f) => f.issue == SplashFitIssue.brandingUnderSafeArea)
          .toList();
      expect(collisions, isNotEmpty);
      // Every modern iPhone has a 34dp indicator.
      expect(collisions.first.amount, closeTo(34, 0.001));
    });

    test('padding past the largest inset clears every phone', () {
      expect(
        checkSplashFit(
          composition(
            surface: SplashSurface.ios,
            branding: true,
            brandingBottomPadding: 40,
          ),
        ),
        isEmpty,
      );
    });

    test('a disabled surface is not swept', () {
      var disabled = SplashComposition(
        surface: SplashSurface.android,
        theme: SplashTheme.light,
        enabled: false,
        image: const SplashLayer(
          path: 'assets/logo.png',
          absolutePath: '/tmp/logo.png',
          fit: SplashFit.none,
          alignment: SplashAlignment.center,
          naturalWidth: 4096,
          naturalHeight: 4096,
        ),
      );
      expect(checkSplashFit(disabled), isEmpty);
    });

    test('an unmeasured image raises nothing rather than guessing', () {
      var unmeasured = SplashComposition(
        surface: SplashSurface.android,
        theme: SplashTheme.light,
        enabled: true,
        image: const SplashLayer(
          path: 'assets/logo.png',
          absolutePath: '/tmp/logo.png',
          fit: SplashFit.none,
          alignment: SplashAlignment.center,
        ),
      );
      expect(checkSplashFit(unmeasured), isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/splash/model/composition.dart';
import 'package:flutterware_app/src/splash/model/config.dart';
import 'package:flutterware_app/src/splash/model/image_facts.dart';
import 'package:flutterware_app/src/splash/model/surface.dart';

/// The geometry, as plain data.
///
/// This is where the real coverage lives: every placement rule is a pure
/// function from config to [SplashComposition], so it can be checked exhaustively
/// without rendering a pixel. The golden tests over `SplashRender` only have to
/// cover the thin mapping onto `BoxFit`, because nothing else happens there.
void main() {
  group('android_gravity', () {
    test('defaults to centred at natural size', () {
      expect(parseAndroidGravity(null), (
        SplashFit.none,
        SplashAlignment.center,
      ));
      expect(parseAndroidGravity(''), (SplashFit.none, SplashAlignment.center));
    });

    test('fill stretches both axes', () {
      expect(parseAndroidGravity('fill').$1, SplashFit.fill);
    });

    test('fill_horizontal and fill_vertical stretch one axis each', () {
      expect(parseAndroidGravity('fill_horizontal').$1, SplashFit.fillWidth);
      expect(parseAndroidGravity('fill_vertical').$1, SplashFit.fillHeight);
    });

    test('both fill flags together are a full stretch', () {
      expect(
        parseAndroidGravity('fill_horizontal|fill_vertical').$1,
        SplashFit.fill,
      );
    });

    test('is a bitmask, so a fit and an alignment can arrive together', () {
      // Android's gravity really is `|`-separated flags; treating the string as
      // one enum value would drop the half that positions the image.
      var (fit, alignment) = parseAndroidGravity('fill_horizontal|bottom');
      expect(fit, SplashFit.fillWidth);
      expect(alignment, SplashAlignment.bottomCenter);
    });

    test(
      'start and end are the direction-aware spellings of left and right',
      () {
        expect(parseAndroidGravity('start').$2, SplashAlignment.centerLeft);
        expect(parseAndroidGravity('end').$2, SplashAlignment.centerRight);
      },
    );

    test('corners combine two flags', () {
      expect(parseAndroidGravity('top|left').$2, SplashAlignment.topLeft);
      expect(
        parseAndroidGravity('bottom|right').$2,
        SplashAlignment.bottomRight,
      );
    });

    test('clip flags are accepted and do not move anything', () {
      // They constrain overdraw, not placement. Modelling them would be a lie
      // the preview could not keep.
      expect(parseAndroidGravity('center|clip_vertical'), (
        SplashFit.none,
        SplashAlignment.center,
      ));
    });

    test('every documented value parses without throwing', () {
      for (var value in androidGravityValues) {
        expect(
          () => parseAndroidGravity(value),
          returnsNormally,
          reason: value,
        );
      }
    });
  });

  group('ios_content_mode', () {
    test('maps the three scaling modes', () {
      expect(parseIosContentMode('scaleToFill').$1, SplashFit.fill);
      expect(parseIosContentMode('scaleAspectFit').$1, SplashFit.contain);
      expect(parseIosContentMode('scaleAspectFill').$1, SplashFit.cover);
    });

    test('positional modes place at natural size', () {
      for (var value in [
        'center',
        'top',
        'bottom',
        'left',
        'right',
        'topLeft',
        'topRight',
        'bottomLeft',
        'bottomRight',
      ]) {
        expect(parseIosContentMode(value).$1, SplashFit.none, reason: value);
      }
      expect(parseIosContentMode('topRight').$2, SplashAlignment.topRight);
    });

    test('defaults to centre, matching the generator', () {
      expect(parseIosContentMode(null), (
        SplashFit.none,
        SplashAlignment.center,
      ));
    });

    test('every documented value parses', () {
      for (var value in iosContentModeValues) {
        expect(
          () => parseIosContentMode(value),
          returnsNormally,
          reason: value,
        );
      }
    });
  });

  group('web_image_mode', () {
    test('maps the CSS background-size vocabulary', () {
      expect(parseWebImageMode('contain').$1, SplashFit.contain);
      expect(parseWebImageMode('cover').$1, SplashFit.cover);
      expect(parseWebImageMode('stretch').$1, SplashFit.fill);
      expect(parseWebImageMode('center').$1, SplashFit.none);
    });
  });

  group('branding_mode', () {
    test('maps the three corners', () {
      expect(parseBrandingMode('bottom'), SplashAlignment.bottomCenter);
      expect(parseBrandingMode('bottomLeft'), SplashAlignment.bottomLeft);
      expect(parseBrandingMode('bottomRight'), SplashAlignment.bottomRight);
    });

    test('defaults to bottom centre', () {
      expect(parseBrandingMode(null), SplashAlignment.bottomCenter);
    });
  });

  group('the Android 12 mask', () {
    test('keeps two thirds, which is the documented one-third masked', () {
      expect(android12MaskFraction, closeTo(2 / 3, 1e-9));
      // Both documented pairs reduce to the same ratio, which is why one
      // constant covers them.
      expect(768 / 1152, closeTo(android12MaskFraction, 1e-9));
      expect(640 / 960, closeTo(android12MaskFraction, 1e-9));
    });

    test('the expected canvas depends on the icon background', () {
      expect(android12IconSize(hasIconBackground: false), 1152);
      expect(android12IconSize(hasIconBackground: true), 960);
    });
  });

  group('composeSplash', () {
    SplashConfig config(Map<String, Object?> raw) => SplashConfig(
      raw: raw,
      kind: SplashConfigKind.file,
      path: 'flutter_native_splash.yaml',
    );

    SplashImageFacts? facts(String path) => SplashImageFacts(
      path: path,
      exists: true,
      absolutePath: '/tmp/$path',
      pixelWidth: 1024,
      pixelHeight: 512,
      isPng: true,
    );

    test('natural size is the source divided by the 4x density', () {
      var c = config({'color': 'FFFFFF', 'image': 'logo.png'});
      var composition = composeSplash(
        resolveSplash(c, SplashSurface.ios, SplashTheme.light),
        facts: facts,
      );
      expect(composition.image!.naturalWidth, 1024 / 4);
      expect(composition.image!.naturalHeight, 512 / 4);
    });

    test('a missing file becomes a drawn hole, not an omission', () {
      var c = config({'color': 'FFFFFF', 'image': 'gone.png'});
      var composition = composeSplash(
        resolveSplash(c, SplashSurface.ios, SplashTheme.light),
        facts: (_) => null,
      );
      expect(composition.image, isNotNull);
      expect(composition.image!.missing, isTrue);
      expect(composition.image!.absolutePath, isNull);
    });

    test(
      'a background image always covers — there is no key to say otherwise',
      () {
        var c = config({'color': 'FFFFFF', 'background_image': 'bg.png'});
        var composition = composeSplash(
          resolveSplash(c, SplashSurface.android, SplashTheme.light),
          facts: facts,
        );
        expect(composition.backgroundImage!.fit, SplashFit.cover);
      },
    );

    test('only Android 12 carries a mask', () {
      var c = config({
        'color': 'FFFFFF',
        'android_12': {'image': 'a12.png'},
      });
      var modern = composeSplash(
        resolveSplash(c, SplashSurface.android12, SplashTheme.light),
        facts: facts,
      );
      expect(modern.iconMaskFraction, android12MaskFraction);
      expect(modern.iconCanvas, android12IconCanvasDp);

      var legacy = composeSplash(
        resolveSplash(c, SplashSurface.android, SplashTheme.light),
        facts: facts,
      );
      expect(legacy.iconMaskFraction, isNull);
    });

    test('summarises itself in words, for the CLI', () {
      var c = config({
        'color': 'FFFFFF',
        'image': 'logo.png',
        'android_gravity': 'bottom',
      });
      var composition = composeSplash(
        resolveSplash(c, SplashSurface.android, SplashTheme.light),
        facts: facts,
      );
      expect(composition.summary, contains('#FFFFFF'));
      expect(composition.summary, contains('logo.png'));
      expect(composition.summary, contains('bottom'));
    });

    test('says out loud when a dark cell is really the light one', () {
      var c = config({'color': 'FFFFFF', 'image': 'logo.png'});
      var composition = composeSplash(
        resolveSplash(c, SplashSurface.ios, SplashTheme.dark),
        facts: facts,
      );
      expect(composition.fallsBackToLight, isTrue);
      expect(composition.summary, contains('light splash'));
    });
  });

  group('the JSON round trip', () {
    // The composition is the payload handed to the headless guest, so a field
    // that does not survive encoding is a field where the exported PNG and the
    // panel disagree.
    test('survives every surface and theme', () {
      for (var surface in SplashSurface.values) {
        for (var theme in SplashTheme.values) {
          var original = SplashComposition(
            surface: surface,
            theme: theme,
            enabled: true,
            backgroundColor: 0xFF1E1E1E,
            image: SplashLayer(
              path: 'logo.png',
              absolutePath: '/tmp/logo.png',
              fit: SplashFit.contain,
              alignment: SplashAlignment.bottomRight,
              naturalWidth: 256,
              naturalHeight: 128,
            ),
            iconBackgroundColor: 0xFFAABBCC,
            iconCanvas: android12IconCanvasDp,
            iconMaskFraction: android12MaskFraction,
            brandingBottomPadding: 24,
            fullscreen: true,
            fallsBackToLight: true,
          );

          var restored = SplashComposition.fromJson(original.toJson());

          expect(restored.surface, surface);
          expect(restored.theme, theme);
          expect(restored.backgroundColor, original.backgroundColor);
          expect(restored.iconBackgroundColor, original.iconBackgroundColor);
          expect(restored.iconCanvas, original.iconCanvas);
          expect(restored.iconMaskFraction, original.iconMaskFraction);
          expect(restored.fullscreen, isTrue);
          expect(restored.fallsBackToLight, isTrue);
          expect(restored.image!.path, 'logo.png');
          expect(restored.image!.absolutePath, '/tmp/logo.png');
          expect(restored.image!.fit, SplashFit.contain);
          expect(restored.image!.alignment, SplashAlignment.bottomRight);
          expect(restored.image!.naturalWidth, 256);
        }
      }
    });

    test('a missing layer stays missing', () {
      var original = const SplashComposition(
        surface: SplashSurface.web,
        theme: SplashTheme.light,
        enabled: true,
        image: SplashLayer(
          path: 'gone.png',
          fit: SplashFit.none,
          alignment: SplashAlignment.center,
          missing: true,
        ),
      );
      var restored = SplashComposition.fromJson(original.toJson());
      expect(restored.image!.missing, isTrue);
    });

    test('a disabled surface stays disabled', () {
      var original = const SplashComposition(
        surface: SplashSurface.android,
        theme: SplashTheme.light,
        enabled: false,
      );
      expect(SplashComposition.fromJson(original.toJson()).enabled, isFalse);
    });
  });
}

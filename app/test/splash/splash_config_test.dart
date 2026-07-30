import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/splash/model/color.dart';
import 'package:flutterware_app/src/splash/model/config.dart';
import 'package:flutterware_app/src/splash/model/surface.dart';

/// The cascade, which is the one thing in this plugin that cannot be got from
/// the README.
///
/// Every expectation here is anchored to a line of the generator's own
/// `cli_commands.dart`, quoted in the test, because "what the docs imply" and
/// "what the code does" differ precisely where it matters most.
void main() {
  SplashConfig config(Map<String, Object?> raw) => SplashConfig(
    raw: raw,
    kind: SplashConfigKind.file,
    path: 'flutter_native_splash.yaml',
  );

  group('the light chain', () {
    // `color: colorAndroid ?? color`
    test('prefers the platform key, then the bare one', () {
      var c = config({'color': 'FFFFFF', 'color_android': '00FF00'});
      expect(
        c.resolve('color', SplashSurface.android, SplashTheme.light).value,
        '00FF00',
      );
      expect(
        c.resolve('color', SplashSurface.ios, SplashTheme.light).value,
        'FFFFFF',
      );
    });

    test('reports which key won', () {
      var c = config({'color': 'FFFFFF', 'color_android': '00FF00'});
      expect(
        c.resolve('color', SplashSurface.android, SplashTheme.light).key,
        'color_android',
      );
      expect(
        c.resolve('color', SplashSurface.ios, SplashTheme.light).key,
        'color',
      );
    });
  });

  group('the dark chain', () {
    // `darkColor: darkColorAndroid ?? darkColor`
    test('prefers the platform key, then the bare dark one', () {
      var c = config({'color_dark': '000000', 'color_dark_android': '101010'});
      expect(
        c.resolve('color', SplashSurface.android, SplashTheme.dark).value,
        '101010',
      );
      expect(
        c.resolve('color', SplashSurface.ios, SplashTheme.dark).value,
        '000000',
      );
    });

    test('never falls through to the light keys', () {
      // This is the trap. `color` is set and `color_dark` is not, so dark
      // resolves *nothing* — the generator writes no -night resources and the
      // OS shows the light splash. A cascade that fell through would report a
      // dark splash that will never exist.
      var c = config({'color': 'FFFFFF', 'color_android': '00FF00'});
      expect(
        c.resolve('color', SplashSurface.android, SplashTheme.dark).isPresent,
        isFalse,
      );
    });

    test('a light platform key does not beat a bare dark key', () {
      var c = config({'color_android': '00FF00', 'color_dark': '000000'});
      expect(
        c.resolve('color', SplashSurface.android, SplashTheme.dark).value,
        '000000',
      );
    });
  });

  group('android_12', () {
    // `android12Color = parseColor(android12Config[color]) ?? color`
    test('colour falls back to the top-level color, not color_android', () {
      var c = config({'color': 'FFFFFF', 'color_android': '00FF00'});
      var resolved = c.android12Color(SplashTheme.light);
      expect(resolved.value, 'FFFFFF');
      expect(resolved.key, 'color');
    });

    test('its own colour wins', () {
      var c = config({
        'color': 'FFFFFF',
        'android_12': {'color': '123456'},
      });
      expect(c.android12Color(SplashTheme.light).key, 'android_12.color');
    });

    test('the image has no fallback to the top-level image', () {
      // The headline footgun: a perfectly good `image:` reaches the legacy path
      // and nothing else.
      var c = config({'image': 'assets/logo.png'});
      expect(c.android12Image(SplashTheme.light).isPresent, isFalse);
    });

    test('the dark image falls back to the section light image', () {
      // `android12DarkImagePath: android12DarkImage ?? android12Image`
      var c = config({
        'android_12': {'image': 'assets/a12.png'},
      });
      expect(c.android12Image(SplashTheme.dark).value, 'assets/a12.png');
    });

    test('a dark icon background falls back to the light one', () {
      var c = config({
        'android_12': {'icon_background_color': 'AABBCC'},
      });
      expect(c.android12IconBackgroundColor(SplashTheme.dark).value, 'AABBCC');
    });
  });

  group('value coercion', () {
    test('a YAML int colour is zero-padded the way the generator pads it', () {
      // `color: 000000` parses as the int 0. The generator does
      // `colorValue.toString().padLeft(6, '0')`, so it must resolve to black
      // rather than to "0".
      var c = config({'color': 0});
      expect(
        c.resolve('color', SplashSurface.ios, SplashTheme.light).value,
        '000000',
      );
      expect(parseSplashColor('000000'), 0xFF000000);
    });

    test('a six-digit int colour survives as written', () {
      var c = config({'color': 123456});
      expect(
        c.resolve('color', SplashSurface.ios, SplashTheme.light).value,
        '123456',
      );
    });
  });

  group('platform toggles', () {
    test('absent means enabled', () {
      var c = config({'color': 'FFFFFF'});
      for (var surface in SplashSurface.values) {
        expect(c.enabled(surface), isTrue, reason: '$surface');
      }
    });

    test('android: false disables both Android surfaces', () {
      var c = config({'color': 'FFFFFF', 'android': false});
      expect(c.enabled(SplashSurface.android), isFalse);
      expect(c.enabled(SplashSurface.android12), isFalse);
      expect(c.enabled(SplashSurface.ios), isTrue);
    });
  });

  group('resolveSplash', () {
    test('marks a dark cell that will show the light splash', () {
      var c = config({'color': 'FFFFFF', 'image': 'assets/logo.png'});
      var dark = resolveSplash(c, SplashSurface.ios, SplashTheme.dark);
      expect(dark.fallsBackToLight, isTrue);

      var light = resolveSplash(c, SplashSurface.ios, SplashTheme.light);
      expect(light.fallsBackToLight, isFalse);
    });

    test('a dark cell with real dark config does not claim a fallback', () {
      var c = config({'color': 'FFFFFF', 'color_dark': '000000'});
      expect(
        resolveSplash(c, SplashSurface.ios, SplashTheme.dark).fallsBackToLight,
        isFalse,
      );
    });

    test('android_gravity does not reach the Android 12 icon', () {
      var c = config({
        'color': 'FFFFFF',
        'android_gravity': 'bottom',
        'android_12': {'image': 'assets/a12.png'},
      });
      var legacy = resolveSplash(c, SplashSurface.android, SplashTheme.light);
      expect(legacy.alignment, SplashAlignment.bottomCenter);

      var modern = resolveSplash(c, SplashSurface.android12, SplashTheme.light);
      expect(modern.alignment, SplashAlignment.center);
    });

    test('fullscreen applies to android and ios only', () {
      var c = config({'color': 'FFFFFF', 'fullscreen': true});
      expect(
        resolveSplash(c, SplashSurface.android, SplashTheme.light).fullscreen,
        isTrue,
      );
      expect(
        resolveSplash(c, SplashSurface.ios, SplashTheme.light).fullscreen,
        isTrue,
      );
      // The web splash has no status bar, and the Android 12 splash is drawn by
      // the system.
      expect(
        resolveSplash(c, SplashSurface.web, SplashTheme.light).fullscreen,
        isFalse,
      );
      expect(
        resolveSplash(c, SplashSurface.android12, SplashTheme.light).fullscreen,
        isFalse,
      );
    });

    test('a background image is absent on Android 12 rather than unused', () {
      var c = config({
        'color': 'FFFFFF',
        'background_image': 'assets/bg.png',
        'android_12': {'image': 'assets/a12.png'},
      });
      expect(
        resolveSplash(
          c,
          SplashSurface.android,
          SplashTheme.light,
        ).backgroundImage.isPresent,
        isTrue,
      );
      expect(
        resolveSplash(
          c,
          SplashSurface.android12,
          SplashTheme.light,
        ).backgroundImage.isPresent,
        isFalse,
      );
    });
  });

  group('colours', () {
    test('accepts exactly six hex digits, with or without a hash', () {
      expect(parseSplashColor('#1E1E1E'), 0xFF1E1E1E);
      expect(parseSplashColor('1E1E1E'), 0xFF1E1E1E);
      expect(parseSplashColor(' 1E 1E 1E '), 0xFF1E1E1E);
    });

    test(
      'rejects eight digits — the generator throws rather than reading alpha',
      () {
        expect(parseSplashColor('FF1E1E1E'), isNull);
      },
    );

    test('rejects three-digit shorthand', () {
      expect(parseSplashColor('#FFF'), isNull);
    });

    test('formats back to canonical #RRGGBB', () {
      expect(formatSplashColor(0xFF1E1E1E), '#1E1E1E');
      expect(formatSplashColor(0xFF000000), '#000000');
    });
  });
}

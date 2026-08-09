import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/splash/model/edit_target.dart';
import 'package:flutterware_app/src/splash/model/surface.dart';

/// Where an edit lands.
///
/// The one rule worth guarding: the key that won is the default, and narrowing
/// to one platform is a second option rather than what happens when you nudge a
/// colour on the Android tile.
void main() {
  List<String> keys(String key, SplashSurface surface) => [
    for (var target in splashEditTargets(key: key, surface: surface))
      target.key,
  ];

  test('the key that won comes first', () {
    expect(
      splashEditTargets(
        key: 'color_dark',
        surface: SplashSurface.android,
      ).first.key,
      'color_dark',
    );
  });

  test('the narrower key is offered second, not chosen', () {
    expect(keys('color_dark', SplashSurface.android), [
      'color_dark',
      'color_dark_android',
    ]);
    expect(keys('image', SplashSurface.ios), ['image', 'image_ios']);
    expect(keys('background_image_dark', SplashSurface.web), [
      'background_image_dark',
      'background_image_dark_web',
    ]);
  });

  test(
    'a key that is already platform-specific has nowhere narrower to go',
    () {
      expect(keys('color_dark_android', SplashSurface.android), [
        'color_dark_android',
      ]);
      expect(keys('image_ios', SplashSurface.ios), ['image_ios']);
    },
  );

  group('Android 12', () {
    test('narrows into the section rather than onto a suffix', () {
      // `android12Color` reads `android_12.color ?? color` — the **top-level**
      // one. `color_android` never reaches this surface, so offering it would
      // be offering an edit that does nothing.
      expect(keys('color', SplashSurface.android12), [
        'color',
        'android_12.color',
      ]);
    });

    test('drops a platform suffix on the way into the section', () {
      expect(keys('color_dark_android', SplashSurface.android12), [
        'color_dark_android',
        'android_12.color_dark',
      ]);
    });

    test('a key already in the section stays there', () {
      expect(keys('android_12.image', SplashSurface.android12), [
        'android_12.image',
      ]);
    });
  });

  test('a narrower key the generator does not accept is not offered', () {
    // There is no `branding_bottom_padding_web`, and writing one is precisely
    // what makes `create` exit.
    expect(keys('branding_bottom_padding', SplashSurface.web), [
      'branding_bottom_padding',
    ]);
    // The Android one does exist.
    expect(keys('branding_bottom_padding', SplashSurface.android), [
      'branding_bottom_padding',
      'branding_bottom_padding_android',
    ]);
  });

  test('every target says why you would pick it', () {
    var targets = splashEditTargets(key: 'color', surface: SplashSurface.ios);
    expect(targets.first.label, 'where it is set now');
    expect(targets.last.label, 'only for iOS');
  });
}

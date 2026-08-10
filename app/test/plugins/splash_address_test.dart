import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/plugins/native/splash_address.dart';
import 'package:flutterware_app/src/splash/model/surface.dart';

/// The round trip is the contract: an address written by the matrix has to read
/// back as the same cell, or a search hit opens the right plugin showing the
/// wrong splash.
void main() {
  SplashPlace? roundTrip(SplashPlace place) => splashPlace(
    splashSegments(place.package, place.flavor),
    splashAxes(surface: place.surface, theme: place.theme, size: place.size),
  );

  test('a package on its own round-trips', () {
    var place = const SplashPlace('examples/example');
    expect(roundTrip(place), place);
  });

  test('a package with slashes stays one segment', () {
    expect(splashSegments('packages/nested/app'), ['packages/nested/app']);
    expect(
      splashPlace(['packages/nested/app'])!.package,
      'packages/nested/app',
    );
  });

  test('every cell of the matrix round-trips', () {
    for (var surface in SplashSurface.values) {
      for (var theme in SplashTheme.values) {
        var place = SplashPlace('.', surface: surface, theme: theme);
        expect(roundTrip(place), place, reason: '$surface/$theme');
      }
    }
  });

  test('a screen size round-trips as a third axis', () {
    var place = const SplashPlace(
      '.',
      surface: SplashSurface.ios,
      theme: SplashTheme.dark,
      size: 'small-phone',
    );
    expect(roundTrip(place), place);
  });

  test('a size this build has never heard of survives the trip', () {
    // Kept raw rather than resolved, so it can be reported. Silently becoming
    // "the default" would draw a picture that is wrong without looking wrong.
    var place = const SplashPlace('.', size: 'nokia-3310');
    expect(roundTrip(place)!.size, 'nokia-3310');
  });

  test('no size round-trips to no size', () {
    expect(splashAxes(surface: SplashSurface.ios).containsKey('size'), false);
    expect(roundTrip(const SplashPlace('.'))!.size, isNull);
  });

  test('a flavor round-trips alongside a cell', () {
    var place = const SplashPlace(
      '.',
      flavor: 'production',
      surface: SplashSurface.android12,
      theme: SplashTheme.dark,
    );
    expect(roundTrip(place), place);
  });

  test('no axes means no cell, rather than a defaulted one', () {
    // Selecting the plugin off the rail lands here, and the panel shows the
    // whole matrix. Defaulting to android/light would silently pick one.
    var place = splashPlace(['.']);
    expect(place!.surface, isNull);
    expect(place.theme, isNull);
    expect(splashAxes(), isEmpty);
  });

  test('an unknown axis value reads back as null rather than throwing', () {
    // An address is a thing people type.
    var place = splashPlace(['.'], {'surface': 'blackberry', 'theme': 'sepia'});
    expect(place!.surface, isNull);
    expect(place.theme, isNull);
  });

  test('empty segments address nothing', () {
    expect(splashPlace([]), isNull);
  });

  test('the surface and theme are axes, not segments', () {
    // Identity is the package; a surface is that package seen differently, so
    // it must survive as a query parameter on a parsed Address.
    var address = Address(
      worktree: 'main',
      plugin: 'flutterware.splash',
      segments: splashSegments('.'),
      axes: splashAxes(
        surface: SplashSurface.android12,
        theme: SplashTheme.dark,
      ),
    );
    var parsed = Address.parse('$address');
    expect(parsed.segments, ['.']);
    expect(parsed.axes, {'surface': 'android12', 'theme': 'dark'});
  });
}

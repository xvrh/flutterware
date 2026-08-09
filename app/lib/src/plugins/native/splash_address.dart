/// How the splash previewer writes itself into an address, and how it reads
/// itself back out.
///
/// **Both directions in one file**, for the reason `assets_address.dart` gives
/// at its own top: the address is written by the matrix, by search and by
/// whoever pastes one; it is read by the panel deciding which cell to show.
/// Drift between the two does not throw — it shows you a different splash.
///
/// The round trip is the contract, and [splashSegments] and [splashPlace] are
/// inverses with a test that says so.
library;

import '../../splash/model/surface.dart';

/// A place in the previewer: a package, a config within it, and — through the
/// axes — one cell of that config's matrix.
///
/// The surface and theme are **axes rather than segments**, which is the
/// framework's own distinction (`lib/src/plugins/address.dart`): segments are
/// identity, query parameters are the same thing seen differently. An Android
/// splash in dark mode is not a different splash, it is this splash on another
/// surface — so it addresses as `…/app?surface=android&theme=dark`, and an
/// address with both resolved is a complete capture spec.
class SplashPlace {
  const SplashPlace(
    this.package, {
    this.flavor,
    this.surface,
    this.theme,
    this.device,
  });

  /// The workspace-relative package path — `.`, `examples/example`.
  final String package;

  /// Which `flutter_native_splash-<flavor>.yaml` this is about, or null for the
  /// default config.
  final String? flavor;

  /// Null when the address names no cell, which is where selecting the plugin
  /// off the rail leaves you — the panel then shows the whole matrix.
  final SplashSurface? surface;
  final SplashTheme? theme;

  /// The screen to draw the cell on — `?device=iphone-se`.
  ///
  /// **The catalog's vocabulary, not a second one.** `Devices.all` is already
  /// what `?device=` means everywhere else in the app, and a splash previewer
  /// inventing its own list of phones would be two tables to keep in step for
  /// no gain. Null means the surface's own default.
  ///
  /// Kept as the raw string rather than a resolved `Device` so an id this build
  /// has never heard of survives the round trip and can be reported, instead of
  /// silently becoming "the default" — a picture that is wrong without looking
  /// wrong.
  final String? device;

  @override
  bool operator ==(Object other) =>
      other is SplashPlace &&
      other.package == package &&
      other.flavor == flavor &&
      other.surface == surface &&
      other.theme == theme &&
      other.device == device;

  @override
  int get hashCode => Object.hash(package, flavor, surface, theme, device);

  @override
  String toString() =>
      'SplashPlace($package${flavor == null ? '' : '/$flavor'}'
      '${surface == null ? '' : ' ${surface!.name}'}'
      '${theme == null ? '' : ' ${theme!.name}'}'
      '${device == null ? '' : ' on $device'})';
}

/// The address segments naming [package] and, if given, [flavor].
///
/// The package stays one segment even though its path may contain slashes,
/// matching the asset inspector — a flavor after it would otherwise be
/// indistinguishable from another directory level.
List<String> splashSegments(String package, [String? flavor]) => [
  package,
  if (flavor != null && flavor.isNotEmpty) flavor,
];

/// The axes naming a cell. Empty entries are omitted rather than written blank,
/// so an address that names no cell round-trips to one that names no cell.
Map<String, String> splashAxes({
  SplashSurface? surface,
  SplashTheme? theme,
  String? device,
}) => {
  if (surface != null) 'surface': surface.name,
  if (theme != null) 'theme': theme.name,
  if (device != null && device.isNotEmpty) 'device': device,
};

/// The inverse of [splashSegments] and [splashAxes].
///
/// An unknown axis value reads back as null rather than throwing: an address is
/// a thing people type, and a typo should land you on the package showing
/// everything rather than on an error.
SplashPlace? splashPlace(
  List<String> segments, [
  Map<String, String> axes = const {},
]) {
  if (segments.isEmpty) return null;
  var flavor = segments.length > 1 ? segments[1] : null;
  var device = axes['device'];
  return SplashPlace(
    segments.first,
    flavor: flavor == null || flavor.isEmpty ? null : flavor,
    surface: axes['surface'] == null
        ? null
        : SplashSurface.byName(axes['surface']!),
    theme: axes['theme'] == null ? null : SplashTheme.byName(axes['theme']!),
    device: device == null || device.isEmpty ? null : device,
  );
}

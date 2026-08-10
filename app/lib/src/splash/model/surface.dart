/// The vocabulary a splash is described in, in **plain Dart**.
///
/// Deliberately free of Flutter, for the reason `catalog/devices.dart` gives at
/// its own top: `fw` and MCP link this to validate `--surface` and to describe a
/// placement in words, and they are compiled with `dart compile exe`, where
/// `package:flutter` cannot load at all. The panel maps [SplashFit] onto
/// `BoxFit` and [SplashAlignment] onto `Alignment` at the one place pixels are
/// drawn.
library;

// Pure Dart, like this file — the device table is shared with `fw` and MCP,
// which are compiled with `dart compile exe`.
import 'package:flutterware/devices.dart';

/// Which rendering path draws the splash.
///
/// [android12] is a surface of its own rather than a flag on [android] because
/// it is genuinely a different path: it reads a different section of the config,
/// ignores most of the legacy keys, and masks its icon. Folding the two together
/// is exactly the mistake this plugin exists to make visible.
enum SplashSurface {
  android('Android', 'Android 11 and earlier'),
  android12('Android 12+', 'Android 12 and later'),
  ios('iOS', 'iOS'),
  web('Web', 'Web');

  const SplashSurface(this.label, this.description);

  /// What goes in an address — `?surface=android12`.
  final String label;
  final String description;

  static SplashSurface? byName(String name) {
    for (var value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The suffix this surface's platform-specific keys carry — `color_android`,
  /// `image_ios`, `background_image_web`.
  ///
  /// Both Android surfaces share `android`: the legacy suffix is the platform's,
  /// and the Android 12 section overrides from inside `android_12:` rather than
  /// by having a suffix of its own.
  String get keySuffix => switch (this) {
    SplashSurface.android || SplashSurface.android12 => 'android',
    SplashSurface.ios => 'ios',
    SplashSurface.web => 'web',
  };

  /// Whether the project switched this surface off with `android: false`.
  String get enableKey => keySuffix;
}

/// Light or dark. The `_dark` half of every key in the cascade.
enum SplashTheme {
  light('Light'),
  dark('Dark');

  const SplashTheme(this.label);

  final String label;

  static SplashTheme? byName(String name) {
    for (var value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// How an image is scaled into the space it is given.
///
/// Ours rather than `BoxFit` so this file stays Flutter-free. The names are
/// `BoxFit`'s where they mean the same thing, so the mapping in the panel is
/// obvious and cannot be got subtly wrong.
enum SplashFit {
  /// Drawn at its natural size — the 4×-density source divided by four.
  none,
  contain,
  cover,
  fill,
  fillWidth,
  fillHeight,
}

/// Where an image sits in the space it is given, in the -1..1 coordinates
/// `Alignment` uses.
class SplashAlignment {
  const SplashAlignment(this.x, this.y);

  static const topLeft = SplashAlignment(-1, -1);
  static const topCenter = SplashAlignment(0, -1);
  static const topRight = SplashAlignment(1, -1);
  static const centerLeft = SplashAlignment(-1, 0);
  static const center = SplashAlignment(0, 0);
  static const centerRight = SplashAlignment(1, 0);
  static const bottomLeft = SplashAlignment(-1, 1);
  static const bottomCenter = SplashAlignment(0, 1);
  static const bottomRight = SplashAlignment(1, 1);

  final double x;
  final double y;

  Map<String, Object?> toJson() => {'x': x, 'y': y};

  static SplashAlignment fromJson(Map<String, Object?> json) => SplashAlignment(
    (json['x']! as num).toDouble(),
    (json['y']! as num).toDouble(),
  );

  /// How a human reads it back — what `fw describe` prints.
  String get label => switch ((x, y)) {
    (0.0, 0.0) => 'center',
    (0.0, -1.0) => 'top',
    (0.0, 1.0) => 'bottom',
    (-1.0, 0.0) => 'left',
    (1.0, 0.0) => 'right',
    (-1.0, -1.0) => 'top left',
    (1.0, -1.0) => 'top right',
    (-1.0, 1.0) => 'bottom left',
    (1.0, 1.0) => 'bottom right',
    _ => '$x, $y',
  };

  @override
  bool operator ==(Object other) =>
      other is SplashAlignment && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'SplashAlignment($label)';
}

/// A fit and an alignment together — what every one of the three placement
/// vocabularies below decodes to.
typedef Placement = (SplashFit fit, SplashAlignment alignment);

/// Decodes `android_gravity`.
///
/// Android's gravity is a bitmask written as `|`-separated names, so `fill` and
/// `bottom` can arrive in one string and both mean something. The `fill*` flags
/// decide the fit; everything else contributes to the alignment. `clip_*` is
/// accepted and ignored — it constrains overdraw rather than placement, and
/// pretending to model it would be a lie the preview could not keep.
///
/// Defaults to centred, which is what the package does with no gravity set.
Placement parseAndroidGravity(String? gravity) {
  if (gravity == null || gravity.trim().isEmpty) {
    return (SplashFit.none, SplashAlignment.center);
  }

  var flags = {
    for (var part in gravity.toLowerCase().split('|'))
      if (part.trim().isNotEmpty) part.trim(),
  };

  var fillH = flags.contains('fill') || flags.contains('fill_horizontal');
  var fillV = flags.contains('fill') || flags.contains('fill_vertical');

  var fit = switch ((fillH, fillV)) {
    (true, true) => SplashFit.fill,
    (true, false) => SplashFit.fillWidth,
    (false, true) => SplashFit.fillHeight,
    (false, false) => SplashFit.none,
  };

  // `start`/`end` are the layout-direction-aware spellings of left/right. The
  // preview is drawn left-to-right, which is the only direction it can know.
  var x = switch (flags) {
    _ when flags.contains('left') || flags.contains('start') => -1.0,
    _ when flags.contains('right') || flags.contains('end') => 1.0,
    _ => 0.0,
  };
  var y = switch (flags) {
    _ when flags.contains('top') => -1.0,
    _ when flags.contains('bottom') => 1.0,
    _ => 0.0,
  };

  return (fit, SplashAlignment(x, y));
}

/// Decodes `ios_content_mode`, a `UIViewContentMode` name.
///
/// Defaults to `center`, which is the package's own default.
Placement parseIosContentMode(String? mode) => switch (mode?.trim()) {
  'scaleToFill' => (SplashFit.fill, SplashAlignment.center),
  'scaleAspectFit' => (SplashFit.contain, SplashAlignment.center),
  'scaleAspectFill' => (SplashFit.cover, SplashAlignment.center),
  'top' => (SplashFit.none, SplashAlignment.topCenter),
  'bottom' => (SplashFit.none, SplashAlignment.bottomCenter),
  'left' => (SplashFit.none, SplashAlignment.centerLeft),
  'right' => (SplashFit.none, SplashAlignment.centerRight),
  'topLeft' => (SplashFit.none, SplashAlignment.topLeft),
  'topRight' => (SplashFit.none, SplashAlignment.topRight),
  'bottomLeft' => (SplashFit.none, SplashAlignment.bottomLeft),
  'bottomRight' => (SplashFit.none, SplashAlignment.bottomRight),
  _ => (SplashFit.none, SplashAlignment.center),
};

/// Decodes `web_image_mode`, which becomes a CSS `background-size`.
Placement parseWebImageMode(String? mode) => switch (mode?.trim()) {
  'contain' => (SplashFit.contain, SplashAlignment.center),
  'stretch' => (SplashFit.fill, SplashAlignment.center),
  'cover' => (SplashFit.cover, SplashAlignment.center),
  _ => (SplashFit.none, SplashAlignment.center),
};

/// The legal values for each vocabulary, for validation and for the choices an
/// action offers. Kept beside the parsers so a value cannot be legal in one and
/// unknown in the other.
const androidGravityValues = [
  'bottom',
  'center',
  'center_horizontal',
  'center_vertical',
  'clip_horizontal',
  'clip_vertical',
  'end',
  'fill',
  'fill_horizontal',
  'fill_vertical',
  'left',
  'right',
  'start',
  'top',
];

const iosContentModeValues = [
  'scaleToFill',
  'scaleAspectFit',
  'scaleAspectFill',
  'center',
  'top',
  'bottom',
  'left',
  'right',
  'topLeft',
  'topRight',
  'bottomLeft',
  'bottomRight',
];

const webImageModeValues = ['center', 'contain', 'stretch', 'cover'];

const brandingModeValues = ['bottom', 'bottomRight', 'bottomLeft'];

/// Where branding sits. A far smaller vocabulary than the image's, and its own
/// key, so it gets its own decoder rather than being squeezed into one of the
/// three above.
SplashAlignment parseBrandingMode(String? mode) => switch (mode?.trim()) {
  'bottomLeft' => SplashAlignment.bottomLeft,
  'bottomRight' => SplashAlignment.bottomRight,
  _ => SplashAlignment.bottomCenter,
};

/// Source images are authored at 4× density, so a natural-size placement draws
/// them at a quarter of their pixel dimensions.
const sourceDensity = 4.0;

/// The device a surface is previewed on when the address names none.
///
/// A real screen rather than one arbitrary rectangle for everything. The old
/// single 393×852 canvas meant the iOS tile and the Android tile were literally
/// the same picture, which hid the only thing worth comparing them for.
String? defaultSplashDeviceId(SplashSurface surface) => switch (surface) {
  // The shape almost every current Android phone is, gesture bar included.
  SplashSurface.android || SplashSurface.android12 => 'android-tall',
  SplashSurface.ios => 'iphone-16',
  // The web splash is a full-page background in a browser, not a device.
  SplashSurface.web => null,
};

/// How big a screen to draw every cell at — the matrix's one size axis.
///
/// **A class, not a device, and that is the whole point.** Naming a device names
/// a platform with it: an iPhone SE cannot be a canvas for the Android row, so a
/// picker offering nineteen devices over eight tiles moved two of them and
/// silently ignored the rest. A size class belongs to no platform, so one
/// control can honestly move all eight — each surface resolves the class to its
/// own hardware through [splashDeviceIdFor], and gets its own insets with it.
///
/// Every platform here has the same four sizes on sale, which is why this works
/// rather than merely reads well: a small phone, a typical one, a large one and
/// a tablet exist on iOS and on Android alike.
enum SplashScreenSize {
  smallPhone('small-phone', 'Small phone'),
  phone('phone', 'Phone'),
  largePhone('large-phone', 'Large phone'),
  tablet('tablet', 'Tablet');

  const SplashScreenSize(this.id, this.label);

  /// What goes in an address — `?size=large-phone`.
  final String id;
  final String label;

  static SplashScreenSize? byId(String id) {
    for (var value in values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

/// The screen [size] means on [surface] — a real device, with real insets.
///
/// Null [size] is each surface's own default, which is what the matrix shows
/// until somebody picks something.
///
/// **Web borrows the iOS dimensions and none of its hardware.** A browser on a
/// phone is a real place a web splash is seen, and the viewport is the only
/// thing that matters there — so the tile takes the size and draws no safe
/// areas, because a browser has no notch.
String? splashDeviceIdFor(SplashSurface surface, SplashScreenSize? size) {
  if (size == null) return defaultSplashDeviceId(surface);
  return switch (surface) {
    SplashSurface.android || SplashSurface.android12 => switch (size) {
      SplashScreenSize.smallPhone => 'android-small',
      SplashScreenSize.phone => 'android-tall',
      SplashScreenSize.largePhone => 'android-big',
      SplashScreenSize.tablet => 'android-medium-tablet',
    },
    SplashSurface.ios || SplashSurface.web => switch (size) {
      SplashScreenSize.smallPhone => 'iphone-se',
      SplashScreenSize.phone => 'iphone-16',
      SplashScreenSize.largePhone => 'iphone-16-pro-max',
      SplashScreenSize.tablet => 'ipad-pro-13',
    },
  };
}

/// Which class a concrete device falls into — the inverse of
/// [splashDeviceIdFor], for the devices it does not name.
///
/// The fit sweep reports against every phone and tablet in the table, not just
/// the four this axis can select, so a finding about an iPhone 13 mini has to
/// land somewhere. Classifying by size rather than by a lookup means it always
/// does, and it is also what pins down what the four class names mean: under
/// 380dp is small, 430 and over is large, a tablet is a tablet.
SplashScreenSize? splashSizeForDevice(String deviceId) {
  var device = deviceById(deviceId);
  if (device == null) return null;
  if (device.kind == DeviceKind.tablet) return SplashScreenSize.tablet;
  if (device.width < 380) return SplashScreenSize.smallPhone;
  if (device.width >= 430) return SplashScreenSize.largePhone;
  return SplashScreenSize.phone;
}

/// The logical canvas a surface is previewed at, in the order (width, height).
///
/// It has to live here rather than in the panel, and it has to be a real
/// device-sized canvas rather than whatever box the tile happens to be. A
/// natural-size placement is 256dp because the source is 1024px at 4×, and
/// "256dp" only means anything against a real screen — rendering it into a
/// 160dp-wide thumbnail would show an image overflowing a phone that does not
/// exist. So the render is always at these dimensions and scaled down to fit
/// afterwards, which keeps every proportion true.
///
/// [width] and [height] come from the chosen device when there is one. The
/// panel and the headless guest both read this, so an exported PNG is the same
/// picture at a different scale rather than a different picture.
(double, double) splashPreviewSize(
  SplashSurface surface, {
  double? width,
  double? height,
}) {
  if (width != null && height != null) return (width, height);
  return switch (surface) {
    // A desktop browser viewport; the web splash is a full-page background.
    SplashSurface.web => (1280, 800),
    _ => (393, 852),
  };
}

/// The fraction of an Android 12 icon canvas that survives the mask.
///
/// The package documents two pairs — a 1152px image fitting a 768px circle, and
/// a 960px image (with an icon background) fitting a 640px one. Both are two
/// thirds, which is the same fact as "one-third of the foreground is masked",
/// and the same ratio as Android's own 240dp icon with its inner 160dp visible.
const android12MaskFraction = 2 / 3;

/// The icon slot Android 12 draws into, in logical pixels.
///
/// Android's splash icon is 240dp square with the inner 160dp visible. The
/// preview draws that slot at that size rather than scaling it to the canvas,
/// because the whole point of this surface is that the icon is *not* screen
/// sized however large the source image is.
const android12IconCanvasDp = 240.0;

/// The icon canvas Android 12 expects, in pixels, with and without an icon
/// background colour.
int android12IconSize({required bool hasIconBackground}) =>
    hasIconBackground ? 960 : 1152;

/// The branding canvas Android 12 expects, in pixels.
const android12BrandingWidth = 800;
const android12BrandingHeight = 320;

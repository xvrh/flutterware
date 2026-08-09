/// The canvases `flutter_native_splash` expects, and how a source image lands
/// on one.
///
/// **This is the arithmetic nobody using the package knows**, which is the whole
/// case for the studio. The loop it replaces is: open Figma, remember that
/// Android 12 masks the inner two thirds, export at exactly 1152×1152, guess the
/// padding, run `create`, build, look at a phone, find it cropped, repeat. Every
/// number in it is already in this codebase — `android12IconSize`,
/// `android12MaskFraction`, `sourceDensity` — and none of them is anywhere the
/// person exporting the PNG will see it.
///
/// Pure Dart and no Flutter, so `fw run splash prepare` computes the same canvas
/// the crop surface draws. The pixels are pushed in `studio_render.dart`, which
/// is the only half that needs `package:image`.
library;

import 'dart:math';

import 'package:flutterware/devices.dart';

import 'surface.dart';

/// What is being made.
enum SplashStudioTarget {
  /// The Android 12 splash icon — the one with the circular mask and the two
  /// canvas sizes nobody remembers.
  android12Icon('Android 12 icon'),

  /// The Android 12 branding image, at the bottom of the window.
  android12Branding('Android 12 branding'),

  /// The legacy `image`, drawn at a quarter of its pixel size.
  image('Splash image'),

  /// A full-bleed `background_image`, scaled to cover whatever screen it meets.
  backgroundImage('Background image');

  const SplashStudioTarget(this.label);

  final String label;

  static SplashStudioTarget? byName(String name) {
    for (var target in values) {
      if (target.name == name) return target;
    }
    return null;
  }

  /// The surface a change to this target shows up on.
  ///
  /// One tile, not eight. Six of the eight do not read the key being made, so a
  /// matrix updating live would be six unchanged pictures around the one that
  /// matters.
  SplashSurface get previewSurface => switch (this) {
    SplashStudioTarget.android12Icon ||
    SplashStudioTarget.android12Branding => SplashSurface.android12,
    SplashStudioTarget.image ||
    SplashStudioTarget.backgroundImage => SplashSurface.android,
  };

  /// The config key this target's output belongs under.
  String keyFor(SplashTheme theme) => switch ((this, theme)) {
    (SplashStudioTarget.android12Icon, SplashTheme.light) => 'android_12.image',
    (SplashStudioTarget.android12Icon, SplashTheme.dark) =>
      'android_12.image_dark',
    (SplashStudioTarget.android12Branding, SplashTheme.light) =>
      'android_12.branding',
    (SplashStudioTarget.android12Branding, SplashTheme.dark) =>
      'android_12.branding_dark',
    (SplashStudioTarget.image, SplashTheme.light) => 'image',
    (SplashStudioTarget.image, SplashTheme.dark) => 'image_dark',
    (SplashStudioTarget.backgroundImage, SplashTheme.light) =>
      'background_image',
    (SplashStudioTarget.backgroundImage, SplashTheme.dark) =>
      'background_image_dark',
  };
}

/// The target and theme a config key names, or null when the key is not one the
/// studio can make.
///
/// This is what turns a warning into a door: a reader looking at "there is no
/// android_12 image" is exactly the person who needs the 1152 canvas, and making
/// them find a menu instead is how a tool ends up unused.
(SplashStudioTarget, SplashTheme)? splashStudioTargetForKey(String key) {
  var theme = key.contains('_dark') ? SplashTheme.dark : SplashTheme.light;
  var target = switch (key) {
    'android_12.image' ||
    'android_12.image_dark' => SplashStudioTarget.android12Icon,
    'android_12.branding' ||
    'android_12.branding_dark' => SplashStudioTarget.android12Branding,
    _ when key.startsWith('background_image') =>
      SplashStudioTarget.backgroundImage,
    _ when key.startsWith('image') => SplashStudioTarget.image,
    _ => null,
  };
  return target == null ? null : (target, theme);
}

/// How wide the legacy `image` is asked to be, in logical pixels, when nobody
/// says.
///
/// The question the studio asks — "how wide on screen?" — is the right one and
/// the one nobody thinks to ask, because the config has no field for it: the
/// answer is baked into the pixel size of the file you export. 160dp is a little
/// under half the width of the narrowest phone in [Devices.all], which is a logo
/// that reads on every screen and is clipped on none.
const splashDefaultImageWidthDp = 160.0;

/// A canvas to export onto, and the part of it that survives.
class SplashStudioCanvas {
  const SplashStudioCanvas({
    required this.target,
    required this.width,
    required this.height,
    required this.usableWidth,
    required this.usableHeight,
    required this.circularMask,
    required this.explanation,
  });

  final SplashStudioTarget target;

  /// The exported file's pixel size — exactly what the generator expects, so
  /// `validateSplash` has nothing to say about it afterwards.
  final int width;
  final int height;

  /// The part a device actually shows. Equal to the canvas for every target but
  /// the Android 12 icon, whose outer third is masked away.
  final double usableWidth;
  final double usableHeight;

  /// The usable area is a circle inscribed in [usableWidth] × [usableHeight],
  /// so a square filling it loses its corners.
  final bool circularMask;

  /// Why these numbers — shown beside the crop surface and printed by the
  /// action, because a canvas size with no reason attached is a number to
  /// mistrust.
  final String explanation;

  double get usableRadius =>
      (usableWidth < usableHeight ? usableWidth : usableHeight) / 2;

  /// The margin between the canvas edge and the usable area, per side.
  double get inset => (width - usableWidth) / 2;

  Map<String, Object?> toJson() => {
    'target': target.name,
    'width': width,
    'height': height,
    'usableWidth': usableWidth,
    'usableHeight': usableHeight,
    if (circularMask) 'circularMask': true,
    'explanation': explanation,
  };
}

/// The canvas [target] wants for a source of [sourceWidth] × [sourceHeight].
///
/// The source only matters for [SplashStudioTarget.image], whose canvas has no
/// fixed size at all — it is however many pixels make the logo the width you
/// asked for, and its aspect follows the source rather than being imposed.
SplashStudioCanvas splashStudioCanvas({
  required SplashStudioTarget target,
  required int sourceWidth,
  required int sourceHeight,
  bool hasIconBackground = false,
  double? logicalWidth,
}) {
  switch (target) {
    case SplashStudioTarget.android12Icon:
      var size = android12IconSize(hasIconBackground: hasIconBackground);
      var usable = size * android12MaskFraction;
      return SplashStudioCanvas(
        target: target,
        width: size,
        height: size,
        usableWidth: usable,
        usableHeight: usable,
        circularMask: true,
        explanation:
            'Android draws the splash icon into a ${android12IconCanvasDp.toInt()}dp '
            'slot and masks it to a circle at '
            '${(android12MaskFraction * 100).round()}%. The package wants a '
            '$size×$size file '
            '${hasIconBackground ? 'when an icon_background_color is set' : 'with no icon background'}, '
            'so keep the logo inside the ${usable.round()}px circle — anything '
            'outside it is cut off, not scaled down.',
      );

    case SplashStudioTarget.android12Branding:
      return SplashStudioCanvas(
        target: target,
        width: android12BrandingWidth,
        height: android12BrandingHeight,
        usableWidth: android12BrandingWidth.toDouble(),
        usableHeight: android12BrandingHeight.toDouble(),
        circularMask: false,
        explanation:
            'The Android 12 branding image is a fixed '
            '$android12BrandingWidth×$android12BrandingHeight, placed at the '
            'bottom of the window by the system. All of it is shown.',
      );

    case SplashStudioTarget.image:
      var dp = logicalWidth ?? splashDefaultImageWidthDp;
      var width = (dp * sourceDensity).round();
      var height = sourceHeight <= 0 || sourceWidth <= 0
          ? width
          : (width * sourceHeight / sourceWidth).round();
      return SplashStudioCanvas(
        target: target,
        width: width,
        height: height,
        usableWidth: width.toDouble(),
        usableHeight: height.toDouble(),
        circularMask: false,
        explanation:
            'A splash image is drawn at a quarter of its pixel size, so '
            '${dp.round()}dp wide on screen means a $width×$height file. That '
            'division is the whole reason a "big" export comes out clipped: '
            'nothing scales it down to fit the phone.',
      );

    case SplashStudioTarget.backgroundImage:
      var extremes = splashBackgroundAspects();
      var width = (extremes.width * sourceDensity).round();
      var height = (width * extremes.tallest).round();
      return SplashStudioCanvas(
        target: target,
        width: width,
        height: height,
        usableWidth: width.toDouble(),
        usableHeight: width * extremes.widest,
        circularMask: false,
        explanation:
            'A background image is scaled to cover the screen, so on anything '
            'less tall than ${extremes.tallest.toStringAsFixed(2)}:1 the top '
            'and bottom are cropped. Keep anything that matters inside the '
            'centre band — that is what every screen in the device table shows.',
      );
  }
}

/// The aspect extremes a background image has to survive.
///
/// Read off [Devices.all] rather than written down, so a device added to that
/// table changes this without anyone remembering to.
({double width, double tallest, double widest}) splashBackgroundAspects() {
  var widthDp = 0.0;
  var tallest = 0.0;
  var widest = double.infinity;
  for (var device in Devices.all) {
    if (device.kind == DeviceKind.desktop) continue;
    var short = device.width < device.height ? device.width : device.height;
    var long = device.width < device.height ? device.height : device.width;
    if (short > widthDp) widthDp = short;
    var aspect = long / short;
    if (aspect > tallest) tallest = aspect;
    if (aspect < widest) widest = aspect;
  }
  // A table with nothing in it is not a state this can reach, but a division by
  // zero downstream would be a very confusing way to find that out.
  if (widthDp == 0) return (width: 400, tallest: 2, widest: 4 / 3);
  return (width: widthDp, tallest: tallest, widest: widest);
}

/// Where the source sits on the canvas.
class SplashCrop {
  const SplashCrop({required this.scale, this.offsetX = 0, this.offsetY = 0});

  /// Multiplier on the source's pixel size. 1 draws it at its own resolution.
  final double scale;

  /// Canvas pixels from the centre, positive right and down.
  final double offsetX;
  final double offsetY;

  SplashCrop copyWith({double? scale, double? offsetX, double? offsetY}) =>
      SplashCrop(
        scale: scale ?? this.scale,
        offsetX: offsetX ?? this.offsetX,
        offsetY: offsetY ?? this.offsetY,
      );

  Map<String, Object?> toJson() => {
    'scale': scale,
    if (offsetX != 0) 'offsetX': offsetX,
    if (offsetY != 0) 'offsetY': offsetY,
  };
}

/// The crop that puts the whole source inside the usable area, centred.
///
/// **Fitted to the usable square, not to the inscribed circle.** For the Android
/// 12 icon that means a square source touches the mask and loses its corners —
/// which is what the package's own "1152 file, 768 image" advice produces, and
/// what a logo with transparent corners wants. Fitting to the circle instead
/// would shrink every icon by 30% to protect corners that are usually empty.
/// [splashCornerOverhang] is how a reader is told which case they are in.
SplashCrop splashFitCrop({
  required SplashStudioCanvas canvas,
  required int sourceWidth,
  required int sourceHeight,
}) {
  if (sourceWidth <= 0 || sourceHeight <= 0) return const SplashCrop(scale: 1);
  var x = canvas.usableWidth / sourceWidth;
  var y = canvas.usableHeight / sourceHeight;
  return SplashCrop(scale: x < y ? x : y);
}

/// How far the drawn source spills outside the usable area, in canvas pixels.
///
/// Zero when it fits. The number is the point: "too big" names no edit, and
/// "84px outside the mask" names one.
double splashCropOverflow({
  required SplashStudioCanvas canvas,
  required SplashCrop crop,
  required int sourceWidth,
  required int sourceHeight,
}) {
  var drawnWidth = sourceWidth * crop.scale;
  var drawnHeight = sourceHeight * crop.scale;
  var overX = (drawnWidth / 2 + crop.offsetX.abs()) - canvas.usableWidth / 2;
  var overY = (drawnHeight / 2 + crop.offsetY.abs()) - canvas.usableHeight / 2;
  var worst = overX > overY ? overX : overY;
  return worst > 0 ? worst : 0;
}

/// How far the drawn source's corners reach past a circular mask.
///
/// Zero for a target with no mask, and zero for a source small enough that its
/// corners are inside the circle. Non-zero is **not** an error: a logo with
/// transparent corners is unaffected, and one with a full-bleed square is not.
/// Only the person looking at it knows which, which is exactly why this is
/// reported rather than corrected.
double splashCornerOverhang({
  required SplashStudioCanvas canvas,
  required SplashCrop crop,
  required int sourceWidth,
  required int sourceHeight,
}) {
  if (!canvas.circularMask) return 0;
  var halfWidth = sourceWidth * crop.scale / 2 + crop.offsetX.abs();
  var halfHeight = sourceHeight * crop.scale / 2 + crop.offsetY.abs();
  var corner = sqrt(halfWidth * halfWidth + halfHeight * halfHeight);
  var over = corner - canvas.usableRadius;
  return over > 0 ? over : 0;
}

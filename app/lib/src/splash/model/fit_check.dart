/// Whether a splash survives the range of screens it will actually meet.
///
/// **The question the preview could not answer.** Every other rule in this
/// plugin is about what the generator does with the config; this one is about
/// what happens afterwards, on a phone whose screen is not the one the tile was
/// drawn at. A 1024px source is 256dp, which is comfortable on the 412dp phone
/// most people are holding and clipped on a 360dp one — and nothing in a config
/// says so.
///
/// It is a sweep rather than a picture on purpose. Making somebody click through
/// eighteen devices looking for the broken one is not an answer; computing which
/// devices break and naming them is. The picture then follows, because the
/// finding carries the device and the panel can go there.
///
/// Pure arithmetic over [Devices.all] — no rendering, no Flutter — so `fw` and
/// MCP report the same thing the panel draws.
library;

import 'package:flutterware/devices.dart';

import 'composition.dart';
import 'surface.dart';

/// What is wrong on a particular screen.
enum SplashFitIssue {
  /// The image is drawn larger than the screen, so its edges are cut off.
  ///
  /// Only reachable through the fits that do not scale to the screen —
  /// [SplashFit.none] always, and the `fill*` pair on their unstretched axis.
  /// `contain` and `cover` cannot clip by construction.
  imageClipped,

  /// The branding sits inside the bottom safe area — under the iOS home
  /// indicator or the Android gesture bar.
  ///
  /// The default `branding_bottom_padding` is 0 and the default
  /// `branding_mode` is `bottom`, so this is what a project that set `branding`
  /// and nothing else gets.
  brandingUnderSafeArea,
}

/// One device a composition does not fit on.
class SplashFitFinding {
  const SplashFitFinding({
    required this.device,
    required this.issue,
    required this.amount,
  });

  final Device device;
  final SplashFitIssue issue;

  /// How far past the line it is, in logical pixels — the number that turns
  /// "does not fit" into "make it 40dp smaller".
  final double amount;
}

/// The devices a surface will actually be seen on.
///
/// Platform-filtered, because "your Android splash is clipped on an iPad" is
/// noise, and noise is what makes people stop reading warnings. Desktop is
/// excluded outright: no surface here ships one, and the web splash is a
/// browser viewport rather than a device.
List<Device> splashDevicesFor(SplashSurface surface) {
  var platform = switch (surface) {
    SplashSurface.android || SplashSurface.android12 => DevicePlatform.android,
    SplashSurface.ios => DevicePlatform.ios,
    SplashSurface.web => null,
  };
  if (platform == null) return const [];
  return [
    for (var device in Devices.all)
      if (device.platform == platform && device.kind != DeviceKind.desktop)
        device,
  ];
}

/// The size a layer is actually drawn at on a screen of [screenWidth] ×
/// [screenHeight].
///
/// **The renderer calls this too.** `SplashRender` used to do the same
/// arithmetic inline, which meant the picture and any claim about the picture
/// were two implementations of one rule — and the first time they disagreed the
/// warning would be the one nobody believed.
(double, double) splashDrawnSize({
  required SplashFit fit,
  required double naturalWidth,
  required double naturalHeight,
  required double screenWidth,
  required double screenHeight,
}) {
  double scaled(bool cover) {
    if (naturalWidth <= 0 || naturalHeight <= 0) return 1;
    var x = screenWidth / naturalWidth;
    var y = screenHeight / naturalHeight;
    if (cover) return x > y ? x : y;
    return x < y ? x : y;
  }

  return switch (fit) {
    SplashFit.none => (naturalWidth, naturalHeight),
    SplashFit.fill => (screenWidth, screenHeight),
    SplashFit.fillWidth => (screenWidth, naturalHeight),
    SplashFit.fillHeight => (naturalWidth, screenHeight),
    SplashFit.contain => (
      naturalWidth * scaled(false),
      naturalHeight * scaled(false),
    ),
    SplashFit.cover => (
      naturalWidth * scaled(true),
      naturalHeight * scaled(true),
    ),
  };
}

/// Every device [composition] does not fit on, worst first.
///
/// Empty is the ordinary answer and the one most configs get. That is the point
/// of computing it rather than showing it: a rule that fires on everything gets
/// ignored, and this one fires on the projects that are actually about to ship
/// a clipped logo.
List<SplashFitFinding> checkSplashFit(SplashComposition composition) {
  if (!composition.enabled) return const [];

  var findings = <SplashFitFinding>[];

  for (var device in splashDevicesFor(composition.surface)) {
    // The Android 12 icon is a fixed 240dp slot the system centres and masks;
    // it is the same size on every screen, so there is nothing here to sweep.
    var image = composition.surface == SplashSurface.android12
        ? null
        : composition.image;

    if (image != null && !image.missing) {
      var width = image.naturalWidth;
      var height = image.naturalHeight;
      if (width != null && height != null) {
        var (drawnWidth, drawnHeight) = splashDrawnSize(
          fit: image.fit,
          naturalWidth: width,
          naturalHeight: height,
          screenWidth: device.width,
          screenHeight: device.height,
        );
        var over = [
          drawnWidth - device.width,
          drawnHeight - device.height,
        ].reduce((a, b) => a > b ? a : b);
        // A hair over is rounding, not a bug worth a warning.
        if (over > 0.5) {
          findings.add(
            SplashFitFinding(
              device: device,
              issue: SplashFitIssue.imageClipped,
              amount: over,
            ),
          );
        }
      }
    }

    // Android 12's branding is `windowSplashScreenBrandingImage`, which the
    // system positions itself — `_applyStylesXml` for the v31 templates takes no
    // padding at all, so `branding_bottom_padding` does not reach this surface
    // and there is no edit that would answer the warning. Sweeping it here was
    // a false positive with no fix behind it.
    var branding = composition.surface == SplashSurface.android12
        ? null
        : composition.branding;
    if (branding != null &&
        composition.brandingAlignment.y > 0 &&
        device.insetBottom > 0) {
      var shortfall =
          device.insetBottom - composition.brandingBottomPadding.toDouble();
      if (shortfall > 0.5) {
        findings.add(
          SplashFitFinding(
            device: device,
            issue: SplashFitIssue.brandingUnderSafeArea,
            amount: shortfall,
          ),
        );
      }
    }
  }

  findings.sort((a, b) => b.amount.compareTo(a.amount));
  return findings;
}

import 'dart:ui' as ui;

import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

// Ours hidden here, not theirs: this file names `device_frame`'s bodies.
import '../catalog/catalog_devices.dart' hide Devices;
import '../plugins/native/scenarios_results.dart';
import '../utils/raw_image_provider.dart';
import '../ui/theme.dart';

/// A captured step, in the silhouette of the device it ran as, wearing the
/// status chrome a real screenshot would have.
///
/// iOS devices get `device_frame`'s **hand-drawn bodies** — an SE with its
/// home button, a 13 with its notch — because the flow is a wall of phones
/// and generic lozenges all read alike. That mapping is the second list the
/// catalog's [deviceFrameFor] doc warns about, made safe the way it says:
/// `frames_test.dart` holds the two sets of measurements together, and any
/// device without a named body falls back to the same generic silhouette the
/// catalog draws. Desktop sizes and the bare test surface get a plain
/// border: a monitor body around a rectangle explains nothing.
///
/// Over the screen, the **fake status bar** (time, network, battery) and the
/// home indicator, tinted by the `SystemUiOverlayStyle` the app declared at
/// capture time — dev_studio's trick, kept because a status bar of the wrong
/// brightness is a shipped bug a screenshot exists to catch.
///
/// Displays `raw` captures through [RawImageProvider] — no decode, which is
/// the point of capturing raw — and `png` through the ordinary file image.
///
/// Unconstrained: renders at the device's logical size plus bezels. Put it in
/// a `FittedBox` (the flow graph does) or size it from outside.
class FramedShot extends StatelessWidget {
  const FramedShot({
    super.key,
    required this.step,
    required this.device,
    this.fallbackBrightness = Brightness.dark,
    this.screenOverlay,
  });

  final ScenarioRunStep step;

  /// The device the run was framed as, or null for the bare surface.
  final Device? device;

  /// Drawn over the screen, inside the frame — **in the screen's own logical
  /// coordinates**, which are exactly the guest coordinates a capture and its
  /// tree were taken in. The inspector's highlight and picker live here, and
  /// because the box is the guest's logical size they need no transform: they
  /// inherit the `FittedBox` and the device body above, like the catalog's
  /// overlay does.
  final Widget? screenOverlay;

  /// Icon brightness when the app declared no `SystemUiOverlayStyle` —
  /// derived from the brightness axis by the caller, so a dark-mode run
  /// defaults to light icons.
  final Brightness fallbackBrightness;

  /// The hand-drawn body for [id], or null for the generic fallback. Only
  /// devices whose named frame matches our table's screen exactly — the test
  /// pins that.
  static DeviceInfo? namedFrameFor(String id) => switch (id) {
    'iphone-se' => Devices.ios.iPhoneSE,
    'iphone-13-mini' => Devices.ios.iPhone13Mini,
    'iphone-13' => Devices.ios.iPhone13,
    'iphone-12-pro-max' => Devices.ios.iPhone12ProMax,
    'ipad' => Devices.ios.iPad,
    _ => null,
  };

  Brightness _brightness(String? declared) => switch (declared) {
    'light' => Brightness.light,
    'dark' => Brightness.dark,
    _ => fallbackBrightness,
  };

  @override
  Widget build(BuildContext context) {
    Widget image = Image(
      image: step.format == 'raw'
          ? RawImageProvider(
              RawImageData(step.imageFile, step.width, step.height),
            )
          : FileImage(step.imageFile),
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    var resolved = device;
    if (resolved == null) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.line),
        ),
        child: SizedBox(
          width: step.width.toDouble(),
          height: step.height.toDouble(),
          child: Stack(fit: StackFit.expand, children: [image, ?screenOverlay]),
        ),
      );
    }
    var screen = SizedBox(
      width: resolved.width,
      height: resolved.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          image,
          _StatusChrome(
            device: resolved,
            statusBrightness: _brightness(step.statusBrightness),
            navBrightness: _brightness(step.navBrightness),
          ),
          ?screenOverlay,
        ],
      ),
    );
    var chrome = namedFrameFor(resolved.id) ?? deviceFrameFor(resolved);
    if (chrome == null) {
      // A desktop size: a hairline, not a monitor body.
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.line),
        ),
        child: screen,
      );
    }
    return DeviceFrame(device: chrome, screen: screen);
  }
}

/// The status bar and the home indicator, drawn in the device's safe areas —
/// ported from dev_studio's `PhoneStatusBar`, SVGs and all.
class _StatusChrome extends StatelessWidget {
  const _StatusChrome({
    required this.device,
    required this.statusBrightness,
    required this.navBrightness,
  });

  final Device device;
  final Brightness statusBrightness;
  final Brightness navBrightness;

  static Color _colorFor(Brightness brightness) =>
      brightness == Brightness.light ? Colors.white : Colors.black;

  @override
  Widget build(BuildContext context) {
    var topColor = _colorFor(statusBrightness);
    var bottomColor = _colorFor(navBrightness);
    var compact = device.insetTop < 24;

    Widget icon(String svg) => SvgPicture.string(
      svg,
      height: compact ? 9 : 11,
      colorFilter: ui.ColorFilter.mode(topColor, BlendMode.srcIn),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (device.insetTop > 0) ...[
            Positioned(
              left: 0,
              top: 0,
              child: SizedBox(
                width: 110,
                height: device.insetTop,
                child: Center(
                  child: Text(
                    '9:41',
                    style: TextStyle(
                      fontSize: compact ? 12 : 14,
                      fontWeight: FontWeight.w600,
                      color: topColor,
                      // The chrome floats over the app's pixels, outside any
                      // Material — explicit, or it wears the yellow
                      // missing-style underline.
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: SizedBox(
                width: 110,
                height: device.insetTop,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      icon(_networkSvg),
                      const SizedBox(width: 5),
                      icon(_wifiSvg),
                      const SizedBox(width: 5),
                      icon(_batterySvg),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (device.insetBottom > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SizedBox(
                height: device.insetBottom,
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.36,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: bottomColor.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _batterySvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24.5" height="11.5" viewBox="0 0 24.5 11.5">
  <g transform="translate(0 -0.56)">
    <path d="M3.589,11.5a4.057,4.057,0,0,1-2.156-.374A2.543,2.543,0,0,1,.374,10.067,4.05,4.05,0,0,1,0,7.911V3.589A4.048,4.048,0,0,1,.374,1.433,2.543,2.543,0,0,1,1.433.374,4.048,4.048,0,0,1,3.589,0H18.41a4.052,4.052,0,0,1,2.157.374,2.543,2.543,0,0,1,1.058,1.058A4.059,4.059,0,0,1,22,3.589V7.911a4.061,4.061,0,0,1-.374,2.156,2.543,2.543,0,0,1-1.058,1.058,4.061,4.061,0,0,1-2.157.374ZM23,3.69s1.5.763,1.5,2-1.5,2-1.5,2Z" transform="translate(0 0.56)" fill="rgba(255,255,255,0.36)" fill-opacity="0.36" />
    <rect width="18" height="7.667" rx="1.6" transform="translate(2 2.477)" fill="#fff"/>
  </g>
</svg>
''';

const _networkSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="17.1" height="10.7" viewBox="0 0 17.1 10.7">
  <path d="M15.3,10.7a1.2,1.2,0,0,1-1.2-1.2V1.2A1.2,1.2,0,0,1,15.3,0h.6a1.2,1.2,0,0,1,1.2,1.2V9.5a1.2,1.2,0,0,1-1.2,1.2Zm-4.7,0A1.2,1.2,0,0,1,9.4,9.5V3.6a1.2,1.2,0,0,1,1.2-1.2h.6a1.2,1.2,0,0,1,1.2,1.2V9.5a1.2,1.2,0,0,1-1.2,1.2ZM6,10.7A1.2,1.2,0,0,1,4.8,9.5V5.9A1.2,1.2,0,0,1,6,4.7h.6A1.2,1.2,0,0,1,7.8,5.9V9.5a1.2,1.2,0,0,1-1.2,1.2Zm-4.8,0A1.2,1.2,0,0,1,0,9.5V7.9A1.2,1.2,0,0,1,1.2,6.7h.6A1.2,1.2,0,0,1,3,7.9V9.5a1.2,1.2,0,0,1-1.2,1.2Z" fill="#fff"/>
</svg>
''';

const _wifiSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="15.4" height="11.057" viewBox="0 0 15.4 11.057">
  <path d="M7.7,11.057a.315.315,0,0,1-.223-.094L5.462,8.932a.317.317,0,0,1,.01-.461,3.451,3.451,0,0,1,4.457,0,.312.312,0,0,1,.1.228.319.319,0,0,1-.094.233L7.924,10.964A.315.315,0,0,1,7.7,11.057ZM11.237,7.49a.309.309,0,0,1-.215-.086,4.945,4.945,0,0,0-6.641,0A.312.312,0,0,1,3.945,7.4L2.78,6.222a.325.325,0,0,1,0-.463,7.22,7.22,0,0,1,9.834,0,.325.325,0,0,1,0,.463L11.459,7.4A.31.31,0,0,1,11.237,7.49ZM13.92,4.783a.308.308,0,0,1-.217-.088,8.714,8.714,0,0,0-12.006,0,.311.311,0,0,1-.217.088.306.306,0,0,1-.22-.092L.094,3.515a.325.325,0,0,1,0-.46,10.989,10.989,0,0,1,15.205,0,.324.324,0,0,1,0,.46L14.14,4.691A.306.306,0,0,1,13.92,4.783Z" fill="#fff"/>
</svg>
''';

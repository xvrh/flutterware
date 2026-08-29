/// The status bar and home indicator a real screenshot has and a capture does
/// not.
///
/// Nothing in a `flutter_tester` draws system chrome, so a capture straight out
/// of one reads as a mockup even though every pixel of the app is real. This
/// draws it back — which also means the time is ours to fix at 9:41, as it has
/// been on every Apple screenshot since 2007.
///
/// **One implementation, two consumers.** The store frame draws it over a
/// device body composed onto a store canvas; the GUI's `FramedShot` draws it
/// over a captured step on the flow canvas. They were two copies for a while,
/// and the copies disagreed: the store's derived its glyph size from
/// [Device.insetTop] — a safe area, not a font metric — and rendered an Android
/// clock at 8 points against a real 14. Reported by a consumer as "the icons
/// and text look too small".
///
/// Published API, because a project's own [StoreFrame] draws it.
///
/// Pure Flutter on purpose. The GUI's copy drew its indicators from SVG through
/// `flutter_svg`, and that dependency is exactly why the store never shared it:
/// a published package does not gain one so that a default can have artwork.
/// [_IndicatorPainter] draws the same three shapes from primitives instead.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../devices.dart';

/// What a platform's status bar actually measures, in the device's own logical
/// pixels.
///
/// Measured rather than styled, on a booted iPhone 16 Pro Max and an Android 15
/// phone at 1080×2400 @420dpi, by scanning the rendered pixels of each. The
/// numbers are the observations; the comments are what they mean.
///
/// The two platforms differ by more than a font size, which is the reason this
/// is a table and not a pair of constants:
///
/// | | iOS | Android |
/// |---|---|---|
/// | safe-area top | 59 | 24 |
/// | clock digit height | 13.3 | 9.9 |
/// | leading margin | 60 | 17.5 |
/// | content centre, as a fraction of the inset | 0.55 | 0.49 |
///
/// The centre fraction is the one that surprises. Android's bar *is* its
/// inset, so its contents sit in the middle of it. An iPhone's 59 points are
/// mostly the space beside the Dynamic Island, and the clock is centred on the
/// island rather than on the safe area — which lands it below the middle.
class _Metrics {
  const _Metrics({
    required this.text,
    required this.weight,
    required this.icon,
    required this.centre,
    required this.leading,
    required this.trailing,
    required this.gap,
  });

  /// Font size. 17 and 14 are the platform's own; the digit heights above are
  /// what those sizes render to, and are how these were read back.
  final double text;
  final FontWeight weight;

  /// Indicator height. The three glyphs are drawn to this and take their
  /// widths from their own proportions.
  final double icon;

  /// Where the contents' vertical centre sits, as a fraction of
  /// [Device.insetTop].
  final double centre;

  /// How far the clock starts from the leading edge, and the indicators from
  /// the trailing one.
  ///
  /// A real device's margin already clears its own rounded corner — an iPhone's
  /// 60 against a corner that intrudes under 5 at the clock's height — so
  /// nothing here solves for the corner. An earlier version did, and on a body
  /// drawn with a corner twice the device's it pushed the clock a third of the
  /// way to the middle of the screen.
  final double leading;
  final double trailing;

  /// Between indicators.
  final double gap;

  static const ios = _Metrics(
    text: 17,
    weight: FontWeight.w600,
    icon: 11.5,
    centre: 0.55,
    leading: 60,
    trailing: 41,
    gap: 4,
  );

  static const android = _Metrics(
    text: 14,
    weight: FontWeight.w500,
    icon: 12,
    centre: 0.49,
    leading: 17.5,
    trailing: 16,
    gap: 5,
  );

  /// A desktop window has no status bar at all, and reaching this at all means
  /// a device with a top inset that is neither phone platform — so Android's
  /// is the closer guess.
  static _Metrics of(Device device) =>
      device.platform == DevicePlatform.ios ? ios : android;
}

/// The chrome, drawn over a screen of [device]'s logical size.
///
/// [scale] is what the screen has been drawn at — 1 where the capture is shown
/// at its own size, less where a store frame has fitted it onto a canvas. Every
/// measurement below is in the device's own units and reaches the canvas
/// through this one multiplication, which is what keeps a body drawn at 0.8
/// looking like the same phone as one drawn at 1.
///
/// Both brightnesses name the **icons**, following `SystemUiOverlayStyle` —
/// [Brightness.dark] is dark icons, for a light app. A scenario records what
/// the app declared at capture time, so a set whose app switches to a dark
/// screen gets light chrome on that shot and dark chrome on the others.
class StatusChrome extends StatelessWidget {
  const StatusChrome({
    super.key,
    required this.device,
    this.scale = 1,
    this.statusBrightness = Brightness.dark,
    this.navBrightness = Brightness.dark,
  });

  final Device device;
  final double scale;
  final Brightness statusBrightness;
  final Brightness navBrightness;

  static Color _colorFor(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    var m = _Metrics.of(device);
    var top = device.insetTop * scale;
    var bottom = device.insetBottom * scale;
    var statusColor = _colorFor(statusBrightness);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Guarded rather than laid out empty: an iPhone in landscape has an
          // `insetTop` of 0, and drawing no status bar there is exactly what
          // the real thing does.
          if (device.insetTop > 0) ...[
            _Slot(
              inset: top,
              centre: m.centre,
              alignment: Alignment.centerLeft,
              padding: m.leading * scale,
              child: Text(
                '9:41',
                style: TextStyle(
                  fontSize: m.text * scale,
                  fontWeight: m.weight,
                  color: statusColor,
                  height: 1,
                  // The chrome floats over the app's pixels, outside any
                  // Material — explicit, or it wears the yellow
                  // missing-style underline.
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            _Slot(
              inset: top,
              centre: m.centre,
              alignment: Alignment.centerRight,
              padding: m.trailing * scale,
              child: CustomPaint(
                size: Size(
                  _IndicatorPainter.widthFor(m.icon * scale, m.gap * scale),
                  m.icon * scale,
                ),
                painter: _IndicatorPainter(
                  color: statusColor,
                  gap: m.gap * scale,
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
                height: bottom,
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.36,
                    child: Container(
                      height: 5 * scale,
                      decoration: BoxDecoration(
                        color: _colorFor(navBrightness).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(2.5 * scale),
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

/// One end of the status bar, positioned by [_Metrics.centre].
///
/// A band of `inset` tall with the child centred in it would put the contents
/// at 0.5 on both platforms, which is right for Android and 3 points high on an
/// iPhone. So the child is centred on a line instead, and the line is the
/// platform's.
class _Slot extends StatelessWidget {
  const _Slot({
    required this.inset,
    required this.centre,
    required this.alignment,
    required this.padding,
    required this.child,
  });

  final double inset;
  final double centre;
  final Alignment alignment;
  final double padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    // Twice the centre line, so centring within it puts the child *on* that
    // line — and the box never reaches below the inset it belongs to, because
    // the contents are shorter than the band.
    height: inset * centre * 2,
    child: Align(
      alignment: alignment,
      child: Padding(
        padding: alignment == Alignment.centerLeft
            ? EdgeInsets.only(left: padding)
            : EdgeInsets.only(right: padding),
        child: child,
      ),
    ),
  );
}

/// Cellular, wi-fi and battery, drawn from primitives.
///
/// Proportions are the artwork the GUI drew through `flutter_svg` — 17.1×10.7,
/// 15.4×11.1 and 24.5×11.5 — so the two consumers show the same silhouettes
/// with no dependency on either side. Everything is expressed against the box's
/// height, so one number sizes all three.
class _IndicatorPainter extends CustomPainter {
  _IndicatorPainter({required this.color, required this.gap});

  final Color color;
  final double gap;

  static const _signalAspect = 17.1 / 10.7;
  static const _wifiAspect = 15.4 / 11.057;
  static const _batteryAspect = 24.5 / 11.5;

  static double widthFor(double height, double gap) =>
      height * (_signalAspect + _wifiAspect + _batteryAspect) + gap * 2;

  @override
  void paint(Canvas canvas, Size size) {
    var h = size.height;
    var paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    var x = 0.0;
    _signal(canvas, paint, Offset(x, 0), h);
    x += h * _signalAspect + gap;
    _wifi(canvas, paint, Offset(x, 0), h);
    x += h * _wifiAspect + gap;
    _battery(canvas, paint, Offset(x, 0), h);
  }

  /// Four bars rising to full height, as the artwork has them: width 3 on a
  /// 1.8 gap, heights 4.0, 6.0, 8.3 and 10.7 of 10.7.
  void _signal(Canvas canvas, Paint paint, Offset at, double h) {
    const heights = [4.0 / 10.7, 6.0 / 10.7, 8.3 / 10.7, 1.0];
    var barWidth = h * (3 / 10.7);
    var step = h * (4.8 / 10.7);
    var radius = Radius.circular(h * (1.2 / 10.7));
    for (var i = 0; i < heights.length; i++) {
      var barHeight = h * heights[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            at.dx + step * i,
            at.dy + h - barHeight,
            barWidth,
            barHeight,
          ),
          radius,
        ),
        paint,
      );
    }
  }

  /// Three arcs over a dot, struck rather than filled — the artwork fills
  /// crescents, and a stroke of the same weight is the same picture.
  void _wifi(Canvas canvas, Paint paint, Offset at, double h) {
    var w = h * _wifiAspect;
    var centre = Offset(at.dx + w / 2, at.dy + h);
    var stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = h * 0.155
      ..isAntiAlias = true;
    for (var r in [0.94, 0.62, 0.30]) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: w / 2 * r),
        math.pi * 1.22,
        math.pi * 0.56,
        false,
        stroke,
      );
    }
    canvas.drawCircle(centre, h * 0.085, paint);
  }

  /// A hairline shell at the artwork's 36% opacity, and a solid core — which
  /// is what makes it read as a battery rather than as a filled rectangle.
  void _battery(Canvas canvas, Paint paint, Offset at, double h) {
    var bodyWidth = h * (22 / 11.5);
    var body = Rect.fromLTWH(at.dx, at.dy, bodyWidth, h);
    var shell = Paint()
      ..color = color.withValues(alpha: 0.36)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * (1 / 11.5)
      ..isAntiAlias = true;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        body.deflate(h * (0.5 / 11.5)),
        Radius.circular(h * (3.5 / 11.5)),
      ),
      shell,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          at.dx + h * (2 / 11.5),
          at.dy + h * (2.477 / 11.5),
          h * (18 / 11.5),
          h * (7.667 / 11.5),
        ),
        Radius.circular(h * (1.6 / 11.5)),
      ),
      paint,
    );
    // The terminal, at the same 36% as the shell it belongs to.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          at.dx + bodyWidth + h * (0.5 / 11.5),
          at.dy + h * (3.8 / 11.5),
          h * (1.5 / 11.5),
          h * (3.9 / 11.5),
        ),
        Radius.circular(h * (0.75 / 11.5)),
      ),
      Paint()..color = color.withValues(alpha: 0.36),
    );
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) =>
      old.color != color || old.gap != gap;
}

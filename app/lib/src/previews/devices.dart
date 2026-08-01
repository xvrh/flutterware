/// The catalog's device *policy* — the defaults and the resolution rules.
///
/// The table itself lives in `package:flutterware` (`Devices.all`), because a
/// project's `tool/flutterware.dart` and a scenario folder's
/// `flutter_test_config.dart` name devices too, and neither can import the
/// GUI. Re-exported here so the panel keeps one import for both halves.
library;

import 'package:flutterware/devices.dart';

export 'package:flutterware/devices.dart';

/// How a device reads in the bar: its screen in logical pixels, which is the
/// number a layout is written against.
String describeDevice(Device device) =>
    '${device.width.round()}×${device.height.round()}';

/// The device an address names, or the panel when it names none.
///
/// **The one place a device comes from.** Nothing holds one: it is a function
/// of the address, recomputed wherever it is needed. That is what stops the
/// picker and the address from being two copies of the same fact chasing each
/// other a frame apart.
///
/// [fitDeviceId] and an absent parameter both resolve to the panel. They used
/// to differ: an entry could declare a form factor, and "fit" was how you said
/// *no* frame rather than *no opinion*. With the declaration gone there is one
/// answer, and the distinction is kept in the address only because a device
/// somebody chose should survive a reload.
Device? resolveDevice(String? param) =>
    param == null ? null : deviceById(param);

/// A `?device=` this build has never heard of, or null.
///
/// Derived rather than remembered, like everything else here. Meant to be shown
/// loudly: silently framing as the panel when the address asked for an iPhone
/// produces a picture that is wrong without looking wrong.
String? unknownDeviceIn(String? param) =>
    param != null && !isDeviceId(param) ? param : null;

/// How big the guest renders, and *as what*.
///
/// Four kinds of number rather than a size, because a phone is not a bitmap of
/// a certain shape. The guest is told its buffer in physical pixels and its
/// ratio separately, so a demo reading `MediaQuery` sees the phone's logical
/// size — 390×844, not 1170×2532 — which is the number the layout was written
/// against. The insets are the notch.
///
/// The panel's own capture is the degenerate case: a rectangle at ratio 1 with
/// nothing cut out of it.
class CaptureViewport {
  const CaptureViewport({
    required this.width,
    required this.height,
    this.pixelRatio = 1,
    this.insetTop = 0,
    this.insetRight = 0,
    this.insetBottom = 0,
    this.insetLeft = 0,
  });

  /// The device's screen, at its own ratio, with its safe areas — the same
  /// three things the panel hands its guest, so a capture and what you were
  /// looking at are the same picture.
  factory CaptureViewport.of(Device device) => CaptureViewport(
    width: (device.width * device.pixelRatio).round(),
    height: (device.height * device.pixelRatio).round(),
    pixelRatio: device.pixelRatio,
    insetTop: device.insetTop,
    insetRight: device.insetRight,
    insetBottom: device.insetBottom,
    insetLeft: device.insetLeft,
  );

  /// What a capture that names no device gets.
  static const panel = CaptureViewport(width: 900, height: 700);

  /// Physical pixels — the size of the image that comes out.
  final int width;
  final int height;

  final double pixelRatio;
  final double insetTop;
  final double insetRight;
  final double insetBottom;
  final double insetLeft;

  /// The same viewport at a different size, for a caller that asked for one
  /// explicitly. The ratio and the insets stay: asking for a taller iPhone is
  /// asking for a taller iPhone, not for a slab of glass with no notch.
  CaptureViewport resized({int? width, int? height}) => CaptureViewport(
    width: width ?? this.width,
    height: height ?? this.height,
    pixelRatio: pixelRatio,
    insetTop: insetTop,
    insetRight: insetRight,
    insetBottom: insetBottom,
    insetLeft: insetLeft,
  );
}

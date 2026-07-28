/// The device vocabulary an address may use, in **plain Dart**.
///
/// Deliberately free of `device_frame`, and by extension of Flutter. `fw` and
/// MCP link this — they have to validate `--device` and render a capture at the
/// right size — and they are compiled with `dart compile exe`, where
/// `package:flutter` cannot load at all. The panel's own frame drawing needs
/// the real `DeviceInfo`, and that lives next door in `catalog_devices.dart`,
/// which maps these ids onto it.
///
/// So the numbers here are a copy, and a copy is a thing that drifts. They are
/// checked against `device_frame`'s own by a test rather than trusted, which is
/// the same bargain as anywhere else: a vocabulary enforced apart from where it
/// is defined is a vocabulary that is quietly wrong.
library;

/// What shape of thing a device is.
///
/// Decides the silhouette drawn around it, and nothing else — every
/// measurement is on the device itself. `desktop` gets no silhouette at all:
/// the panel is already a desktop-shaped canvas, and a monitor body scaled down
/// to fit inside it costs more room than it explains. What a desktop entry is
/// *for* is its size.
enum DeviceKind { phone, tablet, desktop }

/// Ours rather than `TargetPlatform`, which is Flutter-only. Translated at the
/// one place a frame is drawn.
enum DevicePlatform { ios, android, macos, windows, linux }

/// One device an address may name.
class CatalogDevice {
  const CatalogDevice(
    this.id,
    this.label, {
    required this.kind,
    required this.platform,
    required this.group,
    required this.width,
    required this.height,
    required this.pixelRatio,
    this.insetTop = 0,
    this.insetRight = 0,
    this.insetBottom = 0,
    this.insetLeft = 0,
  });

  /// What goes in an address — `?device=iphone-13`.
  ///
  /// Ours rather than `device_frame`'s identifier: an address is written by
  /// hand, pasted into a terminal and produced by an agent, so its vocabulary
  /// has to be stable and guessable. A third party's internal identifier is
  /// neither, and it would leak into every saved link.
  final String id;

  /// What a person reads in the picker.
  final String label;

  /// The heading it appears under.
  final String group;

  /// What silhouette to draw around it, if any.
  final DeviceKind kind;

  final DevicePlatform platform;

  /// The screen in **logical** pixels — the number a layout is written
  /// against, and what the demo reads from `MediaQuery`.
  final double width;
  final double height;

  final double pixelRatio;

  /// The notch, and whatever else is not drawable. Without these an `AppBar`
  /// renders under the cutout and a capture misses the exact thing a phone
  /// screenshot exists to catch.
  final double insetTop;
  final double insetRight;
  final double insetBottom;
  final double insetLeft;
}

/// What `?device=` means "no device at all": the panel itself, at whatever size
/// the window happens to be.
///
/// A value rather than an absent parameter, because picking it is a decision.
/// Leaving it out means "nobody chose", which is what lets an entry's own
/// `formFactor` speak; `fit` means "I chose not to frame this", and those are
/// different answers.
const fitDeviceId = 'fit';

/// The devices worth offering, which is not all of them.
///
/// `Devices.all` is nearly a hundred entries and a menu nobody reads. This is
/// the same shortlist the previous catalog shipped (`default_device_list.dart`)
/// — one small, one large and one tablet per platform, which is what a layout
/// actually gets tested against.
const catalogDevices = <CatalogDevice>[
  CatalogDevice(
    'iphone-se',
    'iPhone SE',
    kind: DeviceKind.phone,
    platform: DevicePlatform.ios,
    group: 'iOS',
    width: 375,
    height: 667,
    pixelRatio: 2,
    insetTop: 20,
  ),
  CatalogDevice(
    'iphone-13-mini',
    'iPhone 13 mini',
    kind: DeviceKind.phone,
    platform: DevicePlatform.ios,
    group: 'iOS',
    width: 375,
    height: 812,
    pixelRatio: 2,
    insetTop: 47,
    insetBottom: 34,
  ),
  CatalogDevice(
    'iphone-13',
    'iPhone 13',
    kind: DeviceKind.phone,
    platform: DevicePlatform.ios,
    group: 'iOS',
    width: 390,
    height: 844,
    pixelRatio: 3,
    insetTop: 47,
    insetBottom: 34,
  ),
  CatalogDevice(
    'iphone-12-pro-max',
    'iPhone 12 Pro Max',
    kind: DeviceKind.phone,
    platform: DevicePlatform.ios,
    group: 'iOS',
    width: 428,
    height: 926,
    pixelRatio: 3,
    insetTop: 44,
    insetBottom: 34,
  ),
  CatalogDevice(
    'ipad',
    'iPad',
    kind: DeviceKind.tablet,
    platform: DevicePlatform.ios,
    group: 'iOS',
    width: 810,
    height: 1080,
    pixelRatio: 2,
    insetTop: 20,
  ),
  CatalogDevice(
    'android-small',
    'Small phone',
    kind: DeviceKind.phone,
    platform: DevicePlatform.android,
    group: 'Android',
    width: 360,
    height: 640,
    pixelRatio: 2,
    insetTop: 24,
  ),
  CatalogDevice(
    'android-medium',
    'Medium phone',
    kind: DeviceKind.phone,
    platform: DevicePlatform.android,
    group: 'Android',
    width: 412,
    height: 732,
    pixelRatio: 2,
    insetTop: 24,
  ),
  CatalogDevice(
    'android-big',
    'Big phone',
    kind: DeviceKind.phone,
    platform: DevicePlatform.android,
    group: 'Android',
    width: 480,
    height: 853,
    pixelRatio: 2,
    insetTop: 24,
  ),
  CatalogDevice(
    'android-small-tablet',
    'Small tablet',
    kind: DeviceKind.tablet,
    platform: DevicePlatform.android,
    group: 'Android',
    width: 800,
    height: 1280,
    pixelRatio: 2,
    insetTop: 24,
  ),
  CatalogDevice(
    'android-medium-tablet',
    'Medium tablet',
    kind: DeviceKind.tablet,
    platform: DevicePlatform.android,
    group: 'Android',
    width: 1024,
    height: 1350,
    pixelRatio: 2,
    insetTop: 24,
  ),
  CatalogDevice(
    'macbook-pro',
    'MacBook Pro',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.macos,
    group: 'Desktop',
    width: 1800,
    height: 970,
    pixelRatio: 2,
  ),
  CatalogDevice(
    'wide-monitor',
    'Wide monitor',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.macos,
    group: 'Desktop',
    width: 1620,
    height: 750,
    pixelRatio: 2,
  ),
  CatalogDevice(
    'windows-laptop',
    'Windows laptop',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.windows,
    group: 'Desktop',
    width: 1620,
    height: 740,
    pixelRatio: 2,
  ),
  CatalogDevice(
    'linux-laptop',
    'Linux laptop',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.linux,
    group: 'Desktop',
    width: 1620,
    height: 740,
    pixelRatio: 2,
  ),
];

/// Every value `?device=` accepts, [fitDeviceId] first.
///
/// One list, so the picker, the address, `fw`'s usage line and MCP's schema
/// read the same thing.
List<String> get deviceIds => [fitDeviceId, for (var d in catalogDevices) d.id];

/// The device [id] names, or null for [fitDeviceId] and for anything unknown —
/// which the caller must tell apart, because one is a choice and the other is a
/// mistake. See [isDeviceId].
CatalogDevice? deviceById(String id) =>
    catalogDevices.where((d) => d.id == id).firstOrNull;

/// Whether [id] is a value this build accepts at all.
bool isDeviceId(String id) => id == fitDeviceId || deviceById(id) != null;

/// How a device reads in the bar: its screen in logical pixels, which is the
/// number a layout is written against.
String describeDevice(CatalogDevice device) =>
    '${device.width.round()}×${device.height.round()}';

/// What an entry declaring `@Demo(formFactor: …)` is shown as when the address
/// names no device of its own.
///
/// A **default, computed on the spot** — never stored, never written into the
/// address. That is the whole of "a choice outranks a declaration": a chosen
/// device is a parameter and this is the `??` behind it, so there is no rule to
/// enforce and no flag remembering which of the two last spoke.
///
/// `desktop` and `all` mean the panel. The panel is already a desktop-shaped
/// canvas, and a 1440-wide frame scaled down inside it is a worse look at a
/// desktop layout than the room it costs; `all` is an entry saying it has no
/// opinion.
CatalogDevice? defaultDeviceFor(String? formFactor) =>
    formFactor == 'mobile' ? deviceById('iphone-13') : null;

/// The device an address names, or the default for [formFactor] when it names
/// none.
///
/// **The one place a device comes from.** Nothing holds one: it is a function
/// of the address and the entry on screen, recomputed wherever it is needed.
/// That is what stops the picker and the address from being two copies of the
/// same fact chasing each other a frame apart.
///
/// [fitDeviceId] resolves to no device *and* suppresses the default, which is
/// why "fit" has to be a value rather than an absent parameter: choosing the
/// panel and choosing nothing are different answers.
CatalogDevice? resolveDevice(String? param, {String? formFactor}) =>
    param == null ? defaultDeviceFor(formFactor) : deviceById(param);

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
  factory CaptureViewport.of(CatalogDevice device) => CaptureViewport(
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

/// The device vocabulary — shared by the GUI's pickers, `fw`, MCP, and the
/// scenario axes.
///
/// In the package rather than the app because three files outside the GUI name
/// devices: a project's `tool/flutterware.dart`, a scenario folder's
/// `flutter_test_config.dart`, and CI. Pure Dart, no Flutter import: it is a
/// table of numbers, and the one place that draws a frame around them
/// translates on the spot.
library;

/// What silhouette to draw around a screen, if any.
enum DeviceKind { phone, tablet, desktop }

/// Ours rather than `TargetPlatform`, which is Flutter-only. Translated at the
/// one place a frame is drawn.
enum DevicePlatform { ios, android, macos, windows, linux }

/// One device an address may name.
class Device {
  const Device(
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

  /// What goes in an address — `?device=iphone-16`.
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

  final DeviceKind kind;

  final DevicePlatform platform;

  /// The screen in **logical** pixels — the number a layout is written
  /// against, and what the app reads from `MediaQuery`.
  final double width;
  final double height;

  final double pixelRatio;

  /// The notch, the island, the gesture bar — whatever is not drawable.
  /// Without these an `AppBar` renders under the cutout and a capture misses
  /// the exact thing a phone frame exists to catch.
  final double insetTop;
  final double insetRight;
  final double insetBottom;
  final double insetLeft;

  @override
  String toString() => 'Device($id)';
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
/// A picker with a hundred entries is a menu nobody reads. What a *layout*
/// meets is a handful of size classes — small, standard, large, tablet,
/// desktop — so this is one of each per platform, named after a device that
/// sits in that class.
///
/// The five with a hand-drawn `device_frame` body ([Devices.iphoneSe],
/// [Devices.iphone13Mini], [Devices.iphone13], [Devices.iphone12ProMax],
/// [Devices.iPad]) carry that package's own measurements, and
/// `app/test/scenarios/frames_test.dart` pins the two together — a mismatch
/// would stretch every screenshot inside its frame. The rest render in a
/// generic silhouette of their [DeviceKind], which is why a modern model can
/// be added here without artwork.
abstract final class Devices {
  // ---------------------------------------------------------------- iOS

  static const iphoneSe = Device(
    'iphone-se',
    'iPhone SE',
    kind: DeviceKind.phone,
    platform: DevicePlatform.ios,
    group: 'iOS',
    width: 375,
    height: 667,
    pixelRatio: 2,
    insetTop: 20,
  );

  static const iphone13Mini = Device(
    'iphone-13-mini',
    'iPhone 13 mini',
    kind: DeviceKind.phone,
    platform: DevicePlatform.ios,
    group: 'iOS',
    width: 375,
    height: 812,
    // 2, not 3, because `device_frame`'s own body says 2 and the frame test
    // pins them together. The mini renders at 3× and downsamples on the real
    // device; correcting both at once is for the measurement pass.
    pixelRatio: 2,
    insetTop: 47,
    insetBottom: 34,
  );

  static const iphone13 = Device(
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
  );

  static const iphone12ProMax = Device(
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
  );

  /// The Dynamic Island generation — the same screen as an iPhone 15, and the
  /// one most users are holding.
  static const iphone16 = Device(
    'iphone-16',
    'iPhone 16',
    kind: DeviceKind.phone,
    platform: DevicePlatform.ios,
    group: 'iOS',
    width: 393,
    height: 852,
    pixelRatio: 3,
    insetTop: 59,
    insetBottom: 34,
  );

  /// The largest iPhone screen there is — what a layout overflows on last and
  /// what a store listing wants first.
  static const iphone16ProMax = Device(
    'iphone-16-pro-max',
    'iPhone 16 Pro Max',
    kind: DeviceKind.phone,
    platform: DevicePlatform.ios,
    group: 'iOS',
    width: 440,
    height: 956,
    pixelRatio: 3,
    insetTop: 59,
    insetBottom: 34,
  );

  static const iPad = Device(
    'ipad',
    'iPad',
    kind: DeviceKind.tablet,
    platform: DevicePlatform.ios,
    group: 'iOS',
    width: 810,
    height: 1080,
    pixelRatio: 2,
    insetTop: 20,
  );

  static const iPadPro13 = Device(
    'ipad-pro-13',
    'iPad Pro 13"',
    kind: DeviceKind.tablet,
    platform: DevicePlatform.ios,
    group: 'iOS',
    width: 1024,
    height: 1366,
    pixelRatio: 2,
    insetTop: 24,
    insetBottom: 20,
  );

  // ------------------------------------------------------------ Android
  //
  // Named by size rather than by model: Android screens cluster into a few
  // logical sizes that a dozen phones share, and claiming a specific handset
  // would be a claim about numbers nobody here has measured.

  static const androidSmall = Device(
    'android-small',
    'Small phone',
    kind: DeviceKind.phone,
    platform: DevicePlatform.android,
    group: 'Android',
    width: 360,
    height: 640,
    pixelRatio: 2,
    insetTop: 24,
  );

  static const androidMedium = Device(
    'android-medium',
    'Medium phone',
    kind: DeviceKind.phone,
    platform: DevicePlatform.android,
    group: 'Android',
    width: 412,
    height: 732,
    pixelRatio: 2,
    insetTop: 24,
  );

  /// The shape almost every current Android phone is: tall, with a gesture bar
  /// eating the bottom.
  static const androidTall = Device(
    'android-tall',
    'Tall phone',
    kind: DeviceKind.phone,
    platform: DevicePlatform.android,
    group: 'Android',
    width: 412,
    height: 915,
    pixelRatio: 2.625,
    insetTop: 24,
    insetBottom: 24,
  );

  static const androidBig = Device(
    'android-big',
    'Big phone',
    kind: DeviceKind.phone,
    platform: DevicePlatform.android,
    group: 'Android',
    width: 480,
    height: 853,
    pixelRatio: 2,
    insetTop: 24,
  );

  static const androidSmallTablet = Device(
    'android-small-tablet',
    'Small tablet',
    kind: DeviceKind.tablet,
    platform: DevicePlatform.android,
    group: 'Android',
    width: 800,
    height: 1280,
    pixelRatio: 2,
    insetTop: 24,
  );

  static const androidMediumTablet = Device(
    'android-medium-tablet',
    'Medium tablet',
    kind: DeviceKind.tablet,
    platform: DevicePlatform.android,
    group: 'Android',
    width: 1024,
    height: 1350,
    pixelRatio: 2,
    insetTop: 24,
  );

  // ------------------------------------------------------------ Desktop

  static const macbookPro = Device(
    'macbook-pro',
    'MacBook Pro',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.macos,
    group: 'Desktop',
    width: 1800,
    height: 970,
    pixelRatio: 2,
  );

  static const wideMonitor = Device(
    'wide-monitor',
    'Wide monitor',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.macos,
    group: 'Desktop',
    width: 1620,
    height: 750,
    pixelRatio: 2,
  );

  static const windowsLaptop = Device(
    'windows-laptop',
    'Windows laptop',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.windows,
    group: 'Desktop',
    width: 1620,
    height: 740,
    pixelRatio: 2,
  );

  static const linuxLaptop = Device(
    'linux-laptop',
    'Linux laptop',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.linux,
    group: 'Desktop',
    width: 1620,
    height: 740,
    pixelRatio: 2,
  );

  /// Every offered device, in picker order.
  static const all = <Device>[
    iphoneSe,
    iphone13Mini,
    iphone13,
    iphone16,
    iphone12ProMax,
    iphone16ProMax,
    iPad,
    iPadPro13,
    androidSmall,
    androidMedium,
    androidTall,
    androidBig,
    androidSmallTablet,
    androidMediumTablet,
    macbookPro,
    wideMonitor,
    windowsLaptop,
    linuxLaptop,
  ];
}

/// Every value `?device=` accepts, [fitDeviceId] first.
///
/// One list, so the picker, the address, `fw`'s usage line and MCP's schema
/// read the same thing.
List<String> get deviceIds => [fitDeviceId, for (var d in Devices.all) d.id];

/// The device [id] names, or null for [fitDeviceId] and for anything unknown —
/// which the caller must tell apart, because one is a choice and the other is a
/// mistake. See [isDeviceId].
Device? deviceById(String id) =>
    Devices.all.where((d) => d.id == id).firstOrNull;

/// Whether [id] is a value this build accepts at all.
bool isDeviceId(String id) => id == fitDeviceId || deviceById(id) != null;

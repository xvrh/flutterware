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

/// Which way up a device is — an axis applied on top of a [Device], not a
/// device of its own.
///
/// A rotated iPad is the same iPad: same id, same ratio, same artwork. A second
/// entry for it would double the table per rotatable device and turn a
/// 4-device × 2-orientation matrix into eight ids instead of two crossed lists.
///
/// **One landscape, not two.** Real hardware has a left and a right, and they
/// differ only in which side the cutout lands on — so a second value would
/// double every matrix to buy a mirrored inset. This one is defined by a fixed
/// physical side: **the cutout on the left**. Deliberately not "the leading
/// side", which flips under an RTL locale: orientation must not change meaning
/// because the language axis moved.
///
/// The enum is open on purpose. A second value can arrive without changing the
/// grammar, and it would be the mirror of this one rather than a new
/// declaration.
///
/// **Not `DeviceOrientation`**, which Flutter already defines in `services.dart`
/// and therefore has in scope in every file that imports `material.dart`. A
/// consumer declaring a profile would have had to hide one of the two to name
/// the other, in the API whose whole job is to be nameable from a
/// `flutter_test_config.dart`. `Orientation` is taken as well, by
/// `widgets.dart`.
enum ScreenOrientation { portrait, landscape }

/// A device's safe areas, as one value.
///
/// Ours rather than `EdgeInsets` because this file is pure Dart by design: a
/// project's `tool/flutterware.dart` and a scenario folder's
/// `flutter_test_config.dart` both import it, and neither should have to pull
/// in Flutter to name a device.
class DeviceInsets {
  const DeviceInsets({
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.left = 0,
  });

  final double top;
  final double right;
  final double bottom;
  final double left;
}

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
    this.landscape,
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

  /// The safe areas when this device is on its side, or null for the swap-only
  /// case: width and height trade places and the insets stay where they are.
  ///
  /// **Declared, not computed.** Permuting the four insets geometrically is
  /// wrong on exactly the devices it matters on. An iPhone in landscape *loses*
  /// its status bar rather than moving it — the top inset goes to 0, not to a
  /// side — the cutout inset lands on both sides, and the home indicator stays
  /// at the interface bottom and shrinks. A tablet, meanwhile, really is just
  /// swap-width-and-height, which is why null is the default: only the notched
  /// phones say anything here.
  ///
  /// `device_frame` storing a separately measured `rotatedSafeAreas` beside its
  /// `safeAreas` is the same conclusion reached from the hardware.
  final DeviceInsets? landscape;

  /// Whether orientation is a question this device answers. Desktops are
  /// windows: there is no other way up.
  ///
  /// Mirrors `device_frame`'s `canRotate`, and it is what stops a matrix from
  /// running a desktop twice to produce the same pixels.
  bool get canRotate => kind != DeviceKind.desktop;

  /// This device as [orientation] shows it — itself for portrait, for null, and
  /// for anything that cannot rotate.
  ///
  /// **The one place the orientation axis becomes geometry.** Everything
  /// downstream takes a [Device] and reads `width`, `height` and the insets —
  /// the capture viewport, the harness args, the silhouette, the splash sweep —
  /// so resolving the axis into a device here leaves all of them untouched.
  Device oriented(ScreenOrientation? orientation) =>
      orientation == ScreenOrientation.landscape && canRotate
      ? rotated()
      : this;

  /// This device on its side, whatever it thinks of the idea — [oriented] is
  /// the one that asks [canRotate] first.
  ///
  /// Keeps [id] and [label]: a rotated iPad is still `ipad`, which is what lets
  /// the frame lookup and every saved address go on working.
  Device rotated() => Device(
    id,
    label,
    kind: kind,
    platform: platform,
    group: group,
    width: height,
    height: width,
    pixelRatio: pixelRatio,
    insetTop: landscape?.top ?? insetTop,
    insetRight: landscape?.right ?? insetRight,
    insetBottom: landscape?.bottom ?? insetBottom,
    insetLeft: landscape?.left ?? insetLeft,
    landscape: landscape,
  );

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
/// `app/test/previews/frames_test.dart` pins the two together — a mismatch
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
    // Asymmetric because the hardware is: the notch side measures 47 and the
    // far side only its rounded corner. `device_frame`'s own body for this
    // model, which is where these four numbers come from.
    landscape: DeviceInsets(left: 47, right: 44, bottom: 21),
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
    landscape: DeviceInsets(left: 47, right: 47, bottom: 21),
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
    landscape: DeviceInsets(left: 44, right: 44, bottom: 21),
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
    // No `device_frame` body for this generation, so these follow the rule the
    // three measured ones agree on rather than a measurement of their own: the
    // status bar goes, the cutout inset lands on both sides at whatever the
    // portrait top was, and the home indicator settles at 21. Said out loud
    // because the rest of this table only claims numbers somebody measured.
    landscape: DeviceInsets(left: 59, right: 59, bottom: 21),
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
    // Derived the same way as [iphone16], and carrying the same caveat.
    landscape: DeviceInsets(left: 59, right: 59, bottom: 21),
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
  //
  // **Windows, not machines.** A phone entry is a screen, because a phone app
  // gets the whole of one and the layout has to survive exactly that. A desktop
  // app gets a *window*, which the user drags to whatever size they like — so
  // the sizes worth checking are the ones a window is opened at, and the
  // machine's screen is not one of them. These used to be screens: `MacBook
  // Pro` was 1800×970, a size no application has ever opened at, and staging it
  // in a panel a third that wide made every preview a thumbnail of itself.
  //
  // Two axes, both worth having. The **size** is what the layout meets, and
  // three of them cover what a desktop layout actually has to do: hold together
  // small, sit at the size most people leave a window, and not fall apart wide.
  // The **platform** is what the widgets meet — scrollbars, fonts, adaptive
  // Cupertino/Material choices, `Theme.of(context).platform` — so Windows and
  // Linux are here as themselves rather than as sizes that happen to differ.

  static const smallWindow = Device(
    'window-small',
    'Small window',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.macos,
    group: 'Desktop',
    width: 1024,
    height: 700,
    pixelRatio: 2,
  );

  static const window = Device(
    'window',
    'Standard window',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.macos,
    group: 'Desktop',
    width: 1280,
    height: 800,
    pixelRatio: 2,
  );

  static const wideWindow = Device(
    'window-wide',
    'Wide window',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.macos,
    group: 'Desktop',
    width: 1600,
    height: 900,
    pixelRatio: 2,
  );

  /// A Windows window, at the scale Windows actually ships at.
  ///
  /// 1.5 rather than the 2 this entry used to carry: 200% is a 4K laptop, and
  /// 150% is what a mainstream Windows machine is set to. The ratio is not
  /// decoration — it picks which asset resolution loads and how big the texture
  /// behind the preview is.
  static const windowsWindow = Device(
    'windows-window',
    'Windows window',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.windows,
    group: 'Desktop',
    width: 1280,
    height: 800,
    pixelRatio: 1.5,
  );

  /// A Linux window, unscaled — which is still the common case there.
  static const linuxWindow = Device(
    'linux-window',
    'Linux window',
    kind: DeviceKind.desktop,
    platform: DevicePlatform.linux,
    group: 'Desktop',
    width: 1280,
    height: 800,
    pixelRatio: 1,
  );

  /// The screens these window sizes replaced.
  ///
  /// Kept because they are published: a project's `tool/flutterware.dart` names
  /// them, and a package that renames a constant out from under a consumer for
  /// a better name has spent their afternoon to save its own. [deviceById]
  /// resolves the old ids too, so an address or a config that names one goes on
  /// working — see [_renamed].
  @Deprecated(
    'Renamed: a desktop preview is a window, not a screen. Use '
    'Devices.wideWindow.',
  )
  static const macbookPro = wideWindow;

  @Deprecated(
    'Renamed: a desktop preview is a window, not a screen. Use '
    'Devices.wideWindow.',
  )
  static const wideMonitor = wideWindow;

  @Deprecated(
    'Renamed: a desktop preview is a window, not a screen. Use '
    'Devices.windowsWindow.',
  )
  static const windowsLaptop = windowsWindow;

  @Deprecated(
    'Renamed: a desktop preview is a window, not a screen. Use '
    'Devices.linuxWindow.',
  )
  static const linuxLaptop = linuxWindow;

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
    smallWindow,
    window,
    wideWindow,
    windowsWindow,
    linuxWindow,
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
///
/// Old ids resolve to what replaced them — see [_renamed]. A stored address is
/// the case that matters: `?device=macbook-pro` was written down by somebody
/// who wanted a desktop stage, and answering "no such device" to it would make
/// a rename look like a broken link.
Device? deviceById(String id) {
  var wanted = _renamed[id] ?? id;
  return Devices.all.where((d) => d.id == wanted).firstOrNull;
}

/// What the desktop entries were called when they were screens rather than
/// windows.
///
/// Deliberately a **map to the current ids** rather than four more rows in
/// [Devices.all]: an alias that appeared in the picker would be a second way to
/// ask for the same stage, and the picker is the one place this rename is meant
/// to be visible.
const _renamed = {
  'macbook-pro': 'window-wide',
  'wide-monitor': 'window-wide',
  'windows-laptop': 'windows-window',
  'linux-laptop': 'linux-window',
};

/// Whether [id] is a value this build accepts at all.
bool isDeviceId(String id) => id == fitDeviceId || deviceById(id) != null;

/// Every value `?orientation=` accepts, portrait first.
///
/// One list, for the same reason [deviceIds] is one: the picker, the address,
/// `fw`'s usage line and MCP's schema all read it.
List<String> get orientationIds => [
  for (var orientation in ScreenOrientation.values) orientation.name,
];

/// The orientation [id] names, or null for anything unknown.
ScreenOrientation? orientationById(String id) =>
    ScreenOrientation.values.where((o) => o.name == id).firstOrNull;

/// Whether [id] is an orientation this build accepts.
bool isOrientationId(String id) => orientationById(id) != null;

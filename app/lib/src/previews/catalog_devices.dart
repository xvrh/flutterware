// `Devices` hidden: theirs is a hundred hand-drawn bodies, ours is the
// offered table, and this file is where the two meet. Prefixed a second time
// because the meeting needs both names — [namedFrameFor] is the only thing
// here that says theirs.
import 'package:device_frame/device_frame.dart' hide Devices;
import 'package:device_frame/device_frame.dart' as artwork show Devices;
import 'package:flutter/widgets.dart';

import 'devices.dart';

export 'devices.dart';

/// The silhouette to draw around a device — the one answer, wherever a frame
/// is drawn: the preview canvas, a scenario's captured step, the flow.
///
/// Two sources, in this order. A handful of ids have a **hand-drawn body** in
/// `device_frame` — an SE with its home button, a 13 with its notch — and
/// [namedFrameFor] borrows it, because a wall of identical lozenges reads
/// alike and the outline is half of what says *iPhone*. Everything else is
/// **built from our own measurements**: [Devices.all] handed to
/// `device_frame`'s generic builders, which take exactly what a [Device]
/// already holds — screen size, safe areas, pixel ratio, a name and a
/// platform. Which is why a modern model can be added to the table without
/// artwork.
///
/// The borrowed half is a second set of measurements, and the price of it is
/// `app/test/scenarios/frames_test.dart`: it holds the two together, because a
/// named body whose screen disagreed with ours would stretch every picture
/// inside its frame. That is also why the list is five and not the fourteen it
/// once was — an id is only on it when the numbers match exactly.
///
/// Null for [DeviceKind.desktop], which gets no silhouette: the panel is
/// already a desktop-shaped canvas, and a monitor body scaled down to fit
/// inside it costs more room than it explains. A desktop entry is a *size*.
///
/// Takes the device **as it stands upright**, and a caller drawing a turned one
/// has to say so: `DeviceFrame` rotates a body it is given an orientation for,
/// so the landscape numbers belong in [DeviceInfo.rotatedSafeAreas] here rather
/// than in a second, sideways `DeviceInfo`. A hand-drawn body leaves no choice
/// about it — the artwork is portrait, and handing it landscape screen numbers
/// would draw a phone lying on its side inside an upright one.
DeviceInfo? deviceFrameFor(Device device) =>
    namedFrameFor(device.id) ?? _genericFrameFor(device);

/// `device_frame`'s hand-drawn body for [id], or null when it has none.
///
/// Only ids whose named body matches our table exactly — screen, pixel ratio
/// and rotated safe areas. `frames_test.dart` is what makes that claim true
/// rather than a hope.
DeviceInfo? namedFrameFor(String id) => switch (id) {
  'iphone-se' => artwork.Devices.ios.iPhoneSE,
  'iphone-13-mini' => artwork.Devices.ios.iPhone13Mini,
  'iphone-13' => artwork.Devices.ios.iPhone13,
  'iphone-12-pro-max' => artwork.Devices.ios.iPhone12ProMax,
  'ipad' => artwork.Devices.ios.iPad,
  _ => null,
};

DeviceInfo? _genericFrameFor(Device device) {
  var screen = Size(device.width, device.height);
  var safeAreas = EdgeInsets.fromLTRB(
    device.insetLeft,
    device.insetTop,
    device.insetRight,
    device.insetBottom,
  );
  // **Passed explicitly, because the default is a trap.** `rotatedSafeAreas`
  // defaults to `EdgeInsets.zero` rather than to null, and `canRotate` is
  // `rotatedSafeAreas != null` — so a generic body left to the default claims
  // it rotates and then renders landscape with no notch and no home indicator
  // at all. Wrong without looking wrong, and only in the rotated case.
  var rotated = device.rotated();
  var rotatedSafeAreas = EdgeInsets.fromLTRB(
    rotated.insetLeft,
    rotated.insetTop,
    rotated.insetRight,
    rotated.insetBottom,
  );

  return switch (device.kind) {
    DeviceKind.phone => DeviceInfo.genericPhone(
      platform: _platform(device.platform),
      id: device.id,
      name: device.label,
      screenSize: screen,
      safeAreas: safeAreas,
      rotatedSafeAreas: rotatedSafeAreas,
      pixelRatio: device.pixelRatio,
    ),
    DeviceKind.tablet => DeviceInfo.genericTablet(
      platform: _platform(device.platform),
      id: device.id,
      name: device.label,
      screenSize: screen,
      safeAreas: safeAreas,
      rotatedSafeAreas: rotatedSafeAreas,
      pixelRatio: device.pixelRatio,
    ),
    DeviceKind.desktop => null,
  };
}

/// The one place our platform enum meets Flutter's.
TargetPlatform _platform(DevicePlatform platform) => switch (platform) {
  DevicePlatform.ios => TargetPlatform.iOS,
  DevicePlatform.android => TargetPlatform.android,
  DevicePlatform.macos => TargetPlatform.macOS,
  DevicePlatform.windows => TargetPlatform.windows,
  DevicePlatform.linux => TargetPlatform.linux,
};

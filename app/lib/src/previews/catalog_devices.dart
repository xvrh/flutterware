// `Devices` hidden: theirs is a hundred hand-drawn bodies, ours is the
// offered table, and this file is where the two meet.
import 'package:device_frame/device_frame.dart' hide Devices;
import 'package:flutter/widgets.dart';

import 'devices.dart';

export 'devices.dart';

/// The silhouette to draw around a device, **built from our own measurements**.
///
/// Not a lookup. [Devices.all] is the only list; this hands its numbers to
/// `device_frame`'s generic builders, which take exactly what a [Device]
/// already holds — screen size, safe areas, pixel ratio, a name and a platform.
/// So there is nothing here to keep in step with anything, and nothing to
/// drift.
///
/// It used to map fourteen ids onto `device_frame`'s *named* devices, to borrow
/// their hand-drawn bodies. That bought a more literal iPhone outline and cost
/// a second list, a second set of measurements, and a test to hold the two
/// together — for scenery around a picture whose size, ratio and safe areas
/// were ours all along.
///
/// Null for [DeviceKind.desktop], which gets no silhouette: the panel is
/// already a desktop-shaped canvas, and a monitor body scaled down to fit
/// inside it costs more room than it explains. A desktop entry is a *size*.
DeviceInfo? deviceFrameFor(Device device) {
  var screen = Size(device.width, device.height);
  var safeAreas = EdgeInsets.fromLTRB(
    device.insetLeft,
    device.insetTop,
    device.insetRight,
    device.insetBottom,
  );

  return switch (device.kind) {
    DeviceKind.phone => DeviceInfo.genericPhone(
      platform: _platform(device.platform),
      id: device.id,
      name: device.label,
      screenSize: screen,
      safeAreas: safeAreas,
      pixelRatio: device.pixelRatio,
    ),
    DeviceKind.tablet => DeviceInfo.genericTablet(
      platform: _platform(device.platform),
      id: device.id,
      name: device.label,
      screenSize: screen,
      safeAreas: safeAreas,
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

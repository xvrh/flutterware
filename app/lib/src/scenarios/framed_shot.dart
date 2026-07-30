import 'dart:io';

import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';

import '../catalog/catalog_devices.dart';
import '../ui/theme.dart';

/// A captured step, in the silhouette of the device it ran as.
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
/// Unconstrained: renders at the device's logical size plus bezels. Put it in
/// a `FittedBox` (the flow graph does) or size it from outside.
class FramedShot extends StatelessWidget {
  const FramedShot({super.key, required this.png, required this.device});

  /// Path to the captured PNG — logical-pixel sized, as the harness writes it.
  final String png;

  /// The device the run was framed as, or null for the bare surface.
  final CatalogDevice? device;

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

  @override
  Widget build(BuildContext context) {
    var image = Image.file(
      File(png),
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    var resolved = device;
    if (resolved == null) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.line),
        ),
        child: image,
      );
    }
    var screen = SizedBox(
      width: resolved.width,
      height: resolved.height,
      child: image,
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

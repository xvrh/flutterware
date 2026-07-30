import 'dart:io';

import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';

import '../catalog/catalog_devices.dart';
import '../ui/theme.dart';

/// A captured step, in the silhouette of the device it ran as.
///
/// The frame is the catalog's own — same [deviceFrameFor], same measurements —
/// so a scenario shot and a catalog capture of the same device look like the
/// same phone. Desktop sizes and the bare test surface get a plain border: a
/// monitor body around a rectangle explains nothing.
///
/// Unconstrained: renders at the device's logical size plus bezels. Put it in
/// a `FittedBox` (the flow graph does) or size it from outside.
class FramedShot extends StatelessWidget {
  const FramedShot({super.key, required this.png, required this.device});

  /// Path to the captured PNG — logical-pixel sized, as the harness writes it.
  final String png;

  /// The device the run was framed as, or null for the bare surface.
  final CatalogDevice? device;

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
    var chrome = deviceFrameFor(resolved);
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

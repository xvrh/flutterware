import 'package:flutterware/src/third_party/device_frame/lib/src/devices/generic/base/draw_extensions.dart';
import 'package:flutterware/src/third_party/device_frame/lib/src/info/device_type.dart';
import 'package:flutterware/src/third_party/device_frame/lib/src/info/identifier.dart';
import 'package:flutterware/src/third_party/device_frame/lib/src/info/info.dart';
import 'package:flutter/material.dart';

part 'frame.dart';

/// Creates a generic tablet device definition.
DeviceInfo buildGenericTabletDevice({
  required TargetPlatform platform,
  required String id,
  required String name,
  required Size screenSize,
  EdgeInsets safeAreas = EdgeInsets.zero,
  EdgeInsets rotatedSafeAreas = EdgeInsets.zero,
  double pixelRatio = 2.0,
  GenericTabletFramePainter framePainter = const GenericTabletFramePainter(),
}) {
  return DeviceInfo(
    identifier: DeviceIdentifier(
      platform,
      DeviceType.tablet,
      id,
    ),
    name: name,
    pixelRatio: pixelRatio,
    frameSize: framePainter.calculateFrameSize(screenSize),
    screenSize: screenSize,
    safeAreas: safeAreas,
    rotatedSafeAreas: rotatedSafeAreas,
    framePainter: framePainter,
    screenPath: framePainter.createScreenPath(screenSize),
  );
}

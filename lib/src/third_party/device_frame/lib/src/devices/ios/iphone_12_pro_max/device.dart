import 'package:flutterware/src/third_party/device_frame/lib/src/info/device_type.dart';
import 'package:flutterware/src/third_party/device_frame/lib/src/info/identifier.dart';
import 'package:flutterware/src/third_party/device_frame/lib/src/info/info.dart';
import 'package:flutter/material.dart';

part 'frame.g.dart';
part 'screen.g.dart';

final info = DeviceInfo(
  identifier: const DeviceIdentifier(
    TargetPlatform.iOS,
    DeviceType.phone,
    'iphone-12-pro-max',
  ),
  name: 'iPhone 12 Pro Max',
  pixelRatio: 3.0,
  frameSize: const Size(873.0, 1770.0),
  screenSize: const Size(428.0, 926.0),
  safeAreas: const EdgeInsets.only(
    left: 0.0,
    top: 44.0,
    right: 0.0,
    bottom: 34.0,
  ),
  rotatedSafeAreas: const EdgeInsets.only(
    left: 44.0,
    top: 0.0,
    right: 44.0,
    bottom: 21.0,
  ),
  framePainter: const _FramePainter(),
  screenPath: _screenPath,
);

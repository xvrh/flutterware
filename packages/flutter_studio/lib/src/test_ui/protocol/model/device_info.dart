import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'rectangle.dart';

part 'device_info.g.dart';

abstract class DeviceInfo implements Built<DeviceInfo, DeviceInfoBuilder> {
  static Serializer<DeviceInfo> get serializer => _$deviceInfoSerializer;

  static final devices = <DeviceInfo>[
    iPhoneX,
    iPhone11ProMax,
    iPhoneSE,
    motoG5,
    androidSmall,
    androidMedium,
    androidLarge,
    iPadLandscape,
    iPadPortrait,
    iPadPro12Landscape,
    iPadPro12Portrait
  ];

  static final iPhoneX = DeviceInfo(
    'iphone_x',
    'iPhone X',
    width: 375,
    height: 812,
    pixelRatio: 3,
    platform: DevicePlatform.iOS,
    safeArea: Rectangle(
      top: 44,
      bottom: 34,
    ),
  );

  static final iPhone11ProMax = DeviceInfo(
    'iphone_11_pro_max',
    'iPhone 11 Pro Max',
    width: 414,
    height: 896,
    pixelRatio: 3,
    platform: DevicePlatform.iOS,
    safeArea: Rectangle(
      top: 44,
      bottom: 34,
    ),
  );

  static final iPhoneSE = DeviceInfo(
    'iphone_se',
    'iPhone SE',
    width: 320,
    height: 568,
    pixelRatio: 2,
    platform: DevicePlatform.iOS,
    safeArea: Rectangle(
      top: 20,
      bottom: 0,
    ),
  );

  static final motoG5 = DeviceInfo(
    'moto_g5',
    'Moto G5',
    platform: DevicePlatform.android,
    width: 360,
    height: 592,
    pixelRatio: 3,
    safeArea: Rectangle(
      top: 24,
      bottom: 0,
    ),
  );

  static final androidSmall = DeviceInfo(
    'android_small',
    'Android small',
    width: 320,
    height: 569,
    pixelRatio: 2,
    platform: DevicePlatform.android,
    safeArea: Rectangle(
      top: 24,
      bottom: 0,
    ),
  );

  static final androidMedium = DeviceInfo(
    'android_medium',
    'Android medium',
    width: 411,
    height: 731,
    pixelRatio: 2,
    platform: DevicePlatform.android,
    safeArea: Rectangle(
      top: 24,
      bottom: 0,
    ),
  );

  static final androidLarge = DeviceInfo(
    'android_large',
    'Android large',
    width: 800,
    height: 1280,
    pixelRatio: 3,
    platform: DevicePlatform.android,
    safeArea: Rectangle(
      top: 24,
      bottom: 0,
    ),
  );

  static final iPadLandscape = DeviceInfo(
    'ipad_landscape',
    'iPad Landscape',
    width: 1024,
    height: 768,
    pixelRatio: 2,
    platform: DevicePlatform.iOS,
    safeArea: Rectangle(
      top: 20,
      bottom: 0,
    ),
  );

  static final iPadPortrait = DeviceInfo(
    'ipad_portrait',
    'iPad Portrait',
    width: 768,
    height: 1024,
    pixelRatio: 2,
    platform: DevicePlatform.iOS,
    safeArea: Rectangle(
      top: 20,
      bottom: 0,
    ),
  );

  static final iPadPro12Portrait = DeviceInfo(
    'ipad_pro_12_portrait',
    'iPad Pro 12.9" Portrait',
    width: 1024,
    height: 1366,
    pixelRatio: 2,
    platform: DevicePlatform.iOS,
    safeArea: Rectangle(
      top: 24,
      bottom: 20,
    ),
  );

  static final iPadPro12Landscape = DeviceInfo(
    'ipad_pro_12_landscape',
    'iPad Pro 12.9" Landscape',
    width: 1366,
    height: 1024,
    pixelRatio: 2,
    platform: DevicePlatform.iOS,
    safeArea: Rectangle(
      top: 24,
      bottom: 20,
    ),
  );

  DeviceInfo._();
  factory DeviceInfo._builder([void Function(DeviceInfoBuilder) updates]) =
      _$DeviceInfo;

  factory DeviceInfo(
    String id,
    String name, {
    required DevicePlatform platform,
    required double width,
    required double height,
    required double pixelRatio,
    required Rectangle safeArea,
  }) =>
      DeviceInfo._builder((b) => b
        ..id = id
        ..name = name
        ..platform = platform
        ..width = width
        ..height = height
        ..pixelRatio = pixelRatio
        ..safeArea.replace(safeArea));

  String get id;
  String get name;
  DevicePlatform get platform;
  double get width;
  double get height;
  double get pixelRatio;
  Rectangle get safeArea;
}

class DevicePlatform extends EnumClass {
  static Serializer<DevicePlatform> get serializer =>
      _$devicePlatformSerializer;

  static const DevicePlatform android = _$android;
  static const DevicePlatform iOS = _$ios;

  const DevicePlatform._(String name) : super(name);

  static BuiltSet<DevicePlatform> get values => _$vls;
  static DevicePlatform valueOf(String name) => _$vlOf(name);
}

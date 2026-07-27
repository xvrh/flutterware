import 'package:device_frame/device_frame.dart';

/// A device the top bar offers, under the heading it appears below.
typedef CatalogDevice = ({String group, String label, DeviceInfo info});

/// The devices worth offering, which is not all of them.
///
/// `Devices.all` is nearly a hundred entries and a menu nobody reads. This is
/// the same shortlist the previous catalog shipped (`default_device_list.dart`)
/// — one small, one large and one tablet per platform, which is what a layout
/// actually gets tested against.
final catalogDevices = <CatalogDevice>[
  (group: 'iOS', label: 'iPhone SE', info: Devices.ios.iPhoneSE),
  (group: 'iOS', label: 'iPhone 13 mini', info: Devices.ios.iPhone13Mini),
  (group: 'iOS', label: 'iPhone 13', info: Devices.ios.iPhone13),
  (group: 'iOS', label: 'iPhone 12 Pro Max', info: Devices.ios.iPhone12ProMax),
  (group: 'iOS', label: 'iPad', info: Devices.ios.iPad),
  (group: 'Android', label: 'Small phone', info: Devices.android.smallPhone),
  (group: 'Android', label: 'Medium phone', info: Devices.android.mediumPhone),
  (group: 'Android', label: 'Big phone', info: Devices.android.bigPhone),
  (group: 'Android', label: 'Small tablet', info: Devices.android.smallTablet),
  (
    group: 'Android',
    label: 'Medium tablet',
    info: Devices.android.mediumTablet,
  ),
  (group: 'Desktop', label: 'MacBook Pro', info: Devices.macOS.macBookPro),
  (group: 'Desktop', label: 'Wide monitor', info: Devices.macOS.wideMonitor),
  (group: 'Desktop', label: 'Windows laptop', info: Devices.windows.laptop),
  (group: 'Desktop', label: 'Linux laptop', info: Devices.linux.laptop),
];

/// How a device reads in the bar: its screen in logical pixels, which is the
/// number a layout is written against.
String describeDevice(DeviceInfo device) =>
    '${device.screenSize.width.round()}×${device.screenSize.height.round()}';

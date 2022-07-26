import 'model/device_info.dart';
import 'model/rectangle.dart';
import 'package:flutter/widgets.dart';

export 'model/accessibility.dart';
export 'model/device_info.dart';
export 'model/message.dart';
export 'model/rectangle.dart';
export 'model/run_args.dart';
export 'model/run_result.dart';
export 'model/test_reference.dart';
export 'model/test_run.dart';
export 'model/screen.dart';
export 'model/locale.dart';
export 'serializers.dart' show modelSerializers;

extension DevicePlatformExtension on DevicePlatform {
  TargetPlatform toTargetPlatform() {
    switch (this) {
      case DevicePlatform.android:
        return TargetPlatform.android;
      case DevicePlatform.iOS:
        return TargetPlatform.iOS;
    }
    throw StateError('Unknown platform $this');
  }
}

extension RectangleExtension on Rectangle {
  EdgeInsets toEdgeInsets() => EdgeInsets.fromLTRB(left, top, right, bottom);
}

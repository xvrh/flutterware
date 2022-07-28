import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'model/accessibility.dart';
import 'model/device_info.dart';
import 'model/locale.dart';
import 'model/rectangle.dart';
import 'model/run_args.dart';
import 'model/run_result.dart';
import 'model/screen.dart';
import 'model/test_reference.dart';
import 'model/test_run.dart';

part 'serializers.g.dart';

@SerializersFor([
  AccessibilityConfig,
  TestReference,
  Rectangle,
  Screen,
  ImageFile,
  ScreenLink,
  TestRun,
  RunArgs,
  DeviceInfo,
  RunResult,
  NewScreen,
  TextInfo,
  SerializableLocale,
])
final Serializers modelSerializers = _$modelSerializers;

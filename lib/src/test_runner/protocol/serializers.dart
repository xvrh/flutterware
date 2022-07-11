import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'model/accessibility.dart';
import 'model/device_info.dart';
import 'model/rectangle.dart';
import 'model/run_args.dart';
import 'model/run_result.dart';
import 'model/scenario.dart';
import 'model/scenario_run.dart';
import 'model/screen.dart';

part 'serializers.g.dart';

@SerializersFor([
  AccessibilityConfig,
  ScenarioReference,
  Rectangle,
  Screen,
  ImageFile,
  ScreenLink,
  ScenarioRun,
  RunArgs,
  DeviceInfo,
  RunResult,
  NewScreen,
  TextInfo,
])
final Serializers modelSerializers = _$modelSerializers;

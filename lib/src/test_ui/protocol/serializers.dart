import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'model/accessibility.dart';
import 'model/device_info.dart';
import 'model/project_info.dart';
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
  ScreenLink,
  ScenarioRun,
  RunArgs,
  AnalyticEvent,
  DeviceInfo,
  RunResult,
  NewScreen,
  TextInfo,
  ProjectInfo,
  ConfluenceInfo,
  FirebaseInfo,
  BrowserInfo,
  EmailInfo,
  PdfInfo,
  JsonInfo,
])
final Serializers modelSerializers = _$modelSerializers;

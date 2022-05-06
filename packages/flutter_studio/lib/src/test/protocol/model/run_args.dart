import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'accessibility.dart';
import 'device_info.dart';

part 'run_args.g.dart';

int _runId = 0;

abstract class RunArgs implements Built<RunArgs, RunArgsBuilder> {
  static Serializer<RunArgs> get serializer => _$runArgsSerializer;

  RunArgs._();
  factory RunArgs._builder([void Function(RunArgsBuilder) updates]) = _$RunArgs;

  factory RunArgs(Iterable<String> scenarioName,
          {required DeviceInfo device,
          required AccessibilityConfig accessibility,
          required String language,
          required double imageRatio,
          bool? onlyWithDocumentationKey}) =>
      RunArgs._builder((b) => b
        ..id = _runId++
        ..scenarioName.replace(scenarioName)
        ..device.replace(device)
        ..accessibility.replace(accessibility)
        ..imageRatio = imageRatio
        ..language = language
        ..onlyWithDocumentationKey = onlyWithDocumentationKey ?? false);

  int get id;
  BuiltList<String> get scenarioName;
  DeviceInfo get device;
  AccessibilityConfig get accessibility;
  double get imageRatio;
  String get language;
  bool get onlyWithDocumentationKey;
}

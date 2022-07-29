import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'accessibility.dart';
import 'device_info.dart';
import 'locale.dart';

part 'run_args.g.dart';

int _runId = 0;

abstract class RunArgs implements Built<RunArgs, RunArgsBuilder> {
  static Serializer<RunArgs> get serializer => _$runArgsSerializer;

  RunArgs._();
  factory RunArgs._builder([void Function(RunArgsBuilder) updates]) = _$RunArgs;

  factory RunArgs(
    Iterable<String> testName, {
    required DeviceInfo device,
    required AccessibilityConfig accessibility,
    required SerializableLocale? locale,
    required double imageRatio,
    int? platformBrightness,
  }) =>
      RunArgs._builder((b) => b
        ..id = _runId++
        ..testName.replace(testName)
        ..device.replace(device)
        ..accessibility.replace(accessibility)
        ..imageRatio = imageRatio
        ..locale = locale?.toBuilder()
        ..platformBrightness = platformBrightness);

  int get id;
  BuiltList<String> get testName;
  DeviceInfo get device;
  AccessibilityConfig get accessibility;
  double get imageRatio;
  SerializableLocale? get locale;
  int? get platformBrightness;
}

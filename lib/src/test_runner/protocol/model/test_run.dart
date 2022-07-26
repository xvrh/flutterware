import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'locale.dart';
import 'run_args.dart';
import 'run_result.dart';
import 'test_reference.dart';
import 'screen.dart';

part 'test_run.g.dart';

abstract class TestRun implements Built<TestRun, TestRunBuilder> {
  static Serializer<TestRun> get serializer => _$testRunSerializer;

  TestRun._();
  factory TestRun._builder([void Function(TestRunBuilder) updates]) =
      _$TestRun;

  factory TestRun(TestReference test, RunArgs args) =>
      TestRun._builder((b) => b
        ..test.replace(test)
        ..args.replace(args));

  TestReference get test;
  RunArgs get args;
  BuiltMap<String, Screen> get screens;
  RunResult? get result;
  bool get isCompleted => result != null;

  Set<SerializableLocale> get supportedLocales {
    return screens.values.expand((s) => s.supportedLocales ?? const <SerializableLocale>[]).toSet();
  }
}

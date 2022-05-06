import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'run_result.g.dart';

abstract class RunResult implements Built<RunResult, RunResultBuilder> {
  static Serializer<RunResult> get serializer => _$runResultSerializer;

  RunResult._();
  factory RunResult._fromBuilder([void Function(RunResultBuilder) updates]) =
      _$RunResult;
  factory RunResult.error(Object error, StackTrace? stackTrace) =>
      RunResult._fromBuilder((b) => b
        ..error = '$error'
        ..errorType = '${error.runtimeType}'
        ..stackTrace = '$stackTrace');

  factory RunResult.success() => RunResult._fromBuilder();

  bool get success => error == null;

  String? get error;
  String? get errorType;
  String? get stackTrace;
  Duration? get duration;
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<RunResult> _$runResultSerializer = _$RunResultSerializer();

class _$RunResultSerializer implements StructuredSerializer<RunResult> {
  @override
  final Iterable<Type> types = const [RunResult, _$RunResult];
  @override
  final String wireName = 'RunResult';

  @override
  Iterable<Object?> serialize(Serializers serializers, RunResult object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[];
    Object? value;
    value = object.error;
    if (value != null) {
      result
        ..add('error')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.errorType;
    if (value != null) {
      result
        ..add('errorType')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.stackTrace;
    if (value != null) {
      result
        ..add('stackTrace')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.duration;
    if (value != null) {
      result
        ..add('duration')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(Duration)));
    }
    return result;
  }

  @override
  RunResult deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = RunResultBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'error':
          result.error = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'errorType':
          result.errorType = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'stackTrace':
          result.stackTrace = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'duration':
          result.duration = serializers.deserialize(value,
              specifiedType: const FullType(Duration)) as Duration?;
          break;
      }
    }

    return result.build();
  }
}

class _$RunResult extends RunResult {
  @override
  final String? error;
  @override
  final String? errorType;
  @override
  final String? stackTrace;
  @override
  final Duration? duration;

  factory _$RunResult([void Function(RunResultBuilder)? updates]) =>
      (RunResultBuilder()..update(updates))._build();

  _$RunResult._({this.error, this.errorType, this.stackTrace, this.duration})
      : super._();

  @override
  RunResult rebuild(void Function(RunResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RunResultBuilder toBuilder() => RunResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RunResult &&
        error == other.error &&
        errorType == other.errorType &&
        stackTrace == other.stackTrace &&
        duration == other.duration;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc($jc($jc(0, error.hashCode), errorType.hashCode),
            stackTrace.hashCode),
        duration.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('RunResult')
          ..add('error', error)
          ..add('errorType', errorType)
          ..add('stackTrace', stackTrace)
          ..add('duration', duration))
        .toString();
  }
}

class RunResultBuilder implements Builder<RunResult, RunResultBuilder> {
  _$RunResult? _$v;

  String? _error;
  String? get error => _$this._error;
  set error(String? error) => _$this._error = error;

  String? _errorType;
  String? get errorType => _$this._errorType;
  set errorType(String? errorType) => _$this._errorType = errorType;

  String? _stackTrace;
  String? get stackTrace => _$this._stackTrace;
  set stackTrace(String? stackTrace) => _$this._stackTrace = stackTrace;

  Duration? _duration;
  Duration? get duration => _$this._duration;
  set duration(Duration? duration) => _$this._duration = duration;

  RunResultBuilder();

  RunResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _error = $v.error;
      _errorType = $v.errorType;
      _stackTrace = $v.stackTrace;
      _duration = $v.duration;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RunResult other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$RunResult;
  }

  @override
  void update(void Function(RunResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RunResult build() => _build();

  _$RunResult _build() {
    final _$result = _$v ??
        _$RunResult._(
            error: error,
            errorType: errorType,
            stackTrace: stackTrace,
            duration: duration);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new

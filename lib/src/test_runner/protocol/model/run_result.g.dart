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
    var _$hash = 0;
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jc(_$hash, errorType.hashCode);
    _$hash = $jc(_$hash, stackTrace.hashCode);
    _$hash = $jc(_$hash, duration.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RunResult')
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

// ignore_for_file: deprecated_member_use_from_same_package,type=lint

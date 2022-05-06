// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scenario_run.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<ScenarioRun> _$scenarioRunSerializer = _$ScenarioRunSerializer();

class _$ScenarioRunSerializer implements StructuredSerializer<ScenarioRun> {
  @override
  final Iterable<Type> types = const [ScenarioRun, _$ScenarioRun];
  @override
  final String wireName = 'ScenarioRun';

  @override
  Iterable<Object?> serialize(Serializers serializers, ScenarioRun object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'scenario',
      serializers.serialize(object.scenario,
          specifiedType: const FullType(ScenarioReference)),
      'args',
      serializers.serialize(object.args,
          specifiedType: const FullType(RunArgs)),
      'screens',
      serializers.serialize(object.screens,
          specifiedType:
              const FullType(BuiltMap, [FullType(String), FullType(Screen)])),
    ];
    Object? value;
    value = object.result;
    if (value != null) {
      result
        ..add('result')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(RunResult)));
    }
    return result;
  }

  @override
  ScenarioRun deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = ScenarioRunBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'scenario':
          result.scenario.replace(serializers.deserialize(value,
                  specifiedType: const FullType(ScenarioReference))!
              as ScenarioReference);
          break;
        case 'args':
          result.args.replace(serializers.deserialize(value,
              specifiedType: const FullType(RunArgs))! as RunArgs);
          break;
        case 'screens':
          result.screens.replace(serializers.deserialize(value,
              specifiedType: const FullType(
                  BuiltMap, [FullType(String), FullType(Screen)]))!);
          break;
        case 'result':
          result.result.replace(serializers.deserialize(value,
              specifiedType: const FullType(RunResult))! as RunResult);
          break;
      }
    }

    return result.build();
  }
}

class _$ScenarioRun extends ScenarioRun {
  @override
  final ScenarioReference scenario;
  @override
  final RunArgs args;
  @override
  final BuiltMap<String, Screen> screens;
  @override
  final RunResult? result;

  factory _$ScenarioRun([void Function(ScenarioRunBuilder)? updates]) =>
      (ScenarioRunBuilder()..update(updates)).build();

  _$ScenarioRun._(
      {required this.scenario,
      required this.args,
      required this.screens,
      this.result})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(scenario, 'ScenarioRun', 'scenario');
    BuiltValueNullFieldError.checkNotNull(args, 'ScenarioRun', 'args');
    BuiltValueNullFieldError.checkNotNull(screens, 'ScenarioRun', 'screens');
  }

  @override
  ScenarioRun rebuild(void Function(ScenarioRunBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScenarioRunBuilder toBuilder() => ScenarioRunBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScenarioRun &&
        scenario == other.scenario &&
        args == other.args &&
        screens == other.screens &&
        result == other.result;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc($jc($jc(0, scenario.hashCode), args.hashCode), screens.hashCode),
        result.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ScenarioRun')
          ..add('scenario', scenario)
          ..add('args', args)
          ..add('screens', screens)
          ..add('result', result))
        .toString();
  }
}

class ScenarioRunBuilder implements Builder<ScenarioRun, ScenarioRunBuilder> {
  _$ScenarioRun? _$v;

  ScenarioReferenceBuilder? _scenario;
  ScenarioReferenceBuilder get scenario =>
      _$this._scenario ??= ScenarioReferenceBuilder();
  set scenario(ScenarioReferenceBuilder? scenario) =>
      _$this._scenario = scenario;

  RunArgsBuilder? _args;
  RunArgsBuilder get args => _$this._args ??= RunArgsBuilder();
  set args(RunArgsBuilder? args) => _$this._args = args;

  MapBuilder<String, Screen>? _screens;
  MapBuilder<String, Screen> get screens =>
      _$this._screens ??= MapBuilder<String, Screen>();
  set screens(MapBuilder<String, Screen>? screens) => _$this._screens = screens;

  RunResultBuilder? _result;
  RunResultBuilder get result => _$this._result ??= RunResultBuilder();
  set result(RunResultBuilder? result) => _$this._result = result;

  ScenarioRunBuilder();

  ScenarioRunBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _scenario = $v.scenario.toBuilder();
      _args = $v.args.toBuilder();
      _screens = $v.screens.toBuilder();
      _result = $v.result?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScenarioRun other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$ScenarioRun;
  }

  @override
  void update(void Function(ScenarioRunBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ScenarioRun build() {
    _$ScenarioRun _$result;
    try {
      _$result = _$v ??
          _$ScenarioRun._(
              scenario: scenario.build(),
              args: args.build(),
              screens: screens.build(),
              result: _result?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'scenario';
        scenario.build();
        _$failedField = 'args';
        args.build();
        _$failedField = 'screens';
        screens.build();
        _$failedField = 'result';
        _result?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            'ScenarioRun', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new

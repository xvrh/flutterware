// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'test_run.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<TestRun> _$testRunSerializer = new _$TestRunSerializer();

class _$TestRunSerializer implements StructuredSerializer<TestRun> {
  @override
  final Iterable<Type> types = const [TestRun, _$TestRun];
  @override
  final String wireName = 'TestRun';

  @override
  Iterable<Object?> serialize(Serializers serializers, TestRun object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'test',
      serializers.serialize(object.test,
          specifiedType: const FullType(TestReference)),
      'args',
      serializers.serialize(object.args,
          specifiedType: const FullType(RunArgs)),
      'screens',
      serializers.serialize(object.screens,
          specifiedType: const FullType(BuiltMap,
              const [const FullType(String), const FullType(Screen)])),
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
  TestRun deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new TestRunBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'test':
          result.test.replace(serializers.deserialize(value,
              specifiedType: const FullType(TestReference))! as TestReference);
          break;
        case 'args':
          result.args.replace(serializers.deserialize(value,
              specifiedType: const FullType(RunArgs))! as RunArgs);
          break;
        case 'screens':
          result.screens.replace(serializers.deserialize(value,
              specifiedType: const FullType(BuiltMap,
                  const [const FullType(String), const FullType(Screen)]))!);
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

class _$TestRun extends TestRun {
  @override
  final TestReference test;
  @override
  final RunArgs args;
  @override
  final BuiltMap<String, Screen> screens;
  @override
  final RunResult? result;

  factory _$TestRun([void Function(TestRunBuilder)? updates]) =>
      (new TestRunBuilder()..update(updates))._build();

  _$TestRun._(
      {required this.test,
      required this.args,
      required this.screens,
      this.result})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(test, r'TestRun', 'test');
    BuiltValueNullFieldError.checkNotNull(args, r'TestRun', 'args');
    BuiltValueNullFieldError.checkNotNull(screens, r'TestRun', 'screens');
  }

  @override
  TestRun rebuild(void Function(TestRunBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TestRunBuilder toBuilder() => new TestRunBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TestRun &&
        test == other.test &&
        args == other.args &&
        screens == other.screens &&
        result == other.result;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, test.hashCode);
    _$hash = $jc(_$hash, args.hashCode);
    _$hash = $jc(_$hash, screens.hashCode);
    _$hash = $jc(_$hash, result.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TestRun')
          ..add('test', test)
          ..add('args', args)
          ..add('screens', screens)
          ..add('result', result))
        .toString();
  }
}

class TestRunBuilder implements Builder<TestRun, TestRunBuilder> {
  _$TestRun? _$v;

  TestReferenceBuilder? _test;
  TestReferenceBuilder get test => _$this._test ??= new TestReferenceBuilder();
  set test(TestReferenceBuilder? test) => _$this._test = test;

  RunArgsBuilder? _args;
  RunArgsBuilder get args => _$this._args ??= new RunArgsBuilder();
  set args(RunArgsBuilder? args) => _$this._args = args;

  MapBuilder<String, Screen>? _screens;
  MapBuilder<String, Screen> get screens =>
      _$this._screens ??= new MapBuilder<String, Screen>();
  set screens(MapBuilder<String, Screen>? screens) => _$this._screens = screens;

  RunResultBuilder? _result;
  RunResultBuilder get result => _$this._result ??= new RunResultBuilder();
  set result(RunResultBuilder? result) => _$this._result = result;

  TestRunBuilder();

  TestRunBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _test = $v.test.toBuilder();
      _args = $v.args.toBuilder();
      _screens = $v.screens.toBuilder();
      _result = $v.result?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TestRun other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$TestRun;
  }

  @override
  void update(void Function(TestRunBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TestRun build() => _build();

  _$TestRun _build() {
    _$TestRun _$result;
    try {
      _$result = _$v ??
          new _$TestRun._(
              test: test.build(),
              args: args.build(),
              screens: screens.build(),
              result: _result?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'test';
        test.build();
        _$failedField = 'args';
        args.build();
        _$failedField = 'screens';
        screens.build();
        _$failedField = 'result';
        _result?.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            r'TestRun', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint

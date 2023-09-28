// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_args.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<RunArgs> _$runArgsSerializer = new _$RunArgsSerializer();

class _$RunArgsSerializer implements StructuredSerializer<RunArgs> {
  @override
  final Iterable<Type> types = const [RunArgs, _$RunArgs];
  @override
  final String wireName = 'RunArgs';

  @override
  Iterable<Object?> serialize(Serializers serializers, RunArgs object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(int)),
      'testName',
      serializers.serialize(object.testName,
          specifiedType:
              const FullType(BuiltList, const [const FullType(String)])),
      'device',
      serializers.serialize(object.device,
          specifiedType: const FullType(DeviceInfo)),
      'accessibility',
      serializers.serialize(object.accessibility,
          specifiedType: const FullType(AccessibilityConfig)),
      'imageRatio',
      serializers.serialize(object.imageRatio,
          specifiedType: const FullType(double)),
    ];
    Object? value;
    value = object.locale;
    if (value != null) {
      result
        ..add('locale')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(SerializableLocale)));
    }
    value = object.platformBrightness;
    if (value != null) {
      result
        ..add('platformBrightness')
        ..add(serializers.serialize(value, specifiedType: const FullType(int)));
    }
    return result;
  }

  @override
  RunArgs deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new RunArgsBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'id':
          result.id = serializers.deserialize(value,
              specifiedType: const FullType(int))! as int;
          break;
        case 'testName':
          result.testName.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, const [const FullType(String)]))!
              as BuiltList<Object?>);
          break;
        case 'device':
          result.device.replace(serializers.deserialize(value,
              specifiedType: const FullType(DeviceInfo))! as DeviceInfo);
          break;
        case 'accessibility':
          result.accessibility.replace(serializers.deserialize(value,
                  specifiedType: const FullType(AccessibilityConfig))!
              as AccessibilityConfig);
          break;
        case 'imageRatio':
          result.imageRatio = serializers.deserialize(value,
              specifiedType: const FullType(double))! as double;
          break;
        case 'locale':
          result.locale.replace(serializers.deserialize(value,
                  specifiedType: const FullType(SerializableLocale))!
              as SerializableLocale);
          break;
        case 'platformBrightness':
          result.platformBrightness = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int?;
          break;
      }
    }

    return result.build();
  }
}

class _$RunArgs extends RunArgs {
  @override
  final int id;
  @override
  final BuiltList<String> testName;
  @override
  final DeviceInfo device;
  @override
  final AccessibilityConfig accessibility;
  @override
  final double imageRatio;
  @override
  final SerializableLocale? locale;
  @override
  final int? platformBrightness;

  factory _$RunArgs([void Function(RunArgsBuilder)? updates]) =>
      (new RunArgsBuilder()..update(updates))._build();

  _$RunArgs._(
      {required this.id,
      required this.testName,
      required this.device,
      required this.accessibility,
      required this.imageRatio,
      this.locale,
      this.platformBrightness})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(id, r'RunArgs', 'id');
    BuiltValueNullFieldError.checkNotNull(testName, r'RunArgs', 'testName');
    BuiltValueNullFieldError.checkNotNull(device, r'RunArgs', 'device');
    BuiltValueNullFieldError.checkNotNull(
        accessibility, r'RunArgs', 'accessibility');
    BuiltValueNullFieldError.checkNotNull(imageRatio, r'RunArgs', 'imageRatio');
  }

  @override
  RunArgs rebuild(void Function(RunArgsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RunArgsBuilder toBuilder() => new RunArgsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RunArgs &&
        id == other.id &&
        testName == other.testName &&
        device == other.device &&
        accessibility == other.accessibility &&
        imageRatio == other.imageRatio &&
        locale == other.locale &&
        platformBrightness == other.platformBrightness;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, testName.hashCode);
    _$hash = $jc(_$hash, device.hashCode);
    _$hash = $jc(_$hash, accessibility.hashCode);
    _$hash = $jc(_$hash, imageRatio.hashCode);
    _$hash = $jc(_$hash, locale.hashCode);
    _$hash = $jc(_$hash, platformBrightness.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RunArgs')
          ..add('id', id)
          ..add('testName', testName)
          ..add('device', device)
          ..add('accessibility', accessibility)
          ..add('imageRatio', imageRatio)
          ..add('locale', locale)
          ..add('platformBrightness', platformBrightness))
        .toString();
  }
}

class RunArgsBuilder implements Builder<RunArgs, RunArgsBuilder> {
  _$RunArgs? _$v;

  int? _id;
  int? get id => _$this._id;
  set id(int? id) => _$this._id = id;

  ListBuilder<String>? _testName;
  ListBuilder<String> get testName =>
      _$this._testName ??= new ListBuilder<String>();
  set testName(ListBuilder<String>? testName) => _$this._testName = testName;

  DeviceInfoBuilder? _device;
  DeviceInfoBuilder get device => _$this._device ??= new DeviceInfoBuilder();
  set device(DeviceInfoBuilder? device) => _$this._device = device;

  AccessibilityConfigBuilder? _accessibility;
  AccessibilityConfigBuilder get accessibility =>
      _$this._accessibility ??= new AccessibilityConfigBuilder();
  set accessibility(AccessibilityConfigBuilder? accessibility) =>
      _$this._accessibility = accessibility;

  double? _imageRatio;
  double? get imageRatio => _$this._imageRatio;
  set imageRatio(double? imageRatio) => _$this._imageRatio = imageRatio;

  SerializableLocaleBuilder? _locale;
  SerializableLocaleBuilder get locale =>
      _$this._locale ??= new SerializableLocaleBuilder();
  set locale(SerializableLocaleBuilder? locale) => _$this._locale = locale;

  int? _platformBrightness;
  int? get platformBrightness => _$this._platformBrightness;
  set platformBrightness(int? platformBrightness) =>
      _$this._platformBrightness = platformBrightness;

  RunArgsBuilder();

  RunArgsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _testName = $v.testName.toBuilder();
      _device = $v.device.toBuilder();
      _accessibility = $v.accessibility.toBuilder();
      _imageRatio = $v.imageRatio;
      _locale = $v.locale?.toBuilder();
      _platformBrightness = $v.platformBrightness;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RunArgs other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$RunArgs;
  }

  @override
  void update(void Function(RunArgsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RunArgs build() => _build();

  _$RunArgs _build() {
    _$RunArgs _$result;
    try {
      _$result = _$v ??
          new _$RunArgs._(
              id: BuiltValueNullFieldError.checkNotNull(id, r'RunArgs', 'id'),
              testName: testName.build(),
              device: device.build(),
              accessibility: accessibility.build(),
              imageRatio: BuiltValueNullFieldError.checkNotNull(
                  imageRatio, r'RunArgs', 'imageRatio'),
              locale: _locale?.build(),
              platformBrightness: platformBrightness);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'testName';
        testName.build();
        _$failedField = 'device';
        device.build();
        _$failedField = 'accessibility';
        accessibility.build();

        _$failedField = 'locale';
        _locale?.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            r'RunArgs', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint

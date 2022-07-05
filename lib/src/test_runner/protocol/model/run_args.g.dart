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
      'scenarioName',
      serializers.serialize(object.scenarioName,
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
      'language',
      serializers.serialize(object.language,
          specifiedType: const FullType(String)),
    ];
    Object? value;
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
        case 'scenarioName':
          result.scenarioName.replace(serializers.deserialize(value,
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
        case 'language':
          result.language = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
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
  final BuiltList<String> scenarioName;
  @override
  final DeviceInfo device;
  @override
  final AccessibilityConfig accessibility;
  @override
  final double imageRatio;
  @override
  final String language;
  @override
  final int? platformBrightness;

  factory _$RunArgs([void Function(RunArgsBuilder)? updates]) =>
      (new RunArgsBuilder()..update(updates))._build();

  _$RunArgs._(
      {required this.id,
      required this.scenarioName,
      required this.device,
      required this.accessibility,
      required this.imageRatio,
      required this.language,
      this.platformBrightness})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(id, 'RunArgs', 'id');
    BuiltValueNullFieldError.checkNotNull(
        scenarioName, 'RunArgs', 'scenarioName');
    BuiltValueNullFieldError.checkNotNull(device, 'RunArgs', 'device');
    BuiltValueNullFieldError.checkNotNull(
        accessibility, 'RunArgs', 'accessibility');
    BuiltValueNullFieldError.checkNotNull(imageRatio, 'RunArgs', 'imageRatio');
    BuiltValueNullFieldError.checkNotNull(language, 'RunArgs', 'language');
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
        scenarioName == other.scenarioName &&
        device == other.device &&
        accessibility == other.accessibility &&
        imageRatio == other.imageRatio &&
        language == other.language &&
        platformBrightness == other.platformBrightness;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc($jc($jc(0, id.hashCode), scenarioName.hashCode),
                        device.hashCode),
                    accessibility.hashCode),
                imageRatio.hashCode),
            language.hashCode),
        platformBrightness.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('RunArgs')
          ..add('id', id)
          ..add('scenarioName', scenarioName)
          ..add('device', device)
          ..add('accessibility', accessibility)
          ..add('imageRatio', imageRatio)
          ..add('language', language)
          ..add('platformBrightness', platformBrightness))
        .toString();
  }
}

class RunArgsBuilder implements Builder<RunArgs, RunArgsBuilder> {
  _$RunArgs? _$v;

  int? _id;
  int? get id => _$this._id;
  set id(int? id) => _$this._id = id;

  ListBuilder<String>? _scenarioName;
  ListBuilder<String> get scenarioName =>
      _$this._scenarioName ??= new ListBuilder<String>();
  set scenarioName(ListBuilder<String>? scenarioName) =>
      _$this._scenarioName = scenarioName;

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

  String? _language;
  String? get language => _$this._language;
  set language(String? language) => _$this._language = language;

  int? _platformBrightness;
  int? get platformBrightness => _$this._platformBrightness;
  set platformBrightness(int? platformBrightness) =>
      _$this._platformBrightness = platformBrightness;

  RunArgsBuilder();

  RunArgsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _scenarioName = $v.scenarioName.toBuilder();
      _device = $v.device.toBuilder();
      _accessibility = $v.accessibility.toBuilder();
      _imageRatio = $v.imageRatio;
      _language = $v.language;
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
              id: BuiltValueNullFieldError.checkNotNull(id, 'RunArgs', 'id'),
              scenarioName: scenarioName.build(),
              device: device.build(),
              accessibility: accessibility.build(),
              imageRatio: BuiltValueNullFieldError.checkNotNull(
                  imageRatio, 'RunArgs', 'imageRatio'),
              language: BuiltValueNullFieldError.checkNotNull(
                  language, 'RunArgs', 'language'),
              platformBrightness: platformBrightness);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'scenarioName';
        scenarioName.build();
        _$failedField = 'device';
        device.build();
        _$failedField = 'accessibility';
        accessibility.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            'RunArgs', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new

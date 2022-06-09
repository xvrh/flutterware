// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DevicePlatform _$android = const DevicePlatform._('android');
const DevicePlatform _$ios = const DevicePlatform._('iOS');

DevicePlatform _$vlOf(String name) {
  switch (name) {
    case 'android':
      return _$android;
    case 'iOS':
      return _$ios;
    default:
      throw new ArgumentError(name);
  }
}

final BuiltSet<DevicePlatform> _$vls =
    new BuiltSet<DevicePlatform>(const <DevicePlatform>[
  _$android,
  _$ios,
]);

Serializer<DeviceInfo> _$deviceInfoSerializer = new _$DeviceInfoSerializer();
Serializer<DevicePlatform> _$devicePlatformSerializer =
    new _$DevicePlatformSerializer();

class _$DeviceInfoSerializer implements StructuredSerializer<DeviceInfo> {
  @override
  final Iterable<Type> types = const [DeviceInfo, _$DeviceInfo];
  @override
  final String wireName = 'DeviceInfo';

  @override
  Iterable<Object?> serialize(Serializers serializers, DeviceInfo object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(String)),
      'name',
      serializers.serialize(object.name, specifiedType: const FullType(String)),
      'platform',
      serializers.serialize(object.platform,
          specifiedType: const FullType(DevicePlatform)),
      'width',
      serializers.serialize(object.width,
          specifiedType: const FullType(double)),
      'height',
      serializers.serialize(object.height,
          specifiedType: const FullType(double)),
      'pixelRatio',
      serializers.serialize(object.pixelRatio,
          specifiedType: const FullType(double)),
      'safeArea',
      serializers.serialize(object.safeArea,
          specifiedType: const FullType(Rectangle)),
    ];

    return result;
  }

  @override
  DeviceInfo deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new DeviceInfoBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'id':
          result.id = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'name':
          result.name = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'platform':
          result.platform = serializers.deserialize(value,
              specifiedType: const FullType(DevicePlatform))! as DevicePlatform;
          break;
        case 'width':
          result.width = serializers.deserialize(value,
              specifiedType: const FullType(double))! as double;
          break;
        case 'height':
          result.height = serializers.deserialize(value,
              specifiedType: const FullType(double))! as double;
          break;
        case 'pixelRatio':
          result.pixelRatio = serializers.deserialize(value,
              specifiedType: const FullType(double))! as double;
          break;
        case 'safeArea':
          result.safeArea.replace(serializers.deserialize(value,
              specifiedType: const FullType(Rectangle))! as Rectangle);
          break;
      }
    }

    return result.build();
  }
}

class _$DevicePlatformSerializer
    implements PrimitiveSerializer<DevicePlatform> {
  @override
  final Iterable<Type> types = const <Type>[DevicePlatform];
  @override
  final String wireName = 'DevicePlatform';

  @override
  Object serialize(Serializers serializers, DevicePlatform object,
          {FullType specifiedType = FullType.unspecified}) =>
      object.name;

  @override
  DevicePlatform deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DevicePlatform.valueOf(serialized as String);
}

class _$DeviceInfo extends DeviceInfo {
  @override
  final String id;
  @override
  final String name;
  @override
  final DevicePlatform platform;
  @override
  final double width;
  @override
  final double height;
  @override
  final double pixelRatio;
  @override
  final Rectangle safeArea;

  factory _$DeviceInfo([void Function(DeviceInfoBuilder)? updates]) =>
      (new DeviceInfoBuilder()..update(updates))._build();

  _$DeviceInfo._(
      {required this.id,
      required this.name,
      required this.platform,
      required this.width,
      required this.height,
      required this.pixelRatio,
      required this.safeArea})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(id, 'DeviceInfo', 'id');
    BuiltValueNullFieldError.checkNotNull(name, 'DeviceInfo', 'name');
    BuiltValueNullFieldError.checkNotNull(platform, 'DeviceInfo', 'platform');
    BuiltValueNullFieldError.checkNotNull(width, 'DeviceInfo', 'width');
    BuiltValueNullFieldError.checkNotNull(height, 'DeviceInfo', 'height');
    BuiltValueNullFieldError.checkNotNull(
        pixelRatio, 'DeviceInfo', 'pixelRatio');
    BuiltValueNullFieldError.checkNotNull(safeArea, 'DeviceInfo', 'safeArea');
  }

  @override
  DeviceInfo rebuild(void Function(DeviceInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DeviceInfoBuilder toBuilder() => new DeviceInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DeviceInfo &&
        id == other.id &&
        name == other.name &&
        platform == other.platform &&
        width == other.width &&
        height == other.height &&
        pixelRatio == other.pixelRatio &&
        safeArea == other.safeArea;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc($jc($jc(0, id.hashCode), name.hashCode),
                        platform.hashCode),
                    width.hashCode),
                height.hashCode),
            pixelRatio.hashCode),
        safeArea.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('DeviceInfo')
          ..add('id', id)
          ..add('name', name)
          ..add('platform', platform)
          ..add('width', width)
          ..add('height', height)
          ..add('pixelRatio', pixelRatio)
          ..add('safeArea', safeArea))
        .toString();
  }
}

class DeviceInfoBuilder implements Builder<DeviceInfo, DeviceInfoBuilder> {
  _$DeviceInfo? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  DevicePlatform? _platform;
  DevicePlatform? get platform => _$this._platform;
  set platform(DevicePlatform? platform) => _$this._platform = platform;

  double? _width;
  double? get width => _$this._width;
  set width(double? width) => _$this._width = width;

  double? _height;
  double? get height => _$this._height;
  set height(double? height) => _$this._height = height;

  double? _pixelRatio;
  double? get pixelRatio => _$this._pixelRatio;
  set pixelRatio(double? pixelRatio) => _$this._pixelRatio = pixelRatio;

  RectangleBuilder? _safeArea;
  RectangleBuilder get safeArea => _$this._safeArea ??= new RectangleBuilder();
  set safeArea(RectangleBuilder? safeArea) => _$this._safeArea = safeArea;

  DeviceInfoBuilder();

  DeviceInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _platform = $v.platform;
      _width = $v.width;
      _height = $v.height;
      _pixelRatio = $v.pixelRatio;
      _safeArea = $v.safeArea.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DeviceInfo other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$DeviceInfo;
  }

  @override
  void update(void Function(DeviceInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DeviceInfo build() => _build();

  _$DeviceInfo _build() {
    _$DeviceInfo _$result;
    try {
      _$result = _$v ??
          new _$DeviceInfo._(
              id: BuiltValueNullFieldError.checkNotNull(id, 'DeviceInfo', 'id'),
              name: BuiltValueNullFieldError.checkNotNull(
                  name, 'DeviceInfo', 'name'),
              platform: BuiltValueNullFieldError.checkNotNull(
                  platform, 'DeviceInfo', 'platform'),
              width: BuiltValueNullFieldError.checkNotNull(
                  width, 'DeviceInfo', 'width'),
              height: BuiltValueNullFieldError.checkNotNull(
                  height, 'DeviceInfo', 'height'),
              pixelRatio: BuiltValueNullFieldError.checkNotNull(
                  pixelRatio, 'DeviceInfo', 'pixelRatio'),
              safeArea: safeArea.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'safeArea';
        safeArea.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            'DeviceInfo', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
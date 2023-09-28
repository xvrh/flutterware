// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DevicePlatform _$android = DevicePlatform._('android');
const DevicePlatform _$ios = DevicePlatform._('iOS');

DevicePlatform _$vlOf(String name) {
  switch (name) {
    case 'android':
      return _$android;
    case 'iOS':
      return _$ios;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DevicePlatform> _$vls =
    BuiltSet<DevicePlatform>(const <DevicePlatform>[
  _$android,
  _$ios,
]);

Serializer<DeviceInfo> _$deviceInfoSerializer = _$DeviceInfoSerializer();
Serializer<DevicePlatform> _$devicePlatformSerializer =
    _$DevicePlatformSerializer();

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
    final result = DeviceInfoBuilder();

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
      (DeviceInfoBuilder()..update(updates))._build();

  _$DeviceInfo._(
      {required this.id,
      required this.name,
      required this.platform,
      required this.width,
      required this.height,
      required this.pixelRatio,
      required this.safeArea})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(id, r'DeviceInfo', 'id');
    BuiltValueNullFieldError.checkNotNull(name, r'DeviceInfo', 'name');
    BuiltValueNullFieldError.checkNotNull(platform, r'DeviceInfo', 'platform');
    BuiltValueNullFieldError.checkNotNull(width, r'DeviceInfo', 'width');
    BuiltValueNullFieldError.checkNotNull(height, r'DeviceInfo', 'height');
    BuiltValueNullFieldError.checkNotNull(
        pixelRatio, r'DeviceInfo', 'pixelRatio');
    BuiltValueNullFieldError.checkNotNull(safeArea, r'DeviceInfo', 'safeArea');
  }

  @override
  DeviceInfo rebuild(void Function(DeviceInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DeviceInfoBuilder toBuilder() => DeviceInfoBuilder()..replace(this);

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
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, platform.hashCode);
    _$hash = $jc(_$hash, width.hashCode);
    _$hash = $jc(_$hash, height.hashCode);
    _$hash = $jc(_$hash, pixelRatio.hashCode);
    _$hash = $jc(_$hash, safeArea.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DeviceInfo')
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
  RectangleBuilder get safeArea => _$this._safeArea ??= RectangleBuilder();
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
          _$DeviceInfo._(
              id: BuiltValueNullFieldError.checkNotNull(
                  id, r'DeviceInfo', 'id'),
              name: BuiltValueNullFieldError.checkNotNull(
                  name, r'DeviceInfo', 'name'),
              platform: BuiltValueNullFieldError.checkNotNull(
                  platform, r'DeviceInfo', 'platform'),
              width: BuiltValueNullFieldError.checkNotNull(
                  width, r'DeviceInfo', 'width'),
              height: BuiltValueNullFieldError.checkNotNull(
                  height, r'DeviceInfo', 'height'),
              pixelRatio: BuiltValueNullFieldError.checkNotNull(
                  pixelRatio, r'DeviceInfo', 'pixelRatio'),
              safeArea: safeArea.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'safeArea';
        safeArea.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'DeviceInfo', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint

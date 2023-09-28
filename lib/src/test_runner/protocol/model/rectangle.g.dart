// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rectangle.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<Rectangle> _$rectangleSerializer = new _$RectangleSerializer();

class _$RectangleSerializer implements StructuredSerializer<Rectangle> {
  @override
  final Iterable<Type> types = const [Rectangle, _$Rectangle];
  @override
  final String wireName = 'Rectangle';

  @override
  Iterable<Object?> serialize(Serializers serializers, Rectangle object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'left',
      serializers.serialize(object.left, specifiedType: const FullType(double)),
      'top',
      serializers.serialize(object.top, specifiedType: const FullType(double)),
      'right',
      serializers.serialize(object.right,
          specifiedType: const FullType(double)),
      'bottom',
      serializers.serialize(object.bottom,
          specifiedType: const FullType(double)),
    ];

    return result;
  }

  @override
  Rectangle deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new RectangleBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'left':
          result.left = serializers.deserialize(value,
              specifiedType: const FullType(double))! as double;
          break;
        case 'top':
          result.top = serializers.deserialize(value,
              specifiedType: const FullType(double))! as double;
          break;
        case 'right':
          result.right = serializers.deserialize(value,
              specifiedType: const FullType(double))! as double;
          break;
        case 'bottom':
          result.bottom = serializers.deserialize(value,
              specifiedType: const FullType(double))! as double;
          break;
      }
    }

    return result.build();
  }
}

class _$Rectangle extends Rectangle {
  @override
  final double left;
  @override
  final double top;
  @override
  final double right;
  @override
  final double bottom;

  factory _$Rectangle([void Function(RectangleBuilder)? updates]) =>
      (new RectangleBuilder()..update(updates))._build();

  _$Rectangle._(
      {required this.left,
      required this.top,
      required this.right,
      required this.bottom})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(left, r'Rectangle', 'left');
    BuiltValueNullFieldError.checkNotNull(top, r'Rectangle', 'top');
    BuiltValueNullFieldError.checkNotNull(right, r'Rectangle', 'right');
    BuiltValueNullFieldError.checkNotNull(bottom, r'Rectangle', 'bottom');
  }

  @override
  Rectangle rebuild(void Function(RectangleBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RectangleBuilder toBuilder() => new RectangleBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Rectangle &&
        left == other.left &&
        top == other.top &&
        right == other.right &&
        bottom == other.bottom;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, left.hashCode);
    _$hash = $jc(_$hash, top.hashCode);
    _$hash = $jc(_$hash, right.hashCode);
    _$hash = $jc(_$hash, bottom.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Rectangle')
          ..add('left', left)
          ..add('top', top)
          ..add('right', right)
          ..add('bottom', bottom))
        .toString();
  }
}

class RectangleBuilder implements Builder<Rectangle, RectangleBuilder> {
  _$Rectangle? _$v;

  double? _left;
  double? get left => _$this._left;
  set left(double? left) => _$this._left = left;

  double? _top;
  double? get top => _$this._top;
  set top(double? top) => _$this._top = top;

  double? _right;
  double? get right => _$this._right;
  set right(double? right) => _$this._right = right;

  double? _bottom;
  double? get bottom => _$this._bottom;
  set bottom(double? bottom) => _$this._bottom = bottom;

  RectangleBuilder();

  RectangleBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _left = $v.left;
      _top = $v.top;
      _right = $v.right;
      _bottom = $v.bottom;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Rectangle other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$Rectangle;
  }

  @override
  void update(void Function(RectangleBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Rectangle build() => _build();

  _$Rectangle _build() {
    final _$result = _$v ??
        new _$Rectangle._(
            left: BuiltValueNullFieldError.checkNotNull(
                left, r'Rectangle', 'left'),
            top:
                BuiltValueNullFieldError.checkNotNull(top, r'Rectangle', 'top'),
            right: BuiltValueNullFieldError.checkNotNull(
                right, r'Rectangle', 'right'),
            bottom: BuiltValueNullFieldError.checkNotNull(
                bottom, r'Rectangle', 'bottom'));
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint

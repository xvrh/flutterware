// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accessibility.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<AccessibilityConfig> _$accessibilityConfigSerializer =
    new _$AccessibilityConfigSerializer();

class _$AccessibilityConfigSerializer
    implements StructuredSerializer<AccessibilityConfig> {
  @override
  final Iterable<Type> types = const [
    AccessibilityConfig,
    _$AccessibilityConfig
  ];
  @override
  final String wireName = 'AccessibilityConfig';

  @override
  Iterable<Object?> serialize(
      Serializers serializers, AccessibilityConfig object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'textScale',
      serializers.serialize(object.textScale,
          specifiedType: const FullType(double)),
      'boldText',
      serializers.serialize(object.boldText,
          specifiedType: const FullType(bool)),
    ];

    return result;
  }

  @override
  AccessibilityConfig deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new AccessibilityConfigBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'textScale':
          result.textScale = serializers.deserialize(value,
              specifiedType: const FullType(double))! as double;
          break;
        case 'boldText':
          result.boldText = serializers.deserialize(value,
              specifiedType: const FullType(bool))! as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$AccessibilityConfig extends AccessibilityConfig {
  @override
  final double textScale;
  @override
  final bool boldText;

  factory _$AccessibilityConfig(
          [void Function(AccessibilityConfigBuilder)? updates]) =>
      (new AccessibilityConfigBuilder()..update(updates))._build();

  _$AccessibilityConfig._({required this.textScale, required this.boldText})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(
        textScale, 'AccessibilityConfig', 'textScale');
    BuiltValueNullFieldError.checkNotNull(
        boldText, 'AccessibilityConfig', 'boldText');
  }

  @override
  AccessibilityConfig rebuild(
          void Function(AccessibilityConfigBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AccessibilityConfigBuilder toBuilder() =>
      new AccessibilityConfigBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AccessibilityConfig &&
        textScale == other.textScale &&
        boldText == other.boldText;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, textScale.hashCode), boldText.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('AccessibilityConfig')
          ..add('textScale', textScale)
          ..add('boldText', boldText))
        .toString();
  }
}

class AccessibilityConfigBuilder
    implements Builder<AccessibilityConfig, AccessibilityConfigBuilder> {
  _$AccessibilityConfig? _$v;

  double? _textScale;
  double? get textScale => _$this._textScale;
  set textScale(double? textScale) => _$this._textScale = textScale;

  bool? _boldText;
  bool? get boldText => _$this._boldText;
  set boldText(bool? boldText) => _$this._boldText = boldText;

  AccessibilityConfigBuilder();

  AccessibilityConfigBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _textScale = $v.textScale;
      _boldText = $v.boldText;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AccessibilityConfig other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$AccessibilityConfig;
  }

  @override
  void update(void Function(AccessibilityConfigBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AccessibilityConfig build() => _build();

  _$AccessibilityConfig _build() {
    final _$result = _$v ??
        new _$AccessibilityConfig._(
            textScale: BuiltValueNullFieldError.checkNotNull(
                textScale, 'AccessibilityConfig', 'textScale'),
            boldText: BuiltValueNullFieldError.checkNotNull(
                boldText, 'AccessibilityConfig', 'boldText'));
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new

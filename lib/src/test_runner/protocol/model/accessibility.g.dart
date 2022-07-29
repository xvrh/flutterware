// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accessibility.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<AccessibilityConfig> _$accessibilityConfigSerializer =
    _$AccessibilityConfigSerializer();

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
      'accessibleNavigation',
      serializers.serialize(object.accessibleNavigation,
          specifiedType: const FullType(bool)),
      'disableAnimations',
      serializers.serialize(object.disableAnimations,
          specifiedType: const FullType(bool)),
      'highContrast',
      serializers.serialize(object.highContrast,
          specifiedType: const FullType(bool)),
      'invertColors',
      serializers.serialize(object.invertColors,
          specifiedType: const FullType(bool)),
      'reduceMotion',
      serializers.serialize(object.reduceMotion,
          specifiedType: const FullType(bool)),
      'onOffSwitchLabels',
      serializers.serialize(object.onOffSwitchLabels,
          specifiedType: const FullType(bool)),
    ];

    return result;
  }

  @override
  AccessibilityConfig deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = AccessibilityConfigBuilder();

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
        case 'accessibleNavigation':
          result.accessibleNavigation = serializers.deserialize(value,
              specifiedType: const FullType(bool))! as bool;
          break;
        case 'disableAnimations':
          result.disableAnimations = serializers.deserialize(value,
              specifiedType: const FullType(bool))! as bool;
          break;
        case 'highContrast':
          result.highContrast = serializers.deserialize(value,
              specifiedType: const FullType(bool))! as bool;
          break;
        case 'invertColors':
          result.invertColors = serializers.deserialize(value,
              specifiedType: const FullType(bool))! as bool;
          break;
        case 'reduceMotion':
          result.reduceMotion = serializers.deserialize(value,
              specifiedType: const FullType(bool))! as bool;
          break;
        case 'onOffSwitchLabels':
          result.onOffSwitchLabels = serializers.deserialize(value,
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
  @override
  final bool accessibleNavigation;
  @override
  final bool disableAnimations;
  @override
  final bool highContrast;
  @override
  final bool invertColors;
  @override
  final bool reduceMotion;
  @override
  final bool onOffSwitchLabels;

  factory _$AccessibilityConfig(
          [void Function(AccessibilityConfigBuilder)? updates]) =>
      (AccessibilityConfigBuilder()..update(updates))._build();

  _$AccessibilityConfig._(
      {required this.textScale,
      required this.boldText,
      required this.accessibleNavigation,
      required this.disableAnimations,
      required this.highContrast,
      required this.invertColors,
      required this.reduceMotion,
      required this.onOffSwitchLabels})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(
        textScale, 'AccessibilityConfig', 'textScale');
    BuiltValueNullFieldError.checkNotNull(
        boldText, 'AccessibilityConfig', 'boldText');
    BuiltValueNullFieldError.checkNotNull(
        accessibleNavigation, 'AccessibilityConfig', 'accessibleNavigation');
    BuiltValueNullFieldError.checkNotNull(
        disableAnimations, 'AccessibilityConfig', 'disableAnimations');
    BuiltValueNullFieldError.checkNotNull(
        highContrast, 'AccessibilityConfig', 'highContrast');
    BuiltValueNullFieldError.checkNotNull(
        invertColors, 'AccessibilityConfig', 'invertColors');
    BuiltValueNullFieldError.checkNotNull(
        reduceMotion, 'AccessibilityConfig', 'reduceMotion');
    BuiltValueNullFieldError.checkNotNull(
        onOffSwitchLabels, 'AccessibilityConfig', 'onOffSwitchLabels');
  }

  @override
  AccessibilityConfig rebuild(
          void Function(AccessibilityConfigBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AccessibilityConfigBuilder toBuilder() =>
      AccessibilityConfigBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AccessibilityConfig &&
        textScale == other.textScale &&
        boldText == other.boldText &&
        accessibleNavigation == other.accessibleNavigation &&
        disableAnimations == other.disableAnimations &&
        highContrast == other.highContrast &&
        invertColors == other.invertColors &&
        reduceMotion == other.reduceMotion &&
        onOffSwitchLabels == other.onOffSwitchLabels;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc(
                        $jc($jc($jc(0, textScale.hashCode), boldText.hashCode),
                            accessibleNavigation.hashCode),
                        disableAnimations.hashCode),
                    highContrast.hashCode),
                invertColors.hashCode),
            reduceMotion.hashCode),
        onOffSwitchLabels.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('AccessibilityConfig')
          ..add('textScale', textScale)
          ..add('boldText', boldText)
          ..add('accessibleNavigation', accessibleNavigation)
          ..add('disableAnimations', disableAnimations)
          ..add('highContrast', highContrast)
          ..add('invertColors', invertColors)
          ..add('reduceMotion', reduceMotion)
          ..add('onOffSwitchLabels', onOffSwitchLabels))
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

  bool? _accessibleNavigation;
  bool? get accessibleNavigation => _$this._accessibleNavigation;
  set accessibleNavigation(bool? accessibleNavigation) =>
      _$this._accessibleNavigation = accessibleNavigation;

  bool? _disableAnimations;
  bool? get disableAnimations => _$this._disableAnimations;
  set disableAnimations(bool? disableAnimations) =>
      _$this._disableAnimations = disableAnimations;

  bool? _highContrast;
  bool? get highContrast => _$this._highContrast;
  set highContrast(bool? highContrast) => _$this._highContrast = highContrast;

  bool? _invertColors;
  bool? get invertColors => _$this._invertColors;
  set invertColors(bool? invertColors) => _$this._invertColors = invertColors;

  bool? _reduceMotion;
  bool? get reduceMotion => _$this._reduceMotion;
  set reduceMotion(bool? reduceMotion) => _$this._reduceMotion = reduceMotion;

  bool? _onOffSwitchLabels;
  bool? get onOffSwitchLabels => _$this._onOffSwitchLabels;
  set onOffSwitchLabels(bool? onOffSwitchLabels) =>
      _$this._onOffSwitchLabels = onOffSwitchLabels;

  AccessibilityConfigBuilder();

  AccessibilityConfigBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _textScale = $v.textScale;
      _boldText = $v.boldText;
      _accessibleNavigation = $v.accessibleNavigation;
      _disableAnimations = $v.disableAnimations;
      _highContrast = $v.highContrast;
      _invertColors = $v.invertColors;
      _reduceMotion = $v.reduceMotion;
      _onOffSwitchLabels = $v.onOffSwitchLabels;
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
        _$AccessibilityConfig._(
            textScale: BuiltValueNullFieldError.checkNotNull(
                textScale, 'AccessibilityConfig', 'textScale'),
            boldText: BuiltValueNullFieldError.checkNotNull(
                boldText, 'AccessibilityConfig', 'boldText'),
            accessibleNavigation: BuiltValueNullFieldError.checkNotNull(
                accessibleNavigation, 'AccessibilityConfig', 'accessibleNavigation'),
            disableAnimations: BuiltValueNullFieldError.checkNotNull(
                disableAnimations, 'AccessibilityConfig', 'disableAnimations'),
            highContrast: BuiltValueNullFieldError.checkNotNull(
                highContrast, 'AccessibilityConfig', 'highContrast'),
            invertColors: BuiltValueNullFieldError.checkNotNull(
                invertColors, 'AccessibilityConfig', 'invertColors'),
            reduceMotion: BuiltValueNullFieldError.checkNotNull(
                reduceMotion, 'AccessibilityConfig', 'reduceMotion'),
            onOffSwitchLabels: BuiltValueNullFieldError.checkNotNull(onOffSwitchLabels, 'AccessibilityConfig', 'onOffSwitchLabels'));
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new

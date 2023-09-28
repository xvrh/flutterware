// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ScreenConfiguration extends ScreenConfiguration {
  factory _$ScreenConfiguration(
          [void Function(ScreenConfigurationBuilder)? updates]) =>
      (new ScreenConfigurationBuilder()..update(updates))._build();

  _$ScreenConfiguration._() : super._();

  @override
  ScreenConfiguration rebuild(
          void Function(ScreenConfigurationBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScreenConfigurationBuilder toBuilder() =>
      new ScreenConfigurationBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScreenConfiguration;
  }

  @override
  int get hashCode {
    return 493652741;
  }

  @override
  String toString() {
    return newBuiltValueToStringHelper(r'ScreenConfiguration').toString();
  }
}

class ScreenConfigurationBuilder
    implements Builder<ScreenConfiguration, ScreenConfigurationBuilder> {
  _$ScreenConfiguration? _$v;

  ScreenConfigurationBuilder();

  @override
  void replace(ScreenConfiguration other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$ScreenConfiguration;
  }

  @override
  void update(void Function(ScreenConfigurationBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScreenConfiguration build() => _build();

  _$ScreenConfiguration _build() {
    final _$result = _$v ?? new _$ScreenConfiguration._();
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint

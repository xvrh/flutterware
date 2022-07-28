// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'locale.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<SerializableLocale> _$serializableLocaleSerializer =
    _$SerializableLocaleSerializer();

class _$SerializableLocaleSerializer
    implements StructuredSerializer<SerializableLocale> {
  @override
  final Iterable<Type> types = const [SerializableLocale, _$SerializableLocale];
  @override
  final String wireName = 'SerializableLocale';

  @override
  Iterable<Object?> serialize(
      Serializers serializers, SerializableLocale object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'language',
      serializers.serialize(object.language,
          specifiedType: const FullType(String)),
    ];
    Object? value;
    value = object.country;
    if (value != null) {
      result
        ..add('country')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  SerializableLocale deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = SerializableLocaleBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'language':
          result.language = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'country':
          result.country = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
      }
    }

    return result.build();
  }
}

class _$SerializableLocale extends SerializableLocale {
  @override
  final String language;
  @override
  final String? country;

  factory _$SerializableLocale(
          [void Function(SerializableLocaleBuilder)? updates]) =>
      (SerializableLocaleBuilder()..update(updates))._build();

  _$SerializableLocale._({required this.language, this.country}) : super._() {
    BuiltValueNullFieldError.checkNotNull(
        language, 'SerializableLocale', 'language');
  }

  @override
  SerializableLocale rebuild(
          void Function(SerializableLocaleBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SerializableLocaleBuilder toBuilder() =>
      SerializableLocaleBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SerializableLocale &&
        language == other.language &&
        country == other.country;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, language.hashCode), country.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('SerializableLocale')
          ..add('language', language)
          ..add('country', country))
        .toString();
  }
}

class SerializableLocaleBuilder
    implements Builder<SerializableLocale, SerializableLocaleBuilder> {
  _$SerializableLocale? _$v;

  String? _language;
  String? get language => _$this._language;
  set language(String? language) => _$this._language = language;

  String? _country;
  String? get country => _$this._country;
  set country(String? country) => _$this._country = country;

  SerializableLocaleBuilder();

  SerializableLocaleBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _language = $v.language;
      _country = $v.country;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SerializableLocale other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$SerializableLocale;
  }

  @override
  void update(void Function(SerializableLocaleBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SerializableLocale build() => _build();

  _$SerializableLocale _build() {
    final _$result = _$v ??
        _$SerializableLocale._(
            language: BuiltValueNullFieldError.checkNotNull(
                language, 'SerializableLocale', 'language'),
            country: country);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new

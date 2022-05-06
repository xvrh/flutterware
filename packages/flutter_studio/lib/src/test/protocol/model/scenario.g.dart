// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scenario.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<ScenarioReference> _$scenarioReferenceSerializer =
    _$ScenarioReferenceSerializer();

class _$ScenarioReferenceSerializer
    implements StructuredSerializer<ScenarioReference> {
  @override
  final Iterable<Type> types = const [ScenarioReference, _$ScenarioReference];
  @override
  final String wireName = 'ScenarioReference';

  @override
  Iterable<Object?> serialize(Serializers serializers, ScenarioReference object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'name',
      serializers.serialize(object.name,
          specifiedType: const FullType(BuiltList, [FullType(String)])),
    ];
    Object? value;
    value = object.description;
    if (value != null) {
      result
        ..add('description')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  ScenarioReference deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = ScenarioReferenceBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'name':
          result.name.replace(serializers.deserialize(value,
                  specifiedType: const FullType(BuiltList, [FullType(String)]))!
              as BuiltList<Object?>);
          break;
        case 'description':
          result.description = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
      }
    }

    return result.build();
  }
}

class _$ScenarioReference extends ScenarioReference {
  @override
  final BuiltList<String> name;
  @override
  final String? description;

  factory _$ScenarioReference(
          [void Function(ScenarioReferenceBuilder)? updates]) =>
      (ScenarioReferenceBuilder()..update(updates)).build();

  _$ScenarioReference._({required this.name, this.description}) : super._() {
    BuiltValueNullFieldError.checkNotNull(name, 'ScenarioReference', 'name');
  }

  @override
  ScenarioReference rebuild(void Function(ScenarioReferenceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScenarioReferenceBuilder toBuilder() =>
      ScenarioReferenceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScenarioReference &&
        name == other.name &&
        description == other.description;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, name.hashCode), description.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ScenarioReference')
          ..add('name', name)
          ..add('description', description))
        .toString();
  }
}

class ScenarioReferenceBuilder
    implements Builder<ScenarioReference, ScenarioReferenceBuilder> {
  _$ScenarioReference? _$v;

  ListBuilder<String>? _name;
  ListBuilder<String> get name => _$this._name ??= ListBuilder<String>();
  set name(ListBuilder<String>? name) => _$this._name = name;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  ScenarioReferenceBuilder();

  ScenarioReferenceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name.toBuilder();
      _description = $v.description;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScenarioReference other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$ScenarioReference;
  }

  @override
  void update(void Function(ScenarioReferenceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ScenarioReference build() {
    _$ScenarioReference _$result;
    try {
      _$result = _$v ??
          _$ScenarioReference._(name: name.build(), description: description);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'name';
        name.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            'ScenarioReference', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new

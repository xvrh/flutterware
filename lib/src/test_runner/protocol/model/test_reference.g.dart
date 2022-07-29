// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'test_reference.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<TestReference> _$testReferenceSerializer =
    new _$TestReferenceSerializer();

class _$TestReferenceSerializer implements StructuredSerializer<TestReference> {
  @override
  final Iterable<Type> types = const [TestReference, _$TestReference];
  @override
  final String wireName = 'TestReference';

  @override
  Iterable<Object?> serialize(Serializers serializers, TestReference object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'name',
      serializers.serialize(object.name,
          specifiedType:
              const FullType(BuiltList, const [const FullType(String)])),
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
  TestReference deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new TestReferenceBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'name':
          result.name.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, const [const FullType(String)]))!
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

class _$TestReference extends TestReference {
  @override
  final BuiltList<String> name;
  @override
  final String? description;

  factory _$TestReference([void Function(TestReferenceBuilder)? updates]) =>
      (new TestReferenceBuilder()..update(updates))._build();

  _$TestReference._({required this.name, this.description}) : super._() {
    BuiltValueNullFieldError.checkNotNull(name, 'TestReference', 'name');
  }

  @override
  TestReference rebuild(void Function(TestReferenceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TestReferenceBuilder toBuilder() => new TestReferenceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TestReference &&
        name == other.name &&
        description == other.description;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, name.hashCode), description.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('TestReference')
          ..add('name', name)
          ..add('description', description))
        .toString();
  }
}

class TestReferenceBuilder
    implements Builder<TestReference, TestReferenceBuilder> {
  _$TestReference? _$v;

  ListBuilder<String>? _name;
  ListBuilder<String> get name => _$this._name ??= new ListBuilder<String>();
  set name(ListBuilder<String>? name) => _$this._name = name;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  TestReferenceBuilder();

  TestReferenceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name.toBuilder();
      _description = $v.description;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TestReference other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$TestReference;
  }

  @override
  void update(void Function(TestReferenceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TestReference build() => _build();

  _$TestReference _build() {
    _$TestReference _$result;
    try {
      _$result = _$v ??
          new _$TestReference._(name: name.build(), description: description);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'name';
        name.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            'TestReference', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new

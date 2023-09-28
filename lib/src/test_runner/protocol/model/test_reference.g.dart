// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'test_reference.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<TestReference> _$testReferenceSerializer =
    _$TestReferenceSerializer();

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
  TestReference deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = TestReferenceBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
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

class _$TestReference extends TestReference {
  @override
  final BuiltList<String> name;
  @override
  final String? description;

  factory _$TestReference([void Function(TestReferenceBuilder)? updates]) =>
      (TestReferenceBuilder()..update(updates))._build();

  _$TestReference._({required this.name, this.description}) : super._() {
    BuiltValueNullFieldError.checkNotNull(name, r'TestReference', 'name');
  }

  @override
  TestReference rebuild(void Function(TestReferenceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TestReferenceBuilder toBuilder() => TestReferenceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TestReference &&
        name == other.name &&
        description == other.description;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TestReference')
          ..add('name', name)
          ..add('description', description))
        .toString();
  }
}

class TestReferenceBuilder
    implements Builder<TestReference, TestReferenceBuilder> {
  _$TestReference? _$v;

  ListBuilder<String>? _name;
  ListBuilder<String> get name => _$this._name ??= ListBuilder<String>();
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
          _$TestReference._(name: name.build(), description: description);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'name';
        name.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'TestReference', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint

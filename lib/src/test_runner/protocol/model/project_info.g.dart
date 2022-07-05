// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<ProjectInfo> _$projectInfoSerializer = new _$ProjectInfoSerializer();

class _$ProjectInfoSerializer implements StructuredSerializer<ProjectInfo> {
  @override
  final Iterable<Type> types = const [ProjectInfo, _$ProjectInfo];
  @override
  final String wireName = 'ProjectInfo';

  @override
  Iterable<Object?> serialize(Serializers serializers, ProjectInfo object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'name',
      serializers.serialize(object.name, specifiedType: const FullType(String)),
      'supportedLanguages',
      serializers.serialize(object.supportedLanguages,
          specifiedType:
              const FullType(BuiltList, const [const FullType(String)])),
    ];
    Object? value;
    value = object.rootPath;
    if (value != null) {
      result
        ..add('rootPath')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.defaultStatusBarBrightness;
    if (value != null) {
      result
        ..add('defaultStatusBarBrightness')
        ..add(serializers.serialize(value, specifiedType: const FullType(int)));
    }
    return result;
  }

  @override
  ProjectInfo deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ProjectInfoBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'name':
          result.name = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'rootPath':
          result.rootPath = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'supportedLanguages':
          result.supportedLanguages.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, const [const FullType(String)]))!
              as BuiltList<Object?>);
          break;
        case 'defaultStatusBarBrightness':
          result.defaultStatusBarBrightness = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int?;
          break;
      }
    }

    return result.build();
  }
}

class _$ProjectInfo extends ProjectInfo {
  @override
  final String name;
  @override
  final String? rootPath;
  @override
  final BuiltList<String> supportedLanguages;
  @override
  final int? defaultStatusBarBrightness;

  factory _$ProjectInfo([void Function(ProjectInfoBuilder)? updates]) =>
      (new ProjectInfoBuilder()..update(updates))._build();

  _$ProjectInfo._(
      {required this.name,
      this.rootPath,
      required this.supportedLanguages,
      this.defaultStatusBarBrightness})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(name, 'ProjectInfo', 'name');
    BuiltValueNullFieldError.checkNotNull(
        supportedLanguages, 'ProjectInfo', 'supportedLanguages');
  }

  @override
  ProjectInfo rebuild(void Function(ProjectInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ProjectInfoBuilder toBuilder() => new ProjectInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ProjectInfo &&
        name == other.name &&
        rootPath == other.rootPath &&
        supportedLanguages == other.supportedLanguages &&
        defaultStatusBarBrightness == other.defaultStatusBarBrightness;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc($jc($jc(0, name.hashCode), rootPath.hashCode),
            supportedLanguages.hashCode),
        defaultStatusBarBrightness.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ProjectInfo')
          ..add('name', name)
          ..add('rootPath', rootPath)
          ..add('supportedLanguages', supportedLanguages)
          ..add('defaultStatusBarBrightness', defaultStatusBarBrightness))
        .toString();
  }
}

class ProjectInfoBuilder implements Builder<ProjectInfo, ProjectInfoBuilder> {
  _$ProjectInfo? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _rootPath;
  String? get rootPath => _$this._rootPath;
  set rootPath(String? rootPath) => _$this._rootPath = rootPath;

  ListBuilder<String>? _supportedLanguages;
  ListBuilder<String> get supportedLanguages =>
      _$this._supportedLanguages ??= new ListBuilder<String>();
  set supportedLanguages(ListBuilder<String>? supportedLanguages) =>
      _$this._supportedLanguages = supportedLanguages;

  int? _defaultStatusBarBrightness;
  int? get defaultStatusBarBrightness => _$this._defaultStatusBarBrightness;
  set defaultStatusBarBrightness(int? defaultStatusBarBrightness) =>
      _$this._defaultStatusBarBrightness = defaultStatusBarBrightness;

  ProjectInfoBuilder();

  ProjectInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _rootPath = $v.rootPath;
      _supportedLanguages = $v.supportedLanguages.toBuilder();
      _defaultStatusBarBrightness = $v.defaultStatusBarBrightness;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ProjectInfo other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$ProjectInfo;
  }

  @override
  void update(void Function(ProjectInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ProjectInfo build() => _build();

  _$ProjectInfo _build() {
    _$ProjectInfo _$result;
    try {
      _$result = _$v ??
          new _$ProjectInfo._(
              name: BuiltValueNullFieldError.checkNotNull(
                  name, 'ProjectInfo', 'name'),
              rootPath: rootPath,
              supportedLanguages: supportedLanguages.build(),
              defaultStatusBarBrightness: defaultStatusBarBrightness);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'supportedLanguages';
        supportedLanguages.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            'ProjectInfo', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new

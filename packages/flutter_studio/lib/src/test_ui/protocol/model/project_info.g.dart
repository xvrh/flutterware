// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<ProjectInfo> _$projectInfoSerializer = new _$ProjectInfoSerializer();
Serializer<ConfluenceInfo> _$confluenceInfoSerializer =
    new _$ConfluenceInfoSerializer();
Serializer<FirebaseInfo> _$firebaseInfoSerializer =
    new _$FirebaseInfoSerializer();

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
    value = object.poEditorProjectId;
    if (value != null) {
      result
        ..add('poEditorProjectId')
        ..add(serializers.serialize(value, specifiedType: const FullType(int)));
    }
    value = object.confluence;
    if (value != null) {
      result
        ..add('confluence')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(ConfluenceInfo)));
    }
    value = object.firebase;
    if (value != null) {
      result
        ..add('firebase')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(FirebaseInfo)));
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
        case 'poEditorProjectId':
          result.poEditorProjectId = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int?;
          break;
        case 'confluence':
          result.confluence.replace(serializers.deserialize(value,
                  specifiedType: const FullType(ConfluenceInfo))!
              as ConfluenceInfo);
          break;
        case 'firebase':
          result.firebase.replace(serializers.deserialize(value,
              specifiedType: const FullType(FirebaseInfo))! as FirebaseInfo);
          break;
      }
    }

    return result.build();
  }
}

class _$ConfluenceInfoSerializer
    implements StructuredSerializer<ConfluenceInfo> {
  @override
  final Iterable<Type> types = const [ConfluenceInfo, _$ConfluenceInfo];
  @override
  final String wireName = 'ConfluenceInfo';

  @override
  Iterable<Object?> serialize(Serializers serializers, ConfluenceInfo object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'site',
      serializers.serialize(object.site, specifiedType: const FullType(String)),
      'space',
      serializers.serialize(object.space,
          specifiedType: const FullType(String)),
      'docPrefix',
      serializers.serialize(object.docPrefix,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  ConfluenceInfo deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ConfluenceInfoBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'site':
          result.site = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'space':
          result.space = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'docPrefix':
          result.docPrefix = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
      }
    }

    return result.build();
  }
}

class _$FirebaseInfoSerializer implements StructuredSerializer<FirebaseInfo> {
  @override
  final Iterable<Type> types = const [FirebaseInfo, _$FirebaseInfo];
  @override
  final String wireName = 'FirebaseInfo';

  @override
  Iterable<Object?> serialize(Serializers serializers, FirebaseInfo object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'projectId',
      serializers.serialize(object.projectId,
          specifiedType: const FullType(String)),
      'androidAppId',
      serializers.serialize(object.androidAppId,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  FirebaseInfo deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new FirebaseInfoBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'projectId':
          result.projectId = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'androidAppId':
          result.androidAppId = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
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
  @override
  final int? poEditorProjectId;
  @override
  final ConfluenceInfo? confluence;
  @override
  final FirebaseInfo? firebase;

  factory _$ProjectInfo([void Function(ProjectInfoBuilder)? updates]) =>
      (new ProjectInfoBuilder()..update(updates))._build();

  _$ProjectInfo._(
      {required this.name,
      this.rootPath,
      required this.supportedLanguages,
      this.defaultStatusBarBrightness,
      this.poEditorProjectId,
      this.confluence,
      this.firebase})
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
        defaultStatusBarBrightness == other.defaultStatusBarBrightness &&
        poEditorProjectId == other.poEditorProjectId &&
        confluence == other.confluence &&
        firebase == other.firebase;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc($jc($jc(0, name.hashCode), rootPath.hashCode),
                        supportedLanguages.hashCode),
                    defaultStatusBarBrightness.hashCode),
                poEditorProjectId.hashCode),
            confluence.hashCode),
        firebase.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ProjectInfo')
          ..add('name', name)
          ..add('rootPath', rootPath)
          ..add('supportedLanguages', supportedLanguages)
          ..add('defaultStatusBarBrightness', defaultStatusBarBrightness)
          ..add('poEditorProjectId', poEditorProjectId)
          ..add('confluence', confluence)
          ..add('firebase', firebase))
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

  int? _poEditorProjectId;
  int? get poEditorProjectId => _$this._poEditorProjectId;
  set poEditorProjectId(int? poEditorProjectId) =>
      _$this._poEditorProjectId = poEditorProjectId;

  ConfluenceInfoBuilder? _confluence;
  ConfluenceInfoBuilder get confluence =>
      _$this._confluence ??= new ConfluenceInfoBuilder();
  set confluence(ConfluenceInfoBuilder? confluence) =>
      _$this._confluence = confluence;

  FirebaseInfoBuilder? _firebase;
  FirebaseInfoBuilder get firebase =>
      _$this._firebase ??= new FirebaseInfoBuilder();
  set firebase(FirebaseInfoBuilder? firebase) => _$this._firebase = firebase;

  ProjectInfoBuilder();

  ProjectInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _rootPath = $v.rootPath;
      _supportedLanguages = $v.supportedLanguages.toBuilder();
      _defaultStatusBarBrightness = $v.defaultStatusBarBrightness;
      _poEditorProjectId = $v.poEditorProjectId;
      _confluence = $v.confluence?.toBuilder();
      _firebase = $v.firebase?.toBuilder();
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
              defaultStatusBarBrightness: defaultStatusBarBrightness,
              poEditorProjectId: poEditorProjectId,
              confluence: _confluence?.build(),
              firebase: _firebase?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'supportedLanguages';
        supportedLanguages.build();

        _$failedField = 'confluence';
        _confluence?.build();
        _$failedField = 'firebase';
        _firebase?.build();
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

class _$ConfluenceInfo extends ConfluenceInfo {
  @override
  final String site;
  @override
  final String space;
  @override
  final String docPrefix;

  factory _$ConfluenceInfo([void Function(ConfluenceInfoBuilder)? updates]) =>
      (new ConfluenceInfoBuilder()..update(updates))._build();

  _$ConfluenceInfo._(
      {required this.site, required this.space, required this.docPrefix})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(site, 'ConfluenceInfo', 'site');
    BuiltValueNullFieldError.checkNotNull(space, 'ConfluenceInfo', 'space');
    BuiltValueNullFieldError.checkNotNull(
        docPrefix, 'ConfluenceInfo', 'docPrefix');
  }

  @override
  ConfluenceInfo rebuild(void Function(ConfluenceInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ConfluenceInfoBuilder toBuilder() =>
      new ConfluenceInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ConfluenceInfo &&
        site == other.site &&
        space == other.space &&
        docPrefix == other.docPrefix;
  }

  @override
  int get hashCode {
    return $jf(
        $jc($jc($jc(0, site.hashCode), space.hashCode), docPrefix.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ConfluenceInfo')
          ..add('site', site)
          ..add('space', space)
          ..add('docPrefix', docPrefix))
        .toString();
  }
}

class ConfluenceInfoBuilder
    implements Builder<ConfluenceInfo, ConfluenceInfoBuilder> {
  _$ConfluenceInfo? _$v;

  String? _site;
  String? get site => _$this._site;
  set site(String? site) => _$this._site = site;

  String? _space;
  String? get space => _$this._space;
  set space(String? space) => _$this._space = space;

  String? _docPrefix;
  String? get docPrefix => _$this._docPrefix;
  set docPrefix(String? docPrefix) => _$this._docPrefix = docPrefix;

  ConfluenceInfoBuilder();

  ConfluenceInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _site = $v.site;
      _space = $v.space;
      _docPrefix = $v.docPrefix;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ConfluenceInfo other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$ConfluenceInfo;
  }

  @override
  void update(void Function(ConfluenceInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ConfluenceInfo build() => _build();

  _$ConfluenceInfo _build() {
    final _$result = _$v ??
        new _$ConfluenceInfo._(
            site: BuiltValueNullFieldError.checkNotNull(
                site, 'ConfluenceInfo', 'site'),
            space: BuiltValueNullFieldError.checkNotNull(
                space, 'ConfluenceInfo', 'space'),
            docPrefix: BuiltValueNullFieldError.checkNotNull(
                docPrefix, 'ConfluenceInfo', 'docPrefix'));
    replace(_$result);
    return _$result;
  }
}

class _$FirebaseInfo extends FirebaseInfo {
  @override
  final String projectId;
  @override
  final String androidAppId;

  factory _$FirebaseInfo([void Function(FirebaseInfoBuilder)? updates]) =>
      (new FirebaseInfoBuilder()..update(updates))._build();

  _$FirebaseInfo._({required this.projectId, required this.androidAppId})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(
        projectId, 'FirebaseInfo', 'projectId');
    BuiltValueNullFieldError.checkNotNull(
        androidAppId, 'FirebaseInfo', 'androidAppId');
  }

  @override
  FirebaseInfo rebuild(void Function(FirebaseInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FirebaseInfoBuilder toBuilder() => new FirebaseInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FirebaseInfo &&
        projectId == other.projectId &&
        androidAppId == other.androidAppId;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, projectId.hashCode), androidAppId.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('FirebaseInfo')
          ..add('projectId', projectId)
          ..add('androidAppId', androidAppId))
        .toString();
  }
}

class FirebaseInfoBuilder
    implements Builder<FirebaseInfo, FirebaseInfoBuilder> {
  _$FirebaseInfo? _$v;

  String? _projectId;
  String? get projectId => _$this._projectId;
  set projectId(String? projectId) => _$this._projectId = projectId;

  String? _androidAppId;
  String? get androidAppId => _$this._androidAppId;
  set androidAppId(String? androidAppId) => _$this._androidAppId = androidAppId;

  FirebaseInfoBuilder();

  FirebaseInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _projectId = $v.projectId;
      _androidAppId = $v.androidAppId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FirebaseInfo other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$FirebaseInfo;
  }

  @override
  void update(void Function(FirebaseInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FirebaseInfo build() => _build();

  _$FirebaseInfo _build() {
    final _$result = _$v ??
        new _$FirebaseInfo._(
            projectId: BuiltValueNullFieldError.checkNotNull(
                projectId, 'FirebaseInfo', 'projectId'),
            androidAppId: BuiltValueNullFieldError.checkNotNull(
                androidAppId, 'FirebaseInfo', 'androidAppId'));
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new

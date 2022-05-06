import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'project_info.g.dart';

abstract class ProjectInfo implements Built<ProjectInfo, ProjectInfoBuilder> {
  static Serializer<ProjectInfo> get serializer => _$projectInfoSerializer;

  ProjectInfo._();
  factory ProjectInfo._fromBuilder(
      [void Function(ProjectInfoBuilder) updates]) = _$ProjectInfo;

  factory ProjectInfo(
    String name, {
    required List<String> supportedLanguages,
    String? rootPath,
    int? defaultStatusBarBrightness,
    int? poEditorProjectId,
    ConfluenceInfo? confluence,
    FirebaseInfo? firebase,
  }) =>
      ProjectInfo._fromBuilder((b) => b
        ..name = name
        ..rootPath = rootPath
        ..supportedLanguages.replace(supportedLanguages)
        ..defaultStatusBarBrightness = defaultStatusBarBrightness
        ..poEditorProjectId = poEditorProjectId
        ..confluence = confluence?.toBuilder()
        ..firebase = firebase?.toBuilder());

  String get name;
  String? get rootPath;
  BuiltList<String> get supportedLanguages;
  int? get defaultStatusBarBrightness;
  int? get poEditorProjectId;
  ConfluenceInfo? get confluence;
  FirebaseInfo? get firebase;
}

abstract class ConfluenceInfo
    implements Built<ConfluenceInfo, ConfluenceInfoBuilder> {
  static Serializer<ConfluenceInfo> get serializer =>
      _$confluenceInfoSerializer;

  ConfluenceInfo._();
  factory ConfluenceInfo._fromBuilder(
      [void Function(ConfluenceInfoBuilder) updates]) = _$ConfluenceInfo;

  factory ConfluenceInfo({
    required String site,
    required String space,
    required String docPrefix,
  }) =>
      ConfluenceInfo._fromBuilder((b) => b
        ..site = site
        ..space = space
        ..docPrefix = docPrefix);

  String get site;
  String get space;
  String get docPrefix;
}

abstract class FirebaseInfo
    implements Built<FirebaseInfo, FirebaseInfoBuilder> {
  static Serializer<FirebaseInfo> get serializer => _$firebaseInfoSerializer;

  FirebaseInfo._();
  factory FirebaseInfo._fromBuilder(
      [void Function(FirebaseInfoBuilder) updates]) = _$FirebaseInfo;

  factory FirebaseInfo({
    required String projectId,
    required String androidAppId,
  }) =>
      FirebaseInfo._fromBuilder((b) => b
        ..projectId = projectId
        ..androidAppId = androidAppId);

  String get projectId;
  String get androidAppId;
}

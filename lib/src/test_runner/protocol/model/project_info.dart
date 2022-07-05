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
  }) =>
      ProjectInfo._fromBuilder((b) => b
        ..name = name
        ..rootPath = rootPath
        ..supportedLanguages.replace(supportedLanguages)
        ..defaultStatusBarBrightness = defaultStatusBarBrightness);

  String get name;
  String? get rootPath;
  BuiltList<String> get supportedLanguages;
  int? get defaultStatusBarBrightness;
}

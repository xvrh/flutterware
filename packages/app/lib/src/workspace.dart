import 'package:json_annotation/json_annotation.dart';

import 'sdk.dart';

part 'workspace.g.dart';

@JsonSerializable()
class Workspace {
  final List<Project> projects;

  Workspace({List<Project>? projects}) : projects = projects ?? [];

  factory Workspace.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceFromJson(json);

  Map<String, dynamic> toJson() => _$WorkspaceToJson(this);
}

@JsonSerializable()
class Project {
  final String directory;
  final FlutterSdk flutterSdk;

  Project(this.directory, this.flutterSdk);

  factory Project.fromJson(Map<String, dynamic> json) =>
      _$ProjectFromJson(json);

  Map<String, dynamic> toJson() => _$ProjectToJson(this);
}

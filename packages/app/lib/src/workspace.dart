import 'dart:io';

import 'package:json_annotation/json_annotation.dart';

import 'sdk.dart';

part 'workspace.g.dart';

class Workspace {
  final File file;
  final projects = <Project>[];

  Workspace(this.file);

  // 1. Save the workspace in a workspace.json file
  // 2. When add project, dispatch Stream event and save the file

  // Generale organisation:
  /*
Create tab bar
Allow to add a project:
  Screen with: pick a folder + pick a Flutter SDK (or paste path)
   List known Flutter SDK (find in "which|where.exe flutter", previous project & FLUTTER_HOME)
For each project, localise the "pubspec.yaml" and parse it.
  Then setup a FileWatcher on it to catch change to the name
  On add a project, if the pubspec.yaml is not found, refuse to create the project
  On reload workspace, reload all pubspec.yaml and re-setup the FileWatcher. If the
  file doesn't exist, remove the project?



   */
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

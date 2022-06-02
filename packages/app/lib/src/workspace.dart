import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';
import 'flutter_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';
import 'utils/data_loader.dart';

part 'workspace.g.dart';

final _logger = Logger('workspace');

class Workspace {
  final File file;
  final _projects = ValueNotifier<List<Project>>([]);
  final _selectedProject = ValueNotifier<Project?>(null);

  Workspace._(this.file);

  static Future<Workspace> load(File file) async {
    var workspace = Workspace._(file);
    if (file.existsSync()) {
      try {
        var content = await file.readAsString();
        var decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          var projects = decoded['projects'] as List;
          for (var project in projects) {
            try {
              workspace.projects.value
                  .add(Project.fromJson(project as Map<String, dynamic>));
            } catch (e, s) {
              _logger.warning('Failed to load project.\n$project', e, s);
            }
          }
          var selected = decoded['selected'] as String;
          var selectedProject = workspace.projects.value
              .firstWhereOrNull((p) => p.directory == selected);
          workspace._selectedProject.value = selectedProject;
        }
      } catch (e, s) {
        _logger.warning('Failed to load Workspace ${file.path}', e, s);
      }
    }
    return workspace;
  }

  Map<String, dynamic> toJson() => {
        'projects': _projects.value,
        'selected': _selectedProject.value?.directory,
      };

  ValueListenable<List<Project>> get projects => _projects;

  ValueListenable<Project?> get selectedProject => _selectedProject;

  Future<Set<FlutterSdkPath>> possibleFlutterSdks() async {
    return {
      ...await FlutterSdkPath.findSdks(),
      ...projects.value.map((p) => p.flutterSdkPath)
    };
  }

  void addProject(Project project) {
    _projects.value = [..._projects.value, project];
    _selectedProject.value = project;
    _save();
  }

  void selectProject(Project project) {
    _selectedProject.value = project;
    _save();
  }

  void closeProject(Project project) {
    project.dispose();
    _projects.value = [..._projects.value.where((p) => p != project)];
    if (_selectedProject.value == project) {
      _selectedProject.value = null;
    }
    _save();
  }

  void unselectProject() {
    _selectedProject.value = null;
    _save();
  }

  void _save() {
    var encodeWorkspace = JsonEncoder.withIndent('  ').convert(this);
    file.writeAsString(encodeWorkspace);
  }

  void dispose() {
    for (var project in _projects.value) {
      project.dispose();
    }
  }
}

@JsonSerializable()
class Project {
  final String directory;
  final FlutterSdkPath flutterSdkPath;
  final FlutterSdk _flutterSdk;
  late DataLoader<Pubspec> _pubspec;
  late StreamSubscription _pubspecWatcher;

  Project(this.directory, this.flutterSdkPath)
      : _flutterSdk = FlutterSdk(flutterSdkPath) {
    var pubspec = p.join(directory, 'pubspec.yaml');
    _pubspec = DataLoader(
      debugName: 'Pubspec',
      lazy: true,
      loader: () async {
        var content = await File(pubspec).readAsString();
        return Pubspec(loadYaml(content) as YamlMap);
      },
    );
    _pubspecWatcher = FileWatcher(pubspec).events.listen((change) {
      _pubspec.refresh(mode: LoadingMode.none);
    });
  }

  factory Project.fromJson(Map<String, dynamic> json) =>
      _$ProjectFromJson(json);

  static Future<bool> isValid(String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      var pubspec = File(p.join(path, 'pubspec.yaml'));
      return pubspec.exists();
    }
    return false;
  }

  ValueListenable<Snapshot<Pubspec>> get pubspec => _pubspec;

  Map<String, dynamic> toJson() => _$ProjectToJson(this);

  void dispose() {
    _pubspecWatcher.cancel();
    _flutterSdk.dispose();
    _pubspec.dispose();
  }
}

class Pubspec {
  final YamlMap _data;

  Pubspec(this._data);

  String get name => _data['name'] as String;
}

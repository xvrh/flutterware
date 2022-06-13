import 'dart:io';

import 'package:flutter_studio_app/src/dependencies/pubspec_lock.dart';
import 'package:flutter_studio_app/src/utils/data_loader.dart';
import 'package:yaml/yaml.dart';

import '../project.dart';
import '../utils/cloc/cloc.dart';
import 'package:path/path.dart' as p;

class ProjectInfoService {
  final Project project;
  late final DataLoader<ProjectSummary> _loader;

  ProjectInfoService(this.project) {
    _loader = DataLoader(loader: _load, debugName: 'Project info');
  }

  Future<ProjectSummary> _load() async {
    var pubspec = project.pubspec.value.requireData;
    var pubspecLock = await PubspecLock.load(project.directory);

    return ProjectSummary(
        pubspec.name,
        icon,
        DependenciesSummary(
            total: pubspecLock.packages.length,
            direct: pubspecLock.packages
                .where((e) => e.type != DependencyType.transitive)
                .length),
        codeMetrics);
  }
}

class ProjectSummary {
  final String packageName;
  final File? icon;
  final DependenciesSummary dependencies;
  final CodeMetrics codeMetrics;

  ProjectSummary(
      this.packageName, this.icon, this.dependencies, this.codeMetrics);
}

class DependenciesSummary {
  final int total;
  final int direct;

  DependenciesSummary({required this.total, required this.direct});
}

class CodeMetrics {
  final ClocResult lib, tests;

  CodeMetrics({required this.lib, required this.tests});

  ClocResult get sum => lib + tests;
}

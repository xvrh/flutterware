import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_studio_app/src/dependencies/pubspec_lock.dart';
import 'package:flutter_studio_app/src/utils/async_value.dart';
import 'package:watcher/watcher.dart';
import 'package:yaml/yaml.dart';

import '../icon/icons.dart';
import '../project.dart';
import '../utils/cloc/cloc.dart';
import 'package:path/path.dart' as p;

class ProjectInfoService {
  final Project project;
  late final dependencies =
      AsyncValue<DependenciesSummary>(loader: _loadDependencies);
  late final AsyncValue<Pubspec> _pubspec;
  late StreamSubscription _pubspecWatcher;

  ProjectInfoService(this.project) {
    var pubspec = p.join(project.directory.path, 'pubspec.yaml');
    _pubspec = AsyncValue(
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

  Future<DependenciesSummary> _loadDependencies() async {
    var pubspecLock = await PubspecLock.load(project.absolutePath);

    var direct = pubspecLock.packages
        .where((e) => e.type != DependencyType.transitive)
        .length;
    return DependenciesSummary(
        transitive: pubspecLock.packages.length - direct, direct: direct);
  }

  ValueListenable<Snapshot<Pubspec>> get pubspec => _pubspec;

  void dispose() {
    _pubspecWatcher.cancel();
    _pubspec.dispose();
    dependencies.dispose();
  }
}

class DependenciesSummary {
  final int direct;
  final int transitive;

  DependenciesSummary({required this.transitive, required this.direct});

  int get total => direct + transitive;
}

class CodeMetrics {
  final ClocResult lib, tests;

  CodeMetrics({required this.lib, required this.tests});

  ClocResult get sum => lib + tests;
}

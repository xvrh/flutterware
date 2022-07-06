import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_config/package_config.dart';
import '../../project.dart';
import '../../utils/async_value.dart';
import '../../utils/cloc/cloc.dart';
import '../model/pubspec_lock.dart';
import 'package:pub_scores/pub_scores.dart';
import 'package:path/path.dart' as p;

class DependenciesService {
  final Project project;
  late final dependencies = AsyncValue<Dependencies>(loader: _load);
  late final pubScores = AsyncValue<PubScores>(loader: _loadPubScores);

  DependenciesService(this.project);

  Future<Dependencies> _load() async {
    var pubspecLock = await PubspecLock.load(project.absolutePath);
    var packageConfig = (await findPackageConfig(project.directory))!;

    var results = <Dependency>[];
    for (var dependency in pubspecLock.packages) {
      var package = packageConfig[dependency.name];
      if (package != null && dependency.source != 'sdk') {
        results.add(Dependency(this, package, dependency));
      }
    }
    return Dependencies(results);
  }

  Future<PubScores> _loadPubScores() async {
    //TODO(xha): we should download a fresh copy of this file as it can change
    // very frequently.
    var appDirectory = Directory.current;
    var appPackageConfig = await findPackageConfig(appDirectory);
    if (appPackageConfig == null) {
      throw Exception(
          'Cannot resolve [package_config] of ${appDirectory.path}');
    }
    var pubScorePackage = appPackageConfig['pub_scores'];
    if (pubScorePackage == null) {
      throw Exception('Cannot find package [pub_scores]');
    }

    var dataPath =
        p.join(pubScorePackage.root.toFilePath(), 'lib/data/all_packages.json');

    return await compute<String, PubScores>((path) async {
      //TODO(xha): consider a lighter parsing as the file is big
      var content = File(path).readAsStringSync();
      var json = jsonDecode(content) as Map<String, dynamic>;
      return PubScores.fromJson(json);
    }, dataPath);
  }

  void dispose() {
    dependencies.dispose();
    pubScores.dispose();
  }
}

class Dependencies implements Disposable {
  final Map<String, Dependency> dependencies;

  Dependencies(List<Dependency> dependencies)
      : dependencies = {
          for (var d in dependencies) d.name: d,
        };

  Dependency? operator [](String packageName) => dependencies[packageName];

  List<Dependency>? _directs;
  List<Dependency> get directs => _directs ??= dependencies.values
      .where((e) =>
          e.lockDependency.type != DependencyType.transitive &&
          e.lockDependency.source == 'hosted')
      .toList();

  List<Dependency>? _transitives;
  List<Dependency> get transitives => _transitives ??= dependencies.values
      .where((e) =>
          e.lockDependency.type == DependencyType.transitive &&
          e.lockDependency.source == 'hosted')
      .toList();

  @override
  void dispose() {
    for (var dependency in dependencies.values) {
      dependency.dispose();
    }
  }
}

class Dependency implements Disposable {
  final DependenciesService _service;
  final Package package;
  final LockDependency lockDependency;
  late final cloc = AsyncValue<ClocReport>(loader: _loadCloc);

  Dependency(this._service, this.package, this.lockDependency);

  String get name => lockDependency.name;

  bool get isTransitive => lockDependency.type == DependencyType.transitive;

  bool get isDirect => !isTransitive;

  Future<ClocReport> _loadCloc() async {
    throw UnimplementedError();
  }

  @override
  String toString() => 'Dependency($name)';

  @override
  void dispose() {
    cloc.dispose();
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:pub_scores/pub_scores.dart';
import '../../project.dart';
import '../../utils/async_value.dart';
import '../../utils/cloc/cloc.dart';
import '../../utils/list_files.dart';
import '../model/pubspec_lock.dart';
import 'dependency_graph.dart';
import 'package_imports.dart';

class DependenciesService {
  final Project project;
  late final dependencies = AsyncValue<Dependencies>(loader: _load);
  late final pubScores = AsyncValue<PubScores>(loader: _loadPubScores);
  late final packageImports = AsyncValue<PackageImports>(
    loader: _loadPackageImports,
  );

  DependenciesService(this.project);

  Future<Dependencies> _load() async {
    //TODO(xha): upgrade for workspace support
    var rootPubspec = await _readPubspec(project.absolutePath);
    var pubspecLock = await PubspecLock.load(project.absolutePath);
    var packageConfig = (await findPackageConfig(project.directory))!;

    var results = Dependencies(rootPubspec, <Dependency>[]);
    for (var package in packageConfig.packages) {
      var pubspecLockDep = pubspecLock?.packages.firstWhereOrNull(
        (e) => e.name == package.name,
      );

      var pubspec = await _readPubspec(package.root.toFilePath());

      results._allPackages[package.name] = Dependency(
        results,
        package,
        pubspec,
        pubspecLockDep,
      );
    }
    results.computeDependants();
    return results;
  }

  static Future<Pubspec> _readPubspec(String path) async {
    var pubspecFile = File(p.join(path, 'pubspec.yaml'));
    return Pubspec.parse(await pubspecFile.readAsString());
  }

  Future<PubScores> _loadPubScores() async {
    //TODO(xha): we should download a fresh copy of this file as it can change
    // very frequently.
    var appDirectory = Directory.current;
    var appPackageConfig = await findPackageConfig(appDirectory);
    if (appPackageConfig == null) {
      throw Exception(
        'Cannot resolve [package_config] of ${appDirectory.path}',
      );
    }
    var pubScorePackage = appPackageConfig['pub_scores'];
    if (pubScorePackage == null) {
      throw Exception('Cannot find package [pub_scores]');
    }

    var dataPath = p.join(
      pubScorePackage.root.toFilePath(),
      'lib/data/all_packages.json',
    );

    return await compute<String, PubScores>((path) async {
      //TODO(xha): consider a lighter parsing as the file is big
      var content = File(path).readAsStringSync();
      var json = jsonDecode(content) as Map<String, dynamic>;
      return PubScores.fromJson(json);
    }, dataPath);
  }

  Future<PackageImports> _loadPackageImports() async {
    return await compute<String, PackageImports>((path) async {
      return PackageImports.gather(
        listFilesInDirectory(
          path,
        ).whereType<File>().where((f) => f.path.endsWith('.dart')),
      );
    }, project.absolutePath);
  }

  void dispose() {
    dependencies.dispose();
    pubScores.dispose();
  }
}

class Dependencies implements Disposable {
  final Pubspec rootPubspec;
  final Map<String, Dependency> _allPackages;

  Dependencies(this.rootPubspec, List<Dependency> dependencies)
    : _allPackages = {for (var d in dependencies) d.name: d};

  Dependency? operator [](String packageName) => _allPackages[packageName];

  /// Names this package depends on directly, from its own pubspec.
  ///
  /// Direct-ness is read here rather than from a lockfile because in a pub
  /// workspace the lockfile lives at the workspace root and describes the whole
  /// resolution — a member has no per-package lock, so every package used to
  /// classify as direct ("170 direct, 0 transitive" for a member with 14).
  late final Set<String> declaredDirect = {
    ...rootPubspec.dependencies.keys,
    ...rootPubspec.devDependencies.keys,
  };

  /// Everything reachable from [declaredDirect]. In a workspace the package
  /// config lists every member's dependencies, so without this a package would
  /// list its siblings' dependencies as its own.
  late final Set<String> reachable = _computeReachable();

  Set<String> _computeReachable() {
    var seen = <String>{};
    var queue = [...declaredDirect];
    while (queue.isNotEmpty) {
      var name = queue.removeLast();
      if (!seen.add(name)) continue;
      var dependency = _allPackages[name];
      if (dependency == null) continue;
      // Only regular dependencies propagate; a transitive package's
      // dev_dependencies are not resolved for its consumers.
      queue.addAll(dependency.pubspec.dependencies.keys);
    }
    return seen;
  }

  Iterable<Dependency> get dependencies => _allPackages.values.where((e) {
    return e.name != rootPubspec.name && reachable.contains(e.name);
  });

  List<Dependency>? _directs;
  List<Dependency> get directs =>
      _directs ??= dependencies.where((e) => !e.isTransitive).toList();

  List<Dependency>? _transitives;
  List<Dependency> get transitives =>
      _transitives ??= dependencies.where((e) => e.isTransitive).toList();

  void computeDependants() {
    for (var dependency in _allPackages.values) {
      for (var sub in dependency.pubspec.dependencies.keys) {
        _allPackages[sub]?.dependants.add(dependency.name);
      }
    }
    for (var directDep in [
      ...rootPubspec.dependencies.keys,
      ...rootPubspec.devDependencies.keys,
    ]) {
      _allPackages[directDep]?.dependants.add(rootPubspec.name);
    }
  }

  @override
  void dispose() {
    for (var dependency in _allPackages.values) {
      dependency.dispose();
    }
  }
}

class Dependency implements Disposable {
  final Dependencies parent;
  final Package package;
  final LockDependency? lockDependency;
  final Pubspec pubspec;
  final dependants = <String>{};
  late final cloc = AsyncValue<ClocReport>(loader: _loadCloc);
  late final size = AsyncValue<SizeReport>(loader: _loadSize);

  Dependency(this.parent, this.package, this.pubspec, this.lockDependency);

  String get name => package.name;

  /// Declared in this package's own pubspec — see [Dependencies.declaredDirect]
  /// for why the lockfile is not consulted.
  bool get isDirect => parent.declaredDirect.contains(name);

  bool get isTransitive => !isDirect;

  Future<ClocReport> _loadCloc() async {
    return compute<String, ClocReport>((path) async {
      return countLinesOfCode(listFilesInDirectory(path));
    }, package.root.toFilePath());
  }

  Future<SizeReport> _loadSize() async {
    return compute<String, SizeReport>((path) async {
      var files = listFilesInDirectory(path);
      var count = 0;
      var size = 0;
      for (var file in files) {
        ++count;
        size += file.lengthSync();
      }
      return SizeReport(fileCount: count, totalBytes: size);
    }, package.root.toFilePath());
  }

  List<List<String>>? _dependencyPaths;

  List<List<String>> get dependencyPaths {
    _dependencyPaths = dependenciesGraph(
      name,
      (e) => parent._allPackages[e]?.dependants ?? const {},
    );
    return _dependencyPaths!;
  }

  @override
  String toString() => 'Dependency($name)';

  @override
  void dispose() {
    cloc.dispose();
  }
}

class SizeReport {
  final int fileCount;
  final int totalBytes;

  SizeReport({required this.fileCount, required this.totalBytes});
}

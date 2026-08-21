import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// `pubspec.lock`, read for what only it knows: the resolved version of each
/// package and the `description:` block that says where the package came from.
///
/// The lock is not asked what is direct. It carries a `dependency:` field —
/// `direct main`, `direct dev`, `transitive` — and reading it is what made a
/// workspace member report every one of 170 resolved packages as direct: in a
/// workspace there is one lockfile for the whole resolution, so that field
/// answers a question about the workspace and not about the package you are
/// looking at. It is deliberately not parsed here, so it cannot be used.
/// Per-member classification comes from `pub deps --json`; see
/// `DependencyResolution`.
class PubspecLock {
  PubspecLock(List<LockDependency> packages)
    : packages = {for (var package in packages) package.name: package};

  final Map<String, LockDependency> packages;

  LockDependency? operator [](String name) => packages[name];

  factory PubspecLock.fromYaml(YamlMap map) {
    var entries = map['packages'] as YamlMap?;
    return PubspecLock([
      for (var name in entries?.keys ?? const [])
        if (entries![name] case YamlMap entry)
          LockDependency(
            '$name',
            source: '${entry['source']}',
            version: '${entry['version']}',
            description: _plain(entry['description']),
          ),
    ]);
  }

  factory PubspecLock.parse(String content) =>
      PubspecLock.fromYaml(loadYaml(content) as YamlMap);

  /// Finds the lockfile governing [packagePath] by walking up.
  ///
  /// A pub workspace puts one lockfile at the root and none in the members, so
  /// looking only beside the package — which is what this used to do — found
  /// nothing for every member of every workspace. Walking up finds the root's,
  /// and in a standalone project finds the package's own on the first step.
  ///
  /// Null when there is no lockfile anywhere above, which means the project has
  /// never been resolved.
  static Future<PubspecLock?> load(String packagePath) async {
    var file = findFile(packagePath);
    if (file == null) return null;
    return PubspecLock.parse(await file.readAsString());
  }

  static File? findFile(String packagePath) {
    var directory = Directory(p.absolute(packagePath));
    while (true) {
      var candidate = File(p.join(directory.path, 'pubspec.lock'));
      if (candidate.existsSync()) return candidate;
      var parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }
}

/// Recursively converts the YAML wrappers to plain Dart, so a `description` can
/// be pattern-matched without every reader importing `package:yaml`.
Object? _plain(Object? node) => switch (node) {
  YamlMap map => {for (var key in map.keys) '$key': _plain(map[key])},
  YamlList list => [for (var item in list) _plain(item)],
  _ => node,
};

class LockDependency {
  LockDependency(
    this.name, {
    required this.source,
    required this.version,
    required this.description,
  });

  final String name;

  /// `hosted`, `git`, `path` or `sdk`.
  final String source;

  /// The resolved version — the one actually on disk. `0.0.0` for anything
  /// from the SDK.
  final String version;

  /// Shape depends on [source]: a map of `name`/`url`/`sha256` for hosted, of
  /// `url`/`ref`/`resolved-ref`/`path` for git, of `path`/`relative` for path —
  /// and, for an SDK package, **a bare string** rather than a map. Kept raw
  /// because interpreting it is `PackageOrigin`'s job.
  final Object? description;

  @override
  String toString() => 'LockDependency($name $version, $source)';
}

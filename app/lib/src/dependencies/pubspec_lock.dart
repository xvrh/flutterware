import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class PubspecLock {
  final List<LockDependency> packages;

  PubspecLock(this.packages);

  factory PubspecLock.fromYaml(YamlMap map) {
    var packages = map['packages'] as YamlMap;

    var results = <LockDependency>[];
    for (var package in packages.keys) {
      var packageInfo = packages[package] as YamlMap;
      results.add(LockDependency(
        package as String,
        source: packageInfo['source'] as String,
        version: packageInfo['version'] as String,
        type: DependencyType.fromName(packageInfo['dependency'] as String),
      ));
    }
    return PubspecLock(results);
  }

  static Future<PubspecLock> load(String packagePath) async {
    var map =
        loadYaml(File(p.join(packagePath, 'pubspec.lock')).readAsStringSync())
            as YamlMap;
    return PubspecLock.fromYaml(map);
  }
}

enum DependencyType {
  transitive('transitive'),
  directMain('direct main'),
  directDev('direct dev'),
  ;

  final String name;

  const DependencyType(this.name);

  static DependencyType fromName(String name) =>
      values.firstWhere((e) => e.name == name);
}

class LockDependency {
  final String name;
  final String source;
  final String version;
  final DependencyType type;

  LockDependency(this.name,
      {required this.source, required this.version, required this.type});

  bool get isHosted => source == 'hosted';

  @override
  String toString() => 'LockDependency($name, version: $version)';
}

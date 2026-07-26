import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Where a project declares its plugins, relative to the repo root.
const configFileName = 'tool/flutterware.dart';

/// Walks up from [start] looking for a worktree root.
///
/// A root is a directory holding `tool/flutterware.dart`, or failing that a
/// `.git`. Launching from `packages/admin/lib` therefore opens the one window
/// for the whole repo — the same idiom the distribution design uses to find
/// `flutter_version`.
String? findRepoRoot(String start) {
  var dir = Directory(p.normalize(p.absolute(start)));
  String? gitRoot;
  while (true) {
    if (File(p.join(dir.path, configFileName)).existsSync()) return dir.path;
    if (gitRoot == null &&
        (Directory(p.join(dir.path, '.git')).existsSync() ||
            File(p.join(dir.path, '.git')).existsSync())) {
      gitRoot = dir.path;
    }
    var parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return gitRoot;
}

/// Finds the repo's packages: the `workspace:` members when the root pubspec
/// declares them, else a shallow scan for `pubspec.yaml`.
///
/// Paths are relative to [root]; the root package itself is `.` when it has a
/// pubspec.
List<String> discoverPackages(String root, {int maxDepth = 3}) {
  var found = <String>[];
  var rootPubspec = File(p.join(root, 'pubspec.yaml'));
  if (rootPubspec.existsSync()) {
    found.add('.');
    try {
      var yaml = loadYaml(rootPubspec.readAsStringSync());
      if (yaml is YamlMap && yaml['workspace'] is YamlList) {
        for (var member in yaml['workspace'] as YamlList) {
          found.add('$member');
        }
        return found;
      }
    } on YamlException {
      // A malformed root pubspec is the project's problem, not a reason to
      // fail discovery — fall through to the scan.
    }
  }

  void scan(Directory dir, String relative, int depth) {
    if (depth > maxDepth) return;
    for (var entity in dir.listSync().whereType<Directory>()) {
      var name = p.basename(entity.path);
      if (name.startsWith('.') || name == 'build' || name == 'node_modules') {
        continue;
      }
      var childRelative = relative.isEmpty ? name : '$relative/$name';
      if (File(p.join(entity.path, 'pubspec.yaml')).existsSync()) {
        found.add(childRelative);
      }
      scan(entity, childRelative, depth + 1);
    }
  }

  try {
    scan(Directory(root), '', 1);
  } on FileSystemException {
    // Unreadable directory — return whatever was found.
  }
  return found;
}

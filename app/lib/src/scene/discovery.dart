// Finding what a package has: its scene groups, their scenes, and its token
// libraries. Every one of them is tool-owned or self-declaring — its first
// line carries a marker — so discovery is a walk and a first line: no
// compile, no analysis, no daemon.
//
// A group is a folder with a `scenes.dart` in it; the scenes are the
// `.scene.dart` files below that folder, the nearest group above a scene
// being the one it belongs to. A library is a `*.tokens.dart`, wherever it
// was written. Nothing is listed in the project's configuration: the walk
// finds what the folders say.
//
// Pure Dart: `fw scene`, an agent and the panel all learn what exists the
// same way.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/list_files.dart';
import 'group_file.dart';
import 'scene_file.dart';
import 'tokens_file.dart';

/// One scene file on disk, before anything parses it in full.
class SceneEntry {
  SceneEntry({required this.path, required this.className, required this.age});

  /// Absolute path.
  final String path;

  /// The scene class, read from the file's own header — the name the editor
  /// shows and the one a nested reference resolves against.
  final String className;

  /// Last modified, so a listing can order by what was touched last.
  final DateTime age;

  String get fileName => p.basename(path);
}

/// One group: a folder, its declaration, and the scenes below it.
class SceneGroupEntry {
  SceneGroupEntry({required this.directory, required this.scenes});

  /// Absolute path of the folder. Its name is the group's.
  final String directory;

  /// Newest first.
  final List<SceneEntry> scenes;

  String get name => p.basename(directory);

  /// The declaration: `scenes.dart` in the folder.
  String get declarationPath => p.join(directory, sceneGroupFileName);

  /// The generated file beside it.
  String get argsPath => p.join(directory, sceneArgsFileName);

  SceneEntry? sceneNamed(String className) {
    for (var scene in scenes) {
      if (scene.className == className) return scene;
    }
    return null;
  }
}

/// One token library: a `*.tokens.dart` and the list symbol it declares.
class SceneLibraryEntry {
  SceneLibraryEntry({required this.path});

  /// Absolute path.
  final String path;

  String get symbol => tokensSymbolFor(path);

  String get fileName => p.basename(path);
}

/// Everything the walk found under one scope.
class ScenePackageScan {
  ScenePackageScan({
    required this.groups,
    required this.libraries,
    required this.strayScenes,
  });

  /// By folder path.
  final List<SceneGroupEntry> groups;

  /// By path.
  final List<SceneLibraryEntry> libraries;

  /// Scene files with no group above them — not scenes the tool knows, and
  /// said once rather than listed.
  final int strayScenes;

  List<SceneEntry> get scenes => [for (var g in groups) ...g.scenes];

  /// The group a scene file belongs to — the nearest folder above it that
  /// is one — or null.
  SceneGroupEntry? groupOf(String scenePath) {
    var canonical = p.canonicalize(scenePath);
    SceneGroupEntry? nearest;
    for (var group in groups) {
      if (!p.isWithin(p.canonicalize(group.directory), canonical)) continue;
      if (nearest == null ||
          group.directory.length > nearest.directory.length) {
        nearest = group;
      }
    }
    return nearest;
  }

  SceneGroupEntry? groupNamed(String name) {
    for (var group in groups) {
      if (group.name == name) return group;
    }
    return null;
  }

  SceneLibraryEntry? libraryAt(String path) {
    var canonical = p.canonicalize(path);
    for (var library in libraries) {
      if (p.canonicalize(library.path) == canonical) return library;
    }
    return null;
  }

  /// The library symbol a path declares, or null when it is not one — the
  /// resolver a group parse takes.
  String? librarySymbolAt(String path) => libraryAt(path)?.symbol;
}

/// Everything under [scope]: groups, their scenes, and libraries. Listed
/// the way git lists — ignored files skipped, symlinks not followed — and
/// stopping at a nested package, which is a project of its own.
ScenePackageScan discoverPackage(String scope) {
  var root = Directory(scope);
  if (!root.existsSync()) {
    return ScenePackageScan(
      groups: const [],
      libraries: const [],
      strayScenes: 0,
    );
  }
  var groupDirs = <String>[];
  var scenes = <SceneEntry>[];
  var libraries = <SceneLibraryEntry>[];
  var nested = <String>{};
  var files = listFilesInDirectory(scope).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (var file in files) {
    if (p.basename(file.path) == 'pubspec.yaml' &&
        p.canonicalize(p.dirname(file.path)) != p.canonicalize(scope)) {
      nested.add(p.dirname(file.path));
    }
  }
  bool inNested(String path) {
    for (var dir in nested) {
      if (p.isWithin(dir, path)) return true;
    }
    return false;
  }

  for (var file in files) {
    var name = p.basename(file.path);
    if (inNested(file.path)) continue;
    if (name == sceneGroupFileName) {
      if (_firstLineHas(file, '@flutterware:scenes')) {
        groupDirs.add(p.dirname(file.path));
      }
    } else if (name.endsWith(sceneTokensFileSuffix)) {
      if (_firstLineHas(file, '@flutterware:tokens')) {
        libraries.add(SceneLibraryEntry(path: file.path));
      }
    } else if (name.endsWith('.scene.dart')) {
      var entry = _sceneEntry(file);
      if (entry != null) scenes.add(entry);
    }
  }

  // The nearest group above a scene is its group: deepest folder first.
  groupDirs.sort((a, b) => b.length.compareTo(a.length));
  var byGroup = {for (var dir in groupDirs) dir: <SceneEntry>[]};
  var stray = 0;
  for (var scene in scenes) {
    var owner = groupDirs
        .where((dir) => p.isWithin(dir, scene.path))
        .firstOrNull;
    if (owner == null) {
      stray++;
    } else {
      byGroup[owner]!.add(scene);
    }
  }
  var groups = [
    for (var dir in groupDirs)
      SceneGroupEntry(
        directory: dir,
        scenes: byGroup[dir]!..sort((a, b) => b.age.compareTo(a.age)),
      ),
  ]..sort((a, b) => a.directory.compareTo(b.directory));
  return ScenePackageScan(
    groups: groups,
    libraries: libraries,
    strayScenes: stray,
  );
}

/// Every scene file under [directory], newest first — one group's worth
/// when [directory] is a group's folder. A file whose first line carries no
/// marker is not a scene file and is skipped in silence.
List<SceneEntry> discoverScenes(String directory) {
  var dir = Directory(directory);
  if (!dir.existsSync()) return const [];
  var found = <SceneEntry>[];
  for (var file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.scene.dart')) continue;
    var entry = _sceneEntry(file);
    if (entry != null) found.add(entry);
  }
  found.sort((a, b) => b.age.compareTo(a.age));
  return found;
}

SceneEntry? _sceneEntry(File file) {
  String source;
  try {
    source = file.readAsStringSync();
  } on FileSystemException {
    return null;
  }
  var className = sceneClassNameOf(source);
  if (className == null) return null;
  return SceneEntry(
    path: file.path,
    className: className,
    age: file.statSync().modified,
  );
}

bool _firstLineHas(File file, String marker) {
  try {
    var source = file.readAsStringSync();
    var end = source.indexOf('\n');
    return (end < 0 ? source : source.substring(0, end)).contains(marker);
  } on FileSystemException {
    return false;
  }
}

/// The scene class a file declares, or null when the file is not a scene
/// file. Deliberately a cheap read — a listing must not pay a full parse per
/// file, and a file that is broken inside still belongs in the list, where
/// opening it can refuse with line numbers.
String? sceneClassNameOf(String source) {
  var lines = source.split('\n');
  if (lines.isEmpty || !lines.first.contains('@flutterware:scene')) return null;
  // The scene class is the one that is not a motion. Told apart by the
  // region each class owns — from its own header to the next one — because a
  // primary constructor puts the extends clause lines below the `class`
  // keyword, where a line-at-a-time scan cannot see it.
  var matches = _classHeader.allMatches(source).toList();
  for (var (index, match) in matches.indexed) {
    var end = index + 1 < matches.length
        ? matches[index + 1].start
        : source.length;
    if (source.substring(match.start, end).contains('extends SceneMotion')) {
      continue;
    }
    return match.group(1);
  }
  return null;
}

final _classHeader = RegExp(r'^class\s+([A-Za-z_$][\w$]*)', multiLine: true);

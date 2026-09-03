// Finding the scene files a project has. A scene file is tool-owned and
// self-declaring: its first line carries the marker, so discovery is a walk
// and a first line — no compile, no analysis, no daemon.
//
// Pure Dart: `fw scene`, an agent and the panel all learn what exists the
// same way.
import 'dart:io';

import 'package:path/path.dart' as p;

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

/// Every scene file under [directory], newest first. A file whose first line
/// carries no marker is not a scene file and is skipped in silence — the
/// marker is what makes one, and a project may keep anything else here.
List<SceneEntry> discoverScenes(String directory) {
  var dir = Directory(directory);
  if (!dir.existsSync()) return const [];
  var found = <SceneEntry>[];
  for (var file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.scene.dart')) continue;
    String source;
    try {
      source = file.readAsStringSync();
    } on FileSystemException {
      continue;
    }
    var className = sceneClassNameOf(source);
    if (className == null) continue;
    found.add(
      SceneEntry(
        path: file.path,
        className: className,
        age: file.statSync().modified,
      ),
    );
  }
  found.sort((a, b) => b.age.compareTo(a.age));
  return found;
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

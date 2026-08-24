import 'dart:io';

import 'package:project_tools/project_tools.dart';

void main() {
  var formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  );
  for (var project in DartProject.find(_repoRoot())) {
    for (var modifiedFile in formatProject(project, formatter)) {
      print(
        'Formatted: ${modifiedFile.project.packageName}:'
        '${modifiedFile.relativePath}',
      );
    }
  }
}

/// The repo root, so running from a subdirectory doesn't silently format
/// only that subtree.
///
/// Anchored on this script's own location, not on cwd or git — cwd may be a
/// subdirectory or another repository entirely. Under `pub run` the script is
/// a snapshot in `<root>/.dart_tool/`, so walk up to the nearest pubspec.yaml
/// rather than assuming `tool/`.
Directory _repoRoot() {
  var dir = File.fromUri(Platform.script).parent;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    var parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('no pubspec.yaml above ${Platform.script}');
    }
    dir = parent;
  }
}

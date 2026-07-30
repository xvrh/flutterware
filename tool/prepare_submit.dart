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
Directory _repoRoot() {
  var result = Process.runSync('git', ['rev-parse', '--show-toplevel']);
  if (result.exitCode != 0) return Directory.current;
  return Directory((result.stdout as String).trim());
}

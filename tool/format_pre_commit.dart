import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:project_tools/project_tools.dart';

Future<void> main() async {
  final gitRoot = _gitRoot();
  final projects = DartProject.find(gitRoot)
    ..sort((a, b) => b.path.length.compareTo(a.path.length));

  final formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  );

  final modified = <ProjectFile>[];
  for (final absPath in _stagedDartFiles(gitRoot)) {
    final file = projects.findFile(absPath);
    if (file == null) continue;
    if (formatFile(file, formatter)) modified.add(file);
  }

  if (modified.isEmpty) return;

  for (final file in modified) {
    Process.runSync('git', [
      'add',
      p.join(file.project.path, file.relativePath),
    ]);
    print(
      'pre-commit: formatted ${file.project.packageName}:'
      '${file.relativePath}',
    );
  }
}

Directory _gitRoot() {
  final result = Process.runSync('git', ['rev-parse', '--show-toplevel']);
  if (result.exitCode != 0) {
    throw StateError('git rev-parse --show-toplevel failed: ${result.stderr}');
  }
  return Directory((result.stdout as String).trim());
}

List<String> _stagedDartFiles(Directory gitRoot) {
  final result = Process.runSync('git', [
    'diff',
    '--cached',
    '--name-only',
    '--diff-filter=ACMR',
  ], workingDirectory: gitRoot.path);
  if (result.exitCode != 0) {
    throw StateError('git diff --cached failed: ${result.stderr}');
  }
  return LineSplitter.split(result.stdout as String)
      .where((line) => line.isNotEmpty && line.endsWith('.dart'))
      .map((rel) => p.join(gitRoot.path, rel))
      .where((abs) => File(abs).existsSync())
      .toList();
}

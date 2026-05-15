import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:project_tools/project_tools.dart';

/// Formats staged Dart files and re-stages them, so unformatted code never
/// reaches CI. Invoked by `hooks/pre-commit`.
///
/// The formatter config must stay in sync with `tool/prepare_submit.dart` —
/// CI runs that one and fails if it produces any change.
///
/// Git-root and staged-file detection are done with `git` directly rather
/// than `project_tools`' `findGitRootOrThrow`, because the latter only
/// recognizes a `.git` directory and fails inside a git worktree (where
/// `.git` is a file). Flutterware is developed across worktrees.
Future<void> main() async {
  final gitRoot = _gitRoot();
  final projects = DartProject.find(gitRoot)
    ..sort((a, b) => b.path.length.compareTo(a.path.length));

  final formatter = DartFormatter(languageVersion: Version(3, 5, 0));

  final modified = <ProjectFile>[];
  for (final absPath in _stagedDartFiles(gitRoot)) {
    final file = projects.findFile(absPath);
    if (file == null) continue;
    if (formatFile(file, formatter)) modified.add(file);
  }

  if (modified.isEmpty) return;

  // Give the filesystem a moment to settle before re-staging.
  await Future<void>.delayed(const Duration(seconds: 1));
  for (final file in modified) {
    Process.runSync('git', [
      'add',
      p.join(file.project.path, file.relativePath),
    ]);
    print('pre-commit: formatted ${file.project.packageName}:'
        '${file.relativePath}');
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
  final result = Process.runSync(
      'git',
      [
        'diff',
        '--cached',
        '--name-only',
        '--diff-filter=ACMR',
      ],
      workingDirectory: gitRoot.path);
  if (result.exitCode != 0) {
    throw StateError('git diff --cached failed: ${result.stderr}');
  }
  return LineSplitter.split(result.stdout as String)
      .where((line) => line.isNotEmpty && line.endsWith('.dart'))
      .map((rel) => p.join(gitRoot.path, rel))
      .where((abs) => File(abs).existsSync())
      .toList();
}

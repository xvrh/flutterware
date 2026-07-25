import 'dart:io';

import 'worktree.dart';

/// Lists the project's worktrees by asking git.
///
/// Any git failure yields a single-entry list for the launch directory rather
/// than an error: flutterware must stay usable in a plain directory that is not
/// a repository at all.
class WorktreeDiscovery {
  WorktreeDiscovery({
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    })?
    runProcess,
  }) : _run = runProcess ?? Process.run;

  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  _run;

  Future<List<Worktree>> discover(String directory) async {
    ProcessResult result;
    try {
      result = await _run('git', [
        'worktree',
        'list',
        '--porcelain',
      ], workingDirectory: directory);
    } on ProcessException {
      return [_fallback(directory)];
    }

    if (result.exitCode != 0) return [_fallback(directory)];

    var worktrees = parseWorktreeList('${result.stdout}');
    return worktrees.isEmpty ? [_fallback(directory)] : worktrees;
  }

  Worktree _fallback(String directory) =>
      Worktree(path: Directory(directory).absolute.path, isMain: true);
}

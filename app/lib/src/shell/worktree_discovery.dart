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
    String? Function(String worktreePath)? readGitPointer,
  }) : _run = runProcess ?? Process.run,
       _readGitPointer = readGitPointer ?? _readPointerFile;

  /// Reads a linked worktree's `.git` file, which is where git records the
  /// worktree's real name. A file read rather than a `git rev-parse` per
  /// worktree: `git worktree list --porcelain` does not report the name, and
  /// spawning a process each to ask would cost far more than opening a
  /// one-line file.
  ///
  /// **Synchronous on purpose.** A widget test drives fake time, so a real
  /// asynchronous read never completes inside one and `pumpAndSettle` waits
  /// forever — every test touching the shell would have to remember to stub
  /// this. One small read, after a subprocess spawn we already waited on, is
  /// not worth that.
  final String? Function(String worktreePath) _readGitPointer;

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
    if (worktrees.isEmpty) return [_fallback(directory)];

    return [for (var w in worktrees) _named(w)];
  }

  /// Fills in git's own name for [worktree]. The main checkout has no pointer
  /// file — its `.git` is a directory — and is named [Worktree.mainName].
  Worktree _named(Worktree worktree) {
    if (worktree.isMain) return worktree;
    var gitName = gitNameFrom(_readGitPointer(worktree.path));
    return gitName == null
        ? worktree
        : Worktree(
            path: worktree.path,
            gitName: gitName,
            branch: worktree.branch,
            head: worktree.head,
            isMain: worktree.isMain,
            title: worktree.title,
          );
  }

  Worktree _fallback(String directory) =>
      Worktree(path: Directory(directory).absolute.path, isMain: true);
}

/// The worktree name out of a `.git` pointer file's contents.
///
/// The file reads `gitdir: /path/to/repo/.git/worktrees/<name>`, and the path
/// may be relative when the repo was created with `--relative-paths` — either
/// way the name is its last component, so nothing here has to resolve it.
///
/// Null when the contents are not a pointer at all, which includes the main
/// checkout (where `.git` is a directory and the read fails).
String? gitNameFrom(String? contents) {
  if (contents == null) return null;
  var line = contents.trim();
  const prefix = 'gitdir:';
  if (!line.startsWith(prefix)) return null;
  var gitDir = line.substring(prefix.length).trim();
  var parts = gitDir
      .split(RegExp(r'[/\\]'))
      .where((s) => s.isNotEmpty)
      .toList();
  // `…/.git/worktrees/<name>` — anything shorter is not a linked worktree.
  if (parts.length < 2 || parts[parts.length - 2] != 'worktrees') return null;
  return parts.last;
}

String? _readPointerFile(String worktreePath) {
  try {
    return File(
      '$worktreePath${Platform.pathSeparator}.git',
    ).readAsStringSync();
  } on IOException {
    // Missing, or a directory because this is the main checkout.
    return null;
  }
}

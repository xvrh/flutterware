import 'dart:io';

/// Which commit a worktree is compared against.
///
/// The **merge base**, not the tip: comparing against the tip of master shows
/// everything other people landed while this branch was being written, which
/// is a different question and a much noisier one. The merge base is where
/// this branch left, so the delta is this branch's own.
///
/// One definition, shared with the changes screen when that lands here — the
/// two must not disagree, or the files tab and the pictures tab describe
/// different diffs.
class BaseRef {
  const BaseRef({required this.sha, required this.against});

  final String sha;

  /// The ref the merge base was taken with — what a header shows.
  final String against;

  /// Resolves the base of [worktree].
  ///
  /// [ref] overrides the default branch. Anything git can name works, so
  /// `--base=origin/main` and `--base=<sha>` both do what they look like.
  static Future<BaseRef> resolve(String worktree, {String? ref}) async {
    var against = ref ?? await defaultBranch(worktree);
    var merged = await _git(worktree, ['merge-base', 'HEAD', against]);
    if (merged == null) {
      // No common ancestor — an unrelated ref, or a shallow clone that does
      // not have one. Naming the ref beats a git error nobody can act on.
      throw BaseRefError(
        'no common commit between HEAD and "$against", so there is no base to '
        'compare against.',
      );
    }
    return BaseRef(sha: merged, against: against);
  }

  /// The repository's default branch, best answer first.
  ///
  /// `origin/HEAD` is the only one that is actually *recorded* — the rest is
  /// convention, and a repo whose trunk is neither `main` nor `master` is
  /// exactly the repo where guessing wrong compares against nothing.
  static Future<String> defaultBranch(String worktree) async {
    var head = await _git(worktree, [
      'symbolic-ref',
      '--short',
      'refs/remotes/origin/HEAD',
    ]);
    if (head != null && head.isNotEmpty) return head;
    for (var candidate in const ['main', 'master']) {
      if (await _git(worktree, ['rev-parse', '--verify', candidate]) != null) {
        return candidate;
      }
    }
    throw BaseRefError(
      "cannot tell what this repository's default branch is. "
      'Name one with --base.',
    );
  }

  /// The top of the checkout [dir] is in — what a base checkout mirrors.
  ///
  /// Not the same as the directory a command was typed in, and not the same as
  /// the *repository*: a linked worktree has its own top level and shares the
  /// repository's object store. A comparison's two sides are two top levels.
  static Future<String> topLevelOf(String dir) async =>
      await _git(dir, ['rev-parse', '--show-toplevel']) ?? dir;

  /// The repository this worktree belongs to — where `git worktree add` has to
  /// be run, which for a linked worktree is not the worktree itself.
  static Future<String> repositoryOf(String worktree) async {
    var common = await _git(worktree, [
      'rev-parse',
      '--path-format=absolute',
      '--git-common-dir',
    ]);
    return common == null ? worktree : Directory(common).parent.path;
  }

  static Future<String?> _git(String worktree, List<String> arguments) async {
    var result = await Process.run('git', [
      '-C',
      worktree,
      ...arguments,
    ], stdoutEncoding: systemEncoding);
    if (result.exitCode != 0) return null;
    var out = '${result.stdout}'.trim();
    return out.isEmpty ? null : out;
  }
}

class BaseRefError implements Exception {
  BaseRefError(this.message);

  final String message;

  @override
  String toString() => message;
}

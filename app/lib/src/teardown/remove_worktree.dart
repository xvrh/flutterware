import 'dart:io';

import 'package:meta/meta.dart';

import '../utils/run_git.dart' as git_process;

/// Removing the checkout itself — the one step the shell owns rather than a
/// plugin, and the one that always runs last.
///
/// `--force` is passed exactly when the user was told there was uncommitted
/// work. Git refuses to remove a worktree with modified or untracked files,
/// and the checklist has already shown that number and been told to go ahead;
/// refusing again here would only send the user to a terminal to type the flag
/// themselves, which is the friction that makes a cleanup tool go unused.
///
/// The pairing matters more than either half. Force without the warning
/// destroys unannounced work; the warning without force produces a
/// dialog that promises to delete files and then fails. Both come from
/// [TeardownPlan.uncommittedFiles], so they cannot disagree.
///
/// On a checkout the plan believed clean it is still **not** forced, and that
/// is the case worth keeping: a file written between the dialog opening and the
/// button being pressed is not in the cached count, and there git's refusal is
/// the only thing that notices.
class WorktreeRemover {
  const WorktreeRemover({this.runGit = git_process.runGit});

  /// A seam for tests, which must not have a real repository to delete.
  @visibleForTesting
  final Future<ProcessResult> Function(
    List<String> arguments, {
    String? workingDirectory,
  })
  runGit;

  /// Removes the checkout at [path]. [repositoryRoot] is where git runs, since
  /// the worktree's own directory is what is being removed.
  Future<GitStepResult> remove({
    required String path,
    required String repositoryRoot,
    bool force = false,
  }) => _git(
    ['worktree', 'remove', if (force) '--force', path],
    repositoryRoot,
    'Removed the worktree at $path.',
  );

  /// Deletes [branch] once its worktree is gone.
  ///
  /// `-d`, never `-D`: git refuses to delete a branch whose commits are not
  /// merged anywhere, and that refusal is the point. A branch is the last
  /// handle on work that is not on a remote, and "delete the branch too" is a
  /// checkbox that gets ticked while thinking about the directory.
  Future<GitStepResult> deleteBranch({
    required String branch,
    required String repositoryRoot,
  }) => _git(
    ['branch', '-d', branch],
    repositoryRoot,
    'Deleted the branch $branch.',
  );

  Future<GitStepResult> _git(
    List<String> arguments,
    String workingDirectory,
    String success,
  ) async {
    ProcessResult result;
    try {
      result = await runGit(arguments, workingDirectory: workingDirectory);
    } on Object catch (e) {
      return GitStepResult(ok: false, output: 'git: $e');
    }
    var output = [
      '${result.stdout}'.trimRight(),
      '${result.stderr}'.trimRight(),
    ].where((s) => s.isNotEmpty).join('\n');
    return GitStepResult(
      ok: result.exitCode == 0,
      // Git's own words when it refused, ours when it did not: a success
      // message nobody reads is better than an empty pane, and a failure
      // message we paraphrased is worse than the one git wrote.
      output: result.exitCode == 0
          ? (output.isEmpty ? success : output)
          : output,
    );
  }
}

class GitStepResult {
  const GitStepResult({required this.ok, required this.output});

  final bool ok;
  final String output;
}

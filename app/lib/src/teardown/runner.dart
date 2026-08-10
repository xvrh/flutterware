import 'dart:async';

import 'package:flutterware/plugins.dart';

import '../plugins/worktree_session.dart';
import 'plan.dart';
import 'remove_worktree.dart';

/// How far one step got.
enum TeardownOutcome { pending, running, done, failed, skipped }

/// One row of the checklist as it runs.
class TeardownProgress {
  TeardownProgress({
    required this.label,
    required this.detail,
    required this.phase,
    this.outcome = TeardownOutcome.pending,
    this.output = '',
  });

  final String label;
  final String? detail;

  /// Null for the two the shell owns — removing the checkout and deleting the
  /// branch — which run after every phase.
  final TeardownPhase? phase;

  TeardownOutcome outcome;

  /// What the step said. Kept for the ones that failed, which is the only time
  /// anybody reads it.
  String output;
}

/// What to do when a step fails.
enum TeardownFailureChoice { retry, skip, abort }

/// Runs a [TeardownPlan]'s selected steps, then removes the checkout.
///
/// **A plugin step is `Session.invoke`, nothing else.** The step's id names an
/// action on the plugin that emitted it, so the checklist runs exactly what
/// `fw run <plugin> <action>` runs. There is no second path to keep in step,
/// and no capability a teardown can reach that the CLI cannot.
///
/// **Removal is gated on the steps.** If a step failed and the user did not
/// explicitly continue past it, the checkout is left alone: a half-torn-down
/// stack is recoverable, and a deleted worktree is not. That ordering is the
/// single most important thing in this file.
class TeardownRunner {
  TeardownRunner({
    required this.plan,
    required this.session,
    required this.repositoryRoot,
    required this.selected,
    this.deleteBranch = false,
    WorktreeRemover? remover,
    this.onFailure,
  }) : remover = remover ?? const WorktreeRemover() {
    for (var planned in selected) {
      _progress.add(
        TeardownProgress(
          label: planned.step.label,
          detail: planned.step.detail,
          phase: planned.step.phase,
        ),
      );
    }
    _progress.add(
      TeardownProgress(
        label: 'Remove the git worktree',
        detail: plan.path,
        phase: null,
      ),
    );
    if (deleteBranch && plan.branch != null) {
      _progress.add(
        TeardownProgress(
          label: 'Delete the branch ${plan.branch}',
          detail: null,
          phase: null,
        ),
      );
    }
  }

  final TeardownPlan plan;

  /// Null for a worktree with nothing open. Only plugin steps need it, and a
  /// plan built without a session has none.
  final WorktreeSession? session;

  /// Where git runs. Not the worktree — that directory is being removed.
  final String repositoryRoot;

  final List<PlannedStep> selected;
  final bool deleteBranch;
  final WorktreeRemover remover;

  /// Asked when a step fails. Returning null aborts, which is the safe answer
  /// for a caller that has no way to ask.
  final Future<TeardownFailureChoice?> Function(TeardownProgress step)?
  onFailure;

  final _progress = <TeardownProgress>[];
  final _changes = StreamController<void>.broadcast();

  List<TeardownProgress> get progress => List.unmodifiable(_progress);

  /// Fires whenever a row changes. The dialog rebuilds; nothing else listens.
  Stream<void> get changes => _changes.stream;

  var _aborted = false;
  var _removed = false;

  /// True once the checkout is gone. The caller closes the tab on this, and on
  /// nothing else — a plan that ran every step and then failed to remove the
  /// directory has not removed the worktree.
  bool get removed => _removed;

  bool get aborted => _aborted;

  /// Runs everything. Never throws: a failed step is a state, not an exception,
  /// for the same reason `Job.done` never completes with an error.
  Future<void> run() async {
    for (var i = 0; i < selected.length; i++) {
      if (_aborted) {
        _mark(i, TeardownOutcome.skipped);
        continue;
      }
      await _runStep(i, selected[i]);
    }
    if (_aborted) {
      // Every remaining row, the removal included, is skipped rather than left
      // pending — a checklist that stops mid-way has to say which half ran.
      for (var i = selected.length; i < _progress.length; i++) {
        _mark(i, TeardownOutcome.skipped);
      }
      return;
    }
    await _runRemoval();
  }

  Future<void> _runStep(int index, PlannedStep planned) async {
    while (true) {
      _mark(index, TeardownOutcome.running);
      var session = this.session;
      if (session == null) {
        _finish(
          index,
          false,
          'This worktree is not open, so its plugins cannot run anything.',
        );
      } else {
        var job = session.invoke(
          planned.pluginId,
          planned.step.id,
          arguments: planned.step.arguments,
        );
        var result = await job.done;
        _finish(
          index,
          result.error == null,
          result.error == null ? '' : '${result.error}',
        );
      }
      if (_progress[index].outcome != TeardownOutcome.failed) return;

      var choice = await onFailure?.call(_progress[index]);
      switch (choice) {
        case TeardownFailureChoice.retry:
          continue;
        case TeardownFailureChoice.skip:
          _mark(index, TeardownOutcome.skipped);
          return;
        case TeardownFailureChoice.abort:
        case null:
          _aborted = true;
          return;
      }
    }
  }

  Future<void> _runRemoval() async {
    var index = selected.length;
    _mark(index, TeardownOutcome.running);
    var result = await remover.remove(
      path: plan.path,
      repositoryRoot: repositoryRoot,
      // Forced only when the checklist said so, so the warning the user read
      // and the flag git receives are the same fact.
      force: plan.destroysUncommittedWork,
    );
    _finish(index, result.ok, result.output);
    if (!result.ok) {
      _aborted = true;
      for (var i = index + 1; i < _progress.length; i++) {
        _mark(i, TeardownOutcome.skipped);
      }
      return;
    }
    _removed = true;

    if (!deleteBranch || plan.branch == null) return;
    var branchIndex = index + 1;
    _mark(branchIndex, TeardownOutcome.running);
    var branch = await remover.deleteBranch(
      branch: plan.branch!,
      repositoryRoot: repositoryRoot,
    );
    // A branch that will not delete does not un-remove the worktree, so this
    // failure is reported and not escalated.
    _finish(branchIndex, branch.ok, branch.output);
  }

  void _mark(int index, TeardownOutcome outcome) {
    _progress[index].outcome = outcome;
    _changes.add(null);
  }

  void _finish(int index, bool ok, String output) {
    _progress[index]
      ..outcome = ok ? TeardownOutcome.done : TeardownOutcome.failed
      ..output = output;
    _changes.add(null);
  }

  void dispose() => unawaited(_changes.close());
}

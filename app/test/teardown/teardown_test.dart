import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/teardown/plan.dart';
import 'package:flutterware_app/src/teardown/remove_worktree.dart';
import 'package:flutterware_app/src/teardown/runner.dart';
import 'package:flutterware_app/src/worktrees/facts.dart';

/// The teardown checklist, from both ends: what it decides to offer, and what
/// it actually does when run.
///
/// The stakes are why these are thorough. Every other test in this app protects
/// a rendering; this one protects a directory that is about to be deleted, and
/// the two rules worth breaking the build over are **never destroy uncommitted
/// work** and **never remove the checkout when a step failed**.
void main() {
  PluginReport reportWith({
    String id = 'acme.thing',
    List<TeardownStep> teardown = const [],
    List<Guard> guards = const [],
  }) => PluginReport(
    id: id,
    label: id,
    status: Status.none,
    teardown: teardown,
    guards: guards,
    view: const PluginView([]),
  );

  WorktreeFacts factsWith({int dirty = 0, int ahead = 0, AgentState? agent}) =>
      WorktreeFacts(
        git: Fact.fresh(GitFacts(dirty: dirty, ahead: ahead)),
        agent: agent == null
            ? const Fact.unknown()
            : Fact.fresh(AgentFacts(state: agent)),
      );

  TeardownPlan planWith({
    bool isMain = false,
    WorktreeFacts facts = const WorktreeFacts(),
    List<PluginReport> reports = const [],
    bool sessionOpen = true,
    String? branch = 'claude/thing',
  }) => TeardownPlan.build(
    worktree: 'thing',
    path: '/tmp/wt/thing',
    branch: branch,
    isMain: isMain,
    facts: facts,
    reports: reports,
    sessionOpen: sessionOpen,
  );

  group('what blocks', () {
    test('uncommitted work warns rather than blocking', () {
      // It used to block. The worktrees anybody needs to remove are the
      // abandoned ones, and those have junk in them almost by definition — so a
      // block refused exactly the case the screen exists for.
      var plan = planWith(facts: factsWith(dirty: 5));
      expect(plan.isBlocked, isFalse);
      expect(plan.warnings.single.reason, contains('5 uncommitted files'));
      expect(plan.warnings.single.reason, contains('nothing can bring them'));
      expect(plan.destroysUncommittedWork, isTrue);
      expect(plan.uncommittedFiles, 5);
    });

    test('one file reads as one file', () {
      expect(
        planWith(facts: factsWith(dirty: 1)).warnings.single.reason,
        startsWith('1 uncommitted file '),
      );
    });

    test('a clean checkout destroys nothing', () {
      var plan = planWith(facts: factsWith());
      expect(plan.destroysUncommittedWork, isFalse);
      expect(plan.uncommittedFiles, 0);
    });

    test('the primary checkout blocks', () {
      expect(planWith(isMain: true).isBlocked, isTrue);
    });

    test('unpushed commits warn rather than block — they are recoverable', () {
      var plan = planWith(facts: factsWith(ahead: 3));
      expect(plan.isBlocked, isFalse);
      expect(plan.warnings.single.reason, contains('3 commits not pushed'));
    });

    test('a working agent warns', () {
      var plan = planWith(facts: factsWith(agent: AgentState.working));
      expect(plan.isBlocked, isFalse);
      expect(plan.warnings.single.reason, contains('still working'));
    });

    test('an idle agent says nothing', () {
      expect(
        planWith(facts: factsWith(agent: AgentState.idle)).guards,
        isEmpty,
      );
    });

    test('facts that never computed raise nothing', () {
      // Blocking on ignorance would make the button unusable on first launch,
      // before any probe has run.
      expect(planWith().guards, isEmpty);
      expect(planWith().isBlocked, isFalse);
    });

    test('the primary checkout is the only thing left that blocks', () {
      expect(planWith(facts: factsWith(dirty: 9, ahead: 2)).isBlocked, isFalse);
      expect(planWith(isMain: true).isBlocked, isTrue);
    });

    test('a plugin guard joins the shell ones, blocks first', () {
      var plan = planWith(
        facts: factsWith(ahead: 1),
        reports: [
          reportWith(guards: const [Guard.block('a plugin says no')]),
        ],
      );
      expect(plan.guards.first.level, GuardLevel.block);
      expect(plan.isBlocked, isTrue);
    });
  });

  group('what it offers', () {
    test('steps come out in phase order, apps before infra', () {
      var plan = planWith(
        reports: [
          reportWith(
            id: 'a',
            teardown: const [
              TeardownStep('x', 'cleanup thing', phase: TeardownPhase.cleanup),
              TeardownStep('y', 'stack', phase: TeardownPhase.infra),
            ],
          ),
          reportWith(
            id: 'b',
            teardown: const [
              TeardownStep('z', 'an app', phase: TeardownPhase.apps),
            ],
          ),
        ],
      );
      expect(
        [for (var s in plan.steps) s.step.label],
        ['an app', 'stack', 'cleanup thing'],
      );
    });

    test('only enabled and checked steps are selected by default', () {
      var plan = planWith(
        reports: [
          reportWith(
            teardown: const [
              TeardownStep('a', 'ticked', checked: true),
              TeardownStep('b', 'unticked'),
              TeardownStep('c', 'nothing to do', enabled: false, checked: true),
            ],
          ),
        ],
      );
      expect([for (var s in plan.defaultSelection) s.step.label], ['ticked']);
    });

    test('a closed worktree says which half is missing', () {
      var plan = planWith(sessionOpen: false);
      expect(plan.sessionOpen, isFalse);
      expect(plan.steps, isEmpty);
    });
  });

  group('running it', () {
    late List<List<String>> gitRan;
    late bool removeSucceeds;

    WorktreeRemover remover() => WorktreeRemover(
      runGit: (arguments, {workingDirectory}) async {
        gitRan.add(arguments);
        var ok = removeSucceeds || arguments.first != 'worktree';
        return ProcessResult(
          0,
          ok ? 0 : 1,
          '',
          ok ? '' : "fatal: '/tmp/wt/thing' contains modified files",
        );
      },
    );

    setUp(() {
      gitRan = [];
      removeSucceeds = true;
    });

    /// A runner over a fake session. `session: null` is the "worktree not open"
    /// path, which is the one that must not silently succeed.
    TeardownRunner runnerFor({
      List<PlannedStep> steps = const [],
      bool deleteBranch = false,
      Future<TeardownFailureChoice?> Function(TeardownProgress)? onFailure,
    }) => TeardownRunner(
      plan: planWith(),
      session: null,
      repositoryRoot: '/tmp/repo',
      selected: steps,
      deleteBranch: deleteBranch,
      remover: remover(),
      onFailure: onFailure,
    );

    test('forces past uncommitted work it warned about', () async {
      // The pairing that has to hold: the dialog said five files would go, so
      // git is told to take them. Warning without force is a dialog that
      // promises a deletion and then fails.
      var runner = TeardownRunner(
        plan: planWith(facts: factsWith(dirty: 5)),
        session: null,
        repositoryRoot: '/tmp/repo',
        selected: const [],
        remover: remover(),
      );
      await runner.run();
      expect(gitRan.single, ['worktree', 'remove', '--force', '/tmp/wt/thing']);
      expect(runner.removed, isTrue);
      runner.dispose();
    });

    test('does not force a checkout it believed clean', () async {
      // Left unforced on purpose: a file written between the dialog opening and
      // the button being pressed is not in the cached count, and git's refusal
      // is the only thing that notices.
      var runner = runnerFor();
      await runner.run();
      expect(gitRan.single, isNot(contains('--force')));
      runner.dispose();
    });

    test('removes the checkout when there is nothing else to do', () async {
      var runner = runnerFor();
      await runner.run();
      expect(runner.removed, isTrue);
      expect(gitRan, [
        ['worktree', 'remove', '/tmp/wt/thing'],
      ]);
      expect(runner.progress.single.outcome, TeardownOutcome.done);
      runner.dispose();
    });

    test('a failed removal is reported, and nothing after it runs', () async {
      removeSucceeds = false;
      var runner = runnerFor(deleteBranch: true);
      await runner.run();
      expect(runner.removed, isFalse);
      expect(runner.progress.first.outcome, TeardownOutcome.failed);
      // Git's own words, not ours.
      expect(runner.progress.first.output, contains('contains modified files'));
      expect(runner.progress.last.outcome, TeardownOutcome.skipped);
      // The branch is never touched when its worktree is still there.
      expect(gitRan.length, 1);
      runner.dispose();
    });

    test('deletes the branch only after the worktree is gone', () async {
      var runner = runnerFor(deleteBranch: true);
      await runner.run();
      expect(gitRan, [
        ['worktree', 'remove', '/tmp/wt/thing'],
        ['branch', '-d', 'claude/thing'],
      ]);
      runner.dispose();
    });

    test('a step that cannot run aborts before the removal', () async {
      // No session, so the step has nothing to invoke. The critical assertion
      // is the second one: the checkout survives.
      var runner = runnerFor(
        steps: const [
          PlannedStep(
            pluginId: 'flutterware.run',
            step: TeardownStep('stop', 'Stop the app'),
          ),
        ],
        onFailure: (_) async => TeardownFailureChoice.abort,
      );
      await runner.run();
      expect(runner.aborted, isTrue);
      expect(runner.removed, isFalse);
      expect(gitRan, isEmpty);
      expect(runner.progress.last.outcome, TeardownOutcome.skipped);
      runner.dispose();
    });

    test('skipping a failed step continues to the removal', () async {
      var runner = runnerFor(
        steps: const [
          PlannedStep(
            pluginId: 'flutterware.run',
            step: TeardownStep('stop', 'Stop the app'),
          ),
        ],
        onFailure: (_) async => TeardownFailureChoice.skip,
      );
      await runner.run();
      expect(runner.progress.first.outcome, TeardownOutcome.skipped);
      expect(runner.removed, isTrue);
      runner.dispose();
    });

    test('no answer to a failure is taken as abort', () async {
      // The safe default: a caller with no way to ask must not fall through to
      // deleting the directory.
      var runner = runnerFor(
        steps: const [
          PlannedStep(
            pluginId: 'flutterware.run',
            step: TeardownStep('stop', 'Stop the app'),
          ),
        ],
      );
      await runner.run();
      expect(runner.aborted, isTrue);
      expect(runner.removed, isFalse);
      runner.dispose();
    });

    test('retry runs the step again', () async {
      var asked = 0;
      var runner = runnerFor(
        steps: const [
          PlannedStep(
            pluginId: 'flutterware.run',
            step: TeardownStep('stop', 'Stop the app'),
          ),
        ],
        onFailure: (_) async => ++asked < 3
            ? TeardownFailureChoice.retry
            : TeardownFailureChoice.abort,
      );
      await runner.run();
      expect(asked, 3);
      runner.dispose();
    });

    test('every row has an outcome when it stops early', () async {
      var runner = runnerFor(
        steps: const [
          PlannedStep(pluginId: 'a', step: TeardownStep('a', 'first')),
          PlannedStep(pluginId: 'b', step: TeardownStep('b', 'second')),
        ],
        onFailure: (_) async => TeardownFailureChoice.abort,
      );
      await runner.run();
      // A checklist that stops mid-way has to say which half ran; nothing is
      // left pending.
      expect(
        runner.progress.map((p) => p.outcome),
        everyElement(isNot(TeardownOutcome.pending)),
      );
      runner.dispose();
    });
  });

  group('a step reaches the plugin that emitted it', () {
    test('by the id recorded at assembly, not by finding the step again', () {
      // The bug this exists for: `report` is a computed getter, so every plugin
      // builds fresh `TeardownStep` objects on each call. A runner that looked
      // its owner up by scanning the reports a second time would be comparing
      // objects that can never match — and the report *is* rebuilt between
      // drawing the checklist and running it, because a poll ticks while the
      // dialog is open.
      var report = reportWith(
        id: 'flutterware.dev_stack',
        teardown: const [
          TeardownStep(
            'stop',
            'Tear down',
            arguments: {'device': 'macos'},
            checked: true,
          ),
        ],
      );
      var plan = planWith(reports: [report]);
      var planned = plan.steps.single;

      expect(planned.pluginId, 'flutterware.dev_stack');
      expect(planned.step.arguments, {'device': 'macos'});
      // A second report carries equal-looking but distinct step objects, and
      // the plan is unaffected because it never goes back to ask.
      expect(
        identical(
          planned.step,
          reportWith(
            id: 'flutterware.dev_stack',
            teardown: const [TeardownStep('stop', 'Tear down')],
          ).teardown.single,
        ),
        isFalse,
      );
    });
  });

  group('the remover', () {
    test('passes --force only when told to', () async {
      var ran = <List<String>>[];
      var remover = WorktreeRemover(
        runGit: (arguments, {workingDirectory}) async {
          ran.add(arguments);
          return ProcessResult(0, 0, '', '');
        },
      );
      await remover.remove(path: '/tmp/x', repositoryRoot: '/tmp/repo');
      await remover.deleteBranch(branch: 'b', repositoryRoot: '/tmp/repo');
      // Unforced unless asked, and the branch is never forced at all: `-d`
      // refusing an unmerged branch is the last handle on work that is not on a
      // remote.
      expect(ran.expand((a) => a), isNot(contains('--force')));
      expect(ran.last, ['branch', '-d', 'b']);
    });

    test('a git that will not spawn is a failed step, not a throw', () async {
      var remover = WorktreeRemover(
        runGit: (arguments, {workingDirectory}) async =>
            throw const ProcessException('git', [], 'not found'),
      );
      var result = await remover.remove(
        path: '/tmp/x',
        repositoryRoot: '/tmp/repo',
      );
      expect(result.ok, isFalse);
      expect(result.output, contains('not found'));
    });
  });
}

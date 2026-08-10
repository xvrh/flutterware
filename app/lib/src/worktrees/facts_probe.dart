/// Turns a list of worktrees into a list of facts.
///
/// The orchestration the design doc's performance section describes, made
/// literal: batch what git can batch, pay the per-worktree cost only for the
/// working tree, and never recompute a branch diff whose two shas have not
/// moved.
///
/// Pure Dart. `fw worktrees` links this; the GUI wraps it in a controller with
/// watchers, and both get the same numbers because both call this.
library;

import 'dart:async';

import '../shell/worktree.dart';
import 'facts.dart';
import 'facts_store.dart';
import 'providers/agent.dart';
import 'providers/git.dart';

class WorktreeFactsProbe {
  WorktreeFactsProbe({
    required this.repoRoot,
    required this.store,
    GitProbe? git,
    AgentProbe? agent,
    this.concurrency = 4,
    DateTime Function()? now,
  }) : git = git ?? GitProbe(),
       agent = agent ?? ClaudeAgentProbe(),
       _now = now ?? DateTime.now;

  /// The main checkout — where the batched calls run, and where every
  /// commit-only question is answered from.
  final String repoRoot;

  final WorktreeFactsStore store;
  final GitProbe git;

  /// Nice to have, never required. Everything it reports is optional, and a
  /// probe that finds nothing is indistinguishable from a repo with no agents —
  /// which is the point.
  final AgentProbe agent;

  /// How many worktrees are probed at once.
  ///
  /// Four rather than all of them: fourteen concurrent `git status` calls on a
  /// cold page cache is a thundering herd against one disk, and the wall-clock
  /// win over four is nil.
  final int concurrency;

  final DateTime Function() _now;

  Future<Map<String, WorktreeFacts>> probe(List<Worktree> worktrees) async {
    // The two batched calls, before anything per-worktree. One process each,
    // for every branch in the repository.
    var tips = await git.branchTips(repoRoot);
    var base = await git.defaultBranch(repoRoot);
    var baseSha = base == null ? null : tips[base]?.sha;

    var facts = <String, WorktreeFacts>{};
    await _pooled(worktrees, (worktree) async {
      facts[worktree.path] = await _probeOne(
        worktree,
        tips: tips,
        base: base,
        baseSha: baseSha,
      );
    });

    store.save();
    return facts;
  }

  Future<WorktreeFacts> _probeOne(
    Worktree worktree, {
    required Map<String, BranchTip> tips,
    required String? base,
    required String? baseSha,
  }) async {
    var agentFacts = await agent.probe(worktree.path);

    var status = await git.status(worktree.path);
    if (status == null) {
      return WorktreeFacts(
        git: const Fact.failed('git could not read this worktree'),
        agent: _agentFact(agentFacts),
        activity: _activity(worktree, null, agentFacts),
      );
    }

    var branch = status.branch ?? worktree.branch;
    var headSha = status.head ?? tips[branch]?.sha;

    var diff = await _branchDiff(
      branch: branch,
      base: base,
      baseSha: baseSha,
      headSha: headSha,
    );

    return WorktreeFacts(
      git: Fact.fresh(
        GitFacts(
          dirty: status.dirty,
          ahead: diff?.ahead ?? status.ahead ?? 0,
          behind: diff?.behind ?? status.behind ?? 0,
          changes: diff?.shape,
          base: base,
        ),
        computedAt: _now(),
        validityKey: baseSha == null || headSha == null
            ? null
            : WorktreeFactsStore.diffKey(baseSha, headSha),
      ),
      agent: _agentFact(agentFacts),
      activity: _activity(worktree, tips[branch]?.committedAt, agentFacts),
    );
  }

  /// `unavailable`, not `failed`, when there is no session.
  ///
  /// Nothing is broken about a checkout no agent has ever touched, and the two
  /// states render differently on purpose — one is a quiet dash, the other is a
  /// complaint that would never clear.
  Fact<AgentFacts> _agentFact(AgentFacts? facts) =>
      facts == null || facts.state == AgentState.none
      ? const Fact.unavailable('no agent session for this checkout')
      : Fact.fresh(facts, computedAt: _now());

  /// The cached half. A sha pair has one diff forever, so a hit is not a stale
  /// answer that happens to be right — it is *the* answer, and the only reason
  /// to recompute it would be that we lost it.
  ///
  /// The base branch itself is skipped rather than diffed against itself: `git`
  /// would happily report nothing, but it would be one process per launch to
  /// learn something already known.
  Future<CachedDiff?> _branchDiff({
    required String? branch,
    required String? base,
    required String? baseSha,
    required String? headSha,
  }) async {
    if (branch == null || base == null || baseSha == null || headSha == null) {
      return null;
    }
    if (branch == base || baseSha == headSha) return null;

    var cached = store.diff(baseSha, headSha);
    if (cached != null) return cached;

    var computed = await git.branchDiff(repoRoot, base: baseSha, head: headSha);
    if (computed == null) return null;

    var diff = CachedDiff(
      shape: computed.shape,
      ahead: computed.ahead,
      behind: computed.behind,
    );
    store.putDiff(baseSha, headSha, diff);
    return diff;
  }

  /// The maximum of the clocks we have, and *which one it was*.
  ///
  /// "Last touched" is three clocks that disagree, so this takes the newest and
  /// records which one won. A bare relative time meaning a commit on one row and
  /// an agent message on the next is worse than no time at all.
  Fact<ActivityFacts> _activity(
    Worktree worktree,
    DateTime? committedAt,
    AgentFacts? agent,
  ) {
    var candidates = <(DateTime, ActivitySource)>[
      if (committedAt != null) (committedAt, ActivitySource.commit),
      if (store.openedAt(worktree.path) case var at?)
        (at, ActivitySource.opened),
      if (agent?.at case var at?) (at, ActivitySource.agent),
    ];
    if (candidates.isEmpty) return const Fact.unknown();
    candidates.sort((a, b) => b.$1.compareTo(a.$1));
    return Fact.fresh(
      ActivityFacts(at: candidates.first.$1, source: candidates.first.$2),
      computedAt: _now(),
    );
  }

  /// Runs [work] over [items], at most [concurrency] at a time.
  ///
  /// Hand-rolled rather than pulled in: it is eight lines, and the alternative
  /// is a dependency for one call site.
  Future<void> _pooled<T>(
    List<T> items,
    Future<void> Function(T item) work,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (true) {
        var index = next++;
        if (index >= items.length) return;
        await work(items[index]);
      }
    }

    await Future.wait([
      for (var i = 0; i < concurrency && i < items.length; i++) worker(),
    ]);
  }
}

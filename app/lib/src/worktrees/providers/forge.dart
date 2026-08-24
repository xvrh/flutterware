/// Whether a branch has a pull request, read from the forge's own CLI.
///
/// CLI only, never a token. `gh` and `glab` already hold the user's
/// credentials, already know the host, and already handle enterprise
/// installations and SSO. Asking for a token would mean storing one, refreshing
/// one and being blamed for one — for a column.
///
/// The contract, the same one [AgentProbe] has and for the same reason: **a
/// forge that cannot answer reports [ForgeReport.unavailable], never an
/// exception.** No `gh` installed, no remote, a host neither tool recognises, an
/// expired login — all of them mean "no PR information here", which the explorer
/// renders as a quiet dash and the table renders by dropping the column.
library;

import 'dart:convert';
import 'dart:io';

import '../../utils/run_git.dart';
import '../facts.dart';

typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Every pull request the forge knows about, keyed by **head branch** — which
/// is the only thing a worktree and a pull request have in common.
class ForgeReport {
  const ForgeReport.ready(this.pullRequests) : unavailable = null;

  const ForgeReport.unavailable(String this.unavailable)
    : pullRequests = const {};

  final Map<String, ForgeFacts> pullRequests;

  /// Why there is nothing to say. Null when the forge answered — including when
  /// it answered with no pull requests at all, which is a fact rather than a
  /// failure.
  final String? unavailable;

  bool get isReady => unavailable == null;
}

/// One forge's way of being asked. GitHub and GitLab are the two
/// implementations; the interface exists so a third is a new file rather than
/// an `if`.
abstract class ForgeProbe {
  /// Every pull request for the repository at [repoRoot], in one sweep.
  ///
  /// One call for the whole repository, not one per worktree. Fourteen
  /// worktrees asking their own question would be fourteen round trips to a
  /// server; one list request covers all of them and is joined locally.
  Future<ForgeReport> probe(String repoRoot);
}

/// Picks the CLI from `origin`, then delegates.
///
/// Host matching is on the substring, so `github.example.com` and
/// `gitlab.corp.internal` resolve without configuration. A host that matches
/// neither tries GitHub and then GitLab — a self-hosted forge under a vanity
/// domain is the case that would otherwise need a setting, and two fast
/// failures are cheaper than a setting nobody knows to set.
class RemoteForgeProbe implements ForgeProbe {
  RemoteForgeProbe({
    RunProcess? runProcess,
    ForgeProbe? github,
    ForgeProbe? gitlab,
  }) : _run = runProcess ?? runGitTool,
       github = github ?? GitHubForgeProbe(runProcess: runProcess),
       gitlab = gitlab ?? GitLabForgeProbe(runProcess: runProcess);

  final RunProcess _run;
  final ForgeProbe github;
  final ForgeProbe gitlab;

  @override
  Future<ForgeReport> probe(String repoRoot) async {
    var remote = await _remote(repoRoot);
    if (remote == null) {
      return const ForgeReport.unavailable('no origin remote');
    }
    var host = remote.toLowerCase();
    if (host.contains('gitlab')) return gitlab.probe(repoRoot);
    if (host.contains('github')) return github.probe(repoRoot);

    var report = await github.probe(repoRoot);
    return report.isReady ? report : gitlab.probe(repoRoot);
  }

  Future<String?> _remote(String repoRoot) async {
    try {
      var result = await _run('git', [
        'config',
        '--get',
        'remote.origin.url',
      ], workingDirectory: repoRoot);
      if (result.exitCode != 0) return null;
      var url = '${result.stdout}'.trim();
      return url.isEmpty ? null : url;
    } on ProcessException {
      return null;
    }
  }
}

/// GitHub, via `gh pr list`.
class GitHubForgeProbe implements ForgeProbe {
  GitHubForgeProbe({RunProcess? runProcess}) : _run = runProcess ?? runGitTool;

  final RunProcess _run;

  /// What an open pull request has to say. `statusCheckRollup` is the expensive
  /// one — see [closedLimit].
  static const openFields =
      'number,title,headRefName,isDraft,state,reviewDecision,url,'
      'statusCheckRollup';

  /// A closed pull request is asked less. Its checks are history; what matters
  /// is that the branch is done.
  static const closedFields = 'number,title,headRefName,state,url';

  /// Measured, 2026-08-10, on a repository with 78 pull requests. Cost
  /// tracks the number returned, because the check rollup is expanded per pull
  /// request:
  ///
  /// | query | cost |
  /// |---|---|
  /// | `--state open --limit 100` with rollup | **0.74 s** |
  /// | `--state all --limit 30` with rollup | 2.12 s |
  /// | `--state all --limit 100` with rollup | 3.94 s |
  /// | `--state closed --limit 30` without rollup | **0.53 s** |
  ///
  /// So: open pull requests in full, and a *bounded window* of closed ones
  /// without their checks, concurrently. That buys the merged state — "this
  /// worktree is finished, delete it", the one genuinely actionable thing the
  /// column says — for no extra wall clock, where asking for all of history
  /// would have cost 5×.
  static const openLimit = 100;
  static const closedLimit = 30;

  @override
  Future<ForgeReport> probe(String repoRoot) async {
    // Concurrent: two requests, one wall clock. The closed window is the
    // shorter of the two, so it is free.
    var results = await Future.wait([
      _gh(repoRoot, [
        'pr',
        'list',
        '--state',
        'open',
        '--limit',
        '$openLimit',
        '--json',
        openFields,
      ]),
      _gh(repoRoot, [
        'pr',
        'list',
        '--state',
        'closed',
        '--limit',
        '$closedLimit',
        '--json',
        closedFields,
      ]),
    ]);

    var open = results[0];
    var closed = results[1];

    // The open list is the one that matters. If it failed there is nothing to
    // report; if only the closed window failed, the answer is merely shorter.
    if (open.output == null) {
      return ForgeReport.unavailable(open.failure ?? 'gh could not answer');
    }

    return ForgeReport.ready({
      if (closed.output case var it?) ...parseGitHubPullRequests(it),
      ...parseGitHubPullRequests(open.output!),
    });
  }

  Future<({String? output, String? failure})> _gh(
    String directory,
    List<String> arguments,
  ) async {
    try {
      var result = await _run('gh', arguments, workingDirectory: directory);
      if (result.exitCode != 0) {
        return (output: null, failure: firstLine('${result.stderr}'));
      }
      return (output: '${result.stdout}', failure: null);
    } on ProcessException {
      return (output: null, failure: 'gh is not installed');
    }
  }
}

/// GitLab, via `glab mr list -F json`.
///
/// Shaped from GitLab's documented merge-request payload rather than measured.
/// Every other parser in this directory was checked against real output; this
/// one could not be, for want of a GitLab checkout. It is written to the
/// documented field names, it treats every one of them as optional, and it
/// degrades to no merge requests rather than to an exception — so the cost of
/// being wrong is the column disappearing. The first person with a GitLab
/// remote should check it and delete this paragraph.
///
/// One documented difference from GitHub, not an oversight: the merge-request
/// *list* carries no pipeline, so checks are [ChecksState.none]. Fetching them
/// would be one request per merge request, which is the thing this design
/// refuses to do.
class GitLabForgeProbe implements ForgeProbe {
  GitLabForgeProbe({RunProcess? runProcess}) : _run = runProcess ?? runGitTool;

  final RunProcess _run;

  @override
  Future<ForgeReport> probe(String repoRoot) async {
    var open = await _glab(repoRoot, [
      'mr',
      'list',
      '-F',
      'json',
      '--per-page',
      '100',
    ]);
    if (open.output == null) {
      return ForgeReport.unavailable(open.failure ?? 'glab could not answer');
    }
    var merged = await _glab(repoRoot, [
      'mr',
      'list',
      '-F',
      'json',
      '--merged',
      '--per-page',
      '30',
    ]);

    return ForgeReport.ready({
      if (merged.output case var it?) ...parseGitLabMergeRequests(it),
      ...parseGitLabMergeRequests(open.output!),
    });
  }

  Future<({String? output, String? failure})> _glab(
    String directory,
    List<String> arguments,
  ) async {
    try {
      var result = await _run('glab', arguments, workingDirectory: directory);
      if (result.exitCode != 0) {
        return (output: null, failure: firstLine('${result.stderr}'));
      }
      return (output: '${result.stdout}', failure: null);
    } on ProcessException {
      return (output: null, failure: 'glab is not installed');
    }
  }
}

/// Parses `gh pr list --json …`, keyed by head branch.
///
/// Every field is optional. `gh` is a moving target and this must survive a
/// version that adds, renames or drops one — a pull request it cannot read is
/// skipped, not thrown on.
Map<String, ForgeFacts> parseGitHubPullRequests(String output) {
  var list = _decodeList(output);
  var byBranch = <String, ForgeFacts>{};
  for (var entry in list) {
    if (entry is! Map) continue;
    var pr = entry.cast<String, Object?>();
    var branch = pr['headRefName'] as String?;
    var number = pr['number'];
    if (branch == null || branch.isEmpty || number is! int) continue;

    var (checks, failing) = parseGitHubChecks(pr['statusCheckRollup']);
    byBranch[branch] = ForgeFacts(
      number: number,
      title: pr['title'] as String? ?? '',
      state: _githubState(pr),
      checks: checks,
      failingChecks: failing,
      review: _githubReview(pr['reviewDecision'] as String?),
      url: pr['url'] as String?,
    );
  }
  return byBranch;
}

PrState _githubState(Map<String, Object?> pr) {
  if (pr['isDraft'] == true) return PrState.draft;
  return switch (pr['state']) {
    'MERGED' => PrState.merged,
    'CLOSED' => PrState.closed,
    _ => PrState.open,
  };
}

/// A review decision, from the perspective that applies here: **these are pull
/// requests you opened**, so the question is never "should I review this" but
/// "is someone waiting for me to do something about it".
ReviewState _githubReview(String? decision) => switch (decision) {
  'APPROVED' => ReviewState.approved,
  'CHANGES_REQUESTED' => ReviewState.changesRequested,
  'REVIEW_REQUIRED' => ReviewState.awaiting,
  _ => ReviewState.none,
};

/// Rolls `statusCheckRollup` up into one state and a count of what broke.
///
/// Verified against real output (2026-08-10): entries are `CheckRun` with
/// `status` plus `conclusion`, or `StatusContext` with `state` — the older
/// commit-status API, still emitted by anything integrating that way.
///
/// Worst wins, because that is the one you have to act on. A cancelled or
/// timed-out run counts as failing: it did not pass, and a green row over an
/// unfinished check is the one outcome this column must never produce.
(ChecksState, int) parseGitHubChecks(Object? rollup) {
  if (rollup is! List || rollup.isEmpty) return (ChecksState.none, 0);

  var failing = 0;
  var pending = false;
  var passing = false;
  for (var entry in rollup) {
    if (entry is! Map) continue;
    var check = entry.cast<String, Object?>();
    switch (_checkOutcome(check)) {
      case ChecksState.failing:
        failing++;
      case ChecksState.pending:
        pending = true;
      case ChecksState.passing:
        passing = true;
      case ChecksState.none:
        break;
    }
  }

  if (failing > 0) return (ChecksState.failing, failing);
  if (pending) return (ChecksState.pending, 0);
  return (passing ? ChecksState.passing : ChecksState.none, 0);
}

ChecksState _checkOutcome(Map<String, Object?> check) {
  // A `CheckRun` that has not completed has no conclusion yet, whatever it will
  // eventually conclude.
  if (check['status'] case var status? when status != 'COMPLETED') {
    return ChecksState.pending;
  }
  return switch (check['conclusion'] ?? check['state']) {
    'SUCCESS' || 'NEUTRAL' || 'SKIPPED' => ChecksState.passing,
    'FAILURE' ||
    'ERROR' ||
    'TIMED_OUT' ||
    'CANCELLED' ||
    'STARTUP_FAILURE' ||
    'ACTION_REQUIRED' => ChecksState.failing,
    'PENDING' || 'EXPECTED' || null => ChecksState.pending,
    // A conclusion no version of this code has heard of. Not an outcome we may
    // paint green.
    _ => ChecksState.pending,
  };
}

/// Parses `glab mr list -F json`, keyed by source branch.
///
/// See [GitLabForgeProbe] for what is and is not known about this shape.
Map<String, ForgeFacts> parseGitLabMergeRequests(String output) {
  var list = _decodeList(output);
  var byBranch = <String, ForgeFacts>{};
  for (var entry in list) {
    if (entry is! Map) continue;
    var mr = entry.cast<String, Object?>();
    var branch = mr['source_branch'] as String?;
    var number = mr['iid'];
    if (branch == null || branch.isEmpty || number is! int) continue;

    byBranch[branch] = ForgeFacts(
      number: number,
      title: mr['title'] as String? ?? '',
      state: mr['draft'] == true || mr['work_in_progress'] == true
          ? PrState.draft
          : switch (mr['state']) {
              'merged' => PrState.merged,
              'closed' || 'locked' => PrState.closed,
              _ => PrState.open,
            },
      url: mr['web_url'] as String?,
    );
  }
  return byBranch;
}

List<Object?> _decodeList(String output) {
  try {
    var decoded = jsonDecode(output);
    return decoded is List ? decoded : const [];
  } on FormatException {
    // `gh` printing a warning where JSON was promised, a half-read pipe, a
    // version that answers differently. All of them are "no pull requests".
    return const [];
  }
}

/// The first thing the tool said, for a cell that has one line to explain
/// itself in.
///
/// `gh` is wordy on failure — an auth error runs to a paragraph with a link —
/// and the first line is the sentence.
String firstLine(String stderr) {
  for (var line in stderr.split('\n')) {
    var trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    return trimmed.length > 120 ? '${trimmed.substring(0, 117)}…' : trimmed;
  }
  return 'the forge said nothing';
}

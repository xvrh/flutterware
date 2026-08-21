import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/worktrees/facts.dart';
import 'package:flutterware_app/src/worktrees/providers/forge.dart';

/// Captured from `gh pr list --json …` on 2026-08-10, trimmed to two pull
/// requests and one check each. Not hand-written: every field name and every
/// enum spelling below is one `gh` actually emitted, which is the only reason
/// the parser can be trusted at all.
const _ghOpen = r'''
[{"headRefName":"claude/previews-mcp-agent-analysis-634af1","isDraft":false,
  "number":79,"reviewDecision":"","state":"OPEN",
  "statusCheckRollup":[{"__typename":"CheckRun","completedAt":"2026-08-10T13:15:09Z",
    "conclusion":"SUCCESS","name":"Flutter analyze (beta)","status":"COMPLETED",
    "workflowName":"Flutterware"}],
  "title":"An agent's reply stops repeating itself",
  "url":"https://github.com/xvrh/flutterware/pull/79"},
 {"headRefName":"claude/icons-launcher-plugin-eval-bf200f","isDraft":false,
  "number":78,"reviewDecision":"CHANGES_REQUESTED","state":"OPEN",
  "statusCheckRollup":[{"__typename":"CheckRun","completedAt":"2026-08-10T12:57:01Z",
    "conclusion":"FAILURE","name":"Flutter analyze (beta)","status":"COMPLETED",
    "workflowName":"Flutterware"}],
  "title":"The launcher icon is what the OS shows",
  "url":"https://github.com/xvrh/flutterware/pull/78"}]
''';

const _ghClosed = r'''
[{"headRefName":"claude/worktree-explorer-brainstorm-e5efdc","number":76,
  "state":"MERGED","title":"An entry point says what it runs on",
  "url":"https://github.com/xvrh/flutterware/pull/76"}]
''';

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');

void main() {
  group('the GitHub parser', () {
    test('keys pull requests by their head branch', () {
      var prs = parseGitHubPullRequests(_ghOpen);
      expect(prs.keys, hasLength(2));

      var pr = prs['claude/previews-mcp-agent-analysis-634af1']!;
      expect(pr.number, 79);
      expect(pr.title, "An agent's reply stops repeating itself");
      expect(pr.state, PrState.open);
      expect(pr.checks, ChecksState.passing);
      expect(pr.url, endsWith('/pull/79'));
    });

    test('counts what broke, and reads the review as a job for you', () {
      var pr = parseGitHubPullRequests(
        _ghOpen,
      )['claude/icons-launcher-plugin-eval-bf200f']!;
      expect(pr.checks, ChecksState.failing);
      expect(pr.failingChecks, 1);
      expect(pr.review, ReviewState.changesRequested);
    });

    test('a merged pull request keeps its state', () {
      var pr = parseGitHubPullRequests(
        _ghClosed,
      )['claude/worktree-explorer-brainstorm-e5efdc']!;
      expect(pr.state, PrState.merged);
      expect(pr.checks, ChecksState.none, reason: 'closed PRs are asked less');
    });

    test('a draft is a draft whatever its state says', () {
      var prs = parseGitHubPullRequests(
        '[{"headRefName":"x","number":1,"isDraft":true,"state":"OPEN"}]',
      );
      expect(prs['x']!.state, PrState.draft);
    });

    test('skips what it cannot read rather than throwing', () {
      // A version that renames a field, a pull request with no head branch,
      // and something that is not an object at all.
      var prs = parseGitHubPullRequests(
        '[{"number":1},{"headRefName":"","number":2},'
        '"nonsense",{"headRefName":"ok","number":3}]',
      );
      expect(prs.keys, ['ok']);
    });

    test('output that is not JSON is no pull requests, not a crash', () {
      expect(parseGitHubPullRequests('gh: warning\n'), isEmpty);
      expect(parseGitHubPullRequests(''), isEmpty);
      expect(parseGitHubPullRequests('{"not":"a list"}'), isEmpty);
    });
  });

  group('the checks rollup', () {
    test('is none when there is nothing to roll up', () {
      expect(parseGitHubChecks(null), (ChecksState.none, 0));
      expect(parseGitHubChecks(const []), (ChecksState.none, 0));
    });

    test('lets the worst outcome win', () {
      expect(
        parseGitHubChecks(const [
          {'status': 'COMPLETED', 'conclusion': 'SUCCESS'},
          {'status': 'COMPLETED', 'conclusion': 'FAILURE'},
          {'status': 'IN_PROGRESS'},
          {'status': 'COMPLETED', 'conclusion': 'TIMED_OUT'},
        ]),
        (ChecksState.failing, 2),
      );
    });

    test('a run still going is pending, not passing', () {
      expect(
        parseGitHubChecks(const [
          {'status': 'COMPLETED', 'conclusion': 'SUCCESS'},
          {'status': 'QUEUED'},
        ]),
        (ChecksState.pending, 0),
      );
    });

    test('reads the older commit-status shape too', () {
      expect(
        parseGitHubChecks(const [
          {'__typename': 'StatusContext', 'state': 'SUCCESS'},
        ]),
        (ChecksState.passing, 0),
      );
      expect(
        parseGitHubChecks(const [
          {'__typename': 'StatusContext', 'state': 'ERROR'},
        ]),
        (ChecksState.failing, 1),
      );
    });

    test('a conclusion nobody has heard of is never painted green', () {
      expect(
        parseGitHubChecks(const [
          {'status': 'COMPLETED', 'conclusion': 'SOMETHING_NEW'},
        ]),
        (ChecksState.pending, 0),
      );
    });

    test('skipped and neutral runs pass — they did not fail', () {
      expect(
        parseGitHubChecks(const [
          {'status': 'COMPLETED', 'conclusion': 'SKIPPED'},
          {'status': 'COMPLETED', 'conclusion': 'NEUTRAL'},
        ]),
        (ChecksState.passing, 0),
      );
    });
  });

  group('the GitHub probe', () {
    test('asks once for open and once for closed, and merges them', () async {
      var commands = <List<String>>[];
      var probe = GitHubForgeProbe(
        runProcess: (executable, arguments, {workingDirectory}) async {
          commands.add([executable, ...arguments]);
          return _ok(arguments.contains('open') ? _ghOpen : _ghClosed);
        },
      );

      var report = await probe.probe('/repo');
      expect(report.isReady, isTrue);
      expect(report.pullRequests, hasLength(3));
      expect(commands, hasLength(2));
      expect(
        commands.every((c) => c.first == 'gh' && c.contains('--json')),
        isTrue,
      );
    });

    test(
      'an open pull request wins over a closed one on the same branch',
      () async {
        const branch = 'shared';
        var probe = GitHubForgeProbe(
          runProcess: (executable, arguments, {workingDirectory}) async => _ok(
            arguments.contains('open')
                ? '[{"headRefName":"$branch","number":9,"state":"OPEN"}]'
                : '[{"headRefName":"$branch","number":4,"state":"MERGED"}]',
          ),
        );

        var report = await probe.probe('/repo');
        expect(report.pullRequests[branch]!.number, 9);
        expect(report.pullRequests[branch]!.state, PrState.open);
      },
    );

    test('no gh is unavailable, with a reason a human can act on', () async {
      var probe = GitHubForgeProbe(
        runProcess: (executable, arguments, {workingDirectory}) async =>
            throw ProcessException(executable, arguments, 'not found', 2),
      );

      var report = await probe.probe('/repo');
      expect(report.isReady, isFalse);
      expect(report.unavailable, 'gh is not installed');
      expect(report.pullRequests, isEmpty);
    });

    test('quotes the first line of what gh complained about', () async {
      var probe = GitHubForgeProbe(
        runProcess: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(
              0,
              1,
              '',
              '\ngh: To get started with GitHub CLI, run: gh auth login\n'
                  'Alternatively, set the GH_TOKEN environment variable.\n',
            ),
      );

      var report = await probe.probe('/repo');
      expect(report.unavailable, startsWith('gh: To get started'));
      expect(report.unavailable, isNot(contains('\n')));
    });

    test('a failed closed window only makes the answer shorter', () async {
      var probe = GitHubForgeProbe(
        runProcess: (executable, arguments, {workingDirectory}) async =>
            arguments.contains('open')
            ? _ok(_ghOpen)
            : ProcessResult(0, 1, '', 'rate limited'),
      );

      var report = await probe.probe('/repo');
      expect(report.isReady, isTrue);
      expect(report.pullRequests, hasLength(2));
    });
  });

  group('choosing a forge from the remote', () {
    Future<String> chosen(String? remoteUrl) async {
      var picked = 'neither';
      var probe = RemoteForgeProbe(
        runProcess: (executable, arguments, {workingDirectory}) async =>
            remoteUrl == null
            ? ProcessResult(0, 1, '', '')
            : _ok('$remoteUrl\n'),
        github: _NamingProbe('github', () => picked = 'github'),
        gitlab: _NamingProbe('gitlab', () => picked = 'gitlab'),
      );
      await probe.probe('/repo');
      return picked;
    }

    test('picks gh for a GitHub remote, in either URL spelling', () async {
      expect(await chosen('git@github.com:xvrh/flutterware.git'), 'github');
      expect(await chosen('https://github.com/xvrh/flutterware'), 'github');
    });

    test('picks glab for a GitLab remote', () async {
      expect(await chosen('git@gitlab.com:group/thing.git'), 'gitlab');
      // Self-hosted under its own domain, which is the common enterprise case.
      expect(await chosen('https://gitlab.corp.internal/x/y.git'), 'gitlab');
    });

    test('no remote asks nobody', () async {
      expect(await chosen(null), 'neither');
    });

    test('an unrecognised host tries GitHub, then GitLab', () async {
      var asked = <String>[];
      var probe = RemoteForgeProbe(
        runProcess: (executable, arguments, {workingDirectory}) async =>
            _ok('git@git.example.com:x/y.git\n'),
        github: _NamingProbe('github', () => asked.add('github'), ready: false),
        gitlab: _NamingProbe('gitlab', () => asked.add('gitlab')),
      );
      var report = await probe.probe('/repo');
      expect(asked, ['github', 'gitlab']);
      expect(report.isReady, isTrue);
    });
  });

  group('the GitLab parser', () {
    // Shaped from GitLab's documented merge-request payload rather than from a
    // measured repository — see [GitLabForgeProbe]. What this test pins is that
    // the parser reads that shape and survives anything else.
    test('keys merge requests by their source branch', () {
      var mrs = parseGitLabMergeRequests(r'''
        [{"iid":12,"title":"Add a thing","source_branch":"feature/thing",
          "state":"opened","draft":false,
          "web_url":"https://gitlab.com/g/p/-/merge_requests/12"},
         {"iid":11,"title":"Old","source_branch":"feature/old","state":"merged"}]
      ''');
      expect(mrs.keys, containsAll(['feature/thing', 'feature/old']));
      expect(mrs['feature/thing']!.number, 12);
      expect(mrs['feature/thing']!.state, PrState.open);
      expect(mrs['feature/thing']!.url, endsWith('/merge_requests/12'));
      expect(mrs['feature/old']!.state, PrState.merged);
    });

    test('has no checks to report, and says so rather than guessing', () {
      var mr = parseGitLabMergeRequests(
        '[{"iid":1,"source_branch":"b","state":"opened"}]',
      )['b']!;
      expect(mr.checks, ChecksState.none);
      expect(mr.review, ReviewState.none);
    });

    test('reads a draft under either name GitLab has used', () {
      expect(
        parseGitLabMergeRequests(
          '[{"iid":1,"source_branch":"a","state":"opened","draft":true}]',
        )['a']!.state,
        PrState.draft,
      );
      expect(
        parseGitLabMergeRequests(
          '[{"iid":2,"source_branch":"b","state":"opened",'
          '"work_in_progress":true}]',
        )['b']!.state,
        PrState.draft,
      );
    });
  });

  test('a pull request survives the cache round trip', () {
    const pr = ForgeFacts(
      number: 78,
      title: 'The launcher icon is what the OS shows',
      state: PrState.draft,
      checks: ChecksState.failing,
      failingChecks: 2,
      review: ReviewState.changesRequested,
      url: 'https://example.com/pull/78',
    );
    var back = ForgeFacts.fromJson(pr.toJson());
    expect(back.number, pr.number);
    expect(back.title, pr.title);
    expect(back.state, pr.state);
    expect(back.checks, pr.checks);
    expect(back.failingChecks, pr.failingChecks);
    expect(back.review, pr.review);
    expect(back.url, pr.url);
  });

  test('a cache written by a version that spelled things differently reads '
      'quietly', () {
    var back = ForgeFacts.fromJson(const {
      'number': 3,
      'state': 'ASCENDED',
      'checks': 'confused',
      'review': 'unheard-of',
    });
    expect(back.state, PrState.open);
    expect(back.checks, ChecksState.none);
    expect(back.review, ReviewState.none);
    expect(back.title, isEmpty);
  });
}

class _NamingProbe implements ForgeProbe {
  _NamingProbe(this.name, this.onProbe, {this.ready = true});

  final String name;
  final void Function() onProbe;
  final bool ready;

  @override
  Future<ForgeReport> probe(String repoRoot) async {
    onProbe();
    return ready
        ? const ForgeReport.ready({})
        : const ForgeReport.unavailable('not this one');
  }
}

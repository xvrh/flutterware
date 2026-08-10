import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/worktrees/facts.dart';
import 'package:flutterware_app/src/worktrees/facts_probe.dart';
import 'package:flutterware_app/src/worktrees/facts_store.dart';
import 'package:flutterware_app/src/worktrees/facts_text.dart';
import 'package:flutterware_app/src/worktrees/providers/git.dart';

/// Faked at the process boundary rather than at [GitProbe], so these exercise
/// the real parsers on the way through. A fake probe would test the
/// orchestration against a mock of the thing most likely to be wrong.
({GitProbe probe, List<List<String>> calls}) _git({
  Map<String, String> responses = const {},
}) {
  var calls = <List<String>>[];
  return (
    calls: calls,
    probe: GitProbe(
      runProcess: (executable, arguments, {workingDirectory}) async {
        calls.add(arguments);
        for (var entry in responses.entries) {
          if (arguments.any((a) => a.contains(entry.key))) {
            return ProcessResult(0, 0, entry.value, '');
          }
        }
        return ProcessResult(0, 0, '', '');
      },
    ),
  );
}

Worktree _wt(String name, {String? branch, bool isMain = false}) => Worktree(
  path: '/repo/$name',
  gitName: name,
  branch: branch,
  isMain: isMain,
);

void main() {
  late Directory temp;
  late File cacheFile;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fw-worktrees-test');
    cacheFile = File('${temp.path}/worktrees.json');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  WorktreeFactsStore store() => WorktreeFactsStore.open('/repo', at: cacheFile);

  group('store', () {
    test('a diff round-trips through the file', () {
      var written = store();
      written.putDiff(
        'basesha',
        'headsha',
        CachedDiff(
          shape: ChangeShape(
            files: 3,
            buckets: [const ChangeBucket('app', added: 10, removed: 4)],
          ),
          ahead: 2,
          behind: 1,
        ),
      );
      written.save();

      var read = store();
      var diff = read.diff('basesha', 'headsha')!;
      expect(diff.ahead, 2);
      expect(diff.behind, 1);
      expect(diff.shape.files, 3);
      expect(diff.shape.ranked.single.name, 'app');
    });

    test('a corrupt cache is an empty cache, not a crash', () {
      cacheFile.writeAsStringSync('{ this is not json');
      expect(store().diff('a', 'b'), isNull);
    });

    test('saving into a home that cannot be written does not throw', () {
      var store = WorktreeFactsStore.open(
        '/repo',
        at: File('/proc/definitely/not/writable/worktrees.json'),
      );
      store.putDiff('a', 'b', _emptyDiff);
      expect(store.save, returnsNormally);
    });

    test('eviction bounds a file that only ever grows', () {
      var written = store();
      for (var i = 0; i < 60; i++) {
        written.putDiff('base', 'head$i', _emptyDiff);
      }
      written.evict(keep: 10);
      // The most recent survive; the oldest are dropped.
      expect(written.diff('base', 'head59'), isNotNull);
      expect(written.diff('base', 'head0'), isNull);
    });

    test('the cache path is keyed by the repo, not by a name', () {
      var one = WorktreeFactsStore.fileFor('/repo/a');
      var two = WorktreeFactsStore.fileFor('/repo/b');
      expect(one, isNot(two));
      expect(one, endsWith('worktrees.json'));
    });
  });

  group('probe', () {
    test(
      'batches the branch calls once, whatever the worktree count',
      () async {
        var git = _git(
          responses: {
            'for-each-ref':
                'main\t1786000000\tbasesha\n'
                'feature\t1786000100\theadsha\n',
            'symbolic-ref': 'origin/main\n',
            'status': '# branch.oid headsha\n# branch.head feature\n',
            'rev-list': '0\t3\n',
            'numstat': '10\t4\tapp/a.dart\n',
          },
        );

        await WorktreeFactsProbe(
          repoRoot: '/repo',
          store: store(),
          git: git.probe,
        ).probe([
          _wt('main', branch: 'main', isMain: true),
          _wt('one', branch: 'feature'),
          _wt('two', branch: 'feature'),
        ]);

        var forEachRef = git.calls.where((c) => c.contains('for-each-ref'));
        expect(
          forEachRef,
          hasLength(1),
          reason: 'one call covers every branch',
        );
      },
    );

    test('a cached diff costs no process at all', () async {
      var warmed = store();
      warmed.putDiff('basesha', 'headsha', _emptyDiff);

      var git = _git(
        responses: {
          'for-each-ref':
              'main\t1786000000\tbasesha\n'
              'feature\t1786000100\theadsha\n',
          'symbolic-ref': 'origin/main\n',
          'status': '# branch.oid headsha\n# branch.head feature\n',
        },
      );

      await WorktreeFactsProbe(
        repoRoot: '/repo',
        store: warmed,
        git: git.probe,
      ).probe([_wt('one', branch: 'feature')]);

      expect(git.calls.any((c) => c.contains('numstat')), isFalse);
      expect(git.calls.any((c) => c.contains('rev-list')), isFalse);
    });

    test('the base branch is not diffed against itself', () async {
      var git = _git(
        responses: {
          'for-each-ref': 'main\t1786000000\tbasesha\n',
          'symbolic-ref': 'origin/main\n',
          'status': '# branch.oid basesha\n# branch.head main\n',
        },
      );

      await WorktreeFactsProbe(
        repoRoot: '/repo',
        store: store(),
        git: git.probe,
      ).probe([_wt('main', branch: 'main', isMain: true)]);

      expect(git.calls.any((c) => c.contains('rev-list')), isFalse);
    });

    test(
      'a worktree git cannot read reports as failed, not as clean',
      () async {
        var probe = GitProbe(
          runProcess: (executable, arguments, {workingDirectory}) async =>
              arguments.contains('status')
              ? ProcessResult(0, 128, '', 'fatal: not a git repository')
              : ProcessResult(0, 0, '', ''),
        );

        var facts = await WorktreeFactsProbe(
          repoRoot: '/repo',
          store: store(),
          git: probe,
        ).probe([_wt('gone', branch: 'feature')]);

        expect(facts['/repo/gone']!.git.state, FactState.failed);
        // Not `Fact.fresh(GitFacts())`, which would render as a clean worktree.
        expect(facts['/repo/gone']!.git.hasValue, isFalse);
      },
    );

    test('activity takes the newest clock, and says which', () async {
      var warmed = store();
      var opened = DateTime.fromMillisecondsSinceEpoch(1786000500 * 1000);
      warmed.markOpened('/repo/one', opened);

      var git = _git(
        responses: {
          // Committed *before* it was opened, so `opened` must win.
          'for-each-ref': 'feature\t1786000100\theadsha\n',
          'status': '# branch.oid headsha\n# branch.head feature\n',
        },
      );

      var facts = await WorktreeFactsProbe(
        repoRoot: '/repo',
        store: warmed,
        git: git.probe,
      ).probe([_wt('one', branch: 'feature')]);

      var activity = facts['/repo/one']!.activity.value!;
      expect(activity.source, ActivitySource.opened);
      expect(activity.at, opened);
    });
  });

  group('text', () {
    var now = DateTime(2026, 8, 10, 14, 30);

    test('a column no row fills is not printed', () {
      var lines = worktreeTable([
        (
          _wt('one', branch: 'feature'),
          WorktreeFacts(
            git: const Fact.fresh(GitFacts(dirty: 2)),
            activity: Fact.fresh(
              ActivityFacts(
                at: now.subtract(const Duration(minutes: 5)),
                source: ActivitySource.commit,
              ),
            ),
          ),
        ),
      ], now: now);

      // No agent and no PR anywhere, so neither column takes a single space —
      // which is the same rule that handles a repo with no agents, a machine
      // with no gh, and an agent format that stopped parsing.
      expect(lines.single, 'feature  uncommitted  5m commit');
    });

    test('a branch name is never truncated, and sets the column width', () {
      var long = 'claude/worktree-dynamic-plugins-brainstorm-c0c628';
      // Both rows carry a fact, so there is a second column to line up against.
      // With only the name column, padding it would be trailing whitespace and
      // is trimmed — which is why this needs one.
      var facts = const WorktreeFacts(git: Fact.fresh(GitFacts(dirty: 1)));
      var lines = worktreeTable([
        (_wt('a', branch: long), facts),
        (_wt('b', branch: 'short'), facts),
      ], now: now);

      expect(lines.first, contains(long));
      expect(
        lines[1].indexOf('uncommitted'),
        lines[0].indexOf('uncommitted'),
        reason: 'the short row pads out to the long one',
      );
    });

    test('a failed probe says so rather than showing nothing', () {
      var lines = worktreeTable([
        (
          _wt('a', branch: 'feature'),
          const WorktreeFacts(git: Fact.failed('index.lock exists')),
        ),
      ], now: now);
      expect(lines.single, contains('unreadable'));
    });
  });
}

final _emptyDiff = CachedDiff(
  shape: const ChangeShape(files: 0, buckets: []),
  ahead: 0,
  behind: 0,
);

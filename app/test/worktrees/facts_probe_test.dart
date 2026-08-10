import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/worktrees/facts.dart';
import 'package:flutterware_app/src/worktrees/facts_probe.dart';
import 'package:flutterware_app/src/worktrees/facts_store.dart';
import 'package:flutterware_app/src/worktrees/facts_text.dart';
import 'package:flutterware_app/src/worktrees/providers/forge.dart';
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

/// Counts what it was asked, so a test can prove the TTL saved a round trip.
class _Forge implements ForgeProbe {
  _Forge([this.report = const ForgeReport.ready({})]);

  final ForgeReport report;
  var calls = 0;

  @override
  Future<ForgeReport> probe(String repoRoot) async {
    calls++;
    return report;
  }
}

const _pr = ForgeFacts(
  number: 79,
  title: 'An entry point says what it runs on',
  state: PrState.open,
  checks: ChecksState.failing,
  failingChecks: 1,
);

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
          forge: _Forge(),
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
        forge: _Forge(),
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
        forge: _Forge(),
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
          forge: _Forge(),
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
        forge: _Forge(),
      ).probe([_wt('one', branch: 'feature')]);

      var activity = facts['/repo/one']!.activity.value!;
      expect(activity.source, ActivitySource.opened);
      expect(activity.at, opened);
    });
  });

  group('pull requests', () {
    ({GitProbe probe, List<List<String>> calls}) branches() => _git(
      responses: {
        'for-each-ref': 'feature\t1786000100\theadsha\n',
        'status': '# branch.oid headsha\n# branch.head feature\n',
      },
    );

    test('are joined to worktrees by branch, and cost one call', () async {
      var forge = _Forge(const ForgeReport.ready({'feature': _pr}));

      // Each checkout is on its own branch, which is the whole point of the
      // join — so unlike the other tests here, `status` answers per directory.
      var git = GitProbe(
        runProcess: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(
              0,
              0,
              arguments.contains('status')
                  ? '# branch.oid headsha\n'
                        '# branch.head '
                        '${workingDirectory == '/repo/three' ? 'unpublished' : 'feature'}\n'
                  : '',
              '',
            ),
      );

      var facts =
          await WorktreeFactsProbe(
            repoRoot: '/repo',
            store: store(),
            git: git,
            forge: forge,
          ).probe([
            _wt('one', branch: 'feature'),
            _wt('two', branch: 'feature'),
            _wt('three', branch: 'unpublished'),
          ]);

      expect(forge.calls, 1, reason: 'one sweep covers the repository');
      expect(facts['/repo/one']!.forge.value!.number, 79);
      expect(facts['/repo/two']!.forge.value!.number, 79);

      // A branch with no pull request has nothing to know, which is not the
      // same as a probe that broke.
      expect(facts['/repo/three']!.forge.state, FactState.unavailable);
      expect(facts['/repo/three']!.forge.failure, contains('no pull request'));
    });

    test('a failing check is what makes a worktree need you', () async {
      var facts = await WorktreeFactsProbe(
        repoRoot: '/repo',
        store: store(),
        git: branches().probe,
        forge: _Forge(const ForgeReport.ready({'feature': _pr})),
      ).probe([_wt('one', branch: 'feature')]);

      expect(facts['/repo/one']!.needsYou, isTrue);
    });

    test('no forge is a quiet dash on every row, never a failure', () async {
      var facts = await WorktreeFactsProbe(
        repoRoot: '/repo',
        store: store(),
        git: branches().probe,
        forge: _Forge(const ForgeReport.unavailable('gh is not installed')),
      ).probe([_wt('one', branch: 'feature')]);

      var fact = facts['/repo/one']!.forge;
      expect(fact.state, FactState.unavailable);
      expect(fact.state, isNot(FactState.failed));
      expect(fact.failure, 'gh is not installed');
      expect(facts['/repo/one']!.needsYou, isFalse);
    });

    test('a probe that throws anyway does not take the sweep down', () async {
      var facts = await WorktreeFactsProbe(
        repoRoot: '/repo',
        store: store(),
        git: branches().probe,
        forge: _ThrowingForge(),
      ).probe([_wt('one', branch: 'feature')]);

      expect(facts['/repo/one']!.forge.state, FactState.unavailable);
      expect(facts['/repo/one']!.git.hasValue, isTrue);
    });

    test('are believed for the TTL, and asked again past it', () async {
      var warmed = store();
      var forge = _Forge(const ForgeReport.ready({'feature': _pr}));
      var clock = DateTime(2026, 8, 10, 14, 30);

      Future<Map<String, WorktreeFacts>> sweep({bool refresh = false}) =>
          WorktreeFactsProbe(
            repoRoot: '/repo',
            store: warmed,
            git: branches().probe,
            forge: forge,
            forgeTtl: const Duration(minutes: 5),
            now: () => clock,
          ).probe([_wt('one', branch: 'feature')], refreshForge: refresh);

      await sweep();
      expect(forge.calls, 1);

      // Glancing at the screen again a minute later.
      clock = clock.add(const Duration(minutes: 1));
      var second = await sweep();
      expect(forge.calls, 1, reason: 'still inside the TTL');
      expect(second['/repo/one']!.forge.value!.number, 79);
      expect(
        second['/repo/one']!.forge.computedAt,
        DateTime(2026, 8, 10, 14, 30),
        reason: 'the row shows when it was answered, not when it was read',
      );

      // The button, which means now.
      var third = await sweep(refresh: true);
      expect(forge.calls, 2);
      expect(
        third['/repo/one']!.forge.computedAt,
        clock,
        reason: 'a forced answer is stamped now',
      );

      clock = clock.add(const Duration(minutes: 6));
      await sweep();
      expect(forge.calls, 3, reason: 'past the TTL, ask again');
    });

    test('survive a relaunch inside the TTL', () async {
      var forge = _Forge(const ForgeReport.ready({'feature': _pr}));
      var clock = DateTime(2026, 8, 10, 14, 30);

      await WorktreeFactsProbe(
        repoRoot: '/repo',
        store: store(),
        git: branches().probe,
        forge: forge,
        now: () => clock,
      ).probe([_wt('one', branch: 'feature')]);

      // A second process, reading the file the first one wrote.
      var facts = await WorktreeFactsProbe(
        repoRoot: '/repo',
        store: store(),
        git: branches().probe,
        forge: forge,
        now: () => clock.add(const Duration(minutes: 1)),
      ).probe([_wt('one', branch: 'feature')]);

      expect(forge.calls, 1, reason: 'the cache outlives the process');
      expect(facts['/repo/one']!.forge.value!.number, 79);
      expect(facts['/repo/one']!.forge.value!.failingChecks, 1);
    });

    test('an undated cache is not believed', () async {
      var warmed = store();
      warmed.putPullRequests({'feature': _pr}, DateTime(2026, 8, 10));
      warmed.save();
      // A file written by something that lost the stamp — the one shape that
      // would otherwise read as current forever.
      var text = cacheFile.readAsStringSync().replaceAll(
        RegExp('"at":"[^"]*"'),
        '"at":"not a date"',
      );
      cacheFile.writeAsStringSync(text);

      expect(store().pullRequests(), isNull);
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

class _ThrowingForge implements ForgeProbe {
  @override
  Future<ForgeReport> probe(String repoRoot) async =>
      throw StateError('the forge exploded');
}

final _emptyDiff = CachedDiff(
  shape: const ChangeShape(files: 0, buckets: []),
  ahead: 0,
  behind: 0,
);

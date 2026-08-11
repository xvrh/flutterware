import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_summary.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/changes/ranking.dart';
import 'package:flutterware_app/src/ui/theme.dart';
import 'package:flutterware_app/src/worktrees/facts.dart';

/// The explorer's third rung: **which files, ranked**, in about 420 px.
///
/// The states worth pinning are the ones a happy path never produces — the
/// moment before the probe returns, a branch with more files than the caps, and
/// a checkout whose interesting file is not tracked yet.
void main() {
  FileChange file(
    String path, {
    ChangeStatus status = ChangeStatus.modified,
    int added = 10,
    int removed = 2,
  }) => FileChange(
    path: path,
    status: status,
    added: added,
    removed: removed,
    hunks: const [],
    byteStart: 0,
    byteEnd: 0,
  );

  Ranking rankingOf(List<FileChange> files, Map<String, RankTier> tiers) =>
      Ranking([
        for (var f in files)
          RankedFile(
            file: f,
            tier: tiers[f.path] ?? RankTier.ordinary,
            rule: tiers.containsKey(f.path) ? '**/migrations/**' : null,
            source: RankSource.project,
          ),
      ]);

  ChangeSet setOf({
    List<FileChange> files = const [],
    Set<String> uncommitted = const {},
    List<UntrackedEntry> untracked = const [],
    Ranking? ranking,
    String? base = 'master',
    BaseSource source = BaseSource.inferred,
  }) => ChangeSet(
    worktreePath: '/repo/feature',
    patch: PatchIndex.empty,
    files: files,
    base: base,
    baseSource: source,
    uncommitted: uncommitted,
    untracked: untracked,
    ranking: ranking,
  );

  Future<void> pump(
    WidgetTester tester,
    ChangeSet set, {
    Completer<void>? gate,
    Fact<GitFacts>? git,
    VoidCallback? onOpen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: Center(
            child: ChangesSummaryCard(
              worktreePath: '/repo/feature',
              git: git,
              onOpen: onOpen,
              load: (_) async {
                if (gate != null) await gate.future;
                return set;
              },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the header is drawn from the row before the probe returns', (
    tester,
  ) async {
    // A popover that opens on a spinner has told you nothing you were not
    // already looking at.
    var gate = Completer<void>();
    await pump(
      tester,
      setOf(files: [file('lib/a.dart')]),
      gate: gate,
      git: Fact.fresh(
        const GitFacts(
          dirty: 3,
          base: 'master',
          changes: ChangeShape(
            files: 12,
            buckets: [ChangeBucket('lib', added: 200, removed: 40)],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('12 files'), findsOneWidget);
    expect(find.text('+200'), findsOneWidget);
    expect(find.text('· 3 uncommitted'), findsOneWidget);
    expect(find.text('base master'), findsOneWidget);
    expect(find.text('Reading the files…'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Reading the files…'), findsNothing);
    expect(find.text('a.dart'), findsOneWidget);
  });

  testWidgets('with nothing cached it still says which checkout it is', (
    tester,
  ) async {
    var gate = Completer<void>();
    await pump(tester, setOf(), gate: gate);
    await tester.pump();
    // No git fact at all — the row had nothing either. It must not throw.
    expect(find.text('—'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('pinned files lead, and name the rule that pinned them', (
    tester,
  ) async {
    var files = [
      file('app/lib/src/motion/timeline.dart', added: 140, removed: 22),
      file('db/migrations/0042_stream_log.sql', added: 8, removed: 0),
    ];
    await pump(
      tester,
      setOf(
        files: files,
        uncommitted: {'db/migrations/0042_stream_log.sql'},
        ranking: rankingOf(files, {
          'db/migrations/0042_stream_log.sql': RankTier.attention,
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LOOK HERE FIRST'), findsOneWidget);
    expect(find.text('matches **/migrations/** · uncommitted'), findsOneWidget);

    // The 8-line migration is drawn above the 162-line file, which is the whole
    // claim: any sort by size inverts them.
    var pinned = tester.getTopLeft(find.text('0042_stream_log.sql'));
    var big = tester.getTopLeft(find.text('timeline.dart'));
    expect(pinned.dy, lessThan(big.dy));
  });

  testWidgets('the name is never the part that is truncated', (tester) async {
    // A plain `overflow: ellipsis` cuts the tail, which is the half that
    // identifies the file — four rows all reading `app/lib/src/mot…`.
    await pump(
      tester,
      setOf(files: [file('app/lib/src/plugins/native/previews_core.dart')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('previews_core.dart'), findsOneWidget);
    expect(find.text('app/lib/src/plugins/native/'), findsOneWidget);
  });

  testWidgets('the list stops, and says how much it stopped short of', (
    tester,
  ) async {
    var files = [for (var i = 0; i < 11; i++) file('lib/f$i.dart', added: i)];
    await pump(tester, setOf(files: files));
    await tester.pumpAndSettle();

    expect(find.text('BIGGEST'), findsOneWidget);
    // Six drawn, five accounted for — a glance, not a list, and the link to the
    // full one is right there.
    expect(find.text('… 5 more'), findsOneWidget);
    expect(find.text('f10.dart'), findsOneWidget);
    expect(find.text('f0.dart'), findsNothing);
  });

  testWidgets('noise is a tally, never a row', (tester) async {
    var files = [
      file('lib/real.dart'),
      file('lib/a.g.dart', added: 100, removed: 90),
      file('lib/b.g.dart', added: 110, removed: 88),
    ];
    await pump(
      tester,
      setOf(
        files: files,
        ranking: rankingOf(files, {
          'lib/a.g.dart': RankTier.noise,
          'lib/b.g.dart': RankTier.noise,
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 low-signal files hidden, +210 -178'), findsOneWidget);
    expect(find.text('a.g.dart'), findsNothing);
  });

  testWidgets('the tallies survive a branch long enough to scroll', (
    tester,
  ) async {
    // **Found by capping the card's height and looking at it.** The tallies are
    // true of the whole delta, like the header — but they were the last thing
    // in the scrolling body, so a checkout with eleven low-signal files pushed
    // the line saying so straight out of sight.
    var files = [
      for (var i = 0; i < 12; i++) file('lib/big$i.dart', added: 100 + i),
      for (var i = 0; i < 11; i++) file('lib/gen$i.g.dart', added: 5),
    ];
    await pump(
      tester,
      setOf(
        files: files,
        untracked: const [UntrackedEntry('scratch.txt')],
        ranking: rankingOf(files, {
          for (var i = 0; i < 11; i++) 'lib/gen$i.g.dart': RankTier.noise,
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('11 low-signal files hidden, +55 -22'), findsOneWidget);
    expect(find.text('1 untracked'), findsOneWidget);
    // …and the list itself did give way, which is what made room for them.
    expect(find.text('… 6 more'), findsOneWidget);
  });

  testWidgets('a pinned untracked file is in the pinned section', (
    tester,
  ) async {
    // The motivating case: an agent wrote a migration and has not staged it.
    await pump(
      tester,
      setOf(
        files: [file('lib/a.dart')],
        untracked: const [
          UntrackedEntry(
            'db/migrations/0043_new.sql',
            reason: 'matches **/migrations/**',
          ),
          UntrackedEntry('scratch.txt'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LOOK HERE FIRST'), findsOneWidget);
    expect(find.text('0043_new.sql'), findsOneWidget);
    expect(
      find.text('matches **/migrations/** · not tracked yet'),
      findsOneWidget,
    );
    // The ordinary untracked file is a tally, not a row — this is a glance.
    expect(find.text('1 untracked'), findsOneWidget);
    expect(find.text('scratch.txt'), findsNothing);
  });

  testWidgets('a checkout with nothing in it says so', (tester) async {
    await pump(tester, setOf());
    await tester.pumpAndSettle();
    expect(find.text('Nothing changed against master.'), findsOneWidget);
  });

  testWidgets('no base is reported, never papered over', (tester) async {
    await pump(
      tester,
      setOf(files: [file('lib/a.dart')], base: null, source: BaseSource.none),
    );
    await tester.pumpAndSettle();
    expect(find.text('no base branch'), findsOneWidget);
  });

  testWidgets('the footer opens the full screen', (tester) async {
    var opened = 0;
    await pump(
      tester,
      setOf(files: [file('lib/a.dart')]),
      onOpen: () => opened++,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open changes'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('a probe that failed says so instead of showing nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: Center(
            child: ChangesSummaryCard(
              worktreePath: '/repo/gone',
              load: (_) async => throw StateError('the checkout vanished'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('the checkout vanished'), findsOneWidget);
  });
}

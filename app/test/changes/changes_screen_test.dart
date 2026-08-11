import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_screen.dart';
import 'package:flutterware_app/src/changes/changes_config_cache.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/changes/ranking.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// The states a happy path never produces are the point of this file: no base,
/// a refused patch, an untracked directory, and the moment before anything has
/// loaded.
void main() {
  var worktree = const Worktree(
    path: '/wt/feature',
    gitName: 'feature',
    branch: 'claude/feature',
  );

  FileChange file(
    String path, {
    ChangeStatus status = ChangeStatus.modified,
    int added = 0,
    int removed = 0,
    String? from,
    int hunks = 1,
  }) => FileChange(
    path: path,
    oldPath: from,
    status: status,
    added: added,
    removed: removed,
    hunks: [
      for (var i = 0; i < hunks; i++)
        HunkSpan(
          oldStart: 1,
          oldCount: 1,
          newStart: 1,
          newCount: 1,
          added: 1,
          removed: 0,
          byteStart: 0,
          byteEnd: 0,
        ),
    ],
    byteStart: 0,
    byteEnd: 0,
  );

  Future<void> pump(
    WidgetTester tester,
    ChangeSet set, {
    Completer<void>? gate,
    bool isOpen = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: ChangesScreen(
            worktree: worktree,
            isOpen: isOpen,
            load: (_) async {
              if (gate != null) await gate.future;
              return set;
            },
          ),
        ),
      ),
    );
  }

  ChangeSet setOf({
    List<FileChange> files = const [],
    Set<String> uncommitted = const {},
    List<UntrackedEntry> untracked = const [],
    String? base = 'master',
    BaseSource source = BaseSource.inferred,
    ChangesRefusal? refusal,
    Ranking? ranking,
    ChangesConfigState configState = ChangesConfigState.none,
  }) => ChangeSet(
    worktreePath: worktree.path,
    patch: PatchIndex.empty,
    files: files,
    base: base,
    baseSource: source,
    uncommitted: uncommitted,
    untracked: untracked,
    refusal: refusal,
    ranking: ranking,
    configState: configState,
  );

  testWidgets('says which checkout it is before anything has loaded', (
    tester,
  ) async {
    // A screen that opens on a spinner tells you nothing you did not know.
    var gate = Completer<void>();
    await pump(tester, setOf(), gate: gate);

    expect(find.text('Changes'), findsOneWidget);
    expect(find.text(worktree.displayName), findsOneWidget);
    expect(find.text('Reading…'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Reading…'), findsNothing);
  });

  testWidgets('lists files with their counts, deletions first', (tester) async {
    await pump(
      tester,
      setOf(
        files: [
          file('lib/big.dart', added: 140, removed: 22),
          // Additions here too, so the header's total (+145) cannot be mistaken
          // for this row's (+140) by a text finder.
          file(
            'lib/gone.dart',
            status: ChangeStatus.deleted,
            added: 5,
            removed: 88,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('gone.dart'), findsOneWidget);
    expect(find.text('big.dart'), findsOneWidget);
    expect(find.text('+140'), findsOneWidget);
    expect(find.text('-88'), findsOneWidget);

    // Ranked: the deletion is the line most worth seeing.
    expect(
      tester.getTopLeft(find.text('gone.dart')).dy,
      lessThan(tester.getTopLeft(find.text('big.dart')).dy),
    );
  });

  testWidgets('an uncommitted file says so; a rename says where from', (
    tester,
  ) async {
    await pump(
      tester,
      setOf(
        files: [
          file('lib/a.dart', added: 1),
          file(
            'lib/new.dart',
            status: ChangeStatus.renamed,
            from: 'lib/old.dart',
          ),
        ],
        uncommitted: {'lib/a.dart'},
      ),
    );
    await tester.pumpAndSettle();

    // Scoped to the index, because the header's summary says "1 uncommitted"
    // too — an unscoped finder here passes without testing its own claim.
    expect(
      find.descendant(
        of: find.byKey(changesListKey),
        matching: find.textContaining('uncommitted'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('from lib/old.dart'), findsOneWidget);

    // …and the directory is on its own line, not trailing the flags, which is
    // what made *where a file lives* the first thing to be truncated.
    expect(
      find.descendant(
        of: find.byKey(changesListKey),
        matching: find.text('lib'),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('the base and where it came from are always shown', (
    tester,
  ) async {
    await pump(tester, setOf(files: [file('a.dart')]));
    await tester.pumpAndSettle();
    expect(find.text('base master (inferred)'), findsOneWidget);
  });

  testWidgets('no base explains itself rather than diffing against a guess', (
    tester,
  ) async {
    await pump(
      tester,
      setOf(files: [file('a.dart')], base: null, source: BaseSource.none),
    );
    await tester.pumpAndSettle();

    expect(find.text('no base'), findsOneWidget);
    expect(find.textContaining('none of origin/HEAD'), findsOneWidget);
  });

  testWidgets('an untracked directory is one row and is never counted', (
    tester,
  ) async {
    // The branch-switch trap, at the widget layer: a count would be the
    // directory walk that keeping this to one row exists to avoid.
    await pump(
      tester,
      setOf(
        files: [file('a.dart')],
        untracked: const [UntrackedEntry.directory('packages/newpkg/build/')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('packages/newpkg/build/'), findsOneWidget);
    expect(find.text('directory, not scanned'), findsOneWidget);
    expect(find.textContaining('files'), findsWidgets); // the header only
  });

  testWidgets('a refused patch says how big it was', (tester) async {
    await pump(
      tester,
      setOf(
        files: [file('a.dart')],
        refusal: const ChangesRefusal(patchBytes: 80 * 1024 * 1024),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('80.0 MB'), findsOneWidget);
    expect(find.textContaining('file list only'), findsOneWidget);
  });

  testWidgets('a clean checkout says so instead of showing an empty page', (
    tester,
  ) async {
    await pump(tester, setOf());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Nothing changed against master'),
      findsOneWidget,
    );
  });

  testWidgets('a failed read keeps the last good answer beside the reason', (
    tester,
  ) async {
    var fail = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: ChangesScreen(
            worktree: worktree,
            load: (_) async {
              if (fail) throw StateError('the checkout vanished');
              return setOf(files: [file('lib/a.dart', added: 3)]);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('a.dart'), findsOneWidget);

    fail = true;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.textContaining('the checkout vanished'), findsOneWidget);
    expect(
      find.text('a.dart'),
      findsOneWidget,
      reason: 'a failed reload must not blank what it last said',
    );
  });

  group('ranking, on screen', () {
    Ranking rankingOf(List<FileChange> files, Map<String, RankTier> tiers) =>
        Ranking([
          for (var file in files)
            RankedFile(
              file: file,
              tier: tiers[file.path] ?? RankTier.ordinary,
              rule: tiers.containsKey(file.path) ? '**/*.g.dart' : null,
              source: RankSource.project,
            ),
        ]);

    testWidgets('the drawer stands in for the noise, and opens', (
      tester,
    ) async {
      var files = [
        file('lib/real.dart', added: 12, removed: 3),
        file('lib/model.g.dart', added: 400, removed: 380),
      ];
      await pump(
        tester,
        setOf(
          files: files,
          ranking: rankingOf(files, {'lib/model.g.dart': RankTier.noise}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 low-signal file'), findsOneWidget);
      expect(find.text('model.g.dart'), findsNothing);
      expect(find.text('real.dart'), findsOneWidget);

      await tester.tap(find.text('1 low-signal file'));
      await tester.pumpAndSettle();
      expect(find.text('model.g.dart'), findsOneWidget);
    });

    testWidgets('a pinned file leads, and names the rule that pinned it', (
      tester,
    ) async {
      var files = [
        file('lib/huge.dart', added: 900, removed: 900),
        file('db/migrations/1.sql', added: 2, removed: 0),
      ];
      await pump(
        tester,
        setOf(
          files: files,
          ranking: rankingOf(files, {
            'db/migrations/1.sql': RankTier.attention,
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Look here first'), findsOneWidget);
      expect(find.textContaining('matches **/*.g.dart'), findsOneWidget);

      // The small pinned file is drawn above the 1800-line one — which is the
      // whole claim, since every other sort would invert them.
      var pinned = tester.getTopLeft(find.text('1.sql'));
      var big = tester.getTopLeft(find.text('huge.dart'));
      expect(pinned.dy, lessThan(big.dy));
    });

    testWidgets('a stale config is said out loud', (tester) async {
      await pump(
        tester,
        setOf(
          files: [file('lib/a.dart')],
          configState: ChangesConfigState.stale,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('changed since'), findsOneWidget);
    });

    testWidgets('a fresh one says nothing at all', (tester) async {
      // A screen that narrates its cache on every load is one whose important
      // message goes unread.
      await pump(
        tester,
        setOf(
          files: [file('lib/a.dart')],
          configState: ChangesConfigState.fresh,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('changed since'), findsNothing);
    });

    testWidgets('the header total counts the noise it is not showing', (
      tester,
    ) async {
      var files = [
        file('lib/real.dart', added: 1),
        file('a.g.dart', added: 1),
        file('b.g.dart', added: 1),
      ];
      await pump(
        tester,
        setOf(
          files: files,
          ranking: rankingOf(files, {
            'a.g.dart': RankTier.noise,
            'b.g.dart': RankTier.noise,
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 files'), findsOneWidget);
      expect(find.text('2 low-signal files'), findsOneWidget);
    });
  });
}

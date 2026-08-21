import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_screen.dart';
import 'package:flutterware_app/src/changes/changes_tree.dart';
import 'package:flutterware_app/src/changes/diff_view.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/changes/ranking.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// Structure, which the ranked list could not carry. A flat column of
/// fifty-three basenames answers "what should I look at" and says nothing about
/// the shape of the branch. The tree was dropped in the master/detail rewrite
/// and put back the same day.
///
/// The interesting half is how it coexists with the ranking rather than
/// competing with it: pinned files stay in a band above, and inside the tree
/// the order is **weight**, not the alphabet.
void main() {
  FileChange at(
    String path, {
    int added = 10,
    int removed = 0,
    ChangeStatus status = ChangeStatus.modified,
  }) => FileChange(
    path: path,
    status: status,
    added: added,
    removed: removed,
    hunks: const [],
    byteStart: 0,
    byteEnd: 0,
  );

  group('the model', () {
    test('single-child directories fold into one row', () {
      var tree = buildTree([
        at('app/lib/src/a.dart'),
        at('app/lib/src/b.dart'),
      ]);
      expect(tree.sortedChildren.single.name, 'app/lib/src');
    });

    test('a fork stops the folding', () {
      var tree = buildTree([at('app/lib/a.dart'), at('app/test/b.dart')]);
      expect(tree.sortedChildren.single.name, 'app');
      expect(
        tree.sortedChildren.single.sortedChildren.map((c) => c.name),
        containsAll(['lib', 'test']),
      );
    });

    test('counts are totals, not just what is directly inside', () {
      var tree = buildTree([
        at('app/lib/a.dart'),
        at('app/lib/deep/b.dart'),
        at('app/lib/deep/c.dart'),
      ]);
      expect(tree.sortedChildren.single.totalFiles, 3);
    });

    test('directories sort by weight, so the hammered module leads', () {
      // **The one change from the version that was deleted.** Alphabetical is
      // right for a file explorer, where you know the name you want. Here you
      // do not, which is the whole reason the screen exists.
      var tree = buildTree([
        at('alpha/small.dart', added: 2),
        at('zulu/huge.dart', added: 900),
      ]);
      expect(tree.sortedChildren.map((c) => c.name), ['zulu', 'alpha']);
    });

    test('files sort by weight too, with deletions promoted', () {
      // Same rule the flat list had: `D −88` is the line most worth seeing, and
      // a plain churn sort buries it under three larger edits.
      var tree = buildTree([
        at('lib/big.dart', added: 400),
        at(
          'lib/gone.dart',
          added: 0,
          removed: 12,
          status: ChangeStatus.deleted,
        ),
        at('lib/small.dart', added: 3),
      ]);
      expect(tree.sortedChildren.single.sortedFiles.map((f) => f.path), [
        'lib/gone.dart',
        'lib/big.dart',
        'lib/small.dart',
      ]);
    });

    test('equal weight falls back to the name, so the order is stable', () {
      var tree = buildTree([
        at('b/x.dart', added: 0),
        at('a/y.dart', added: 0),
      ]);
      expect(tree.sortedChildren.map((c) => c.name), ['a', 'b']);
    });
  });

  group('on screen', () {
    var worktree = const Worktree(
      path: '/wt/feature',
      gitName: 'feature',
      branch: 'claude/feature',
    );

    late ChangeSet current;

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme,
          home: Scaffold(
            body: ChangesScreen(
              worktree: worktree,
              live: false,
              load: (_) async => current,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ChangeSet setOf(List<FileChange> files, {Ranking? ranking}) => ChangeSet(
      worktreePath: worktree.path,
      patch: PatchIndex.empty,
      base: 'master',
      baseSource: BaseSource.inferred,
      files: files,
      ranking: ranking,
    );

    testWidgets('the shape of the branch is on screen', (tester) async {
      current = setOf([
        at('app/lib/a.dart'),
        at('app/lib/b.dart'),
        at('docs/design.md'),
      ]);
      await pump(tester);

      expect(find.text('app/lib'), findsOneWidget);
      expect(find.text('docs'), findsOneWidget);
      // The count is the thing a flat list cannot say.
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets(
      'a file in the tree is selectable, and does not repeat its path',
      (tester) async {
        current = setOf([at('app/lib/a.dart')]);
        await pump(tester);

        await tester.tap(
          find.descendant(
            of: find.byKey(changesListKey),
            matching: find.text('a.dart'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(changesFileKey), findsOneWidget);

        // `app/lib` is the folder row; the file under it does not say it again.
        expect(
          find.descendant(
            of: find.byKey(changesListKey),
            matching: find.text('app/lib'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a pinned file is in Important and also where it lives', (
      tester,
    ) async {
      // Taking pins *out* of the tree to avoid listing a file twice made the
      // tree an incomplete map: its counts came out one short per pin, so the
      // header said 53 over a tree totalling 52, and browsing to the pinned
      // file could not find it. The Important tab is a view onto the tree, not
      // a removal from it.
      var files = [at('app/lib/a.dart'), at('db/migrations/2.sql', added: 4)];
      current = setOf(
        files,
        ranking: Ranking([
          for (var f in files)
            RankedFile(
              file: f,
              tier: f.path.endsWith('.sql')
                  ? RankTier.attention
                  : RankTier.ordinary,
              rule: f.path.endsWith('.sql') ? '**/migrations/**' : null,
            ),
        ]),
      );
      await pump(tester);

      // It opens on Important, where the pin is one flat row carrying its own
      // directory line — the tab is all pins, so nothing there is flagged.
      expect(find.text('2.sql'), findsOneWidget);
      expect(find.text('matches **/migrations/**'), findsOneWidget);
      expect(find.text('db/migrations'), findsOneWidget);
      expect(find.text('app/lib'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      // The tree is a complete map: both directories, one file each, and the
      // pinned one flagged where it lives.
      expect(find.text('2.sql'), findsOneWidget);
      expect(find.text('app/lib'), findsOneWidget);
      expect(find.text('db/migrations'), findsOneWidget);
      expect(
        tester
            .widgetList<IndexFileRow>(find.byType(IndexFileRow))
            .where((r) => r.pinned),
        hasLength(1),
      );
    });

    testWidgets('folders open one level down, and can be shut', (tester) async {
      current = setOf([at('app/lib/deep/a.dart'), at('app/test/b.dart')]);
      await pump(tester);

      // Depth 0 is the root, so the first folder anybody sees is depth 1 —
      // off by that one and every top-level folder opens shut, which looks
      // exactly like an empty index.
      expect(find.text('app'), findsOneWidget);
      expect(find.text('lib/deep'), findsOneWidget);

      await tester.tap(find.text('app'));
      await tester.pumpAndSettle();
      expect(find.text('lib/deep'), findsNothing);
    });
  });
}

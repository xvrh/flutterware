import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_screen.dart';
import 'package:flutterware_app/src/changes/diff_view.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// **Selection is the whole interaction.** One file is showing, the address
/// says which, and the index says the same. Everything the old screen got wrong
/// here — a click that scrolled instead of opening, a file that could only be
/// reached by scrolling past another one's diff — was a consequence of not
/// having this.
void main() {
  var worktree = const Worktree(
    path: '/wt/feature',
    gitName: 'feature',
    branch: 'claude/feature',
  );

  FileChange file(String path, {int added = 10}) => FileChange(
    path: path,
    status: ChangeStatus.modified,
    added: added,
    removed: 0,
    hunks: [
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

  late List<String?> addressed;
  late ChangeSet current;

  ChangeSet setOf(
    List<FileChange> files, {
    List<UntrackedEntry> untracked = const [],
  }) => ChangeSet(
    worktreePath: worktree.path,
    patch: PatchIndex.empty,
    base: 'master',
    baseSource: BaseSource.inferred,
    files: files,
    untracked: untracked,
  );

  Future<void> pump(WidgetTester tester, {String? initialPath}) async {
    addressed = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: ChangesScreen(
            worktree: worktree,
            live: false,
            initialPath: initialPath,
            onPathChanged: addressed.add,
            load: (_) async => current,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inIndex(String text) => find.descendant(
    of: find.byKey(changesListKey),
    matching: find.text(text),
  );

  setUp(
    () => current = setOf([
      file('lib/alpha.dart', added: 90),
      file('lib/beta.dart', added: 60),
    ]),
  );

  testWidgets('the screen opens on the index, not on a file', (tester) async {
    // **Nothing is auto-selected**, tempting as it is: the screen's claim is
    // that it knows what to look at first, so opening straight into the
    // top-ranked file would seem to follow. It does not. The first question is
    // the *shape* of what an agent did, which is the index; reading a file is
    // the second question, and one you should have asked.
    await pump(tester);
    expect(find.text('Pick a file'), findsOneWidget);
    expect(addressed, isEmpty, reason: 'and the address was not rewritten');
  });

  testWidgets('picking a file writes it into the address', (tester) async {
    await pump(tester);
    await tester.tap(inIndex('beta.dart'));
    await tester.pumpAndSettle();

    expect(addressed, ['lib/beta.dart']);
  });

  testWidgets('an address that names a file opens on it', (tester) async {
    // What makes a file's diff something you can paste to somebody.
    await pump(tester, initialPath: 'lib/beta.dart');
    expect(find.textContaining('@@'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(changesFileKey),
        matching: find.textContaining('@@'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a selection that is no longer in the delta says so', (
    tester,
  ) async {
    // The live case: an agent committed the file away, or reverted it. Falling
    // silently back to nothing would look like the app forgetting.
    await pump(tester, initialPath: 'lib/gone.dart');
    expect(find.text('lib/gone.dart'), findsOneWidget);
    expect(find.textContaining('no longer part of the delta'), findsOneWidget);
  });

  testWidgets('an untracked file explains itself instead of showing a diff', (
    tester,
  ) async {
    current = setOf(
      [file('lib/alpha.dart')],
      untracked: const [UntrackedEntry('scratch.txt')],
    );
    await pump(tester);
    await tester.tap(inIndex('scratch.txt'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not tracked yet'), findsOneWidget);
    expect(find.textContaining('@@'), findsNothing);
  });

  testWidgets('an untracked directory opens nothing at all', (tester) async {
    // Reading it would be the walk that keeping it to one row exists to avoid.
    current = setOf(
      [file('lib/alpha.dart')],
      untracked: const [UntrackedEntry.directory('packages/newpkg/build/')],
    );
    await pump(tester);
    await tester.tap(inIndex('packages/newpkg/build/'));
    await tester.pumpAndSettle();

    expect(find.text('Pick a file'), findsOneWidget);
    expect(addressed, isEmpty);
  });

  group('the lenses', () {
    // **The answer to "filter this huge list down to what matters".** The
    // pinned band says what a *rule* declared important; these two say what is
    // fresh and what is skippable, which are the other two questions a
    // fifty-file branch raises. Counts on both, because the count is the
    // information: `11 low-signal` says the branch is mostly generated code.

    testWidgets("uncommitted narrows the index to the agent's fresh work", (
      tester,
    ) async {
      current = ChangeSet(
        worktreePath: worktree.path,
        patch: PatchIndex.empty,
        base: 'master',
        baseSource: BaseSource.inferred,
        files: [file('lib/fresh.dart'), file('lib/landed.dart')],
        uncommitted: {'lib/fresh.dart'},
        untracked: const [UntrackedEntry('scratch.txt')],
      );
      await pump(tester);
      expect(inIndex('landed.dart'), findsOneWidget);

      await tester.tap(find.widgetWithText(IndexLens, 'uncommitted'));
      await tester.pumpAndSettle();

      expect(inIndex('fresh.dart'), findsOneWidget);
      expect(inIndex('landed.dart'), findsNothing);
      expect(
        inIndex('scratch.txt'),
        findsOneWidget,
        reason: 'an untracked file is the most uncommitted thing on the screen',
      );
    });

    testWidgets('its count includes the untracked, and it toggles back', (
      tester,
    ) async {
      current = ChangeSet(
        worktreePath: worktree.path,
        patch: PatchIndex.empty,
        base: 'master',
        baseSource: BaseSource.inferred,
        files: [file('lib/fresh.dart'), file('lib/landed.dart')],
        uncommitted: {'lib/fresh.dart'},
        untracked: const [UntrackedEntry('scratch.txt')],
      );
      await pump(tester);

      expect(
        tester
            .widget<IndexLens>(find.widgetWithText(IndexLens, 'uncommitted'))
            .count,
        2,
      );

      await tester.tap(find.widgetWithText(IndexLens, 'uncommitted'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(IndexLens, 'uncommitted'));
      await tester.pumpAndSettle();
      expect(inIndex('landed.dart'), findsOneWidget);
    });

    testWidgets('a lens that would say nothing is not drawn', (tester) async {
      // A `0 uncommitted` chip is a control that does nothing, which is worse
      // than no control — the same rule the section headings follow.
      current = setOf([file('lib/a.dart')]);
      await pump(tester);
      expect(find.byType(IndexLens), findsNothing);
    });

    testWidgets('the typed filter and a lens compose', (tester) async {
      current = ChangeSet(
        worktreePath: worktree.path,
        patch: PatchIndex.empty,
        base: 'master',
        baseSource: BaseSource.inferred,
        files: [
          file('lib/fresh.dart'),
          file('lib/other_fresh.dart'),
          file('lib/landed.dart'),
        ],
        uncommitted: {'lib/fresh.dart', 'lib/other_fresh.dart'},
      );
      await pump(tester);

      await tester.tap(find.widgetWithText(IndexLens, 'uncommitted'));
      await tester.enterText(find.byType(TextField), 'other');
      await tester.pumpAndSettle();

      expect(inIndex('other_fresh.dart'), findsOneWidget);
      expect(inIndex('fresh.dart'), findsNothing);
      expect(inIndex('landed.dart'), findsNothing);
    });

    testWidgets('typing finds an untracked file, which it could not before', (
      tester,
    ) async {
      // `pathsMatching` took `FileChange`s, so an untracked entry was never in
      // the candidate set: typing its name hid it.
      current = setOf(
        [file('lib/a.dart')],
        untracked: const [UntrackedEntry('scratch.txt')],
      );
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'scratch');
      await tester.pumpAndSettle();
      expect(inIndex('scratch.txt'), findsOneWidget);
      expect(inIndex('a.dart'), findsNothing);
    });
  });

  testWidgets('the index marks which file the pane is showing', (tester) async {
    await pump(tester, initialPath: 'lib/beta.dart');
    var rows = tester
        .widgetList<IndexFileRow>(find.byType(IndexFileRow))
        .toList();
    expect(rows.where((r) => r.selected).map((r) => r.file.path), [
      'lib/beta.dart',
    ]);
  });
}

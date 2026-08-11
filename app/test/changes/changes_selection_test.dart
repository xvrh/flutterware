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

  FileChange file(
    String path, {
    int added = 10,
    ChangeStatus status = ChangeStatus.modified,
  }) => FileChange(
    path: path,
    status: status,
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
    // **The answer to "filter this list down to what I care about".** The
    // pinned band says what a *rule* declared important; these say what is
    // **moving** and what is **skippable**, which are the other two questions a
    // fifty-file branch raises. Counts on both, because the count is the
    // information: `11 low-signal` says the branch is mostly generated code.

    testWidgets('just changed is empty on arrival, so it is not drawn', (
      tester,
    ) async {
      // Nothing has moved yet — a chip saying `0` is a control that does
      // nothing, which is worse than no control.
      current = setOf([file('lib/a.dart')]);
      await pump(tester);
      expect(find.byType(IndexLens), findsNothing);
    });

    testWidgets('it appears when the agent writes, and narrows to that', (
      tester,
    ) async {
      current = setOf([file('lib/quiet.dart'), file('lib/busy.dart')]);
      await pump(tester);

      // A re-probe in which one file moved and the other did not.
      current = setOf([
        file('lib/quiet.dart'),
        file('lib/busy.dart', added: 90),
      ]);
      await tester.tap(find.byTooltip('Read this checkout again'));
      await tester.pumpAndSettle();

      var lens = tester.widget<IndexLens>(
        find.widgetWithText(IndexLens, 'just changed'),
      );
      expect(lens.count, 1);

      await tester.tap(find.widgetWithText(IndexLens, 'just changed'));
      await tester.pumpAndSettle();
      expect(inIndex('busy.dart'), findsOneWidget);
      expect(inIndex('quiet.dart'), findsNothing);
    });

    testWidgets('it accumulates, because a probe fires every two seconds', (
      tester,
    ) async {
      // Per-probe it would empty itself before anybody could look at it. This
      // answers "what has happened while I have been here".
      current = setOf([file('lib/a.dart'), file('lib/b.dart')]);
      await pump(tester);

      current = setOf([file('lib/a.dart', added: 50), file('lib/b.dart')]);
      await tester.tap(find.byTooltip('Read this checkout again'));
      await tester.pumpAndSettle();
      current = setOf([
        file('lib/a.dart', added: 50),
        file('lib/b.dart', added: 60),
      ]);
      await tester.tap(find.byTooltip('Read this checkout again'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<IndexLens>(find.widgetWithText(IndexLens, 'just changed'))
            .count,
        2,
      );
    });

    testWidgets('a file whose bytes moved without its counts still counts', (
      tester,
    ) async {
      // An edit that swaps one line for another of the same length moves
      // neither `+n` nor `−n`, and is exactly the sort of thing you want to
      // have noticed.
      current = setOf([file('lib/a.dart')]);
      await pump(tester);

      current = ChangeSet(
        worktreePath: worktree.path,
        patch: PatchIndex.empty,
        base: 'master',
        baseSource: BaseSource.inferred,
        files: [file('lib/a.dart', status: ChangeStatus.added)],
      );
      await tester.tap(find.byTooltip('Read this checkout again'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<IndexLens>(find.widgetWithText(IndexLens, 'just changed'))
            .count,
        1,
      );
    });

    testWidgets('a project with no rules is told once that they exist', (
      tester,
    ) async {
      // **There are no built-in attention rules**, so without this line the
      // band is simply absent and the whole ranking reads as a feature that
      // does not work.
      current = setOf([file('lib/a.dart')]);
      await pump(tester);
      expect(find.textContaining('Nothing is pinned'), findsOneWidget);
    });

    testWidgets('a project that has rules is told nothing', (tester) async {
      current = ChangeSet(
        worktreePath: worktree.path,
        patch: PatchIndex.empty,
        base: 'master',
        baseSource: BaseSource.inferred,
        files: [file('lib/a.dart')],
        attentionConfigured: true,
      );
      await pump(tester);
      expect(find.textContaining('Nothing is pinned'), findsNothing);
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

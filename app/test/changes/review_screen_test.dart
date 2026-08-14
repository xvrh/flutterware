import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_screen.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/changes/review_comment.dart';
import 'package:flutterware_app/src/changes/review_store.dart';
import 'package:flutterware_app/src/changes/review_view.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// The loop the whole feature is: drop a note on a line, watch it accumulate,
/// hand the batch off, and find it in history.
///
/// Every one of these goes through the real store — an append-only file in a
/// temporary directory — because the interesting failures are in the folding,
/// not in a mock that would agree with whatever the screen did.
void main() {
  const worktree = Worktree(
    path: '/wt/feature',
    gitName: 'feature',
    branch: 'claude/feature',
  );

  var patch = [
    'diff --git a/lib/a.dart b/lib/a.dart',
    '--- a/lib/a.dart',
    '+++ b/lib/a.dart',
    '@@ -1,3 +1,4 @@',
    ' first',
    '-second was',
    '+second is',
    '+second and a half',
    ' third',
    'diff --git a/lib/b.dart b/lib/b.dart',
    '--- a/lib/b.dart',
    '+++ b/lib/b.dart',
    '@@ -1 +1 @@',
    '-old b',
    '+new b',
    '',
  ].join('\n');

  late Directory dir;
  late ReviewStore store;

  /// What the clipboard route actually put there.
  String? copied;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('review-screen');
    store = ReviewStore(File('${dir.path}/review.jsonl'));
    copied = null;
    // Without a handler `Clipboard.setData` throws here, and the sheet is
    // right to treat that as a failed handoff — so the test has to provide
    // one, and it may as well be the assertion.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    dir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: ChangesScreen(
            worktree: worktree,
            reviewStore: store,
            load: (_) async => ChangeSet(
              worktreePath: worktree.path,
              patch: indexPatch(Uint8List.fromList(utf8.encode(patch))),
              base: 'master',
              baseSource: BaseSource.inferred,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the composer on the [n]th drawable line of the open file.
  ///
  /// The `+` is a real target whether or not a pointer is hovering it — see
  /// `_AddComment`. Gated on hover it would be unreachable from here, which is
  /// the reason it is not.
  Future<void> plus(WidgetTester tester, int n) async {
    await tester.tap(
      find
          .byTooltip('Comment on this line — shift-click to extend a span')
          .at(n),
    );
    await tester.pumpAndSettle();
  }

  Future<void> write(WidgetTester tester, String body) async {
    await tester.enterText(find.byKey(reviewComposerKey), body);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add comment'));
    await tester.pumpAndSettle();
  }

  Future<void> openFile(WidgetTester tester, String name) async {
    await tester.tap(find.text(name).first);
    await tester.pumpAndSettle();
  }

  testWidgets('a note on a line, and the note is in the diff', (tester) async {
    await pump(tester);
    await openFile(tester, 'a.dart');

    // Nothing advertises the gesture except the empty state, so it had better
    // say it.
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('No comments yet'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    await plus(tester, 0);
    expect(find.byType(ReviewComposer), findsOneWidget);
    // The staleness contract, stated where it is accepted.
    expect(find.textContaining('1 line captured'), findsOneWidget);

    await write(tester, 'This should be a constant.');

    expect(find.byType(ReviewComposer), findsNothing);
    expect(find.byType(ReviewThread), findsOneWidget);
    expect(find.text('This should be a constant.'), findsWidgets);
  });

  testWidgets('the quote is read once, and kept as it was', (tester) async {
    await pump(tester);
    await openFile(tester, 'a.dart');
    await plus(tester, 0);
    await write(tester, 'note');

    // Row 0 of this hunk is ` first`, and the marker is not part of it: what
    // travels to the agent is the code, not the diff.
    expect(store.read().open.single.quote, ['first']);
  });

  testWidgets('shift-click extends the span and keeps what you typed', (
    tester,
  ) async {
    await pump(tester);
    await openFile(tester, 'a.dart');

    await plus(tester, 0);
    await tester.enterText(find.byKey(reviewComposerKey), 'half written');
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    // Row 3 is `+second and a half`, two new-side lines below row 0.
    await plus(tester, 3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    // **Extended, not restarted.** A modifier that quietly began a new comment
    // would take the sentence you had already written with it.
    expect(find.textContaining('3 lines captured'), findsOneWidget);
    expect(find.text('half written'), findsOneWidget);

    await tester.tap(find.text('Add comment'));
    await tester.pumpAndSettle();

    var comment = store.read().open.single;
    expect(comment.anchor.label, 'lib/a.dart:1–3');
    expect(comment.quote, ['first', 'second is', 'second and a half']);
  });

  testWidgets('a comment on the whole review needs no file', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Comment on the whole review'));
    await tester.pumpAndSettle();
    await write(tester, 'Three of these are the same problem.');

    var comment = store.read().open.single;
    expect(comment.anchor, isA<ReviewWide>());
    expect(comment.anchor.path, isNull);
    expect(comment.quote, isEmpty);
  });

  testWidgets('a comment on a file is not a lie about line 1', (tester) async {
    await pump(tester);
    await openFile(tester, 'a.dart');

    await tester.tap(find.text('Comment on this file'));
    await tester.pumpAndSettle();
    await write(tester, 'No test covers this.');

    var comment = store.read().open.single;
    expect(comment.anchor, isA<FileAnchor>());
    expect(comment.anchor.label, 'lib/a.dart');
  });

  testWidgets('the tab count is what is waiting to be handed off', (
    tester,
  ) async {
    await pump(tester);
    await openFile(tester, 'a.dart');
    await plus(tester, 0);
    await write(tester, 'one');
    await plus(tester, 1);
    await write(tester, 'two');

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    // Numbered, so "the second one" means something when you tell the agent.
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(find.text('Hand off 2 comments'), findsOneWidget);
  });

  testWidgets('a comment opens the file it is about', (tester) async {
    await pump(tester);
    await openFile(tester, 'b.dart');
    await plus(tester, 0);
    await write(tester, 'about b');

    await openFile(tester, 'a.dart');
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewThread), findsNothing);

    await tester.tap(find.text('about b'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewThread), findsOneWidget);
  });

  testWidgets('deleting takes it off the screen, and can be taken back', (
    tester,
  ) async {
    await pump(tester);
    await openFile(tester, 'a.dart');
    await plus(tester, 0);
    await write(tester, 'oops');

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Gone from the screen at once — that is what a delete has to look like —
    // while the log still has it, which is what makes the undo lossless.
    expect(find.byType(ReviewThread), findsNothing);
    expect(find.byType(ReviewUndoStrip), findsOneWidget);
    expect(store.read().open, hasLength(1));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewThread), findsOneWidget);
    expect(store.read().open.single.body, 'oops');
  });

  testWidgets('the delete lands when the window closes', (tester) async {
    await pump(tester);
    await openFile(tester, 'a.dart');
    await plus(tester, 0);
    await write(tester, 'oops');

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // Past the undo window. The tombstone is written now, and not before.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewUndoStrip), findsNothing);
    expect(store.read().open, isEmpty);
  });

  testWidgets('a deleted comment does not travel with the batch', (
    tester,
  ) async {
    await pump(tester);
    await openFile(tester, 'a.dart');
    await plus(tester, 0);
    await write(tester, 'keep this');
    await plus(tester, 1);
    await write(tester, 'oops');

    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    // The count is what is waiting, not what the log happens to hold.
    expect(find.text('Hand off 1 comment'), findsOneWidget);

    await tester.tap(find.text('Hand off 1 comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hand off'));
    await tester.pumpAndSettle();

    expect(copied, contains('keep this'));
    expect(copied, isNot(contains('oops')));
    expect(store.read().open, isEmpty);
  });

  testWidgets('a comment shows the code it captured', (tester) async {
    await pump(tester);
    await openFile(tester, 'a.dart');
    await plus(tester, 0);
    await write(tester, 'this line is wrong');

    // The quote is the whole design — a comment carries the code it is about —
    // and for one release it was written into the comment and drawn nowhere.
    expect(find.byType(ReviewQuote), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ReviewQuote),
        matching: find.text('first'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('editing rewrites the body and keeps the anchor', (tester) async {
    await pump(tester);
    await openFile(tester, 'a.dart');
    await plus(tester, 0);
    await write(tester, 'first go');

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(reviewComposerKey), 'second go');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    var comments = store.read().open;
    expect(comments, hasLength(1));
    expect(comments.single.body, 'second go');
    expect(comments.single.anchor, isA<LineAnchor>());
  });

  testWidgets('handing off closes the batch and history remembers it', (
    tester,
  ) async {
    await pump(tester);
    await openFile(tester, 'a.dart');
    await plus(tester, 0);
    await write(tester, 'a note');

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hand off 1 comment'));
    await tester.pumpAndSettle();

    // What leaves is shown before it leaves.
    expect(find.textContaining('# Review — claude/feature'), findsOneWidget);
    expect(find.textContaining('## lib/a.dart:1'), findsOneWidget);

    await tester.tap(find.text('Hand off'));
    await tester.pumpAndSettle();

    var state = store.read();
    expect(state.open, isEmpty, reason: 'the batch is closed');
    expect(state.history.single.comments.single.body, 'a note');
    // The preview and the clipboard are the same string, by construction.
    expect(copied, contains('## lib/a.dart:1'));
    expect(copied, contains('a note'));
    expect(find.text('Handed off'), findsOneWidget);
    expect(find.text('Nothing to hand off'), findsOneWidget);
    // And the diff no longer draws it: it has been sent.
    expect(find.byType(ReviewThread), findsNothing);
  });

  testWidgets('cancelling the sheet leaves the batch open', (tester) async {
    await pump(tester);
    await openFile(tester, 'a.dart');
    await plus(tester, 0);
    await write(tester, 'a note');

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hand off 1 comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(store.read().open, hasLength(1));
    expect(store.read().history, isEmpty);
    expect(find.text('Hand off 1 comment'), findsOneWidget);
  });

  testWidgets('Esc discards the draft, and takes nothing else with it', (
    tester,
  ) async {
    await pump(tester);
    await openFile(tester, 'a.dart');
    await plus(tester, 0);
    await tester.enterText(find.byKey(reviewComposerKey), 'never mind');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(ReviewComposer), findsNothing);
    expect(store.read().open, isEmpty);
  });

  testWidgets('what was written before this launch is still there', (
    tester,
  ) async {
    store.append([
      CommentAdded(
        ReviewComment(
          id: 'earlier',
          anchor: const LineAnchor(
            path: 'lib/a.dart',
            from: 1,
            to: 1,
            side: ReviewSide.after,
          ),
          body: 'written yesterday',
          createdAt: DateTime.utc(2026, 8, 13),
          quote: const ['first'],
        ),
      ),
    ]);

    await pump(tester);
    await openFile(tester, 'a.dart');
    expect(find.text('written yesterday'), findsOneWidget);
  });

  testWidgets('a comment whose line is gone is kept, at the top of the file', (
    tester,
  ) async {
    // The agent rewrote the hunk out from under it — which is exactly when the
    // note matters. It still carries its quote, so it reads on its own.
    store.append([
      CommentAdded(
        ReviewComment(
          id: 'orphan',
          anchor: const LineAnchor(
            path: 'lib/a.dart',
            from: 900,
            to: 900,
            side: ReviewSide.after,
          ),
          body: 'this line has moved on',
          createdAt: DateTime.utc(2026, 8, 13),
          quote: const ['what used to be here'],
        ),
      ),
    ]);

    await pump(tester);
    await openFile(tester, 'a.dart');
    expect(find.text('this line has moved on'), findsOneWidget);
  });

  testWidgets('a file that moved since the comment says so', (tester) async {
    store.append([
      CommentAdded(
        ReviewComment(
          id: 'stale',
          anchor: const LineAnchor(
            path: 'lib/a.dart',
            from: 1,
            to: 1,
            side: ReviewSide.after,
          ),
          body: 'written against an older diff',
          createdAt: DateTime.utc(2026, 8, 13),
          quote: const ['first'],
          fileDigest: 'a digest this patch cannot produce',
        ),
      ),
    ]);

    await pump(tester);
    await openFile(tester, 'a.dart');
    expect(
      find.textContaining('This file changed after you commented'),
      findsOneWidget,
    );
  });
}

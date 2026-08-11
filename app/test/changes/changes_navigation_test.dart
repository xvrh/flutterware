import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_screen.dart';
import 'package:flutterware_app/src/changes/churn_map.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// **Naming a file opens it, and the keyboard can name one.**
///
/// Both of these were reported as broken by someone using the screen, and both
/// were: the tree and the churn map scrolled to a file and left it shut, and
/// this screen had no keyboard at all while the explorer you arrive from does.
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

  var files = [
    file('lib/alpha.dart', added: 90),
    file('lib/beta.dart', added: 60),
    file('lib/gamma.dart', added: 30),
  ];

  late List<String?> addressed;

  Future<void> pump(WidgetTester tester) async {
    addressed = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: ChangesScreen(
            worktree: worktree,
            live: false,
            onPathChanged: addressed.add,
            load: (_) async => ChangeSet(
              worktreePath: worktree.path,
              patch: PatchIndex.empty,
              base: 'master',
              baseSource: BaseSource.inferred,
              files: files,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The `@@` line only exists for an expanded file.
  Finder expandedBodies() => find.textContaining('@@');

  testWidgets('clicking a file in the tree opens it', (tester) async {
    await pump(tester);
    expect(expandedBodies(), findsNothing);

    // The tree draws the basename; the list draws the whole path, so this is
    // unambiguously the tree's row.
    await tester.tap(find.text('beta.dart'));
    await tester.pumpAndSettle();

    expect(expandedBodies(), findsOneWidget);
    expect(
      addressed,
      ['lib/beta.dart'],
      reason: 'and what you are looking at is what the address bar says',
    );
  });

  testWidgets('clicking it again does not shut it', (tester) async {
    // Picking a name out of the tree twice means "show me that file" twice.
    // Toggling on the second click is the opposite of the ask; the row itself
    // is the toggle.
    await pump(tester);
    await tester.tap(find.text('beta.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('beta.dart'));
    await tester.pumpAndSettle();

    expect(expandedBodies(), findsOneWidget);
  });

  testWidgets('and so does clicking its column in the churn map', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(
      find
          .descendant(
            of: find.byType(ChurnMap),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(expandedBodies(), findsOneWidget);
  });

  testWidgets('the row itself still toggles both ways', (tester) async {
    await pump(tester);
    await tester.tap(find.text('lib/beta.dart'));
    await tester.pumpAndSettle();
    expect(expandedBodies(), findsOneWidget);

    await tester.tap(find.text('lib/beta.dart'));
    await tester.pumpAndSettle();
    expect(expandedBodies(), findsNothing);
    expect(addressed, ['lib/beta.dart', null]);
  });

  testWidgets('down lands on the first file, not the second', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(expandedBodies(), findsOneWidget);
    expect(addressed, ['lib/alpha.dart']);
  });

  testWidgets('the arrows walk the files and enter opens the one you are on', (
    tester,
  ) async {
    await pump(tester);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(addressed, ['lib/beta.dart']);
  });

  testWidgets('the cursor stops at the ends rather than wrapping', (
    tester,
  ) async {
    await pump(tester);
    for (var i = 0; i < 9; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(addressed, ['lib/gamma.dart']);
  });

  testWidgets('right opens and left closes, and neither flaps', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(expandedBodies(), findsOneWidget, reason: 'right never closes');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(expandedBodies(), findsNothing, reason: 'and left never opens');
  });

  testWidgets('typing in the filter is typing, not navigating', (tester) async {
    // The field takes the focus and consumes its own arrows for the caret,
    // which is what keeps this handler out of the way while you are typing.
    await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pumpAndSettle();

    expect(find.text('lib/alpha.dart'), findsNothing);
    expect(find.text('lib/beta.dart'), findsOneWidget);
  });

  testWidgets('the keyboard says what it does', (tester) async {
    await pump(tester);
    expect(find.textContaining('↑↓ move'), findsOneWidget);
  });
}

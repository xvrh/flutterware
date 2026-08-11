import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_summary.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';
import 'package:flutterware_app/src/worktrees/explorer_screen.dart';
import 'package:flutterware_app/src/worktrees/facts.dart';

/// The third rung, and the gesture that reaches it.
///
/// **Hover shows the card; click goes to the screen.** It used to be a click on
/// the fingerprint bar, with a `Tooltip` over the cell around it — one target,
/// two interactions, and the cheap one winning every time. The bar is four
/// pixels tall, so in a real window every click aimed at it hit the row behind
/// instead, and the tooltip answered the hover it stole. Both halves of that
/// are pinned here.
void main() {
  var now = DateTime(2026, 8, 11, 9);

  ExplorerEntry entry(String branch, {ChangeShape? shape, int dirty = 2}) =>
      ExplorerEntry(
        worktree: Worktree(
          path: '/repo/$branch',
          gitName: branch,
          branch: branch,
        ),
        facts: WorktreeFacts(
          git: Fact.fresh(
            GitFacts(
              base: 'master',
              dirty: dirty,
              changes:
                  shape ??
                  const ChangeShape(
                    files: 4,
                    buckets: [ChangeBucket('lib', added: 90, removed: 12)],
                  ),
            ),
          ),
          activity: Fact.fresh(
            ActivityFacts(at: now, source: ActivitySource.commit),
          ),
        ),
      );

  /// A checkout with nothing at all to show: no card, because there is nothing
  /// to put in one.
  ExplorerEntry quiet(String branch) => ExplorerEntry(
    worktree: Worktree(path: '/repo/$branch', gitName: branch, branch: branch),
    facts: WorktreeFacts(
      git: Fact.fresh(const GitFacts(base: 'master')),
      activity: Fact.fresh(
        ActivityFacts(at: now, source: ActivitySource.commit),
      ),
    ),
  );

  ChangeSet setFor(String path) => ChangeSet(
    worktreePath: path,
    patch: PatchIndex.empty,
    base: 'master',
    baseSource: BaseSource.inferred,
    files: [
      FileChange(
        path: 'lib/${path.split('/').last}_thing.dart',
        status: ChangeStatus.modified,
        added: 9,
        removed: 1,
        hunks: const [],
        byteStart: 0,
        byteEnd: 0,
      ),
    ],
  );

  late List<String> openedChanges;
  late String query;

  Future<void> pump(WidgetTester tester, List<ExplorerEntry> rows) async {
    openedChanges = [];
    query = '';
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) => WorktreeExplorerView(
              entries: rows,
              now: now,
              query: query,
              onQueryChanged: (value) => setState(() => query = value),
              onOpenChanges: (e) => openedChanges.add(e.worktree.branch!),
              changesLoad: (path) async => setFor(path),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The cell, found by the counts only it draws.
  Finder cellOf(String files) =>
      find.ancestor(of: find.text(files), matching: find.byType(Row)).first;

  /// Rests the pointer on [target] long enough for the card to open.
  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    var gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    return gesture;
  }

  testWidgets('resting on the changes cell shows the ranked list', (
    tester,
  ) async {
    await pump(tester, [entry('alpha')]);
    expect(find.byKey(changesSummaryKey), findsNothing);

    await hover(tester, cellOf('4f'));

    expect(find.byKey(changesSummaryKey), findsOneWidget);
    expect(find.text('alpha_thing.dart'), findsOneWidget);
  });

  testWidgets('a pointer passing through does not open anything', (
    tester,
  ) async {
    // The difference between a hover card and a screen that flashes at you.
    await pump(tester, [entry('alpha')]);
    var gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(cellOf('4f')));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.byKey(changesSummaryKey), findsNothing);
  });

  testWidgets('leaving the cell shuts it again', (tester) async {
    await pump(tester, [entry('alpha')]);
    var gesture = await hover(tester, cellOf('4f'));
    expect(find.byKey(changesSummaryKey), findsOneWidget);

    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(changesSummaryKey), findsNothing);
  });

  testWidgets('the card survives the pointer travelling into it', (
    tester,
  ) async {
    // **The classic hover-card bug.** The gap between trigger and card is real
    // space the pointer has to cross; closing the instant it leaves the trigger
    // makes the footer link unclickable.
    await pump(tester, [entry('alpha')]);
    var gesture = await hover(tester, cellOf('4f'));

    await gesture.moveTo(tester.getCenter(find.byKey(changesSummaryKey)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.byKey(changesSummaryKey), findsOneWidget);
    await tester.tap(find.text('Open changes'));
    await tester.pumpAndSettle();
    expect(openedChanges, ['alpha']);
  });

  testWidgets('clicking the cell goes straight to the screen', (tester) async {
    // The card is what hovering does, so the click is free to mean the next
    // thing along rather than toggling what is already showing.
    await pump(tester, [entry('alpha')]);
    await tester.tap(cellOf('4f'));
    await tester.pumpAndSettle();

    expect(openedChanges, ['alpha']);
    expect(find.text('PATH'), findsNothing, reason: 'and the row stayed shut');
  });

  testWidgets('the rest of the row still expands', (tester) async {
    await pump(tester, [entry('alpha')]);
    await tester.tap(find.text('alpha').first);
    await tester.pumpAndSettle();

    expect(find.text('PATH'), findsOneWidget);
    expect(openedChanges, isEmpty);
  });

  testWidgets('c opens it on the cursor row, without the hover delay', (
    tester,
  ) async {
    await pump(tester, [entry('alpha'), entry('beta')]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();

    expect(find.byKey(changesSummaryKey), findsOneWidget);
    expect(
      find.text('beta_thing.dart'),
      findsOneWidget,
      reason: 'the cursor row, not the first one',
    );
  });

  testWidgets('c with the filter in use types instead of opening', (
    tester,
  ) async {
    await pump(tester, [entry('alpha')]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.enterText(find.byType(TextField), 'al');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.byKey(changesSummaryKey), findsNothing);
  });

  testWidgets('a checkout whose work is all uncommitted still has one', (
    tester,
  ) async {
    // **The case the whole feature exists for.** `ChangeShape` is the branch
    // diff, keyed by two commit shas and so committed-only, so a checkout whose
    // agent has written fifteen files and committed none draws no fingerprint.
    // Hanging the trigger off the fingerprint put the card out of reach for
    // exactly the worktree §1 is about.
    await pump(tester, [
      ExplorerEntry(
        worktree: const Worktree(
          path: '/repo/fresh',
          gitName: 'fresh',
          branch: 'fresh',
        ),
        facts: WorktreeFacts(
          git: Fact.fresh(const GitFacts(base: 'master', dirty: 11)),
          activity: Fact.fresh(
            ActivityFacts(at: now, source: ActivitySource.commit),
          ),
        ),
      ),
    ]);

    await hover(tester, find.text('uncommitted'));
    expect(find.byKey(changesSummaryKey), findsOneWidget);
    expect(find.text('fresh_thing.dart'), findsOneWidget);
  });

  testWidgets('a checkout with nothing to show stays inert', (tester) async {
    await pump(tester, [quiet('sync')]);
    await hover(tester, find.text('in sync'));
    expect(find.byKey(changesSummaryKey), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.byKey(changesSummaryKey), findsNothing);
  });

  testWidgets('the keyboard keeps walking the list with a card open', (
    tester,
  ) async {
    // The card must not take the focus: the filter field holds it the whole
    // time, which is what makes `c ↓ c ↓` across checkouts possible.
    await pump(tester, [entry('alpha'), entry('beta')]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.text('alpha_thing.dart'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();

    expect(find.text('beta_thing.dart'), findsOneWidget);
    expect(find.text('alpha_thing.dart'), findsNothing);
  });

  testWidgets('escape shuts the card, and only then the filter', (
    tester,
  ) async {
    await pump(tester, [entry('alpha')]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.byKey(changesSummaryKey), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(changesSummaryKey), findsNothing);

    await tester.enterText(find.byType(TextField), 'al');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(query, isEmpty);
  });
}

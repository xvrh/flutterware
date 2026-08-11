import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_summary.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';
import 'package:flutterware_app/src/worktrees/explorer_row.dart';
import 'package:flutterware_app/src/worktrees/explorer_screen.dart';
import 'package:flutterware_app/src/worktrees/facts.dart';

/// The third rung's **trigger**, which is the part with a cost.
///
/// The row is one tap target that expands, so every new target is subtracted
/// from that gesture. These pin down which pixels were spent and which were
/// not.
void main() {
  var now = DateTime(2026, 8, 11, 9);

  ExplorerEntry entry(String branch, {ChangeShape? shape}) => ExplorerEntry(
    worktree: Worktree(path: '/repo/$branch', gitName: branch, branch: branch),
    facts: WorktreeFacts(
      git: Fact.fresh(
        GitFacts(
          base: 'master',
          dirty: 2,
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

  /// A checkout with nothing to show: no bar, and so no trigger.
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

  testWidgets('clicking the fingerprint bar opens the ranked list', (
    tester,
  ) async {
    await pump(tester, [entry('alpha')]);
    expect(find.byKey(changesSummaryKey), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(WorktreeRow),
        matching: find.byTooltip('Which files changed  ·  c'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(changesSummaryKey), findsOneWidget);
    expect(find.text('alpha_thing.dart'), findsOneWidget);
  });

  testWidgets('and does not also expand the row underneath it', (tester) async {
    // The cost of the trigger, stated: ~100 px of ~1200 stop expanding. That is
    // deliberate — but the tap must go to exactly one of the two, not both.
    await pump(tester, [entry('alpha')]);
    await tester.tap(find.byTooltip('Which files changed  ·  c'));
    await tester.pumpAndSettle();

    expect(find.byKey(changesSummaryKey), findsOneWidget);
    expect(find.text('PATH'), findsNothing, reason: 'the detail stayed shut');
  });

  testWidgets('the rest of the row still expands', (tester) async {
    await pump(tester, [entry('alpha')]);
    await tester.tap(find.text('alpha').first);
    await tester.pumpAndSettle();

    expect(find.text('PATH'), findsOneWidget);
    expect(find.byKey(changesSummaryKey), findsNothing);
  });

  testWidgets('c opens it on the cursor row', (tester) async {
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
    // The filter takes every printable key, so this binding only exists in the
    // state where the keyboard is driving the list rather than the field.
    await pump(tester, [entry('alpha')]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.enterText(find.byType(TextField), 'al');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.byKey(changesSummaryKey), findsNothing);
  });

  testWidgets('c with no cursor does nothing at all', (tester) async {
    await pump(tester, [entry('alpha')]);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.byKey(changesSummaryKey), findsNothing);
  });

  testWidgets('a checkout with nothing to show has no trigger', (tester) async {
    // No bar is drawn, so there is nothing to click and nothing to open —
    // which is correct rather than a gap.
    await pump(tester, [quiet('sync')]);
    expect(find.byTooltip('Which files changed  ·  c'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.byKey(changesSummaryKey), findsNothing);
  });

  testWidgets('Open changes reports the checkout and shuts the popover', (
    tester,
  ) async {
    await pump(tester, [entry('alpha')]);
    await tester.tap(find.byTooltip('Which files changed  ·  c'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open changes'));
    await tester.pumpAndSettle();

    expect(openedChanges, ['alpha']);
    expect(
      find.byKey(changesSummaryKey),
      findsNothing,
      reason: 'a popover left open over the screen it just opened is litter',
    );
  });

  testWidgets('the keyboard keeps walking the list with a card open', (
    tester,
  ) async {
    // **The popover must not take the focus.** The explorer's filter field
    // holds it the whole time, which is what makes `c ↓ c ↓` across several
    // checkouts possible — and sweeping several checkouts is the case the
    // whole screen exists for.
    await pump(tester, [entry('alpha'), entry('beta')]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.text('alpha_thing.dart'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();

    // One at a time, unlike the detail: a ranked file list is not comparable,
    // so two of them over the list is clutter rather than a comparison.
    expect(find.text('beta_thing.dart'), findsOneWidget);
    expect(find.text('alpha_thing.dart'), findsNothing);
  });

  testWidgets('escape shuts the card, and only then the filter', (
    tester,
  ) async {
    // The card does not hold the focus, so nothing else would close it.
    await pump(tester, [entry('alpha')]);
    await tester.tap(find.byTooltip('Which files changed  ·  c'));
    await tester.pumpAndSettle();
    expect(find.byKey(changesSummaryKey), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(changesSummaryKey), findsNothing);

    // With nothing in the way, Escape goes back to meaning what it meant.
    await tester.enterText(find.byType(TextField), 'al');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(query, isEmpty);
  });
}

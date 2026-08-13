import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/changes/range_picker.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// The control, as a control: what a click means, what shift-click means, and
/// what the chip says about where you are.
void main() {
  CommitEntry commit(String sha, String subject) => CommitEntry(
    sha: '${sha}full',
    shortSha: sha,
    subject: subject,
    author: 'Ada',
  );

  var commits = [
    commit('c3', 'the third'),
    commit('c2', 'the second'),
    commit('c1', 'the first'),
  ];

  ChangeSet setOf({ChangeRange range = ChangeRange.everything}) => ChangeSet(
    worktreePath: '/w',
    patch: PatchIndex.empty,
    base: 'master',
    baseSource: BaseSource.inferred,
    mergeBase: 'basesha',
    head: 'c3full',
    commits: commits,
    range: range,
  );

  Future<List<ChangeRange>> pump(
    WidgetTester tester, {
    ChangeRange range = ChangeRange.everything,
    bool withBase = true,
  }) async {
    var picked = <ChangeRange>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RangePicker(
              set: setOf(range: range),
              withBase: withBase,
              onRange: picked.add,
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(rangeTriggerKey));
    await tester.pumpAndSettle();
  }

  group('the chip', () {
    testWidgets('unnarrowed, it is the base sentence it replaced', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('base master (inferred)'), findsOneWidget);
    });

    testWidgets('under a strip it drops the base, which is stated above', (
      tester,
    ) async {
      await pump(tester, withBase: false);
      expect(find.text('Everything'), findsOneWidget);
    });

    testWidgets('one commit names it', (tester) async {
      await pump(
        tester,
        range: const ChangeRange(from: 'c1full', to: 'c2full'),
      );
      expect(find.text('commit c2'), findsOneWidget);
    });

    testWidgets('a run names its ends, oldest first', (tester) async {
      await pump(tester, range: const ChangeRange(to: 'c2full'));
      expect(find.text('2 commits · c1…c2'), findsOneWidget);
    });

    testWidgets('the working tree alone says so in words', (tester) async {
      await pump(tester, range: const ChangeRange(from: 'c3full'));
      expect(find.text('uncommitted only'), findsOneWidget);
    });

    testWidgets('since a commit counts what it covers', (tester) async {
      await pump(tester, range: const ChangeRange(from: 'c2full'));
      expect(find.text('1 commit + uncommitted'), findsOneWidget);
    });
  });

  group('picking', () {
    testWidgets('a commit is a range of one', (tester) async {
      var picked = await pump(tester);
      await open(tester);
      await tester.tap(find.byKey(rangeRowKey('c2full')));
      await tester.pumpAndSettle();

      expect(picked, [const ChangeRange(from: 'c1full', to: 'c2full')]);
    });

    testWidgets('the oldest commit takes the merge base as its left edge', (
      tester,
    ) async {
      var picked = await pump(tester);
      await open(tester);
      await tester.tap(find.byKey(rangeRowKey('c1full')));
      await tester.pumpAndSettle();

      expect(picked, [const ChangeRange(to: 'c1full')]);
    });

    testWidgets('the working tree is a row, not a mode', (tester) async {
      var picked = await pump(tester);
      await open(tester);
      await tester.tap(find.byKey(rangeRowKey('worktree')));
      await tester.pumpAndSettle();

      expect(picked, [const ChangeRange(from: 'c3full')]);
    });

    testWidgets('everything writes an empty range', (tester) async {
      var picked = await pump(tester, range: const ChangeRange(to: 'c2full'));
      await open(tester);
      await tester.tap(find.byKey(rangeRowKey('everything')));
      await tester.pumpAndSettle();

      expect(picked, [ChangeRange.everything]);
    });

    testWidgets('while everything is on, no commit row is lit', (tester) async {
      // Every commit is inside the whole delta, so marking them all would make
      // the top row indistinguishable from a run spanning the branch — and a
      // list where every row is lit has stopped saying anything.
      await pump(tester);
      await open(tester);

      expect(_dots(tester, 'everything'), 1);
      expect(_dots(tester, 'c2full'), 0);
    });

    testWidgets('a run lights exactly the rows it covers', (tester) async {
      await pump(
        tester,
        range: const ChangeRange(from: 'c1full', to: 'c3full'),
      );
      await open(tester);

      expect(_dots(tester, 'c3full'), 1);
      expect(_dots(tester, 'c2full'), 1);
      expect(_dots(tester, 'c1full'), 0);
      expect(_dots(tester, 'everything'), 0);
    });
  });

  group('shift-click', () {
    /// Held for the duration of [body], the way a finger is.
    Future<void> withShift(Future<void> Function() body) async {
      await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      try {
        await body();
      } finally {
        await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
    }

    testWidgets('extends from the row clicked before it', (tester) async {
      var picked = await pump(tester);
      await open(tester);
      await tester.tap(find.byKey(rangeRowKey('c3full')));
      await tester.pumpAndSettle();

      await open(tester);
      await withShift(() async {
        await tester.tap(find.byKey(rangeRowKey('c1full')));
        await tester.pumpAndSettle();
      });

      expect(picked.last, const ChangeRange(to: 'c3full'));
    });

    testWidgets('onto the working tree is *since this commit*', (tester) async {
      var picked = await pump(tester);
      await open(tester);
      await tester.tap(find.byKey(rangeRowKey('c2full')));
      await tester.pumpAndSettle();

      await open(tester);
      await withShift(() async {
        await tester.tap(find.byKey(rangeRowKey('worktree')));
        await tester.pumpAndSettle();
      });

      expect(picked.last, const ChangeRange(from: 'c1full'));
    });

    testWidgets('with nothing clicked yet it is a plain click', (tester) async {
      // A range restored from the address has no anchor — nobody clicked a row
      // to produce it — so the first shift-click has nothing to extend and
      // behaves as an ordinary pick rather than guessing an end.
      var picked = await pump(tester);
      await open(tester);
      await withShift(() async {
        await tester.tap(find.byKey(rangeRowKey('c2full')));
        await tester.pumpAndSettle();
      });

      expect(picked, [const ChangeRange(from: 'c1full', to: 'c2full')]);
    });
  });
}

/// How many filled dots the row [id] is drawing — 1 when it is in the range.
int _dots(WidgetTester tester, String id) {
  var found = tester.widgetList<Container>(
    find.descendant(
      of: find.byKey(rangeRowKey(id)),
      matching: find.byType(Container),
    ),
  );
  return found
      .where(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).shape == BoxShape.circle &&
            (c.decoration! as BoxDecoration).color != Colors.transparent,
      )
      .length;
}

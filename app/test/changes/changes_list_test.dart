import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_screen.dart';
import 'package:flutterware_app/src/changes/churn_map.dart';
import 'package:flutterware_app/src/changes/diff_view.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// The view's own claims: that a body appears only when asked for, that the
/// churn map keeps whole-branch context while the list narrows, and that a
/// four-thousand-line file costs a screenful rather than four thousand widgets.
void main() {
  const worktree = Worktree(
    path: '/wt/feature',
    gitName: 'feature',
    branch: 'claude/feature',
  );

  PatchIndex index(String patch) =>
      indexPatch(Uint8List.fromList(utf8.encode(patch)));

  Future<void> pumpPatch(WidgetTester tester, PatchIndex patch) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: ChangesScreen(
            worktree: worktree,
            load: (_) async => ChangeSet(
              worktreePath: worktree.path,
              patch: patch,
              base: 'master',
              baseSource: BaseSource.inferred,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  var twoFiles = [
    'diff --git a/lib/alpha.dart b/lib/alpha.dart',
    '--- a/lib/alpha.dart',
    '+++ b/lib/alpha.dart',
    '@@ -1,3 +1,3 @@',
    ' keep',
    '-was here',
    '+is here now',
    ' tail',
    'diff --git a/lib/beta.dart b/lib/beta.dart',
    '--- a/lib/beta.dart',
    '+++ b/lib/beta.dart',
    '@@ -1 +1 @@',
    '-old beta',
    '+new beta',
    '',
  ].join('\n');

  testWidgets('a file shows no body until it is expanded', (tester) async {
    await pumpPatch(tester, index(twoFiles));

    expect(find.byType(DiffLineView), findsNothing);

    await tester.tap(find.text('lib/alpha.dart'));
    await tester.pumpAndSettle();

    expect(find.byType(DiffLineView), findsWidgets);
    expect(find.text('is here now'), findsOneWidget);
    expect(find.text('was here'), findsOneWidget);
    // The other file kept its body to itself.
    expect(find.text('new beta'), findsNothing);
  });

  testWidgets('the hunk header is drawn from the span, with its context', (
    tester,
  ) async {
    await pumpPatch(
      tester,
      index(
        [
          'diff --git a/lib/a.dart b/lib/a.dart',
          '--- a/lib/a.dart',
          '+++ b/lib/a.dart',
          '@@ -12,2 +12,2 @@ class StreamParser {',
          ' a',
          '-b',
          '+B',
          '',
        ].join('\n'),
      ),
    );

    await tester.tap(find.text('lib/a.dart'));
    await tester.pumpAndSettle();

    expect(find.text('@@ -12,2 +12,2 @@'), findsOneWidget);
    expect(find.text('class StreamParser {'), findsOneWidget);
  });

  testWidgets('expanding again puts it away', (tester) async {
    await pumpPatch(tester, index(twoFiles));

    await tester.tap(find.text('lib/alpha.dart'));
    await tester.pumpAndSettle();
    expect(find.byType(DiffLineView), findsWidgets);

    await tester.tap(find.text('lib/alpha.dart'));
    await tester.pumpAndSettle();
    expect(find.byType(DiffLineView), findsNothing);
  });

  testWidgets('the churn map keeps every column while the list narrows', (
    tester,
  ) async {
    await pumpPatch(tester, index(twoFiles));
    expect(find.text('lib/alpha.dart'), findsOneWidget);
    expect(find.text('lib/beta.dart'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pumpAndSettle();

    expect(find.text('lib/beta.dart'), findsNothing);
    // **Dimmed, not dropped.** The strip is the whole-branch context, and a
    // column that vanished would take it with it.
    var map = tester.widget<ChurnMap>(find.byType(ChurnMap));
    expect(map.files, hasLength(2));
    expect(map.visible, {'lib/alpha.dart'});
  });

  testWidgets('a filter that matches nothing says so', (tester) async {
    await pumpPatch(tester, index(twoFiles));

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('Nothing matches.'), findsOneWidget);
  });

  testWidgets('a four-thousand-line file costs a screenful', (tester) async {
    // The whole reason the rows are flat and the text is decoded per hunk.
    var lines = <String>[
      'diff --git a/lib/huge.dart b/lib/huge.dart',
      '--- a/lib/huge.dart',
      '+++ b/lib/huge.dart',
      '@@ -1,2000 +1,2000 @@',
    ];
    for (var i = 0; i < 2000; i++) {
      lines
        ..add('-line $i was')
        ..add('+line $i is');
    }
    lines.add('');

    await pumpPatch(tester, index(lines.join('\n')));
    await tester.tap(find.text('lib/huge.dart'));
    await tester.pumpAndSettle();

    var built = tester.widgetList<DiffLineView>(find.byType(DiffLineView));
    expect(built, isNotEmpty);
    expect(
      built.length,
      lessThan(200),
      reason: '4,000 lines exist; only what fits on screen was built',
    );
  });
  testWidgets('a header that overstates its hunk says so instead of crashing', (
    tester,
  ) async {
    // Truncated mid-hunk, or written by something that is not git: the counts
    // promise nine lines and the body has three. Row extents come from the
    // header, so this used to index past the end of the decoded lines and throw
    // while scrolling.
    await pumpPatch(
      tester,
      index(
        [
          'diff --git a/lib/a.dart b/lib/a.dart',
          '--- a/lib/a.dart',
          '+++ b/lib/a.dart',
          '@@ -1,9 +1,9 @@',
          ' a',
          '-b',
          '+B',
          '',
        ].join('\n'),
      ),
    );

    await tester.tap(find.text('lib/a.dart'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('ended before its header said'),
      findsOneWidget,
      reason: 'drawn, not silently swallowed',
    );
  });
}

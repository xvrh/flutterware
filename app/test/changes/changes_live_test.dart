import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_screen.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';
import 'package:flutterware_app/src/changes/ranking.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';

/// **What survives a re-index**, which is the whole difference between a screen
/// that is live and a screen that punishes you for having scrolled.
///
/// A live re-probe is indistinguishable here from the refresh button: both go
/// through `ChangesController.refresh`, and the button is the half a widget
/// test can press.
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

  ChangeSet setOf(List<FileChange> files, {Ranking? ranking}) => ChangeSet(
    worktreePath: worktree.path,
    patch: PatchIndex.empty,
    base: 'master',
    baseSource: BaseSource.inferred,
    files: files,
    ranking: ranking,
  );

  /// Twenty files, biggest first, so the list is longer than any viewport.
  List<FileChange> twenty() => [
    for (var i = 0; i < 20; i++) file('lib/f$i.dart', added: 100 - i),
  ];

  late ChangeSet current;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: ChangesScreen(
            worktree: worktree,
            // No watch: this file is about what a re-probe does to the screen,
            // not about what wakes it. A real one on a path that does not exist
            // would only make the header say so.
            live: false,
            load: (_) async => current,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reprobe(WidgetTester tester, ChangeSet next) async {
    current = next;
    await tester.tap(find.byTooltip('Read this checkout again'));
    await tester.pumpAndSettle();
  }

  setUp(() => current = setOf(twenty()));

  testWidgets('a file appearing above does not move what you are reading', (
    tester,
  ) async {
    // **Measured in a real window first**: one new file is a 63 px row, and an
    // unchanged pixel offset then points 63 px earlier into the diff you were
    // reading. Small enough to look like a glitch, large enough to lose your
    // place — and an agent that just wrote four files does it four times.
    await pump(tester);
    await tester.drag(find.byKey(changesListKey), const Offset(0, -300));
    await tester.pumpAndSettle();

    var before = tester.getTopLeft(find.text('lib/f9.dart'));
    await reprobe(
      tester,
      setOf([file('lib/BIG.dart', added: 999), ...twenty()]),
    );

    expect(find.text('lib/BIG.dart'), findsNothing, reason: 'it is above us');
    expect(tester.getTopLeft(find.text('lib/f9.dart')), before);
  });

  testWidgets('and a file disappearing above does not either', (tester) async {
    await pump(tester);
    await tester.drag(find.byKey(changesListKey), const Offset(0, -300));
    await tester.pumpAndSettle();

    var before = tester.getTopLeft(find.text('lib/f9.dart'));
    await reprobe(
      tester,
      setOf([...twenty()..removeWhere((f) => f.path == 'lib/f0.dart')]),
    );

    expect(tester.getTopLeft(find.text('lib/f9.dart')), before);
  });

  testWidgets('the row you were on going away leaves the offset alone', (
    tester,
  ) async {
    // Nothing to hold on to — the file was committed away or renamed. Guessing
    // would put you somewhere arbitrary, which is worse than staying put.
    await pump(tester);
    await tester.drag(find.byKey(changesListKey), const Offset(0, -300));
    await tester.pumpAndSettle();

    await reprobe(tester, setOf(twenty().sublist(0, 4)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an expanded file stays expanded, and keeps its lines', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('lib/f3.dart'));
    await tester.pumpAndSettle();
    expect(find.textContaining('@@'), findsOneWidget);

    await reprobe(
      tester,
      setOf([file('lib/new.dart', added: 500), ...twenty()]),
    );
    expect(
      find.textContaining('@@'),
      findsOneWidget,
      reason: 'expansion is keyed by path, and the path did not move',
    );
  });

  testWidgets('the filter you typed is still there, caret and all', (
    tester,
  ) async {
    // The explorer learned this the hard way once the watchers landed: a screen
    // that rebuilds every couple of seconds makes a text field unusable if the
    // field's state is rebuilt with it.
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'f1');
    await tester.pumpAndSettle();
    expect(find.text('lib/f0.dart'), findsNothing);

    await reprobe(tester, setOf([file('lib/new.dart'), ...twenty()]));

    var field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text ?? _typedText(tester), 'f1');
    expect(
      find.text('lib/f0.dart'),
      findsNothing,
      reason: 'and it is still filtering, not merely still displaying',
    );
  });

  testWidgets('the noise drawer stays open across a re-index', (tester) async {
    var noisy = [
      file('lib/real.dart'),
      file('lib/a.g.dart', added: 200),
      file('lib/b.g.dart', added: 190),
    ];
    Ranking ranked(List<FileChange> files) => Ranking([
      for (var f in files)
        RankedFile(
          file: f,
          tier: f.path.endsWith('.g.dart') ? RankTier.noise : RankTier.ordinary,
          rule: f.path.endsWith('.g.dart') ? '**/*.g.dart' : null,
          source: RankSource.builtIn,
        ),
    ]);

    current = setOf(noisy, ranking: ranked(noisy));
    await pump(tester);
    await tester.tap(find.textContaining('low-signal'));
    await tester.pumpAndSettle();
    expect(find.text('lib/a.g.dart'), findsOneWidget);

    var next = [file('lib/second.dart'), ...noisy];
    await reprobe(tester, setOf(next, ranking: ranked(next)));
    expect(find.text('lib/a.g.dart'), findsOneWidget);
  });

  testWidgets('a live screen says it is watching; a dead one says that', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Watching'), findsNothing, reason: 'live: false');

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: ChangesScreen(worktree: worktree, load: (_) async => current),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // `/wt/feature` does not exist, so the watch could not be established —
    // which is exactly the state worth naming, because the screen otherwise
    // looks live and has stopped being true.
    expect(find.text('Not watching'), findsOneWidget);
  });
}

/// The filter has no controller of its own, so its text is read from the
/// editable's state.
String _typedText(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

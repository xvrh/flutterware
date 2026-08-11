import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/native/dev_stack_results.dart';
import 'package:flutterware_app/src/ui/theme.dart';
import 'package:flutterware_app/src/worktrees/facts.dart';
import 'package:flutterware_app/src/worktrees/facts_text.dart';
import 'package:flutterware_app/src/worktrees/explorer_row.dart';
import 'package:flutterware_app/src/worktrees/providers/stack.dart';
import 'package:flutterware_app/src/shell/worktree.dart';

/// The explorer's stack column.
///
/// **The screen answers "which of my checkouts is holding the port block".**
/// That question is the whole reason per-worktree port allocation exists, and
/// until this column there was no way to ask it except to open eight checkouts
/// one at a time.
///
/// What is guarded here is the bargain that makes it affordable: it is a
/// **cache read and never a probe**, so the column can be wrong in one specific
/// way — a stack torn down from a terminal — and the design's answer is to dim
/// it and print its age rather than to spawn a subprocess per row.
void main() {
  late Directory runDir;
  late Directory project;

  setUp(() {
    runDir = Directory.systemTemp.createTempSync('fw-stack-col-run-');
    project = Directory.systemTemp.createTempSync('fw-stack-col-');
  });

  tearDown(() {
    for (var dir in [runDir, project]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  void writeCache(StackReading reading) => File(
    stackCachePath(runDir.path, project.path),
  ).writeAsStringSync(jsonEncode(reading.toJson()));

  group('the probe', () {
    test('reads back what a session left behind', () async {
      writeCache(
        StackReading(
          state: StackState.up,
          at: DateTime.now(),
          detail: 'localhost:8080',
          services: const [
            StackService(name: 'http', port: 8080, state: StackState.up),
          ],
        ),
      );
      var reading = await RunDirStackProbe(
        runDir: () => runDir.path,
      ).probe(project.path);
      expect(reading!.state, StackState.up);
      expect(reading.services.single.port, 8080);
    });

    test('a checkout nobody has opened has nothing to say', () async {
      // Not a failure and not "down": no session has ever probed this one, and
      // finding out would mean running its config and its probe — which is the
      // cost this column exists to avoid.
      expect(
        await RunDirStackProbe(runDir: () => runDir.path).probe(project.path),
        isNull,
      );
    });

    test('a reading with no clock is no reading', () async {
      // It could never be aged, and an un-ageable reading is worse than none:
      // it would sit in the column looking current forever.
      File(
        stackCachePath(runDir.path, project.path),
      ).writeAsStringSync('{"state":"up"}');
      expect(
        await RunDirStackProbe(runDir: () => runDir.path).probe(project.path),
        isNull,
      );
    });

    test('a half-written cache is no cache', () async {
      File(
        stackCachePath(runDir.path, project.path),
      ).writeAsStringSync('{"state":"u');
      expect(
        await RunDirStackProbe(runDir: () => runDir.path).probe(project.path),
        isNull,
      );
    });
  });

  group('the cell', () {
    var now = DateTime(2026, 8, 11, 12);

    Future<void> pump(WidgetTester tester, WorktreeFacts facts) async {
      tester.view.physicalSize = const Size(1400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme,
          home: Material(
            child: WorktreeRow(
              label: 'A worktree',
              branch: 'claude/thing',
              path: '/repo/thing',
              facts: facts,
              now: now,
              showStack: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    WorktreeFacts factsWith(
      StackReading reading, {
      Duration age = Duration.zero,
    }) {
      var at = now.subtract(age);
      var stamped = StackReading(
        state: reading.state,
        at: at,
        detail: reading.detail,
        services: reading.services,
        failure: reading.failure,
      );
      return WorktreeFacts(
        stack: age > stackFreshFor
            ? Fact.stale(stamped, computedAt: at)
            : Fact.fresh(stamped, computedAt: at),
      );
    }

    testWidgets('up carries the port, because that is what you look for', (
      tester,
    ) async {
      await pump(
        tester,
        factsWith(
          const StackReading(
            state: StackState.up,
            at: null,
            services: [
              StackService(name: 'http', port: 8080, state: StackState.up),
            ],
          ),
        ),
      );
      expect(find.text('up'), findsOneWidget);
      expect(find.text(':8080'), findsOneWidget);
      // Fresh readings do not announce their age. A column that says "now" on
      // every row has spent a line saying nothing.
      expect(find.textContaining('seen'), findsNothing);
    });

    testWidgets('a stale reading says when it was taken', (tester) async {
      await pump(
        tester,
        factsWith(
          const StackReading(state: StackState.up, at: null),
          age: const Duration(hours: 2),
        ),
      );
      expect(find.text('up'), findsOneWidget);
      expect(find.text('seen 2h'), findsOneWidget);
    });

    testWidgets('a probe that failed says so in one word', (tester) async {
      // The sentence explaining it is in the expanded detail — 116 pixels can
      // hold a state or an explanation, not both.
      await pump(
        tester,
        factsWith(
          const StackReading(
            state: StackState.unavailable,
            at: null,
            failure: 'Something else is listening on :8080.',
          ),
        ),
      );
      expect(find.text("can't tell"), findsOneWidget);
    });

    testWidgets('partly up is counted, not rounded to up', (tester) async {
      await pump(
        tester,
        factsWith(
          const StackReading(
            state: StackState.up,
            at: null,
            services: [
              StackService(name: 'db', port: 8200, state: StackState.up),
              StackService(
                name: 'sync',
                port: 8202,
                state: StackState.starting,
              ),
            ],
          ),
        ),
      );
      expect(find.text('up 1/2'), findsOneWidget);
    });

    testWidgets('a checkout with no stack draws nothing', (tester) async {
      await pump(tester, const WorktreeFacts());
      expect(find.byKey(stackCellKey), findsOneWidget);
      expect(find.text('up'), findsNothing);
      expect(find.text('down'), findsNothing);
    });

    testWidgets('the column is last to be dropped when the row is short', (
      tester,
    ) async {
      // Widest-first: at 116 it is the narrowest column here, so dropping it
      // is the smallest saving available and the worst trade on offer.
      var facts = factsWith(const StackReading(state: StackState.up, at: null));
      for (var width in [1400.0, 1000.0, 800.0]) {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme,
            home: Material(
              child: WorktreeRow(
                label: 'A worktree',
                facts: facts,
                now: now,
                showStack: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'overflowed at $width');
        expect(
          find.byKey(stackCellKey),
          findsOneWidget,
          reason: 'the stack column went at ${width}px',
        );
      }

      // Everything else has gone by 700, and it still holds.
      tester.view.physicalSize = const Size(700, 600);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme,
          home: Material(
            child: WorktreeRow(
              label: 'A worktree',
              facts: facts,
              now: now,
              showStack: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(changesCellKey), findsNothing);
      expect(find.byKey(stackCellKey), findsOneWidget);
    });
  });

  group('the same words in a terminal', () {
    test('fw worktrees prints what the cell draws', () {
      var now = DateTime(2026, 8, 11, 12);
      var text = worktreeTable([
        (
          Worktree(path: '/repo/a', branch: 'a'),
          WorktreeFacts(
            stack: Fact.fresh(
              StackReading(
                state: StackState.up,
                at: now,
                services: const [
                  StackService(name: 'http', port: 8080, state: StackState.up),
                ],
              ),
            ),
          ),
        ),
        (
          Worktree(path: '/repo/b', branch: 'b'),
          WorktreeFacts(
            stack: Fact.stale(
              StackReading(
                state: StackState.unavailable,
                at: now.subtract(const Duration(hours: 3)),
              ),
            ),
          ),
        ),
      ], now: now).join('\n');
      expect(text, contains('up :8080'));
      expect(text, contains("can't tell (3h)"));
    });

    test('a repo with no stack anywhere loses the column', () {
      var now = DateTime(2026, 8, 11, 12);
      var text = worktreeTable([
        (Worktree(path: '/repo/a', branch: 'a'), const WorktreeFacts()),
      ], now: now).join('\n');
      expect(text, isNot(contains('up')));
    });
  });
}

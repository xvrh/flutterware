import 'dart:io';

import 'package:flutterware/comparison_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/comparison/comparison_controller.dart';
import 'package:flutterware_app/src/comparison/last_run.dart';
import 'package:flutterware_app/src/comparison/last_run_store.dart';
import 'package:flutterware_app/src/comparison/ui/verdict.dart';
import 'package:flutterware_app/src/ui/theme.dart';

void main() {
  ComparedItem eventStep(String id, {String hash = '1'}) => ComparedItem.of(
    id: id,
    baseEvents: [
      {
        'channel': 'system',
        'title': 'flutter/textinput TextInput.setClient',
        'data': {'autofill': 'EditableText-$hash'},
      },
    ],
    headEvents: [
      {
        'channel': 'system',
        'title': 'flutter/textinput TextInput.setClient',
        'data': {'autofill': 'EditableText-'},
      },
    ],
  );

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: appTheme,
      home: Scaffold(body: SizedBox(width: 900, child: child)),
    ),
  );

  // The line no chip can say, and the one the measurement made the case for:
  // every finding on that branch was invisible to a screenshot.
  testWidgets('it names the channels that stayed silent', (tester) async {
    await pump(
      tester,
      ComparisonVerdict(findings: [eventStep('a')], unit: 'step'),
    );

    expect(find.text('nothing moved on pixels, tree or texts'), findsOne);
    expect(find.text('events · 1 step'), findsOne);
  });

  // Drawing the counts here too was the first thing this got wrong, and the
  // two disagreed: the list counts flows and the channels live on steps.
  testWidgets("it does not repeat the receipt strip's counts", (tester) async {
    await pump(
      tester,
      ComparisonVerdict(
        findings: [eventStep('a'), eventStep('b')],
        unit: 'step',
      ),
    );

    expect(find.textContaining('finding'), findsNothing);
    expect(find.textContaining('changed'), findsNothing);
  });

  testWidgets('one repeated shape is one line with its count', (tester) async {
    await pump(
      tester,
      ComparisonVerdict(
        findings: [
          eventStep('a', hash: '11'),
          eventStep('b', hash: '22'),
          eventStep('c', hash: '33'),
        ],
        unit: 'step',
      ),
    );

    expect(find.text('in 3 steps'), findsOne);
    expect(find.textContaining('data.autofill'), findsOne);
  });

  // Null and zero are different answers: no previous run means "new" cannot
  // be answered, where an empty one means every finding is new.
  testWidgets('no previous comparison says nothing about new', (tester) async {
    await pump(
      tester,
      ComparisonVerdict(findings: [eventStep('a')], unit: 'step'),
    );

    expect(find.textContaining('new'), findsNothing);
  });

  testWidgets('a finding the last comparison did not have is new', (
    tester,
  ) async {
    await pump(
      tester,
      ComparisonVerdict(findings: [eventStep('a')], unit: 'step', newCount: 1),
    );

    expect(find.text('1 new since the last comparison'), findsOne);
  });

  testWidgets('a half where no channel spoke draws nothing at all', (
    tester,
  ) async {
    await pump(tester, const ComparisonVerdict(findings: [], unit: 'entry'));

    expect(find.byType(Padding), findsNothing);
  });

  group('the previous run', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('fw-last-run');
    });
    tearDown(() => directory.deleteSync(recursive: true));

    LastComparison run(String id) => LastComparison(
      at: DateTime(2026, 8, 30),
      baseSha: 'abc',
      against: 'master',
      elapsed: Duration.zero,
      items: [ComparedItem(id: id, state: ComparedState.changed)],
    );

    test('the first ever run has no predecessor', () {
      var store = LastRunStore(directory.path);
      store.write(ComparisonHalfKind.previews, run('a'));

      expect(store.readPrevious(ComparisonHalfKind.previews), isNull);
      expect(store.read(ComparisonHalfKind.previews)?.items?.single.id, 'a');
    });

    // One generation, because that is the whole question — not a history.
    test('writing rotates the last run into the previous slot', () {
      var store = LastRunStore(directory.path);
      store.write(ComparisonHalfKind.previews, run('a'));
      store.write(ComparisonHalfKind.previews, run('b'));

      expect(store.read(ComparisonHalfKind.previews)?.items?.single.id, 'b');
      expect(
        store.readPrevious(ComparisonHalfKind.previews)?.items?.single.id,
        'a',
      );
    });

    test('the halves keep their own history', () {
      var store = LastRunStore(directory.path);
      store.write(ComparisonHalfKind.previews, run('a'));
      store.write(ComparisonHalfKind.previews, run('b'));

      expect(store.readPrevious(ComparisonHalfKind.scenarios), isNull);
    });
  });
}

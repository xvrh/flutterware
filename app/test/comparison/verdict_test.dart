import 'dart:io';

import 'package:flutterware/comparison_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/comparison/comparison_controller.dart';
import 'package:flutterware_app/src/comparison/last_run.dart';
import 'package:flutterware_app/src/comparison/last_run_store.dart';
import 'package:flutterware_app/src/comparison/rules.dart';
import 'package:flutterware_app/src/comparison/ui/verdict.dart';
import 'package:flutterware_app/src/ui/theme.dart';

void main() {
  /// A `TextInput.setClient` as the framework really reports it — the autofill
  /// id is four levels down, which is what makes the untrimmed property path
  /// unreadable.
  ComparedItem eventStep(String id, {String hash = '1'}) => ComparedItem.of(
    id: id,
    baseEvents: [
      {
        'channel': 'system',
        'title': 'flutter/textinput TextInput.setClient',
        'data': {
          'arguments': [
            1,
            {
              'autofill': {'uniqueIdentifier': 'EditableText-$hash'},
            },
          ],
        },
      },
    ],
    headEvents: [
      {
        'channel': 'system',
        'title': 'flutter/textinput TextInput.setClient',
        'data': {
          'arguments': [
            1,
            {
              'autofill': {'uniqueIdentifier': 'EditableText-'},
            },
          ],
        },
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

  // It read `system · flutter/textinput TextInput.setClient ·
  // data.arguments[1].autofill.uniqueIdentifier ⟨11⟩ in 11 steps` — three
  // identifiers and two numbers that were the same number, telling a reader
  // nothing to conclude.
  testWidgets('one repeated shape is a sentence, not a pile of ids', (
    tester,
  ) async {
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

    expect(
      find.textContaining('the same field moved in all 3 steps'),
      findsOne,
    );
    // Trimmed to the half anybody could name: the plumbing in front of it is
    // a wire path, not a field.
    expect(find.textContaining('data.arguments'), findsNothing);
    expect(find.textContaining('autofill.uniqueIdentifier'), findsOne);
  });

  testWidgets('a shape only some findings wear is a proportion', (
    tester,
  ) async {
    await pump(
      tester,
      ComparisonVerdict(
        findings: [
          eventStep('a', hash: '11'),
          eventStep('b', hash: '22'),
          ComparedItem.of(
            id: 'c',
            baseTexts: const ['Save'],
            headTexts: const ['Pay'],
          ),
        ],
        unit: 'step',
      ),
    );

    expect(find.textContaining('the same field moved in 2 of 3'), findsOne);
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

  group('rules', () {
    ChannelDelta delta(String channel, {String? sub, String? origin}) =>
        ChannelDelta(
          channel: channel,
          subchannel: sub,
          property: 'x',
          origin: origin,
        );

    test('a one-constraint rule is what a chip builds', () {
      var rule = ComparisonRule.on('subchannel', 'system');

      expect(rule.isSingle, isTrue);
      expect(rule.label, 'system');
      expect(rule.matches(delta('events', sub: 'system')), isTrue);
      expect(rule.matches(delta('events', sub: 'db')), isFalse);
    });

    // The seam the whole staging rests on: the chip and the authored rule are
    // one record, so v2 lengthens it rather than replacing it.
    test('constraints are ANDed, so a longer rule is narrower', () {
      var rule = const ComparisonRule([
        RuleConstraint('subchannel', 'db'),
        RuleConstraint('origin', 'lib/cache.dart'),
      ]);

      expect(
        rule.matches(delta('events', sub: 'db', origin: 'lib/cache.dart')),
        isTrue,
      );
      expect(
        rule.matches(delta('events', sub: 'db', origin: 'lib/other.dart')),
        isFalse,
      );
      expect(rule.label, 'db · lib/cache.dart');
    });

    test('a finding is hidden only when every delta of it is', () {
      var set = RuleSet([ComparisonRule.on('subchannel', 'system')]);
      var noisy = eventStep('a');
      var mixed = ComparedItem.of(
        id: 'b',
        baseEvents: [
          {'channel': 'system', 'title': 't', 'detail': '1'},
          {'channel': 'network', 'title': 'POST /x', 'detail': '200'},
        ],
        headEvents: [
          {'channel': 'system', 'title': 't', 'detail': '2'},
          {'channel': 'network', 'title': 'POST /x', 'detail': '500'},
        ],
      );

      expect(set.hidesAll(noisy), isTrue);
      expect(set.hidesAll(mixed), isFalse);
      expect(set.visible(mixed), hasLength(1));
    });

    // `added`, `removed` and `broke` say something no channel does, and a rule
    // about channels has no opinion about them. Hiding those would be the
    // filter deciding what the comparison found.
    test('a finding with no deltas at all is never hidden by a rule', () {
      var set = RuleSet([ComparisonRule.on('channel', 'events')]);

      expect(
        set.hidesAll(const ComparedItem(id: 'a', state: ComparedState.added)),
        isFalse,
      );
    });

    testWidgets('an excluded chip keeps the count it is hiding', (
      tester,
    ) async {
      await pump(
        tester,
        ComparisonVerdict(
          findings: [eventStep('a'), eventStep('b')],
          unit: 'step',
          rules: [ComparisonRule.on('subchannel', 'system')],
          onToggle: (_) {},
        ),
      );

      // Not `0 steps`: a chip reading zero is one nobody would turn back on.
      expect(find.text('system · 2 steps'), findsOne);
      expect(find.text('2 steps hidden by 1 rule'), findsOne);
    });

    testWidgets('tapping a chip asks for the rule it stands for', (
      tester,
    ) async {
      ComparisonRule? asked;
      await pump(
        tester,
        ComparisonVerdict(
          findings: [eventStep('a')],
          unit: 'step',
          onToggle: (rule) => asked = rule,
        ),
      );
      await tester.tap(find.text('system · 1 step'));

      expect(asked?.constraints.single.facet, 'subchannel');
      expect(asked?.constraints.single.value, 'system');
    });
  });
}

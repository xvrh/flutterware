import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/events.dart';
import 'package:flutterware/src/scenarios/run_listener.dart';

/// What the app did between two captured steps, and which step it lands on.
///
/// The buffer these exercise is the harness's in a real run; here the test is
/// the harness, which is also what a bare `flutter test` looks like to the
/// code under test.
void main() {
  var captures = <ScenarioStepCapture>[];
  setUp(() {
    captures = [];
    scenarioRunListener = captures.add;
    scenarioEventBuffer = ScenarioEventBuffer();
  });
  tearDown(() {
    scenarioRunListener = null;
    scenarioEventBuffer = null;
  });

  List<String> titles(ScenarioStepCapture capture) => [
    for (var event in capture.events) event.title,
  ];

  scenario('an event lands on the step that follows it', (s) async {
    await s.pumpWidget(const _App());

    recordScenarioEvent(ScenarioEvent.analytics('checkout_started'));
    await s.tap('Save');

    expect(titles(captures[0]), isEmpty);
    expect(titles(captures[1]), ['checkout_started']);
  });

  scenario('the transition names the verb and its target', (s) async {
    await s.pumpWidget(const _App());
    await s.tap('Save');
    await s.enterText(TextField, 'hello');
    await s.screen('Done');

    expect(
      [for (var c in captures) '${c.verb} ${c.target ?? ''}'.trim()],
      ['pumpWidget _App', 'tap "Save"', 'enterText TextField', 'screen'],
    );
  });

  scenario('events recorded before the first step land on it', (s) async {
    recordScenarioEvent(ScenarioEvent.log('booting'));
    await s.pumpWidget(const _App());

    expect(titles(captures.single), ['booting']);
  });

  scenario('a skipped shot passes its events to the next capture', (s) async {
    await s.pumpWidget(const _App(), shot: Shot.skip);
    recordScenarioEvent(ScenarioEvent.log('during'));

    await s.tap('Save');

    expect(titles(captures.single), ['during']);
  });

  // A scenario's replays share one capture list, and only the test that
  // follows sees all of them — the last replay is still running when the body
  // ends for the last time.
  var branched = <ScenarioStepCapture>[];
  scenario('every branch records its own events', (s) async {
    await s.pumpWidget(const _App());
    recordScenarioEvent(ScenarioEvent.log('on the shared prefix'));
    await s.tap('Save');

    await s.split({
      'left': () async {
        recordScenarioEvent(ScenarioEvent.log('left only'));
        await s.screen('Left');
      },
      'right': () async {
        recordScenarioEvent(ScenarioEvent.log('right only'));
        await s.screen('Right');
      },
    });
    branched = captures;
  });

  test('the split above recorded its prefix once, not once per branch', () {
    // Four steps: the two shared ones, then one per branch. The prefix's event
    // is on step 2 exactly once — the second replay walks the same positions
    // and its buffer is discarded rather than appended.
    expect(
      [for (var c in branched) c.name ?? 'auto'],
      ['auto', 'auto', 'Left', 'Right'],
    );
    expect(titles(branched[1]), ['on the shared prefix']);
    expect(titles(branched[2]), ['left only']);
    expect(titles(branched[3]), ['right only']);
  });

  scenario('the failing step carries the events that led to it', (s) async {
    await s.pumpWidget(const _App());
    recordScenarioEvent(
      ScenarioEvent.request(method: 'POST', url: '/pay', status: 500),
    );
    try {
      await s.tap('Nothing here');
    } on ScenarioTargetError {
      // The verb fails, the failure step captures, and the request that
      // preceded it is the reason a reader opens that step at all.
    }

    expect(captures.last.failure, isNotNull);
    expect(titles(captures.last), ['POST /pay']);
    expect(captures.last.events.single.error, isTrue);
  });

  scenario('events past the per-step cap are counted, not silently lost', (
    s,
  ) async {
    await s.pumpWidget(const _App());
    for (var i = 0; i < maxScenarioEventsPerStep + 5; i++) {
      recordScenarioEvent(ScenarioEvent.log('$i'));
    }
    await s.tap('Save');

    expect(captures.last.events, hasLength(maxScenarioEventsPerStep));
    expect(captures.last.eventsDropped, 5);
  });

  testWidgets('recording outside a run is a no-op', (tester) async {
    scenarioEventBuffer = null;
    expect(
      () => recordScenarioEvent(ScenarioEvent.log('nobody is listening')),
      returnsNormally,
    );
  });

  test('a request event reads as a line, and 4xx is an error', () {
    var event = ScenarioEvent.request(
      method: 'POST',
      url: '/login',
      status: 401,
    );
    expect(event.title, 'POST /login');
    expect(event.detail, '401');
    expect(event.error, isTrue);
    expect(ScenarioEvent.request(method: 'GET', url: '/me').error, isFalse);
  });

  test(
    'a query event summarises to its first line and keeps the whole SQL',
    () {
      var event = ScenarioEvent.query(
        sql: 'SELECT *\nFROM items\nWHERE id = ?',
        args: [42],
        rows: 1,
      );
      expect(event.title, 'SELECT * …');
      expect(event.detail, '1 row');
      expect(event.body, contains('WHERE id = ?'));
      expect(event.data, {
        'args': [42],
      });
    },
  );

  test('a payload the encoder cannot take does not break the artifact', () {
    // A fake reports whatever it had in hand, and a channel's decoded
    // arguments are whatever the plugin sent. The harness writes these with a
    // `toEncodable` fallback for exactly this reason: a value JSON cannot take
    // must degrade to what it prints as, never throw out of the step listener
    // that was only describing it.
    var event = ScenarioEvent.custom(
      channel: 'network',
      title: 'GET /me',
      data: {'when': DateTime(2026), 'who': Object()},
    );
    expect(
      () => jsonEncode([event.toJson()], toEncodable: (value) => '$value'),
      returnsNormally,
    );
    expect(() => jsonEncode([event.toJson()]), throwsA(anything));
  });

  test('an oversized body is truncated with a marker', () {
    var event = ScenarioEvent.custom(
      channel: 'network',
      title: 'GET /big',
      body: 'x' * 5000,
    );
    var body = event.toJson()['body']! as String;
    expect(body, contains('more characters'));
    expect(body.length, lessThan(5000));
  });
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          TextButton(onPressed: () {}, child: const Text('Save')),
          const TextField(),
        ],
      ),
    ),
  );
}

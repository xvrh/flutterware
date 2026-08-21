import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/app_events.dart';
// ignore: implementation_imports
import 'package:flutterware/src/scenarios/harness.dart';

/// The one-line summaries that ride inline on a step.
///
/// Two jobs, and the second is why this file exists. They keep a step's
/// summary small enough to read without opening anything — and where they
/// cannot, they have to *say so*. Twelve titles handed back out of forty read
/// as "the app did twelve things", and the arithmetic that would disprove it
/// needs the `system` exclusion to be known first.
void main() {
  List<AppEvent> events(int count, {String channel = AppChannel.analytics}) => [
    for (var i = 0; i < count; i++)
      AppEvent.custom(channel: channel, title: 'event $i'),
  ];

  test('a quiet step has none at all, rather than an empty list', () {
    expect(inlineEventTitles([]), isNull);
  });

  test('the detail rides beside the title', () {
    expect(
      inlineEventTitles([
        AppEvent.request(method: 'POST', url: '/login', status: 401),
      ]),
      ['POST /login → 401'],
    );
  });

  test('system is left out — it is the volume and none of the signal', () {
    var titles = inlineEventTitles([
      AppEvent.custom(channel: AppChannel.system, title: 'flutter/textinput'),
      AppEvent.analytics('checkout'),
    ]);

    expect(titles, ['checkout']);
  });

  test('a step under the cap is handed back whole', () {
    expect(inlineEventTitles(events(12)), hasLength(12));
    expect(inlineEventTitles(events(12))!.last, 'event 11');
  });

  test('over the cap it says how many it kept back, and how to get them', () {
    var titles = inlineEventTitles(events(40))!;

    expect(titles, hasLength(13), reason: 'twelve, and the marker');
    expect(titles.take(12), everyElement(startsWith('event ')));
    expect(titles.last, '… 28 more — scenarios read events: true');
  });

  test('the count that is marked is of the titles, not of the events', () {
    // 30 events, 20 of them system: the marker has to describe what a reader
    // would otherwise think it was seeing all of, which is the 10 that are
    // left after the exclusion — not the 30 the step recorded.
    var titles = inlineEventTitles([
      ...events(20, channel: AppChannel.system),
      ...events(18),
    ])!;

    expect(titles.last, '… 6 more — scenarios read events: true');
  });
}

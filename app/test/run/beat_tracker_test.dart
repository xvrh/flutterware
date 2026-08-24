import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/run/beat_tracker.dart';

/// The collector for a run nobody is driving. What is under test is the
/// polling contract — not the wire, which is `DriveSession`'s.
void main() {
  test('an empty drain reports nothing at all', () async {
    var calls = 0;
    var tracker = RunBeatTracker(
      drain: () async => const [],
      onBeats: (_) => calls++,
    );

    expect(await tracker.poll(), 0);
    expect(calls, 0, reason: 'a quiet app must not look like an event');
  });

  test('what the guest buffered is handed over whole', () async {
    var seen = <Map>[];
    var tracker = RunBeatTracker(
      drain: () async => [
        {'at': '2026-08-24T10:00:00Z', 'verb': 'tap', 'target': '"Pay"'},
        {
          'at': '2026-08-24T10:00:01Z',
          'verb': 'tap',
          'target': '"Confirm"',
          'screenshot': {'base64': 'xx'},
          'texts': ['Thanks'],
        },
      ],
      onBeats: seen.addAll,
    );

    expect(await tracker.poll(), 2);
    expect(seen, hasLength(2));
    expect(
      seen.last['screenshot'],
      isNotNull,
      reason: 'the burst-ender keeps its picture across the wire',
    );
  });

  test('polling stops after the app has failed enough times', () {
    fakeAsync((async) {
      var drains = 0;
      var tracker = RunBeatTracker(
        drain: () async {
          drains++;
          throw StateError('gone');
        },
        onBeats: (_) => fail('a failed drain reports nothing'),
      );

      tracker.start(const Duration(milliseconds: 100));
      async.elapse(const Duration(seconds: 2));

      expect(tracker.broken, isTrue);
      expect(
        drains,
        5,
        reason:
            'it gives up after five, rather than polling a dead app '
            'for the life of the session',
      );
    });
  });

  test('a stopped tracker stops asking', () {
    fakeAsync((async) {
      var drains = 0;
      var tracker = RunBeatTracker(
        drain: () async {
          drains++;
          return const [];
        },
        onBeats: (_) {},
      );

      tracker.start(const Duration(milliseconds: 100));
      async.elapse(const Duration(milliseconds: 350));
      var atStop = drains;
      tracker.stop();
      async.elapse(const Duration(seconds: 1));

      expect(atStop, greaterThan(0));
      expect(drains, atStop);
    });
  });
}

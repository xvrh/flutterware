import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/scan_cache.dart';

/// The shared scan cache, exercised on the seams where its four predecessors
/// diverged: the stale-pending trap after an invalidate, sticky versus
/// retrying failures, and a scan that loses the race to the invalidation that
/// disowned it.
void main() {
  test('a scan runs once, however many times it is asked for', () async {
    var scans = 0;
    var cache = ScanCache<String, int>(
      scan: (key) async => ++scans,
      onChanged: () {},
    );

    cache.track('.');
    await Future.wait([cache.load('.'), cache.load('.')]);
    await cache.load('.');

    expect(scans, 1);
    expect(cache['.'], 1);
  });

  test('a load after invalidate re-reads — the stale-pending trap', () async {
    var scans = 0;
    var cache = ScanCache<String, int>(
      // Completes as fast as a scan can: the shape that historically left a
      // finished future registered as pending forever.
      scan: (key) async => ++scans,
      onChanged: () {},
    );

    await cache.load('.');
    cache.invalidate('.');
    expect(cache['.'], isNull);

    await cache.load('.');
    expect(scans, 2);
    expect(cache['.'], 2);
  });

  test('a failure is sticky for load, and reload is the way back', () async {
    var scans = 0;
    var broken = true;
    var cache = ScanCache<String, int>(
      scan: (key) async {
        scans++;
        if (broken) throw ScanFailure('the disk said no');
        return scans;
      },
      onChanged: () {},
    );

    await cache.load('.');
    expect(cache.failureFor('.'), 'the disk said no');
    expect(cache.anyFailed, isTrue);

    // Remounting panels keep asking; the known-bad scan must not re-run.
    await cache.load('.');
    cache.track('.');
    await cache.load('.');
    expect(scans, 1);

    broken = false;
    await cache.reload('.');
    expect(scans, 2);
    expect(cache.failureFor('.'), isNull);
    expect(cache['.'], 2);
  });

  test('retryAfterFailure re-reads on the next load', () async {
    var scans = 0;
    var broken = true;
    var cache = ScanCache<String, int>(
      scan: (key) async {
        scans++;
        if (broken) throw ScanFailure('half-written');
        return scans;
      },
      onChanged: () {},
      retryAfterFailure: true,
    );

    await cache.load('.');
    expect(cache.failureFor('.'), 'half-written');

    broken = false;
    await cache.load('.');
    expect(scans, 2);
    expect(cache['.'], 2);
    expect(cache.failureFor('.'), isNull, reason: 'a success clears it');
  });

  test(
    'an invalidated scan cannot land over the one that replaced it',
    () async {
      var settled = <String>[];
      var slow = Completer<int>();
      var answers = <Future<int>>[slow.future, Future.value(42)];
      var cache = ScanCache<String, int>(
        scan: (key) => answers.removeAt(0),
        onChanged: () {},
        onSettled: settled.add,
      );

      var first = cache.load('.');
      expect(cache.isScanning('.'), isTrue);

      // The reload disowns the in-flight scan and reads again.
      await cache.reload('.');
      expect(cache['.'], 42);
      expect(cache.isScanning('.'), isTrue, reason: 'the old scan still runs');

      // The old scan settles late, with an answer from before the invalidate.
      slow.complete(1);
      await first;
      expect(cache['.'], 42, reason: 'the stale answer is discarded');
      expect(cache.isScanning('.'), isFalse);
      expect(settled, ['.'], reason: 'onSettled skips the disowned scan');
    },
  );

  test('a stale failure cannot shadow the fresh answer either', () async {
    var slow = Completer<int>();
    var answers = <Future<int>>[slow.future, Future.value(7)];
    var cache = ScanCache<String, int>(
      scan: (key) => answers.removeAt(0),
      onChanged: () {},
    );

    var first = cache.load('.');
    await cache.reload('.');

    slow.completeError(ScanFailure('from before the reload'));
    await first;
    expect(cache.failureFor('.'), isNull);
    expect(cache['.'], 7);
  });

  test('settledKeys holds values and failures, and iterates safely', () async {
    var cache = ScanCache<String, int>(
      scan: (key) async {
        if (key == 'bad') throw ScanFailure('no');
        return key.length;
      },
      onChanged: () {},
    );
    await Future.wait([cache.load('a'), cache.load('bad')]);

    expect(cache.settledKeys, {'a', 'bad'});
    // A poller invalidates while walking; a snapshot must not throw.
    for (var key in cache.settledKeys) {
      cache.invalidate(key);
    }
    expect(cache.settledKeys, isEmpty);
  });

  test(
    'onChanged fires for a scan starting, landing and invalidating',
    () async {
      var changes = 0;
      var cache = ScanCache<String, int>(
        scan: (key) async => 1,
        onChanged: () => changes++,
      );

      await cache.load('.');
      expect(changes, 2, reason: 'once starting, once landing');
      cache.invalidate('.');
      expect(changes, 3);
    },
  );
}

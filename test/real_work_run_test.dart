import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/real_work/tracker.dart';

void main() {
  setUp(resetTrackedRealWork);

  test('run counts the work and runs it in the root zone', () async {
    Zone? seen;
    var result = await runZoned(() {
      return RealWork.run(() async {
        seen = Zone.current;
        return 7;
      });
    });
    expect(result, 7);
    expect(seen, same(Zone.root));
    expect(RealWork.pending, 0);
  });

  test(
    'an error inside run reaches the caller, and the count still drops',
    () async {
      var failing = RealWork.run<int>(() async => throw StateError('no'));
      await expectLater(failing, throwsStateError);
      expect(RealWork.pending, 0);
    },
  );

  test('a memoized future from another zone resolves through run', () async {
    // The trap run exists for: a future created in one zone, awaited from
    // another whose queue nobody drains. Here the "other" zone is a plain
    // one, so the await would resume anyway; what this pins is that the
    // work sees the root zone and the caller sees the value.
    late Future<int> memo;
    runZoned(() {
      memo = Future.delayed(const Duration(milliseconds: 1), () => 3);
    });
    var v = await runZoned(() => RealWork.run(() => memo));
    expect(v, 3);
  });
}

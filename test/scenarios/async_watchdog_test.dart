import 'dart:async';

import 'package:flutterware/src/scenarios/async_watchdog.dart';
import 'package:flutterware/flutter_test.dart';

/// The one failure mode of fake time that looks exactly like nothing
/// happening: a `runAsync` that never returns. The watchdog cannot break it —
/// the body is suspended inside it — but it must say so, in seconds, instead
/// of leaving the run silent until something far away gives up.
void main() {
  var budget = scenarioRunAsyncStallBudget;
  setUp(() => scenarioRunAsyncStallBudget = const Duration(milliseconds: 50));
  tearDown(() {
    scenarioRunAsyncStallBudget = budget;
    scenarioAsyncStall = null;
  });

  test('a runAsync that never returns is named, not waited on', () async {
    var wedged = Completer<void>();
    unawaited(watchRunAsync(() => wedged.future));

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(scenarioAsyncStall, isNotNull);
    // The diagnosis, not the list of possibilities: the cache that is nearly
    // always behind it, and the two ways out.
    expect(scenarioAsyncStall, contains('CachingAssetBundle'));
    expect(scenarioAsyncStall, contains('ScenarioAssetBundle'));

    wedged.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test('one that returns leaves nothing behind', () async {
    await watchRunAsync(() async => 'done');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(scenarioAsyncStall, isNull);
  });

  test('a slow one that finishes clears its own finding', () async {
    await watchRunAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );

    expect(scenarioAsyncStall, isNull);
  });
}

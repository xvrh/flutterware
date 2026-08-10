import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/capture/settle.dart';
import 'package:flutterware_app/src/capture/settle_wait.dart';

/// A source whose busyness a test drives.
class _Source implements SettleSource {
  _Source([this.busyWith]);

  @override
  String? busyWith;
}

/// The wait behind `fw capture` — which had no tests, and one way to hang.
///
/// **Plain `test`, with real timers and a real clock, on purpose.** The loop
/// measures its deadline with a `Stopwatch`, so a `testWidgets` fake clock does
/// not move it: `tester.pump(seconds: 30)` advances Flutter's notion of time
/// and leaves this function believing no time has passed at all. Every duration
/// here is therefore real, and small.
///
/// No frames are produced either, which is not a gap in the harness — it is the
/// condition under test. A window the platform has stopped driving produces
/// none, and the loop has to keep its promises anyway.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Short enough that a test does not sit through the real two seconds.
  const grace = Duration(milliseconds: 10);

  test('settles once nothing has been busy for the quiet period', () async {
    var registry = SettleRegistry()..add(_Source());

    var outcome = await waitForSettle(
      registry,
      quiet: const Duration(milliseconds: 50),
      timeout: const Duration(seconds: 5),
      frameGrace: grace,
    );

    expect(outcome.settled, isTrue);
    expect(outcome.waitingOn, isEmpty);
  });

  test('a source that stays busy is reported, not waited on forever', () async {
    // The shape of the bug this file exists for: a plugin whose panel was never
    // opened, reporting work that is not in flight. It has to end, and it has
    // to name who held it up.
    var registry = SettleRegistry()..add(_Source('finding devices'));

    var outcome = await waitForSettle(
      registry,
      quiet: const Duration(milliseconds: 20),
      timeout: const Duration(milliseconds: 200),
      frameGrace: grace,
    );

    expect(outcome.settled, isFalse);
    expect(outcome.waitingOn, ['finding devices']);
  });

  test('the deadline is honoured with no frame to help it along', () async {
    // **The hang.** Every iteration used to end on a bare `await endOfFrame`,
    // which completes in a post-frame callback — so a platform that has stopped
    // delivering vsync (macOS, for a minimised or fully occluded window) never
    // completed it, and the `while` that consults the deadline was never
    // reached a second time. `--timeout` could not fire, and `fw capture` waited
    // on a child that was never coming back.
    //
    // Nothing here produces a frame. The wait must still return, and roughly on
    // time.
    var registry = SettleRegistry()..add(_Source('compiling'));
    var elapsed = Stopwatch()..start();

    var outcome = await waitForSettle(
      registry,
      quiet: const Duration(milliseconds: 20),
      timeout: const Duration(milliseconds: 300),
      frameGrace: grace,
    );
    elapsed.stop();

    expect(outcome.settled, isFalse);
    expect(
      elapsed.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: 'it returned because of its deadline, not because of a frame',
    );
  });

  test('busy then idle settles', () async {
    var source = _Source('compiling');
    var registry = SettleRegistry()..add(source);
    Future<void>.delayed(
      const Duration(milliseconds: 80),
      () => source.busyWith = null,
    );

    var outcome = await waitForSettle(
      registry,
      quiet: const Duration(milliseconds: 30),
      timeout: const Duration(seconds: 5),
      frameGrace: grace,
    );

    expect(outcome.settled, isTrue);
  });

  test('the quiet period outlasts a gap between two pieces of work', () async {
    // The catalog goes briefly idle between compiling an entry and reloading it
    // into the guest. A wait that fired in that gap would photograph the
    // previous entry, looking every bit like a success — which is why idle once
    // is not enough.
    var source = _Source('compiling');
    var registry = SettleRegistry()..add(source);
    Future<void>.delayed(
      const Duration(milliseconds: 40),
      () => source.busyWith = null,
    );
    Future<void>.delayed(
      const Duration(milliseconds: 70),
      () => source.busyWith = 'reloading',
    );
    Future<void>.delayed(
      const Duration(milliseconds: 140),
      () => source.busyWith = null,
    );

    var outcome = await waitForSettle(
      registry,
      quiet: const Duration(milliseconds: 60),
      timeout: const Duration(seconds: 5),
      frameGrace: grace,
    );

    expect(outcome.settled, isTrue);
    expect(
      source.busyWith,
      isNull,
      reason: 'it waited through the hand-off rather than firing inside it',
    );
  });
}

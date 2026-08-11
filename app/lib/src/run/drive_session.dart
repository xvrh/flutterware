import 'dart:async';

import 'handle.dart';
import 'connection.dart';

/// The app was there and said nothing in time.
///
/// Carries the diagnosis as its whole message: every surface renders a drive
/// error by stringifying it, and "DriveTimeout: …" in front of a sentence
/// written for an agent helps nobody.
class DriveTimeout implements Exception {
  DriveTimeout(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A held connection for the drive loop.
///
/// `RunCore`'s per-call connect-read-dispose is right for probes and wrong
/// for a loop of act calls: the drive transaction is called in bursts —
/// observe, tap, observe — and paying a fresh websocket and `getVM` per step
/// is pure latency. This holds one [RunConnection] across calls and drops it
/// on any error, so the next call reconnects against whatever the app has
/// become (a hot restart keeps the VM service; a relaunch does not).
///
/// Concurrent actors need no lease: the guest serializes transactions on its
/// side, and the journal is the coordination mechanism — two writers
/// interleave as two actors in one story.
class DriveSession {
  DriveSession(this.handle);

  final RunHandle handle;

  /// The connect in flight or done — memoized as a future, so two overlapping
  /// acts on a fresh session share one websocket instead of the second
  /// silently orphaning the first.
  Future<RunConnection>? _connection;

  /// One drive transaction: `ext.flutterware.act` with [args], the guest's
  /// bundle back. Throws what the connection threw — the caller owns turning
  /// "no such extension" into "this app runs without the guest".
  ///
  /// Bounded by [_deadlineFor], because the guest's own "never hang" rule only
  /// covers a guest that is *running*. A backgrounded iOS app is suspended by
  /// the OS: it is not scheduled, so the extension is never dispatched and no
  /// answer ever comes. Measured 2026-08-11 — the MCP client gave up at 1800s,
  /// which is the one behavior this surface may not have. On the deadline the
  /// call is diagnosed ([_whyNoAnswer]) and thrown as a [DriveTimeout].
  ///
  /// **A suspended app has two doors and both had to be shut.** The session is
  /// dropped whenever a probe finds the app unresponsive, so the *next* call
  /// re-connects — and against a suspended process the connect is what times
  /// out, five seconds earlier and with `TimeoutException after 0:00:05` as
  /// its whole message. Measured while fixing the first door: an agent got a
  /// sentence about a future instead of a sentence about its app.
  Future<Map<String, dynamic>> act(Map<String, String> args) async {
    RunConnection connection;
    try {
      connection = await _ensure();
    } on TimeoutException {
      await _drop();
      throw DriveTimeout('Could not reach the app. $_notScheduled');
    }
    var deadline = _deadlineFor(args);
    try {
      var response = await connection.service
          .callServiceExtension(
            'ext.flutterware.act',
            isolateId: connection.isolateId,
            args: args,
          )
          .timeout(deadline);
      return response.json ?? const {};
    } on TimeoutException {
      var why = await _whyNoAnswer(connection);
      await _drop();
      throw DriveTimeout(
        'The app did not answer in ${deadline.inSeconds}s. $why',
      );
    } on Object {
      await _drop();
      rethrow;
    }
  }

  /// How long to wait for a bundle before calling the app unresponsive.
  ///
  /// Derived from what this very call asked the guest to spend rather than
  /// fixed, so raising `settleMs` for a slow screen does not turn into a
  /// timeout: the guest's own budgets, plus slack for the parts that are not
  /// budgeted — the screenshot, the tree walk, the round trip, and another
  /// actor's transaction this one may be queued behind.
  ///
  /// `scrollTo` is the one verb whose work is bounded by a count instead of a
  /// clock: `maxScrolls` drags, each with a pump. It gets an allowance per
  /// scroll on top, so a long list does not read as a hung app.
  Duration _deadlineFor(Map<String, String> args) {
    int ms(String key, int fallback) =>
        int.tryParse(args[key] ?? '') ?? fallback;
    var budget =
        ms('settleMs', 800) + ms('actTimeoutMs', 3000) + ms('waitMs', 0);
    if (args['verb'] == 'scrollTo') budget += ms('maxScrolls', 50) * 500;
    return Duration(milliseconds: budget) + const Duration(seconds: 20);
  }

  /// Why nothing came back, asked of the VM itself.
  ///
  /// The distinction is worth a round trip: if the VM service answers, the
  /// process is being scheduled and something inside the app is slow or stuck;
  /// if it does not, the process is not running at all — which on a phone is
  /// the ordinary case of an app that went to the background, not a fault.
  Future<String> _whyNoAnswer(RunConnection connection) async {
    try {
      await connection.service.getVersion().timeout(const Duration(seconds: 2));
      return 'Its VM service still answers, so the app is running and the '
          'verb itself is slow or wedged — an animation that never ends, or a '
          'transaction from another actor ahead of this one in the queue. Try '
          'again with a larger settleMs, or `observe` to see the screen.';
    } on Object {
      return _notScheduled;
    }
  }

  /// The diagnosis both doors share.
  ///
  /// Says what to do rather than what broke, and says the step is not lost
  /// because that is the surprising part: the guest is not gone, it is
  /// unscheduled, and the request it was handed runs the moment the OS gives
  /// it a thread again (measured — a tap sent to a backgrounded app landed on
  /// resume).
  static const _notScheduled =
      'Its VM service does not answer, so the process is not being scheduled: '
      'on iOS the OS suspends a backgrounded app, and it answers nothing until '
      'it is in the foreground again. Bring the app to the front and retry. '
      'The step is not lost — a suspended guest runs the request it was sent '
      'when it resumes.';

  Future<RunConnection> _ensure() {
    if (_connection case var held?) return held;
    var uri = handle.vmService;
    if (uri == null) {
      throw StateError(
        '${handle.entrypointLabel} has no VM service yet — it is still '
        'building. Watch ${handle.logPath}.',
      );
    }
    var connecting = RunConnection.connect(uri);
    _connection = connecting;
    // A failed connect must not stay memoized: the next act should try again,
    // not rethrow a stale failure forever. The caller still sees the error —
    // this side-chain only clears the cache.
    unawaited(
      connecting.then(
        (_) {},
        onError: (Object _) {
          if (_connection == connecting) _connection = null;
        },
      ),
    );
    return connecting;
  }

  Future<void> _drop() async {
    var held = _connection;
    _connection = null;
    if (held != null) {
      try {
        await (await held).close();
      } on Object {
        // Dropped because it was broken; a close that fails too says nothing
        // new.
      }
    }
  }

  Future<void> close() => _drop();
}

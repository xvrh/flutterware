import 'dart:async';

import 'handle.dart';
import 'connection.dart';

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
  Future<Map<String, dynamic>> act(Map<String, String> args) async {
    var connection = await _ensure();
    try {
      var response = await connection.service.callServiceExtension(
        'ext.flutterware.act',
        isolateId: connection.isolateId,
        args: args,
      );
      return response.json ?? const {};
    } on Object {
      await _drop();
      rethrow;
    }
  }

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

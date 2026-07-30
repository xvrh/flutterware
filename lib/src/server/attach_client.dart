import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'protocol.dart';

/// One event received from an inspected server — replayed from its ring or
/// live off its tail.
class ServerEvent {
  ServerEvent({
    required this.channel,
    required this.id,
    required this.time,
    required this.payload,
    required this.isReplay,
    this.rid,
  });

  final String channel;
  final int id;
  final DateTime time;

  /// The correlation id an adapter stamped — the HTTP request this event
  /// happened under, for everything the shelf middleware wraps.
  final String? rid;

  final Map<String, Object?> payload;

  /// True for events that predate this attachment.
  final bool isReplay;
}

/// What the server answered `meta/attach` with.
class ServerHello {
  ServerHello({
    required this.name,
    required this.pid,
    required this.projectRoot,
    required this.startedAt,
    required this.channels,
    required this.eventCount,
  });

  final String name;
  final int pid;
  final String projectRoot;
  final DateTime startedAt;
  final List<String> channels;

  /// How many ring events the replay will deliver.
  final int eventCount;
}

/// The attacher's half of the protocol — what the GUI core, `fw` and MCP use
/// to read a live server.
///
/// [connect] performs the `meta/attach` handshake, so constructing one of
/// these is an *attachment*: the ring replays into [events] (marked
/// [ServerEvent.isReplay]), then the live tail follows. A liveness probe that
/// wants no replay should just `Socket.connect` and destroy — the server
/// writes nothing to a connection that has not attached.
class ServerAttachClient {
  ServerAttachClient._(this.handle, this._socket) {
    _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onClosed, onError: (Object _) => _onClosed());
  }

  /// Connects and attaches, or throws — on refused connect, on timeout, on a
  /// hello that never comes. The caller decides whether a failure means
  /// "delete the handle" ([attachToServer] does).
  static Future<ServerAttachClient> connect(
    ServerHandle handle, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    // Closed by [close] / [_onClosed]; the analyzer cannot follow the handoff.
    // ignore: close_sinks
    var socket = await Socket.connect(
      InternetAddress(handle.socketPath, type: InternetAddressType.unix),
      0,
    ).timeout(timeout);
    var client = ServerAttachClient._(handle, socket);
    try {
      client._hello = await client
          ._request(metaChannel, metaAttach)
          .then(_decodeHello)
          .timeout(timeout);
      return client;
    } on Object {
      await client.close();
      rethrow;
    }
  }

  final ServerHandle handle;
  final Socket _socket;

  ServerHello? _hello;

  /// Available once [connect] returned.
  ServerHello get hello => _hello!;

  /// Every event this attachment has seen — the replay, then the live tail.
  ///
  /// A retained list rather than a bare stream, deliberately: the server
  /// replays in the same socket flush as the hello, so by the time [connect]
  /// returns the replay has already been read — a broadcast stream would have
  /// dropped it before the caller could subscribe. Bounded by the server's
  /// ring plus this attachment's lifetime.
  List<ServerEvent> get received => List.unmodifiable(_received);
  final _received = <ServerEvent>[];

  /// Fires after each event is appended to [received] — a change signal, not
  /// the storage.
  Stream<ServerEvent> get events => _events.stream;
  final _events = StreamController<ServerEvent>.broadcast();

  /// Flips when the replay boundary passes; events after this are live.
  bool get replayComplete => _replayComplete;
  var _replayComplete = false;

  /// Resolves when the server goes away.
  Future<void> get done => _done.future;
  final _done = Completer<void>();

  final _pending = <int, Completer<Map<String, Object?>>>{};
  var _nextRequestId = 1;

  /// Sends a `req` frame and returns the response payload; throws
  /// [ServerRequestException] when the server answers with `err` — a missing
  /// handler, or the handler itself throwing.
  Future<Map<String, Object?>> request(
    String channel,
    String method, [
    Map<String, Object?> params = const {},
  ]) => _request(channel, method, params);

  Future<Map<String, Object?>> _request(
    String channel,
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    var id = _nextRequestId++;
    var completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _socket.write(
      encodeFrame({
        frameChannel: channel,
        frameType: typeRequest,
        frameRequestId: id,
        frameMethod: method,
        framePayload: params,
      }),
    );
    return completer.future;
  }

  void _onLine(String line) {
    var frame = tryDecodeFrame(line);
    if (frame == null) return;
    switch (frame[frameType]) {
      case typeEvent:
        _onEvent(frame);
      case typeResponse || typeError:
        var id = frame[frameRequestId];
        var completer = id is int ? _pending.remove(id) : null;
        if (completer == null) return;
        var payload = frame[framePayload];
        var map = payload is Map
            ? payload.cast<String, Object?>()
            : <String, Object?>{};
        if (frame[frameType] == typeError) {
          completer.completeError(
            ServerRequestException(map['message']?.toString() ?? 'error'),
          );
        } else {
          completer.complete(map);
        }
    }
  }

  void _onEvent(Map<String, Object?> frame) {
    var channel = frame[frameChannel];
    if (channel is! String) return;
    var payload = frame[framePayload];
    var map = payload is Map
        ? payload.cast<String, Object?>()
        : <String, Object?>{};
    if (channel == metaChannel && map['type'] == metaReplayDone) {
      _replayComplete = true;
      return;
    }
    var ts = frame[frameTimestamp];
    var event = ServerEvent(
      channel: channel,
      id: frame[frameEventId] is int ? frame[frameEventId]! as int : 0,
      time: ts is int
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : DateTime.now(),
      rid: frame[frameCorrelation] as String?,
      payload: map,
      isReplay: !_replayComplete,
    );
    _received.add(event);
    _events.add(event);
  }

  void _onClosed() {
    if (!_done.isCompleted) _done.complete();
    for (var completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(ServerRequestException('server disconnected'));
      }
    }
    _pending.clear();
    unawaited(_events.close());
  }

  Future<void> close() async {
    _socket.destroy();
    _onClosed();
  }

  static ServerHello _decodeHello(Map<String, Object?> payload) => ServerHello(
    name: payload['name']?.toString() ?? '?',
    pid: payload['pid'] is int ? payload['pid']! as int : 0,
    projectRoot: payload['projectRoot']?.toString() ?? '',
    startedAt:
        DateTime.tryParse(payload['startedAt']?.toString() ?? '') ??
        DateTime.now(),
    channels: [
      for (var channel in payload['channels'] as List? ?? const [])
        channel.toString(),
    ],
    eventCount: payload['events'] is int ? payload['events']! as int : 0,
  );
}

class ServerRequestException implements Exception {
  ServerRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// [ServerAttachClient.connect] with `attachToLiveSession`'s cleanup rule: a
/// handle that will not connect is deleted on the way past, and null comes
/// back instead of an error. This is what keeps the published list truthful —
/// dead servers disappear the first time anything tries to reach them.
Future<ServerAttachClient?> attachToServer(
  ServerHandle handle, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    return await ServerAttachClient.connect(handle, timeout: timeout);
  } on Object {
    deleteServerHandle(handle);
    return null;
  }
}

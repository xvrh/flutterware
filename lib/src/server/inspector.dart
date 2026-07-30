import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show pid;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'protocol.dart';

/// What a command handler receives and returns. A returned map becomes the
/// response payload as-is; anything else is wrapped as `{"value": …}`.
typedef ServerCommandHandler =
    FutureOr<Object?> Function(Map<String, Object?> params);

/// The primitives a Dart server reports through.
///
/// This is the whole public runtime surface: `event`, `span`/`spanSync`,
/// `handle`, and zone correlation. Adapters — a shelf middleware, a query
/// interceptor, a log listener — are copy-paste snippets over these four,
/// deliberately not code in this package (spec decision 5).
///
/// **There is no init call.** The first reported event activates the
/// inspector: it binds a unix socket in `~/.flutterware/run`, publishes a
/// `srv-*.json` handle, and replays its ring to whoever attaches. When the
/// gates say no — a release build, a machine without a run dir,
/// `FW_SERVER_INSPECT=0` — every primitive is a cheap no-op and the server
/// runs exactly as if this library were not there.
class FlutterwareServer {
  FlutterwareServer._();

  /// The zone key the correlation id travels under. A request-scoped adapter
  /// (the shelf middleware) runs its handler in
  /// `runZoned(zoneValues: {FlutterwareServer.requestIdKey: id}, …)`, and
  /// every event and span emitted below it is stamped automatically.
  static const Symbol requestIdKey = #fwRequestId;

  /// The correlation id of the current zone, if an adapter installed one.
  static Object? get correlationId => Zone.current[requestIdKey];

  static ServerInspector? _inspector;
  static var _started = false;
  static String? _configuredName;
  static String? _configuredRoot;

  /// Overrides the defaults — the entrypoint basename for the name,
  /// `Directory.current` for the project root. Must run before the first
  /// event: after activation the handle file is already published, and a
  /// silently ignored override would be worse than this error.
  static void configure({String? name, String? root}) {
    if (_started) {
      throw StateError(
        'FlutterwareServer.configure must run before the first event.',
      );
    }
    _configuredName = name ?? _configuredName;
    _configuredRoot = root ?? _configuredRoot;
  }

  /// Reports one event on [channel]. Fire-and-forget and safe everywhere:
  /// when the inspector is inert this is a null check and a return.
  static void event(String channel, Map<String, Object?> payload) {
    _active?.addEvent(channel, payload, rid: _rid());
  }

  /// Runs [body] and reports it as a timed event on [channel] — duration in
  /// fractional milliseconds under `ms`, the error under `error` if it threw.
  /// The error is rethrown; this observes, it never swallows.
  static Future<T> span<T>(
    String channel,
    Map<String, Object?> payload,
    Future<T> Function() body,
  ) async {
    var watch = Stopwatch()..start();
    Object? error;
    try {
      return await body();
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      _spanEvent(channel, payload, watch, error);
    }
  }

  /// [span] for synchronous work — a sqlite call should not become async just
  /// to be observed.
  static T spanSync<T>(
    String channel,
    Map<String, Object?> payload,
    T Function() body,
  ) {
    var watch = Stopwatch()..start();
    Object? error;
    try {
      return body();
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      _spanEvent(channel, payload, watch, error);
    }
  }

  /// Registers the handler an attacher's `req` frames on [channel]/[method]
  /// reach. This is what makes queries explainable: the handler runs *inside*
  /// the server, against its own live connections.
  static void handle(
    String channel,
    String method,
    ServerCommandHandler handler,
  ) {
    _active?.registerHandler(channel, method, handler);
  }

  static void _spanEvent(
    String channel,
    Map<String, Object?> payload,
    Stopwatch watch,
    Object? error,
  ) {
    event(channel, {
      ...payload,
      'ms': watch.elapsedMicroseconds / 1000,
      if (error != null) 'error': '$error',
    });
  }

  static String? _rid() {
    var id = correlationId;
    return id?.toString();
  }

  static ServerInspector? get _active {
    if (!_started) {
      _started = true;
      _inspector = _tryStart();
    }
    return _inspector;
  }

  /// Never throws: a broken inspector must cost the server nothing but its
  /// observability.
  static ServerInspector? _tryStart() {
    try {
      var runDir = existingRunDir();
      var enabled = serverInspectionEnabled(
        product: const bool.fromEnvironment('dart.vm.product'),
        envOverride: Platform.environment['FW_SERVER_INSPECT'],
        runDirExists: runDir != null,
      );
      if (!enabled || runDir == null) return null;
      return ServerInspector.start(
        runDir: runDir,
        projectRoot: _configuredRoot ?? p.canonicalize(Directory.current.path),
        name: _configuredName ?? _defaultName(),
      );
    } on Object {
      return null;
    }
  }

  static String _defaultName() =>
      p.basenameWithoutExtension(Platform.script.path);

  /// Routes the primitives to [inspector] — a test's temp-dir instance —
  /// instead of letting the gates decide against the real environment.
  @visibleForTesting
  static void debugAttachInspector(ServerInspector inspector) {
    _started = true;
    _inspector = inspector;
  }

  /// Tears down the active inspector and re-arms the gates, so a test can run
  /// several activations in one process. Not part of the server-facing API.
  @visibleForTesting
  static Future<void> reset() async {
    _started = false;
    _configuredName = null;
    _configuredRoot = null;
    var inspector = _inspector;
    _inspector = null;
    await inspector?.stop();
  }
}

class _RingEvent {
  _RingEvent(this.id, this.channel, this.time, this.rid, this.payload);

  final int id;
  final String channel;
  final DateTime time;
  final String? rid;
  final Map<String, Object?> payload;

  Map<String, Object?> toFrame() => {
    frameChannel: channel,
    frameType: typeEvent,
    frameEventId: id,
    frameTimestamp: time.millisecondsSinceEpoch,
    if (rid != null) frameCorrelation: rid,
    framePayload: payload,
  };
}

/// The machinery behind [FlutterwareServer], constructible directly so tests
/// can point it at a temp dir instead of faking the gates.
class ServerInspector {
  ServerInspector._({
    required this.runDir,
    required this.projectRoot,
    required this.name,
    required this.ringSize,
    required this.pid,
  });

  /// Starts publishing immediately, but asynchronously: events reported while
  /// the socket is still binding only land in the ring, which is where an
  /// attacher would find them anyway.
  ///
  /// [pid] defaults to this process — overridable so a single-process test
  /// can stage a "restart", which is otherwise invisible: the handle key is
  /// `name-pid`, and two inspectors in one test share a pid.
  factory ServerInspector.start({
    required String runDir,
    required String projectRoot,
    required String name,
    int ringSize = 500,
    int? pid,
  }) {
    var inspector = ServerInspector._(
      runDir: runDir,
      projectRoot: projectRoot,
      name: name,
      ringSize: ringSize,
      pid: pid ?? io.pid,
    );
    unawaited(inspector._publish());
    return inspector;
  }

  final String runDir;
  final String projectRoot;
  final String name;

  /// Kept events per channel; the oldest fall off first.
  final int ringSize;

  final startedAt = DateTime.now();

  final _ring = <String, Queue<_RingEvent>>{};
  final _handlers = <String, Map<String, ServerCommandHandler>>{};
  final _attached = <Socket>{};
  var _nextEventId = 1;
  var _stopped = false;

  ServerSocket? _socket;
  String? _socketPath;
  String? _handlePath;

  /// Resolves when the handle is on disk — what tests await. A publish that
  /// failed resolves too: the server must not care.
  Future<void> get published => _published.future;
  final _published = Completer<void>();

  String get _baseName =>
      serverHandleBaseName(projectRoot: projectRoot, name: name, pid: pid);

  final int pid;

  /// Destroys every attached connection without touching the handle or the
  /// socket — a transient drop, as a test stages it.
  @visibleForTesting
  void debugDropConnections() {
    for (var socket in _attached.toList()) {
      _drop(socket);
    }
  }

  void addEvent(String channel, Map<String, Object?> payload, {String? rid}) {
    if (_stopped) return;
    var event = _RingEvent(
      _nextEventId++,
      channel,
      DateTime.now(),
      rid,
      payload,
    );
    var ring = _ring.putIfAbsent(channel, Queue.new);
    ring.add(event);
    while (ring.length > ringSize) {
      ring.removeFirst();
    }
    if (_attached.isNotEmpty) {
      _broadcast(encodeFrame(event.toFrame()));
    }
  }

  void registerHandler(
    String channel,
    String method,
    ServerCommandHandler handler,
  ) {
    _handlers.putIfAbsent(channel, () => {})[method] = handler;
  }

  Future<void> _publish() async {
    try {
      await _cleanUpPredecessors();
      var socketPath = p.join(runDir, '$_baseName.sock');
      // The 104-byte `sun_path` cap, checked here so a pathological home
      // directory degrades to "inert" rather than to an OS error mid-request.
      if (socketPath.length > 103) throw StateError('socket path too long');
      _socketPath = socketPath;
      _socket = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      _socket!.listen(_onConnection);
      var handle = ServerHandle(
        projectRoot: projectRoot,
        name: name,
        socketPath: socketPath,
        pid: pid,
        startedAt: startedAt,
      );
      var handlePath = p.join(runDir, '$_baseName.json');
      File(handlePath).writeAsStringSync(jsonEncode(handle.toJson()));
      _handlePath = handlePath;
    } on Object {
      await stop();
    } finally {
      if (!_published.isCompleted) _published.complete();
    }
  }

  /// Deletes dead handles this same server left behind — same project root
  /// and name, different pid, socket answering nothing. Restarts self-clean
  /// instead of waiting a day for the sweep.
  Future<void> _cleanUpPredecessors() async {
    var prefix =
        'srv-${projectRootHash(projectRoot)}-${sanitizeServerName(name)}-';
    for (var handle in scanServerHandles(runDir)) {
      var fileName = p.basename(handle.handlePath!);
      if (!fileName.startsWith(prefix) || handle.pid == pid) continue;
      if (await _answers(handle.socketPath)) continue;
      deleteServerHandle(handle);
    }
  }

  static Future<bool> _answers(String socketPath) async {
    try {
      var socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      ).timeout(const Duration(milliseconds: 300));
      socket.destroy();
      return true;
    } on Object {
      return false;
    }
  }

  void _onConnection(Socket socket) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _onLine(socket, line),
          onDone: () => _drop(socket),
          onError: (Object _) => _drop(socket),
          cancelOnError: true,
        );
  }

  void _onLine(Socket socket, String line) {
    var frame = tryDecodeFrame(line);
    if (frame == null || frame[frameType] != typeRequest) return;
    var channel = frame[frameChannel];
    var method = frame[frameMethod];
    var id = frame[frameRequestId];
    if (channel is! String || method is! String || id is! int) return;
    if (channel == metaChannel && method == metaAttach) {
      _attach(socket, id);
      return;
    }
    var handler = _handlers[channel]?[method];
    if (handler == null) {
      _send(socket, {
        frameChannel: channel,
        frameType: typeError,
        frameRequestId: id,
        framePayload: {'message': 'no handler for $channel.$method'},
      });
      return;
    }
    var params = frame[framePayload];
    unawaited(
      _respond(
        socket,
        channel,
        id,
        handler,
        params is Map ? params.cast<String, Object?>() : const {},
      ),
    );
  }

  Future<void> _respond(
    Socket socket,
    String channel,
    int id,
    ServerCommandHandler handler,
    Map<String, Object?> params,
  ) async {
    try {
      var result = await handler(params);
      _send(socket, {
        frameChannel: channel,
        frameType: typeResponse,
        frameRequestId: id,
        framePayload: result is Map
            ? result.cast<String, Object?>()
            : {'value': result},
      });
    } catch (e) {
      _send(socket, {
        frameChannel: channel,
        frameType: typeError,
        frameRequestId: id,
        framePayload: {'message': '$e'},
      });
    }
  }

  /// The handshake that makes connection ≠ attachment: nothing is written to
  /// a socket that has not asked, so a liveness probe that connects and
  /// closes costs a read loop and nothing else.
  void _attach(Socket socket, int id) {
    var events = _ring.values.expand((q) => q).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    _send(socket, {
      frameChannel: metaChannel,
      frameType: typeResponse,
      frameRequestId: id,
      framePayload: {
        'name': name,
        'pid': pid,
        'projectRoot': projectRoot,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'channels': {..._ring.keys, ..._handlers.keys}.toList()..sort(),
        'events': events.length,
      },
    });
    for (var event in events) {
      _send(socket, event.toFrame());
    }
    _send(socket, {
      frameChannel: metaChannel,
      frameType: typeEvent,
      framePayload: {'type': metaReplayDone},
    });
    _attached.add(socket);
  }

  void _send(Socket socket, Map<String, Object?> frame) {
    try {
      socket.write(encodeFrame(frame));
    } on Object {
      _drop(socket);
    }
  }

  void _broadcast(String data) {
    for (var socket in _attached.toList()) {
      try {
        socket.write(data);
      } on Object {
        _drop(socket);
      }
    }
  }

  void _drop(Socket socket) {
    _attached.remove(socket);
    socket.destroy();
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    for (var socket in _attached.toList()) {
      socket.destroy();
    }
    _attached.clear();
    await _socket?.close();
    for (var path in [_handlePath, _socketPath]) {
      if (path == null) continue;
      try {
        File(path).deleteSync();
      } on FileSystemException {
        // Already gone — a sweep or a successor got there first.
      }
    }
  }
}

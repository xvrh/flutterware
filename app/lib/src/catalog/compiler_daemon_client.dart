import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'daemon_address.dart';
import 'protocol.dart';

/// Talks to the compiler daemon, which runs as a separate plain-Dart process.
///
/// The daemon is not a workaround. It is where the catalog pipeline lives so
/// that the GUI, `fw`, and an agent are three *drivers* of one pipeline rather
/// than three copies of it: a screenshot must not require a running GUI, and a
/// second consumer must not repeat the first one's work.
///
/// So [connect] connects before it considers spawning. Whoever arrives first
/// pays for the scan, the bundle, the host and the cold compile; everyone after
/// gets a compiler that already holds the whole catalog in memory.
///
/// (It was once also a containment measure: `package:frontend_server_client`
/// spawns the compiler through `Platform.resolvedExecutable`, which inside a
/// Flutter app is the app binary, so compiling in-process relaunched the app
/// recursively. `FrontendServer` takes an explicit executable, so that class of
/// bug is gone and no longer the reason for anything here.)
/// The shape of [CompilerDaemonClient.connect], for callers that take the
/// connect as a parameter so a test can hold it open.
typedef DaemonConnector =
    Future<(CompilerDaemonClient, DaemonReady)> Function({
      required String dartExecutable,
      required DaemonConfig config,
      void Function(String)? onLog,
    });

class CompilerDaemonClient {
  CompilerDaemonClient._(this._socket, this.address, this._onLog) {
    _lines = _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: _onGone, onDone: _onGone);
  }

  final Socket _socket;
  final DaemonAddress address;
  final void Function(String)? _onLog;

  late final StreamSubscription<String> _lines;

  var _nextRequestId = 0;

  /// The reply each in-flight [select] is waiting for, by request id.
  ///
  /// **Futures rather than a filtered stream.** This used to be
  /// `_responses.where(…).first` over `socket.asBroadcastStream()`, and a
  /// broadcast stream *drops* what arrives while nobody is listening — verified,
  /// not assumed. Registering a completer before the request is written closes
  /// that window by construction, and gives the two things a filtered stream
  /// could not: somewhere to put a timeout, and somewhere to deliver "the daemon
  /// died" to every caller waiting on it.
  final _pending = <int, Completer<DaemonCompiled>>{};

  /// The daemon's first word, which is either [DaemonReady] or [DaemonFailed].
  final _handshake = Completer<DaemonResponse>();

  final _changes = StreamController<CatalogChanged>.broadcast();

  /// An event and not a value, unlike [lastChange]: this message carries no
  /// snapshot to catch up on — a client attaching after assets moved reads a
  /// bundle that already moved with them.
  final _assetsChanges = StreamController<AssetsChanged>.broadcast();

  /// The most recent [CatalogChanged], whether or not anyone was listening.
  ///
  /// **State, not a replayed event**, and the distinction is the whole point.
  /// This message is a snapshot — the servable set and the quarantine — so a
  /// caller that subscribed after one landed does not need the event, it needs
  /// the value. There is a real window between [connect] returning and a caller
  /// reaching `.listen`, and a panel that missed the only notice it was going to
  /// get would go on offering an entry the daemon cannot build.
  ///
  /// Injecting it into [catalogChanges] instead was tried and was worse: the
  /// generator that did it subscribed to the live stream one microtask after the
  /// caller listened, so a change arriving inside *that* window went to the held
  /// value and was never delivered to the stream already waiting for it. Only a
  /// real daemon caught it — the announcement checks in
  /// `integration_test/compiler_daemon_test.dart` are what stand there now. A
  /// stream that is only a stream, and a value that is only a value, has no such
  /// window.
  CatalogChanged? get lastChange => _lastChange;
  CatalogChanged? _lastChange;

  /// Why the connection ended, once it has.
  String? _gone;

  /// Connects to the daemon for [config], starting one if nobody is serving.
  ///
  /// [dartExecutable] must be a real Dart VM — pass the Flutter SDK's `dart`.
  static Future<(CompilerDaemonClient, DaemonReady)> connect({
    required String dartExecutable,
    required DaemonConfig config,
    void Function(String)? onLog,
    Duration readyTimeout = const Duration(minutes: 5),
  }) async {
    // Compiled before the address is derived, not after: the daemon's own build
    // is part of the config, and so part of the address, so a client never
    // attaches to a daemon compiled from different sources than it expects.
    var launch = await _ensureCompiled(
      dartExecutable: dartExecutable,
      appPackageRoot: config.appPackageRoot,
      onLog: onLog,
    );
    config = config.withDaemonRevision(launch.revision);
    var address = DaemonAddress(config);
    address.ensureRunDir();

    return _shakeHands(
      await _attachOrSpawn(
        address: address,
        launch: launch,
        config: config,
        onLog: onLog,
      ),
      address: address,
      onLog: onLog,
      readyTimeout: readyTimeout,
    );
  }

  /// Attaches to the daemon already serving [address], and fails if none is.
  ///
  /// [connect] minus everything with a side effect: no snapshot, no lock, no
  /// spawn. For a caller that knows a daemon is up and does not want to be the
  /// one that starts one — and for a test, which is the only present user.
  static Future<(CompilerDaemonClient, DaemonReady)> attach({
    required DaemonAddress address,
    void Function(String)? onLog,
    Duration readyTimeout = const Duration(minutes: 5),
  }) async {
    var socket = await _connect(address);
    if (socket == null) {
      throw StateError('nothing is serving ${address.socketPath}');
    }
    return _shakeHands(
      socket,
      address: address,
      onLog: onLog,
      readyTimeout: readyTimeout,
    );
  }

  /// Waits for the daemon's first word, which is what decides whether there is a
  /// client at all.
  ///
  /// The client is built *before* the handshake rather than after, because it is
  /// what reads the socket: constructing it is how the pump starts, and the ready
  /// message is just the first thing the pump delivers. The socket is never held
  /// in a local of its own past here — the client owns it from the moment it
  /// exists, and [close] is the only thing that ends it.
  static Future<(CompilerDaemonClient, DaemonReady)> _shakeHands(
    Socket socket, {
    required DaemonAddress address,
    required Duration readyTimeout,
    void Function(String)? onLog,
  }) async {
    var client = CompilerDaemonClient._(socket, address, onLog);
    var first = await client._handshake.future.timeout(
      readyTimeout,
      onTimeout: () => throw StateError(
        'the compiler daemon did not become ready within '
        '${readyTimeout.inSeconds}s. See ${address.logPath}',
      ),
    );

    switch (first) {
      case DaemonReady():
        return (client, first);
      case DaemonFailed(:var message, :var stackTrace):
        await client.close();
        throw StateError('the compiler daemon failed: $message\n$stackTrace');
      case DaemonCompiled():
      case CatalogChanged():
      case AssetsChanged():
        await client.close();
        throw StateError('the daemon spoke before it was ready: $first');
    }
  }

  /// Sorts one line from the daemon to whoever is waiting for it.
  ///
  /// The whole reason this is a method rather than a chain of stream operators:
  /// a reply goes to *its* caller's future, an event goes to the event stream or
  /// is held for the first subscriber, and a line that is not protocol at all is
  /// a log. Three destinations, one of which has to be reliable.
  void _onLine(String line) {
    var json = tryDecodeLine(line);
    // Anything the daemon writes that is not protocol is a log, not a reason to
    // fail.
    if (json == null) {
      _onLog?.call(line);
      return;
    }
    DaemonResponse response;
    try {
      response = DaemonResponse.decode(json);
    } on FormatException catch (e) {
      // An older client against a newer daemon. Symmetrical with the daemon's
      // own guard, and for the same reason: one unreadable line must not take
      // down a connection that is otherwise working.
      _onLog?.call('unreadable line from the daemon: $e');
      return;
    }

    switch (response) {
      case DaemonReady():
      case DaemonFailed():
        if (!_handshake.isCompleted) _handshake.complete(response);
      case DaemonCompiled(:var requestId):
        // Matched on the id, not on "the next compiled message". Absent means a
        // reply that arrived after its caller gave up — dropped, not an error.
        _pending.remove(requestId)?.complete(response);
      case CatalogChanged():
        _lastChange = response;
        if (!_changes.isClosed) _changes.add(response);
      case AssetsChanged():
        if (!_assetsChanges.isClosed) _assetsChanges.add(response);
    }
  }

  /// The connection ended. Everyone waiting on it has to be told, once.
  void _onGone([Object? error]) {
    if (_gone != null) return;
    _gone =
        'the compiler daemon closed the connection'
        '${error == null ? '' : ': $error'}\n${_tailLog(address)}';
    var reason = StateError(_gone!);
    if (!_handshake.isCompleted) _handshake.completeError(reason);
    for (var completer in _pending.values.toList()) {
      if (!completer.isCompleted) completer.completeError(reason);
    }
    _pending.clear();
    if (!_changes.isClosed) _changes.close();
    if (!_assetsChanges.isClosed) _assetsChanges.close();
  }

  /// Fires whenever the set of servable entries moves — an entry quarantined
  /// because it stopped compiling, or brought back because it was fixed.
  ///
  /// Pushed rather than polled: a panel sitting idle while someone edits a demo
  /// would otherwise keep offering an entry the daemon can no longer build.
  ///
  /// A plain broadcast stream, so listening subscribes synchronously and there
  /// is no window between the two. For what landed *before* a caller got here,
  /// read [lastChange] once after subscribing.
  Stream<CatalogChanged> get catalogChanges => _changes.stream;

  /// Fires when a refresh rebuilt the shared asset bundle and it differed —
  /// the notice a session turns into evicting its guest's caches.
  Stream<AssetsChanged> get assetsChanges => _assetsChanges.stream;

  /// Makes [id] the active entry and compiles it into the entrypoint.
  ///
  /// [full] asks for a whole kernel rather than a delta — needed when the
  /// result will be loaded by a guest spawned from scratch. [ifChanged] asks
  /// the daemon to answer `unchanged` instead of working, when nothing on disk
  /// has moved and this entry is already the compiled one.
  ///
  /// [timeout] is generous on purpose, and is a deadlock guard rather than a
  /// service-level expectation: the daemon serialises every client's work on one
  /// compiler, so a legitimate wait here is another client's cold compile plus
  /// this one. What it rules out is the case it exists for — a daemon that is
  /// alive, holding the queue, and never going to answer — which without it hangs
  /// the caller, and with it hangs the GUI's catalog panel forever.
  Future<DaemonCompiled> select(
    String id, {
    bool full = false,
    bool ifChanged = false,
    Duration timeout = const Duration(minutes: 5),
  }) {
    if (_gone case var reason?) return Future.error(StateError(reason));

    var requestId = _nextRequestId++;
    var completer = Completer<DaemonCompiled>();
    // Registered *before* the write. The reply cannot be missed for the same
    // reason it cannot be misdelivered: there is somewhere for it to go before
    // the daemon has been asked.
    _pending[requestId] = completer;
    try {
      _socket.writeln(
        encodeLine(
          SelectRequest(requestId, id, full: full, ifChanged: ifChanged),
        ),
      );
    } on Object catch (e) {
      _pending.remove(requestId);
      return Future.error(
        StateError('could not reach the compiler daemon: $e'),
      );
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(requestId);
        throw StateError(
          'the compiler daemon did not answer "$id" within '
          '${timeout.inSeconds}s. See ${address.logPath}',
        );
      },
    );
  }

  /// Asks the daemon to look for entries that appeared or disappeared.
  ///
  /// Fire and forget: what it finds arrives on [catalogChanges], to every
  /// client, which is also how this client hears about somebody else's.
  void refresh() {
    try {
      _socket.writeln(encodeLine(const RefreshRequest()));
    } catch (_) {
      // A daemon on its way out is not worth reporting over a poll.
    }
  }

  /// Leaves the daemon running for whoever else wants it.
  Future<void> close() async {
    _onGone();
    await _lines.cancel();
    try {
      await _socket.close();
    } catch (_) {
      // Falls through to the destroy below.
    }
    _socket.destroy();
  }

  /// Stops the daemon process, disconnecting every other client too.
  ///
  /// For tooling that wants a clean slate. Ordinary consumers call [close].
  Future<void> stopDaemon() async {
    try {
      _socket.writeln(encodeLine(const StopDaemonRequest()));
      await _socket.flush();
    } catch (_) {
      // The daemon may already be gone.
    }
    await close();
    // Give it a moment to unlink its socket, so an immediately following
    // connect does not attach to a daemon on its way out.
    for (var i = 0; i < 50; i++) {
      if (!File(address.socketPath).existsSync()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// The socket for [address] — the one already being served, or one belonging
  /// to a daemon this starts.
  static Future<Socket> _attachOrSpawn({
    required DaemonAddress address,
    required _DaemonLaunch launch,
    required DaemonConfig config,
    void Function(String)? onLog,
  }) async {
    if (await _connect(address) case var existing?) {
      onLog?.call('attached to the daemon already serving ${address.key}');
      return existing;
    }
    return _spawnAndConnect(
      address: address,
      launch: launch,
      config: config,
      onLog: onLog,
    );
  }

  static Future<Socket?> _connect(DaemonAddress address) async {
    if (!File(address.socketPath).existsSync()) return null;
    try {
      return await Socket.connect(
        InternetAddress(address.socketPath, type: InternetAddressType.unix),
        0,
      );
    } on SocketException {
      // The file is there but nobody is listening: a daemon that died without
      // unlinking. The caller holds the lock before cleaning it up.
      return null;
    }
  }

  /// Starts a daemon under a lock, so several clients racing produce one.
  static Future<Socket> _spawnAndConnect({
    required DaemonAddress address,
    required _DaemonLaunch launch,
    required DaemonConfig config,
    void Function(String)? onLog,
  }) async {
    var lock = File(address.lockPath).openSync(mode: FileMode.write);
    try {
      lock.lockSync(FileLock.blockingExclusive);

      // Someone may have won the race while we waited for the lock.
      var existing = await _connect(address);
      if (existing != null) {
        onLog?.call('attached to a daemon started while we waited');
        return existing;
      }

      var stale = File(address.socketPath);
      if (stale.existsSync()) stale.deleteSync();

      // Under the daemon's own key: two clients spawning at once would
      // otherwise overwrite one another's config before either daemon read it.
      var configFile = File(
        p.join(
          config.appPackageRoot,
          'build',
          'catalog',
          address.key,
          'daemon_config.json',
        ),
      );
      configFile.parent.createSync(recursive: true);
      configFile.writeAsStringSync(jsonEncode(config.toJson()));

      // Detached, so the daemon outlives whoever happened to start it — that is
      // the whole point of sharing it. Its output goes to a log file rather
      // than to our pipes, which would break the moment we exit; the shell is
      // how a detached process gets a redirect it did not open itself, and so
      // catches VM-level failures too.
      await Process.start(
        '/bin/sh',
        [
          '-c',
          r'exec "$@" >> "$FW_DAEMON_LOG" 2>&1',
          'sh',
          launch.executable,
          ...launch.arguments,
          configFile.path,
        ],
        workingDirectory: config.appPackageRoot,
        mode: ProcessStartMode.detached,
        environment: {'FW_DAEMON_LOG': address.logPath},
      );
      onLog?.call('started a daemon for ${address.key}');

      // The daemon binds before it prepares, so this waits only for the bind.
      var deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        var socket = await _connect(address);
        if (socket != null) return socket;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      throw StateError(
        'the compiler daemon never started listening on '
        '${address.socketPath}\n${_tailLog(address)}',
      );
    } finally {
      try {
        lock.unlockSync();
      } catch (_) {
        // Already released by the close below.
      }
      lock.closeSync();
    }
  }

  /// The last of whatever the daemon managed to say before it died.
  static String _tailLog(DaemonAddress address) {
    var log = File(address.logPath);
    if (!log.existsSync()) return '(no daemon log at ${address.logPath})';
    var lines = log.readAsLinesSync();
    return lines.skip(lines.length > 40 ? lines.length - 40 : 0).join('\n');
  }
}

/// A **guess** at the daemon's closure, used only until a depfile exists.
///
/// Kept deliberately coarse: it is the first run's answer, and the compile it
/// triggers replaces it with the compiler's own list. See [_newestSource] for why
/// a hand-maintained version of this could not stay right.
const _daemonSources = [
  'tool/catalog/compiler_daemon.dart',
  'lib/src/catalog',
  'lib/src/embedder',
];

/// Returns how to launch the daemon: a **kernel snapshot** when one is present
/// and fresh, else `dart run` on the source.
///
/// `dart run` re-compiles the daemon and everything it imports — analyzer,
/// image, vm_service — on **every** start. Measured at 3214ms against 121ms
/// from a snapshot: the single largest cost in bringing a catalog up, and none
/// of it the user's project.
///
/// A kernel snapshot rather than `dart compile exe` only because AOT costs
/// about the same to build and saves ~80ms at startup; the snapshot rebuilds
/// far more often than it runs during development. Nothing forbids AOT now that
/// `FrontendServer` is handed its executable.
/// How to launch the daemon, and which build of it that is.
class _DaemonLaunch {
  _DaemonLaunch(this.executable, this.arguments, this.revision);

  final String executable;
  final List<String> arguments;

  /// Changes whenever the daemon's own sources change. Part of the daemon's
  /// address, so a newer client starts a newer daemon rather than attaching to
  /// one running yesterday's code.
  final String revision;
}

Future<_DaemonLaunch> _ensureCompiled({
  required String dartExecutable,
  required String appPackageRoot,
  void Function(String)? onLog,
}) async {
  var script = p.join(
    appPackageRoot,
    'tool',
    'catalog',
    'compiler_daemon.dart',
  );
  // Checked rather than assumed, because the way this goes wrong is silent and
  // slow: `dart compile kernel` on a missing file fails, `onLog` is null on the
  // headless path so nobody sees it, the fallback spawns `dart run` on the same
  // missing file into a detached process, and the client then polls a socket
  // that will never appear for 30 seconds before reporting that the daemon
  // "never started listening". Which is true, and says nothing.
  //
  // The cause is always the same: `appPackageRoot` is not flutterware's `app/`.
  // See [DaemonConfig.forPackage], which is what stops a caller getting here.
  if (!File(script).existsSync()) {
    throw StateError(
      'No daemon script at $script.\n'
      "DaemonConfig.appPackageRoot must be flutterware's own app/ directory, "
      'not the package being catalogued — it is where the daemon script, the '
      'embedder framework and the native host live.',
    );
  }
  var snapshot = File(
    p.join(appPackageRoot, 'build', 'catalog', 'daemon.dill'),
  );
  var depfile = File('${snapshot.path}.d');

  var newest = _newestSource(appPackageRoot, depfile);
  if (snapshot.existsSync() && snapshot.statSync().modified.isAfter(newest)) {
    return _DaemonLaunch(dartExecutable, [
      snapshot.path,
    ], '${newest.millisecondsSinceEpoch}');
  }

  snapshot.parent.createSync(recursive: true);
  var watch = Stopwatch()..start();
  var result = await Process.run(dartExecutable, [
    'compile',
    'kernel',
    script,
    '-o',
    snapshot.path,
    // The compiler's own account of what it read. See [_newestSource].
    '--depfile',
    depfile.path,
  ], workingDirectory: appPackageRoot);
  if (result.exitCode != 0) {
    // Not fatal: the daemon still runs from source, just slower.
    onLog?.call('could not snapshot the daemon: ${result.stderr}');
    return _DaemonLaunch(dartExecutable, [
      'run',
      script,
    ], '${newest.millisecondsSinceEpoch}');
  }
  onLog?.call('snapshotted the daemon in ${watch.elapsedMilliseconds}ms');
  // Read again, against the depfile this compile just wrote. The reading above
  // may have been the guessed list, which is what a new import is missing from —
  // so without this, the first run after adding one keeps yesterday's revision.
  return _DaemonLaunch(
    dartExecutable,
    [snapshot.path],
    '${_newestSource(appPackageRoot, depfile).millisecondsSinceEpoch}',
  );
}

/// The most recently modified file the daemon is built from.
///
/// **The compiler's list, not ours.** `dart compile kernel --depfile` writes
/// exactly what it read, so the closure is maintained by the thing that knows
/// it. The hand-written [_daemonSources] guess missed
/// `lib/src/utils/run_dir.dart` and `lib/src/assets/model/asset_catalog.dart` —
/// both genuinely in the closure — which meant editing either one neither
/// rebuilt the snapshot nor moved the revision. A stale daemon then went on
/// serving, and a stale daemon is precisely what `daemonRevision` exists to
/// prevent: it decides what goes into a hot-reload delta, and an older one hands
/// a guest a delta missing a library the guest never had.
///
/// Cheaper than the guess, too: the depfile names ~756 files, of which ~21 are
/// ours, against a recursive walk of two directory trees.
///
/// **Ours means under the workspace root**, and the root is taken from the
/// depfile itself — the `package_config.json` it lists is by definition at the
/// root of the resolution that built the daemon. Everything outside is the SDK
/// or the pub cache: immutable by construction, since the way you change one is
/// to resolve differently, which rewrites that same `package_config.json`. Which
/// is in the list, so a re-resolution moves the revision on its own.
///
/// Falls back to [_daemonSources] when there is no depfile — the first run, or a
/// compile that failed.
DateTime _newestSource(String appPackageRoot, File depfile) {
  var files = readDaemonDepfile(depfile) ?? _guessedSources(appPackageRoot);
  var newest = DateTime.fromMillisecondsSinceEpoch(0);
  for (var file in files) {
    try {
      var modified = File(file).statSync().modified;
      if (modified.isAfter(newest)) newest = modified;
    } on FileSystemException {
      // A dependency that has since been deleted. Its absence will show up as a
      // failed compile, which is a better place to report it than here.
    }
  }
  return newest;
}

/// The workspace-local dependencies named in a Ninja depfile, or null when there
/// is none to read.
///
/// Public so the escaping can be tested. It is the one piece of parsing in this
/// file, and the cases it has to get right — a space inside a path, a
/// `\`-continued line — are ones this machine will never produce and somebody
/// else's will.
List<String>? readDaemonDepfile(File depfile) {
  if (!depfile.existsSync()) return null;
  String text;
  try {
    text = depfile.readAsStringSync();
  } on FileSystemException {
    return null;
  }

  // `<output>: <dep> <dep> …`, with `\ ` for a space in a path and `\`-newline
  // for a continuation.
  var separator = text.indexOf(': ');
  if (separator < 0) return null;
  var deps = <String>[];
  var current = StringBuffer();
  for (var i = separator + 2; i < text.length; i++) {
    var char = text[i];
    if (char == r'\' && i + 1 < text.length) {
      var next = text[i + 1];
      if (next == '\n') {
        i++;
        continue;
      }
      if (next == ' ') {
        current.write(' ');
        i++;
        continue;
      }
    }
    if (char == ' ' || char == '\n') {
      if (current.isNotEmpty) deps.add(current.toString());
      current.clear();
      continue;
    }
    current.write(char);
  }
  if (current.isNotEmpty) deps.add(current.toString());

  var config = deps.firstWhere(
    (dep) => p.basename(dep) == 'package_config.json',
    orElse: () => '',
  );
  if (config.isEmpty) return null;
  // Never empty: the config that defines the root is itself within it, and it is
  // a dependency worth watching in its own right — a re-resolution rewrites it,
  // and a daemon linked against the old resolution has to be replaced.
  var root = p.dirname(p.dirname(config));
  return [
    for (var dep in deps)
      if (p.isWithin(root, dep)) dep,
  ];
}

Iterable<String> _guessedSources(String appPackageRoot) {
  var files = <String>[];
  for (var relative in _daemonSources) {
    var path = p.join(appPackageRoot, relative);
    var entities = FileSystemEntity.isDirectorySync(path)
        ? Directory(path).listSync(recursive: true)
        : <FileSystemEntity>[File(path)];
    for (var entity in entities) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(entity.path);
      }
    }
  }
  return files;
}

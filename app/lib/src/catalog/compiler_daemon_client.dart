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
class CompilerDaemonClient {
  CompilerDaemonClient._(this._socket, this._responses, this.address);

  final Socket _socket;
  final Stream<DaemonResponse> _responses;
  final DaemonAddress address;

  var _nextRequestId = 0;

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

    var socket = await _connect(address);
    if (socket == null) {
      socket = await _spawnAndConnect(
        address: address,
        launch: launch,
        config: config,
        onLog: onLog,
      );
    } else {
      onLog?.call('attached to the daemon already serving ${address.key}');
    }

    var responses = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) {
          var json = tryDecodeLine(line);
          // Anything the daemon writes that is not protocol is a log, not a
          // reason to fail.
          if (json == null) {
            onLog?.call(line);
            return null;
          }
          return DaemonResponse.decode(json);
        })
        .where((r) => r != null)
        .cast<DaemonResponse>()
        .asBroadcastStream();

    var first = await responses.first
        .timeout(
          readyTimeout,
          onTimeout: () => throw StateError(
            'the compiler daemon did not become ready within '
            '${readyTimeout.inSeconds}s. See ${address.logPath}',
          ),
        )
        .onError<StateError>((e, _) => throw e)
        .catchError((Object e) {
          throw StateError(
            'the compiler daemon closed the connection before it was ready: '
            '$e\n${_tailLog(address)}',
          );
        });

    switch (first) {
      case DaemonReady():
        return (CompilerDaemonClient._(socket, responses, address), first);
      case DaemonFailed(:var message, :var stackTrace):
        socket.destroy();
        throw StateError('the compiler daemon failed: $message\n$stackTrace');
      case DaemonCompiled():
      case CatalogChanged():
        socket.destroy();
        throw StateError('the daemon spoke before it was ready: $first');
    }
  }

  /// Fires whenever the set of servable entries moves — an entry quarantined
  /// because it stopped compiling, or brought back because it was fixed.
  ///
  /// Pushed rather than polled: a panel sitting idle while someone edits a demo
  /// would otherwise keep offering an entry the daemon can no longer build.
  Stream<CatalogChanged> get catalogChanges =>
      _responses.where((r) => r is CatalogChanged).cast<CatalogChanged>();

  /// Makes [id] the active entry and compiles it into the entrypoint.
  ///
  /// [full] asks for a whole kernel rather than a delta — needed when the
  /// result will be loaded by a guest spawned from scratch.
  Future<DaemonCompiled> select(String id, {bool full = false}) {
    var requestId = _nextRequestId++;
    // Matched on the id, not on "the next compiled message": the daemon serves
    // other clients on the same compiler, and their replies share this stream's
    // shape but not its meaning.
    var reply = _responses
        .where((r) => r is DaemonCompiled && r.requestId == requestId)
        .cast<DaemonCompiled>()
        .first;
    _socket.writeln(encodeLine(SelectRequest(requestId, id, full: full)));
    return reply;
  }

  /// Leaves the daemon running for whoever else wants it.
  Future<void> close() async {
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

      var configFile = File(
        p.join(config.appPackageRoot, 'build', 'catalog', 'daemon_config.json'),
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
          'exec "\$@" >> "\$FW_DAEMON_LOG" 2>&1',
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

/// The daemon's source, and everything it pulls in that we own. Newer than the
/// compiled binary means the binary is stale.
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
  var newest = _newestSource(appPackageRoot);
  var revision = '${newest.millisecondsSinceEpoch}';
  var fallback = _DaemonLaunch(dartExecutable, ['run', script], revision);

  var snapshot = File(
    p.join(appPackageRoot, 'build', 'catalog', 'daemon.dill'),
  );
  if (snapshot.existsSync() && snapshot.statSync().modified.isAfter(newest)) {
    return _DaemonLaunch(dartExecutable, [snapshot.path], revision);
  }

  snapshot.parent.createSync(recursive: true);
  var watch = Stopwatch()..start();
  var result = await Process.run(dartExecutable, [
    'compile',
    'kernel',
    script,
    '-o',
    snapshot.path,
  ], workingDirectory: appPackageRoot);
  if (result.exitCode != 0) {
    // Not fatal: the daemon still runs from source, just slower.
    onLog?.call('could not snapshot the daemon: ${result.stderr}');
    return fallback;
  }
  onLog?.call('snapshotted the daemon in ${watch.elapsedMilliseconds}ms');
  return _DaemonLaunch(dartExecutable, [snapshot.path], revision);
}

DateTime _newestSource(String appPackageRoot) {
  var newest = DateTime.fromMillisecondsSinceEpoch(0);
  for (var relative in _daemonSources) {
    var path = p.join(appPackageRoot, relative);
    var entities = FileSystemEntity.isDirectorySync(path)
        ? Directory(path).listSync(recursive: true)
        : [File(path)];
    for (var entity in entities) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      var modified = entity.statSync().modified;
      if (modified.isAfter(newest)) newest = modified;
    }
  }
  return newest;
}

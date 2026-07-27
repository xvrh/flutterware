import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'protocol.dart';

/// Talks to the compiler daemon, which runs as a separate plain-Dart process.
///
/// The GUI never compiles in-process: `FrontendServerClient` spawns the
/// compiler through `Platform.resolvedExecutable`, which inside a Flutter app
/// is the app binary — so an app that compiles relaunches itself, recursively.
/// The daemon exists to keep that impossible.
class CompilerDaemonClient {
  CompilerDaemonClient._(this._process, this._responses);

  final Process _process;
  final Stream<DaemonResponse> _responses;

  /// Starts the daemon and waits for it to finish the slow one-time work.
  ///
  /// [dartExecutable] must be a real Dart VM — pass the Flutter SDK's `dart`,
  /// never `Platform.resolvedExecutable`.
  static Future<(CompilerDaemonClient, DaemonReady)> start({
    required String dartExecutable,
    required DaemonConfig config,
    void Function(String)? onLog,
  }) async {
    var configFile = File(
      p.join(config.appPackageRoot, 'build', 'catalog', 'daemon_config.json'),
    );
    configFile.parent.createSync(recursive: true);
    configFile.writeAsStringSync(jsonEncode(config.toJson()));

    var executable = await _ensureCompiled(
      dartExecutable: dartExecutable,
      appPackageRoot: config.appPackageRoot,
      onLog: onLog,
    );
    var process = await Process.start(executable.$1, [
      ...executable.$2,
      configFile.path,
    ], workingDirectory: config.appPackageRoot);

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog?.call(line));

    var responses = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) {
          var json = tryDecodeLine(line);
          // Anything the daemon prints that is not protocol is a log, not a
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

    var first = await responses.first;
    switch (first) {
      case DaemonReady():
        return (CompilerDaemonClient._(process, responses), first);
      case DaemonFailed(:var message, :var stackTrace):
        process.kill();
        throw StateError('the compiler daemon failed: $message\n$stackTrace');
      case DaemonCompiled():
        process.kill();
        throw StateError('the daemon compiled before it was ready');
    }
  }

  /// Makes [id] the active entry and compiles it into the entrypoint.
  ///
  /// [full] asks for a whole kernel rather than a delta — needed when the
  /// result will be loaded by a guest spawned from scratch.
  Future<DaemonCompiled> select(String id, {bool full = false}) async {
    var reply = _responses
        .where((r) => r is DaemonCompiled)
        .cast<DaemonCompiled>()
        .first;
    _process.stdin.writeln(encodeLine(SelectRequest(id, full: full)));
    return reply;
  }

  Future<void> shutdown() async {
    try {
      _process.stdin.writeln(encodeLine(const ShutdownRequest()));
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Falls through to the kill below.
    }
    _process.kill();
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
/// A kernel snapshot rather than `dart compile exe`, and this is not a
/// preference: `FrontendServerClient` spawns the compiler as
/// `Platform.resolvedExecutable <frontend_server snapshot>`, so the daemon must
/// *be* a Dart VM invocation. An AOT binary would make the daemon relaunch
/// itself — `ResidentCompiler` refuses to start at all in that case.
Future<(String, List<String>)> _ensureCompiled({
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
  var fallback = (dartExecutable, ['run', script]);

  var snapshot = File(
    p.join(appPackageRoot, 'build', 'catalog', 'daemon.dill'),
  );
  if (snapshot.existsSync() &&
      snapshot.statSync().modified.isAfter(_newestSource(appPackageRoot))) {
    return (dartExecutable, [snapshot.path]);
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
  return (dartExecutable, [snapshot.path]);
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

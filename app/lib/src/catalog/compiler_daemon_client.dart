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

    var process = await Process.start(dartExecutable, [
      'run',
      p.join('tool', 'catalog', 'compiler_daemon.dart'),
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
  Future<DaemonCompiled> select(String id) async {
    var reply = _responses
        .where((r) => r is DaemonCompiled)
        .cast<DaemonCompiled>()
        .first;
    _process.stdin.writeln(encodeLine(SelectRequest(id)));
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

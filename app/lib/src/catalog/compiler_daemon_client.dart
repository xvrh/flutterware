import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'daemon_protocol.dart';

/// Talks to the compiler daemon, which runs as a separate plain-Dart process.
///
/// The GUI never compiles in-process: `FrontendServerClient` spawns the
/// compiler through `Platform.resolvedExecutable`, which inside a Flutter app
/// is the app binary — so an app that compiles relaunches itself, recursively.
/// The daemon exists to keep that impossible.
class CompilerDaemonClient {
  CompilerDaemonClient._(this._process, this._messages);

  final Process _process;
  final Stream<Map<String, Object?>> _messages;

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
    configFile.writeAsStringSync(config.encode());

    var process = await Process.start(dartExecutable, [
      'run',
      p.join('tool', 'catalog', 'compiler_daemon.dart'),
      configFile.path,
    ], workingDirectory: config.appPackageRoot);

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog?.call(line));

    var messages = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          try {
            return jsonDecode(line) as Map<String, Object?>;
          } catch (_) {
            onLog?.call(line);
            return <String, Object?>{'type': 'log'};
          }
        })
        .asBroadcastStream();

    var first = await messages.firstWhere((m) => m['type'] != 'log');
    if (first['type'] != 'ready') {
      process.kill();
      throw StateError('the compiler daemon failed: ${first['message']}');
    }
    return (
      CompilerDaemonClient._(process, messages),
      DaemonReady.fromJson(first),
    );
  }

  /// Makes [id] the active entry and compiles it into the entrypoint.
  Future<DaemonCompiled> select(String id) async {
    var reply = _messages.firstWhere((m) => m['type'] == 'compiled');
    _process.stdin.writeln(jsonEncode({'type': 'select', 'id': id}));
    return DaemonCompiled.fromJson(await reply);
  }

  Future<void> shutdown() async {
    try {
      _process.stdin.writeln(jsonEncode({'type': 'shutdown'}));
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Falls through to the kill below.
    }
    _process.kill();
  }
}

import 'dart:io';

import 'package:args/command_runner.dart';

import 'dart_define.dart';
import 'project_resolution.dart';
import 'session_sink.dart';
import 'transport.dart';

/// Heavy-path command for an *interesting* intercepted run.
///
/// Invoked by the generated bash shim as:
///   wrap run --real `<binary>` --kind `<flutter|dart>` -- `<original args...>`
///
/// Rewrites argv to inject `--dart-define=FW_MARKER=<token>`, runs the real
/// binary under the transport, and captures output to a local session sink.
/// Any failure degrades to a plain run of the real binary.
class RunCommand extends Command<int> {
  @override
  final name = 'run';
  @override
  final description = 'Run an intercepted flutter/dart invocation.';

  RunCommand() {
    argParser
      ..addOption('real', help: 'Absolute path to the real binary.')
      ..addOption('kind', help: 'flutter or dart.');
  }

  @override
  Future<int> run() async {
    final real = argResults!['real'] as String?;
    final original = argResults!.rest;
    if (real == null || real.isEmpty) {
      stderr.writeln('[wrap] missing --real');
      return 64;
    }
    try {
      final ctx = resolveProject(Directory.current);
      if (ctx == null) return _degrade(real, original);

      final token = newSessionId();
      final injected =
          injectDartDefine(original, key: 'FW_MARKER', value: token);

      final flutterwareDir = Directory('${ctx.projectRoot.path}/.flutterware');
      final sink = SessionSink(flutterwareDir, token);
      final out = sink.openOutput();

      final code = await runIntercepted(
        executable: real,
        arguments: injected,
        captureSink: out,
      );

      await out.flush();
      await out.close();
      sink.writeMeta({
        'sessionId': token,
        'worktree': ctx.worktreeName,
        'kind': argResults!['kind'],
        'argvOriginal': original,
        'argvInjected': injected,
        'marker': token,
        'exitCode': code,
      });
      return code;
    } catch (e) {
      stderr.writeln('[wrap] degraded to plain run: $e');
      return _degrade(real, original);
    }
  }

  /// Plain spawn of the real binary with the original argv — the guiding
  /// principle: the user's command always runs.
  Future<int> _degrade(String real, List<String> original) async {
    final proc = await Process.start(
      real,
      original,
      mode: ProcessStartMode.inheritStdio,
    );
    return proc.exitCode;
  }
}

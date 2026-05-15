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
      // Without a binary path there is nothing to run or degrade to.
      stderr.writeln('[wrap] missing --real');
      return 64;
    }

    IOSink? out;
    try {
      final ctx = resolveProject(Directory.current);
      if (ctx == null) return _degrade(real, original);

      final token = newSessionId();
      final injected =
          injectDartDefine(original, key: 'FW_MARKER', value: token);

      final flutterwareDir = Directory('${ctx.projectRoot.path}/.flutterware');
      final sink = SessionSink(flutterwareDir, token);
      out = sink.openOutput();

      final code = await runIntercepted(
        executable: real,
        arguments: injected,
        captureSink: out,
      );

      // Post-run finalisation must never trigger a degrade — the run
      // already happened. Log and swallow any failure, still return code.
      try {
        await out.flush();
        await out.close();
        out = null;
        sink.writeMeta({
          'sessionId': token,
          'worktree': ctx.worktreeName,
          'kind': argResults!['kind'] ?? 'unknown',
          'argvOriginal': original,
          'argvInjected': injected,
          'marker': token,
          'exitCode': code,
        });
      } catch (e) {
        stderr.writeln('[wrap] failed to finalise session: $e');
      }
      return code;
    } catch (e) {
      stderr.writeln('[wrap] degraded to plain run: $e');
      // Close a leaked sink from a failed setup/run before degrading.
      if (out != null) {
        try {
          await out.close();
        } catch (_) {}
      }
      return _degrade(real, original);
    }
  }

  /// Plain spawn of the real binary with the original argv — the guiding
  /// principle: the user's command always runs. If even this fails (the
  /// binary is genuinely not runnable) there is nothing to salvage; report
  /// and exit non-zero rather than crashing with a stack trace.
  Future<int> _degrade(String real, List<String> original) async {
    try {
      final proc = await Process.start(
        real,
        original,
        mode: ProcessStartMode.inheritStdio,
      );
      return proc.exitCode;
    } catch (e) {
      stderr.writeln('[wrap] degrade failed: $e');
      return 1;
    }
  }
}

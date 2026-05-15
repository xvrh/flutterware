import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';

import 'pty/pty.dart';
import 'pty/bindings/libc_bindings.dart' show SIGINT, SIGTERM;
import 'tee_sink.dart';

class PassthroughCommand extends Command<int> {
  @override
  final name = 'run';

  @override
  final description = 'Run a subprocess under a PTY.';

  PassthroughCommand() {
    argParser
      ..addOption('cwd', help: 'Working directory for the child process.')
      ..addFlag('print-capture-summary',
          defaultsTo: true,
          help: 'After exit, print captured byte count + exit code to stderr.');
  }

  @override
  Future<int> run() async {
    final cwd = argResults!['cwd'] as String?;
    final printSummary = argResults!['print-capture-summary'] as bool;
    final rest = argResults!.rest;

    if (rest.isEmpty) {
      stderr.writeln(
          'Usage: passthrough run [options] -- <executable> [args...]');
      return 64;
    }

    final executable = rest.first;
    final arguments = rest.skip(1).toList();

    // Validate parent stdio.
    if (!stdin.hasTerminal || !stdout.hasTerminal) {
      stderr.writeln(
          '[passthrough] warning: parent stdin/stdout is not a TTY, interactive features may not work');
    }

    return await runUnderPty(
      executable: executable,
      arguments: arguments,
      workingDirectory: cwd,
      printSummary: printSummary,
    );
  }
}

/// Extracted as a top-level function so it can be unit-tested without
/// constructing a CommandRunner.
Future<int> runUnderPty({
  required String executable,
  required List<String> arguments,
  String? workingDirectory,
  bool printSummary = true,
}) async {
  // Snapshot parent terminal modes for restoration.
  final originalLineMode = stdin.hasTerminal ? stdin.lineMode : true;
  final originalEchoMode = stdin.hasTerminal ? stdin.echoMode : true;

  // Declare subscriptions and tee outside the try so finally can cancel them.
  StreamSubscription<List<int>>? stdinSub;
  StreamSubscription<ProcessSignal>? winchSub;
  StreamSubscription<ProcessSignal>? intSub;
  StreamSubscription<ProcessSignal>? termSub;
  StreamSubscription<Uint8List>? outputSub;

  late TeeSink tee;

  try {
    if (stdin.hasTerminal) {
      stdin.lineMode = false;
      stdin.echoMode = false;
    }

    final pty = await spawnPty(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );

    tee = TeeSink(onBytes: stdout.add);

    // PTY output → tee (stdout + capture).
    final outputDone = Completer<void>();
    outputSub = pty.output.listen(
      tee.add,
      onDone: outputDone.complete,
      onError: (Object e, StackTrace st) {
        if (!outputDone.isCompleted) outputDone.completeError(e, st);
      },
    );

    // Parent stdin → PTY input.
    if (stdin.hasTerminal) {
      stdinSub = stdin.listen(pty.writeInput);
    }

    // Resize forwarding.
    winchSub = ProcessSignal.sigwinch.watch().listen((_) {
      if (stdout.hasTerminal) {
        pty.resize(stdout.terminalColumns, stdout.terminalLines);
      }
    });

    // Signal forwarding.
    intSub = ProcessSignal.sigint.watch().listen((_) => pty.sendSignal(SIGINT));
    termSub =
        ProcessSignal.sigterm.watch().listen((_) => pty.sendSignal(SIGTERM));

    final code = await pty.exitCode;
    await outputDone.future;

    if (printSummary) {
      stderr
          .writeln('[passthrough] captured ${tee.byteCount} bytes, exit $code');
    }

    return code;
  } finally {
    try {
      if (stdin.hasTerminal) {
        stdin.lineMode = originalLineMode;
        stdin.echoMode = originalEchoMode;
      }
    } catch (_) {
      // If terminal vanished mid-run, swallow — subscription cleanup must still run.
    }
    await stdinSub?.cancel();
    await winchSub?.cancel();
    await intSub?.cancel();
    await termSub?.cancel();
    await outputSub?.cancel();
  }
}

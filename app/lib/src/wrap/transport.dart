import 'dart:async';
import 'dart:io';

/// Runs [executable] with [arguments], streaming I/O to the parent and
/// teeing all output into [captureSink].
///
/// Plain pipes, always. There used to be a PTY branch for interactive runs
/// (the deleted `src/passthrough/` tree carried the bindings); if wrap ever
/// needs a child that believes it has a terminal again, that is the history
/// to resurrect. The pipes are the mode every wired caller used — an IDE /
/// `--machine` run whose stdin/stdout carry the daemon JSON-RPC protocol.
Future<int> runIntercepted({
  required String executable,
  required List<String> arguments,
  required IOSink captureSink,
  String? workingDirectory,
}) => _runPiped(
  executable: executable,
  arguments: arguments,
  workingDirectory: workingDirectory,
  captureSink: captureSink,
);

Future<int> _runPiped({
  required String executable,
  required List<String> arguments,
  required IOSink captureSink,
  String? workingDirectory,
}) async {
  final proc = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );

  StreamSubscription<List<int>>? stdinSub;
  try {
    stdinSub = stdin.listen(
      proc.stdin.add,
      onDone: () => proc.stdin.close().catchError((_) {}),
      onError: (_) {},
    );
  } catch (_) {
    // stdin may not be listenable in all environments (e.g. flutter test);
    // proceed without forwarding stdin.
    unawaited(proc.stdin.close().catchError((_) {}));
  }

  final outDone = Completer<void>();
  final errDone = Completer<void>();
  proc.stdout.listen(
    (chunk) {
      stdout.add(chunk);
      captureSink.add(chunk);
    },
    onDone: outDone.complete,
    onError: (Object e, StackTrace st) {
      if (!outDone.isCompleted) outDone.completeError(e, st);
    },
  );
  proc.stderr.listen(
    (chunk) {
      stderr.add(chunk);
      captureSink.add(chunk);
    },
    onDone: errDone.complete,
    onError: (Object e, StackTrace st) {
      if (!errDone.isCompleted) errDone.completeError(e, st);
    },
  );

  try {
    final code = await proc.exitCode;
    await outDone.future;
    await errDone.future;
    return code;
  } finally {
    await stdinSub?.cancel();
  }
}

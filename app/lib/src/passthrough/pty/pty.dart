import 'dart:async';
import 'dart:typed_data';
import 'pty_impl.dart';

/// Handle to a child process running under a pseudo-terminal.
abstract class PtyProcess {
  /// Combined stdout+stderr from the PTY master fd.
  Stream<Uint8List> get output;

  /// Send bytes to the child's stdin.
  void writeInput(List<int> bytes);

  /// Update the PTY window size (sent as TIOCSWINSZ).
  void resize(int cols, int rows);

  /// Send a signal to the child process.
  void sendSignal(int signal);

  /// Resolves with the child's exit code (0-255 for normal exit,
  /// 128+signum for signal death, 127 for execvp failure).
  Future<int> get exitCode;
}

/// Spawn [executable] with [arguments] under a new PTY.
///
/// If [cols] or [rows] is null, the parent stdout's terminal size is used.
/// If [workingDirectory] is provided, the child chdir's to it before exec.
Future<PtyProcess> spawnPty(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  int? cols,
  int? rows,
}) =>
    PtyProcessImpl.spawn(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      cols: cols,
      rows: rows,
    );

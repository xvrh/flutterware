

import 'package:meta/meta.dart';
import 'dart:io' as io;

import 'async_guard.dart';
/// A class that wraps stdout, stderr, and stdin, and exposes the allowed
/// operations.
///
/// In particular, there are three ways that writing to stdout and stderr
/// can fail. A call to stdout.write() can fail:
///   * by throwing a regular synchronous exception,
///   * by throwing an exception asynchronously, and
///   * by completing the Future stdout.done with an error.
///
/// This class enapsulates all three so that we don't have to worry about it
/// anywhere else.
class Stdio {
  Stdio();

  /// Tests can provide overrides to use instead of the stdout and stderr from
  /// dart:io.
  @visibleForTesting
  Stdio.test({
    required io.Stdout stdout,
    required io.IOSink stderr,
  }) : _stdoutOverride = stdout, _stderrOverride = stderr;

  io.Stdout? _stdoutOverride;
  io.IOSink? _stderrOverride;

  // These flags exist to remember when the done Futures on stdout and stderr
  // complete to avoid trying to write to a closed stream sink, which would
  // generate a [StateError].
  bool _stdoutDone = false;
  bool _stderrDone = false;

  Stream<List<int>> get stdin => io.stdin;

  io.Stdout get stdout {
    if (_stdout != null) {
      return _stdout!;
    }
    _stdout = _stdoutOverride ?? io.stdout;
    _stdout!.done.then(
          (void _) { _stdoutDone = true; },
      onError: (Object err, StackTrace st) { _stdoutDone = true; },
    );
    return _stdout!;
  }
  //ignore: close_sinks
  io.Stdout? _stdout;

  @visibleForTesting
  io.IOSink get stderr {
    if (_stderr != null) {
      return _stderr!;
    }
    _stderr = _stderrOverride ?? io.stderr;
    _stderr!.done.then(
          (void _) { _stderrDone = true; },
      onError: (Object err, StackTrace st) { _stderrDone = true; },
    );
    return _stderr!;
  }
  //ignore: close_sinks
  io.IOSink? _stderr;

  bool get hasTerminal => io.stdout.hasTerminal;

  static bool? _stdinHasTerminal;

  /// Determines whether there is a terminal attached.
  ///
  /// [io.Stdin.hasTerminal] only covers a subset of cases. In this check the
  /// echoMode is toggled on and off to catch cases where the tool running in
  /// a docker container thinks there is an attached terminal. This can cause
  /// runtime errors such as "inappropriate ioctl for device" if not handled.
  bool get stdinHasTerminal {
    if (_stdinHasTerminal != null) {
      return _stdinHasTerminal!;
    }
    if (stdin is! io.Stdin) {
      return _stdinHasTerminal = false;
    }
    final ioStdin = stdin as io.Stdin;
    if (!ioStdin.hasTerminal) {
      return _stdinHasTerminal = false;
    }
    try {
      final currentEchoMode = ioStdin.echoMode;
      ioStdin.echoMode = !currentEchoMode;
      ioStdin.echoMode = currentEchoMode;
    } on io.StdinException {
      return _stdinHasTerminal = false;
    }
    return _stdinHasTerminal = true;
  }

  int? get terminalColumns => hasTerminal ? stdout.terminalColumns : null;
  int? get terminalLines => hasTerminal ? stdout.terminalLines : null;
  bool get supportsAnsiEscapes => hasTerminal && stdout.supportsAnsiEscapes;

  /// Writes [message] to [stderr], falling back on [fallback] if the write
  /// throws any exception. The default fallback calls [print] on [message].
  void stderrWrite(
      String message, {
        void Function(String, dynamic, StackTrace)? fallback,
      }) {
    if (!_stderrDone) {
      _stdioWrite(stderr, message, fallback: fallback);
      return;
    }
    fallback == null ? print(message) : fallback(
      message,
      const io.StdoutException('stderr is done'),
      StackTrace.current,
    );
  }

  /// Writes [message] to [stdout], falling back on [fallback] if the write
  /// throws any exception. The default fallback calls [print] on [message].
  void stdoutWrite(
      String message, {
        void Function(String, dynamic, StackTrace)? fallback,
      }) {
    if (!_stdoutDone) {
      _stdioWrite(stdout, message, fallback: fallback);
      return;
    }
    fallback == null ? print(message) : fallback(
      message,
      const io.StdoutException('stdout is done'),
      StackTrace.current,
    );
  }

  // Helper for [stderrWrite] and [stdoutWrite].
  void _stdioWrite(io.IOSink sink, String message, {
    void Function(String, dynamic, StackTrace)? fallback,
  }) {
    asyncGuard<void>(() async {
      sink.write(message);
    }, onError: (Object error, StackTrace stackTrace) {
      if (fallback == null) {
        print(message);
      } else {
        fallback(message, error, stackTrace);
      }
    });
  }

  /// Adds [stream] to [stdout].
  Future<void> addStdoutStream(Stream<List<int>> stream) => stdout.addStream(stream);

  /// Adds [stream] to [stderr].
  Future<void> addStderrStream(Stream<List<int>> stream) => stderr.addStream(stream);
}
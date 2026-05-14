import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings/libc_bindings.dart';
import 'pty.dart';

class PtyProcessImpl implements PtyProcess {
  final int _masterFd;
  final int _pid;
  final LibcBindings _libc;
  final StreamController<Uint8List> _output;
  final Completer<int> _exitCode = Completer<int>();
  late final Isolate _reader;
  late final ReceivePort _rp;

  PtyProcessImpl._(this._masterFd, this._pid, this._libc)
      : _output = StreamController<Uint8List>.broadcast();

  static Future<PtyProcessImpl> spawn(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    int? cols,
    int? rows,
  }) async {
    final libc = LibcBindings();

    // Build argv: [executable, ...arguments, nullptr]
    final argv = calloc<Pointer<Utf8>>(arguments.length + 2);
    argv[0] = executable.toNativeUtf8();
    for (var i = 0; i < arguments.length; i++) {
      argv[i + 1] = arguments[i].toNativeUtf8();
    }
    argv[arguments.length + 1] = nullptr;

    // Build winsize (use parent terminal size as default)
    final ws = calloc<WinSize>()
      ..ref.ws_col = cols ?? (stdout.hasTerminal ? stdout.terminalColumns : 80)
      ..ref.ws_row = rows ?? (stdout.hasTerminal ? stdout.terminalLines : 24);

    final masterOut = calloc<Int32>();
    final exePtr = executable.toNativeUtf8();
    final cwdPtr =
        workingDirectory != null ? workingDirectory.toNativeUtf8() : nullptr;

    final pid = libc.forkpty(masterOut, nullptr, nullptr, ws);

    if (pid < 0) {
      _freeArgv(argv, arguments.length + 2);
      calloc.free(ws);
      calloc.free(masterOut);
      calloc.free(exePtr);
      if (cwdPtr != nullptr) calloc.free(cwdPtr);
      throw PtyException('forkpty failed');
    }

    if (pid == 0) {
      // ====== CHILD BRANCH ======
      // Only async-signal-safe calls below.
      if (cwdPtr != nullptr) {
        final rc = libc.chdir(cwdPtr);
        if (rc != 0) libc.exitProcess(127);
      }
      libc.execvp(exePtr, argv);
      libc.exitProcess(127); // execvp failed
      // Unreachable.
    }

    // ====== PARENT BRANCH ======
    final masterFd = masterOut.value;
    calloc.free(masterOut);
    calloc.free(ws);
    _freeArgv(argv, arguments.length + 2);
    calloc.free(exePtr);
    if (cwdPtr != nullptr) calloc.free(cwdPtr);

    final impl = PtyProcessImpl._(masterFd, pid, libc);
    await impl._startReader();
    return impl;
  }

  static void _freeArgv(Pointer<Pointer<Utf8>> argv, int count) {
    for (var i = 0; i < count; i++) {
      final p = argv[i];
      if (p != nullptr) calloc.free(p);
    }
    calloc.free(argv);
  }

  Future<void> _startReader() async {
    _rp = ReceivePort();
    _reader = await Isolate.spawn(
      _readerEntry,
      _ReaderArgs(_masterFd, _pid, _rp.sendPort),
    );
    _rp.listen((msg) {
      if (msg is Uint8List) {
        _output.add(msg);
      } else if (msg is _ExitEvent) {
        if (!_exitCode.isCompleted) _exitCode.complete(msg.code);
        _output.close();
        _rp.close();
      }
    });
  }

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  void writeInput(List<int> bytes) {
    final buf = calloc<Uint8>(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      buf[i] = bytes[i];
    }
    _libc.write(_masterFd, buf, bytes.length);
    calloc.free(buf);
  }

  @override
  void resize(int cols, int rows) {
    final ws = calloc<WinSize>()
      ..ref.ws_col = cols
      ..ref.ws_row = rows;
    _libc.ioctl(_masterFd, TIOCSWINSZ, ws);
    calloc.free(ws);
  }

  @override
  void sendSignal(int signal) {
    _libc.kill(_pid, signal);
  }
}

class PtyException implements Exception {
  final String message;
  PtyException(this.message);
  @override
  String toString() => 'PtyException: $message';
}

class _ReaderArgs {
  final int masterFd;
  final int pid;
  final SendPort sendPort;
  _ReaderArgs(this.masterFd, this.pid, this.sendPort);
}

class _ExitEvent {
  final int code;
  _ExitEvent(this.code);
}

void _readerEntry(_ReaderArgs args) {
  final libc = LibcBindings();
  final buf = calloc<Uint8>(8192);
  try {
    while (true) {
      final n = libc.read(args.masterFd, buf, 8192);
      if (n <= 0) break;
      final bytes = Uint8List(n);
      for (var i = 0; i < n; i++) {
        bytes[i] = buf[i];
      }
      args.sendPort.send(bytes);
    }
  } finally {
    calloc.free(buf);
  }
  // Reap child.
  final statusPtr = calloc<Int32>();
  libc.waitpid(args.pid, statusPtr, 0);
  final status = statusPtr.value;
  calloc.free(statusPtr);

  int code;
  if (WIFEXITED(status)) {
    code = WEXITSTATUS(status);
  } else if (WIFSIGNALED(status)) {
    code = 128 + WTERMSIG(status);
  } else {
    code = 1;
  }
  args.sendPort.send(_ExitEvent(code));
}

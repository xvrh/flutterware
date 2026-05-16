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

  PtyProcessImpl._(this._masterFd, this._pid, this._libc)
      : _output = StreamController<Uint8List>();

  static Future<PtyProcessImpl> spawn(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    int? cols,
    int? rows,
  }) async {
    final libc = LibcBindings();

    // Open a PTY master. The child is spawned with posix_spawn, which does the
    // fork+exec entirely inside libc — no Dart code runs in the child. That is
    // deliberate: forkpty() returns into the caller in the child too, and
    // running *any* Dart in a forked child of the multi-threaded Dart VM can
    // deadlock if a GC/safepoint was in progress at fork() time.
    final masterFd = libc.posixOpenpt(O_RDWR | O_NOCTTY);
    if (masterFd < 0) {
      throw PtyException('posix_openpt failed');
    }
    if (libc.grantpt(masterFd) != 0 || libc.unlockpt(masterFd) != 0) {
      libc.close(masterFd);
      throw PtyException('grantpt/unlockpt failed');
    }
    final slaveNamePtr = libc.ptsname(masterFd);
    if (slaveNamePtr == nullptr) {
      libc.close(masterFd);
      throw PtyException('ptsname failed');
    }
    final slavePath = slaveNamePtr.toDartString();

    // Set the initial window size. The slave's first open resets the PTY's
    // winsize to 0x0, so the parent opens the slave once itself to absorb that
    // reset, then sets the size. The fd is held open across posix_spawn (so the
    // child's open is not the "first" one) and closed afterwards.
    final slavePathPtr = slavePath.toNativeUtf8();
    final parentSlaveFd = libc.openFile(slavePathPtr, O_RDWR | O_NOCTTY);
    final ws = calloc<WinSize>()
      ..ref.ws_col = cols ?? (stdout.hasTerminal ? stdout.terminalColumns : 80)
      ..ref.ws_row = rows ?? (stdout.hasTerminal ? stdout.terminalLines : 24);
    libc.ioctl(masterFd, TIOCSWINSZ, ws);
    calloc.free(ws);

    // argv: [executable, ...arguments, nullptr]
    final argv = calloc<Pointer<Utf8>>(arguments.length + 2);
    argv[0] = executable.toNativeUtf8();
    for (var i = 0; i < arguments.length; i++) {
      argv[i + 1] = arguments[i].toNativeUtf8();
    }
    argv[arguments.length + 1] = nullptr;

    // envp: inherit the current process environment.
    final env = Platform.environment;
    final envp = calloc<Pointer<Utf8>>(env.length + 1);
    var ei = 0;
    env.forEach((k, v) {
      envp[ei++] = '$k=$v'.toNativeUtf8();
    });
    envp[env.length] = nullptr;

    // posix_spawn_file_actions_t / posix_spawnattr_t are opaque structs whose
    // size differs by platform; a generously-sized zeroed buffer covers both.
    final fileActions = calloc<Uint8>(1024);
    final attr = calloc<Uint8>(1024);
    final exePtr = executable.toNativeUtf8();
    final cwdPtr =
        workingDirectory != null ? workingDirectory.toNativeUtf8() : nullptr;
    final pidOut = calloc<Int32>();

    libc.faInit(fileActions.cast());
    libc.attrInit(attr.cast());
    libc.attrSetflags(attr.cast(), POSIX_SPAWN_SETSID);

    // The child opens the slave (without O_NOCTTY) as a fresh session leader,
    // so the PTY becomes its controlling terminal, then mirrors it onto stdio.
    libc.faAddopen(fileActions.cast(), 0, slavePathPtr, O_RDWR, 0);
    libc.faAdddup2(fileActions.cast(), 0, 1);
    libc.faAdddup2(fileActions.cast(), 0, 2);
    // Don't leak the master fd into the child.
    libc.faAddclose(fileActions.cast(), masterFd);
    if (cwdPtr != nullptr) {
      libc.faAddchdir(fileActions.cast(), cwdPtr);
    }

    final rc = libc.posixSpawnp(
      pidOut,
      exePtr,
      fileActions.cast(),
      attr.cast(),
      argv,
      envp,
    );
    final pid = pidOut.value;

    libc.faDestroy(fileActions.cast());
    libc.attrDestroy(attr.cast());
    if (parentSlaveFd >= 0) libc.close(parentSlaveFd);
    calloc.free(fileActions);
    calloc.free(attr);
    calloc.free(pidOut);
    calloc.free(exePtr);
    calloc.free(slavePathPtr);
    if (cwdPtr != nullptr) calloc.free(cwdPtr);
    _freeStrArray(argv);
    _freeStrArray(envp);

    if (rc != 0) {
      // posix_spawn could not exec the target (e.g. binary not found). Mirror
      // the historical execvp-failure contract: exit code 127, no output.
      libc.close(masterFd);
      final impl = PtyProcessImpl._(masterFd, -1, libc);
      impl._exitCode.complete(127);
      unawaited(impl._output.close());
      return impl;
    }

    final impl = PtyProcessImpl._(masterFd, pid, libc);
    await impl._startReader();
    return impl;
  }

  static void _freeStrArray(Pointer<Pointer<Utf8>> arr) {
    for (var i = 0;; i++) {
      final p = arr[i];
      if (p == nullptr) break;
      calloc.free(p);
    }
    calloc.free(arr);
  }

  Future<void> _startReader() async {
    final rp = ReceivePort();
    await Isolate.spawn(
      _readerEntry,
      _ReaderArgs(_masterFd, _pid, rp.sendPort),
    );
    rp.listen((msg) {
      if (msg is Uint8List) {
        _output.add(msg);
      } else if (msg is _ExitEvent) {
        if (!_exitCode.isCompleted) _exitCode.complete(msg.code);
        _output.close();
        _libc.close(_masterFd);
        rp.close();
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
    if (_pid > 0) _libc.kill(_pid, signal);
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

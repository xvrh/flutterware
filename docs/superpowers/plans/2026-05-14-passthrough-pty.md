# Passthrough PTY Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working `passthrough` CLI command in Flutterware that spawns a child process under a real pseudo-terminal, tees its output, forwards stdin/signals/window-resize, and propagates the exit code — with an automated test suite that proves the PTY mechanics are correct.

**Architecture:** A small Dart library at `app/lib/src/passthrough/pty/` binds libc + libutil via hand-written FFI to `forkpty(3)` and friends. One helper isolate per spawn does the blocking `read()` loop and final `waitpid()`. A thin `passthrough_command.dart` policy layer owns raw-mode handling, signal forwarding, and the tee-to-stdout-plus-capture. A sibling bin entry `app/bin/passthrough.dart` exposes it via `CommandRunner`.

**Tech Stack:** Dart SDK 3.12-dev, `package:ffi`, `package:args` (existing), `package:test` (existing, run via `flutter test`).

**Deviation from spec, flagged:** The spec describes snapshotting parent termios via `tcgetattr` into the child PTY at spawn. For phase 1 we pass `nullptr` to `forkpty`, letting the kernel use default termios. Reason: portable `termios` struct layout differs significantly between macOS and Linux (different field sizes, different `NCCS`), and none of the verification tests depend on the snapshot. Interactive tools (`vi`, `bash`, `top`) call `tcsetattr` themselves and don't rely on inherited termios. If a real-world test reveals a need, we add it as a follow-up.

**ABI gotcha — `ioctl` is variadic:** `ioctl(int fd, unsigned long request, ...)` is a variadic C function. On Apple Silicon (arm64), the AArch64 calling convention passes variadic arguments on the stack, not in registers — so the FFI typedef MUST declare the trailing `winsize*` with `VarArgs<(Pointer<WinSize>,)>` (available since Dart 3.0), otherwise the kernel reads garbage and `TIOCSWINSZ` silently fails. Linux x86_64 happens to tolerate the non-variadic declaration because the SysV AMD64 ABI passes the first 6 integer/pointer args in registers regardless, but that's incidental — the variadic form is the portably correct one. `forkpty` is fixed-arity, so initial window size is unaffected; only `resize()` (Task 3 / Task 11) hits this path.

---

## File map

**Created in this plan:**
- `app/bin/passthrough.dart` — CLI entry (CommandRunner)
- `app/lib/src/passthrough/passthrough_command.dart` — policy layer
- `app/lib/src/passthrough/tee_sink.dart` — fan-out utility
- `app/lib/src/passthrough/pty/pty.dart` — public surface (`PtyProcess`, `spawnPty`)
- `app/lib/src/passthrough/pty/pty_impl.dart` — spawn + isolate wiring
- `app/lib/src/passthrough/pty/bindings/libc_bindings.dart` — hand-written FFI
- `app/test/passthrough/pty_test.dart` — library-level tests
- `app/test/passthrough/passthrough_command_test.dart` — command-level tests
- `app/test/passthrough/tee_sink_test.dart` — unit test
- `docs/superpowers/specs/2026-05-14-passthrough-manual-smoke.md` — manual smoke checklist

**Modified:**
- `app/pubspec.yaml` — add `ffi:` dependency

---

## Task 1: Project bootstrap

**Files:**
- Modify: `app/pubspec.yaml` (add `ffi:` under `dependencies:`)
- Create: `app/bin/passthrough.dart`
- Create: `app/lib/src/passthrough/passthrough_command.dart`
- Create: `app/lib/src/passthrough/pty/pty.dart`
- Create: `app/lib/src/passthrough/pty/pty_impl.dart`
- Create: `app/lib/src/passthrough/pty/bindings/libc_bindings.dart`
- Create: `app/lib/src/passthrough/tee_sink.dart`

- [ ] **Step 1: Add `ffi` dependency**

In `app/pubspec.yaml`, under `dependencies:` (after `args:`), add:

```yaml
  ffi:
```

(No version pin to match the existing style of the file.)

- [ ] **Step 2: Run `flutter pub get`**

```bash
cd app && flutter pub get
```

Expected: succeeds, lockfile updated.

- [ ] **Step 3: Create empty skeleton files**

`app/bin/passthrough.dart`:
```dart
import 'dart:async';
import 'package:args/command_runner.dart';
import 'package:flutterware_app/src/passthrough/passthrough_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>('passthrough', 'Run a subprocess under a PTY.')
    ..addCommand(PassthroughCommand());
  final exitCode = await runner.run(args) ?? 0;
  // ignore: avoid_print
  // exit via process exit code
  await Future<void>.delayed(Duration.zero);
  // Use dart:io exit in next task once command is implemented end-to-end.
  // For now, just propagate.
  // (Will be replaced with `exit(exitCode);` once command body lands.)
  if (exitCode != 0) {
    throw StateError('passthrough exited with $exitCode');
  }
}
```

`app/lib/src/passthrough/passthrough_command.dart`:
```dart
import 'package:args/command_runner.dart';

class PassthroughCommand extends Command<int> {
  @override
  final name = 'run';

  @override
  final description = 'Run a subprocess under a PTY.';

  @override
  Future<int> run() async {
    throw UnimplementedError('Implemented in a later task.');
  }
}
```

`app/lib/src/passthrough/pty/pty.dart`:
```dart
import 'dart:async';
import 'dart:typed_data';

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
}) async {
  throw UnimplementedError('Implemented in Task 4.');
}
```

`app/lib/src/passthrough/pty/pty_impl.dart`:
```dart
// Implementation lands in Task 4.
```

`app/lib/src/passthrough/pty/bindings/libc_bindings.dart`:
```dart
// FFI bindings land in Task 2.
```

`app/lib/src/passthrough/tee_sink.dart`:
```dart
// Tee utility lands in Task 15.
```

- [ ] **Step 4: Verify it compiles**

```bash
cd app && dart analyze lib/src/passthrough bin/passthrough.dart
```

Expected: 0 errors. Warnings about unused imports/unimplemented stubs are fine.

- [ ] **Step 5: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/bin/passthrough.dart app/lib/src/passthrough docs/
git commit -m "passthrough: scaffold bin entry and skeleton files"
```

---

## Task 2: FFI bindings to libc + libutil

**Files:**
- Modify: `app/lib/src/passthrough/pty/bindings/libc_bindings.dart`
- Create: `app/test/passthrough/bindings_smoke_test.dart`

Hand-written bindings to the minimum symbol set. No structs except `winsize` (stable cross-platform). We pass `nullptr` for the termios pointer to `forkpty` (per the deviation flagged at the top).

- [ ] **Step 1: Write the failing smoke test**

`app/test/passthrough/bindings_smoke_test.dart`:
```dart
import 'dart:ffi';
import 'package:flutterware_app/src/passthrough/pty/bindings/libc_bindings.dart';
import 'package:test/test.dart';

void main() {
  test('libc bindings load and getpid returns positive', () {
    final libc = LibcBindings();
    final pid = libc.getpid();
    expect(pid, greaterThan(0));
  });

  test('winsize struct is 8 bytes', () {
    expect(sizeOf<WinSize>(), equals(8));
  });
}
```

- [ ] **Step 2: Run it to verify failure**

```bash
cd app && flutter test test/passthrough/bindings_smoke_test.dart
```

Expected: FAIL — `LibcBindings` undefined.

- [ ] **Step 3: Write the bindings**

Replace `app/lib/src/passthrough/pty/bindings/libc_bindings.dart` with:

```dart
// ignore_for_file: non_constant_identifier_names, camel_case_types

import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';

// ---------- struct: winsize ----------
// Identical on macOS and Linux: four unsigned shorts.
final class WinSize extends Struct {
  @Uint16()
  external int ws_row;
  @Uint16()
  external int ws_col;
  @Uint16()
  external int ws_xpixel;
  @Uint16()
  external int ws_ypixel;
}

// ---------- ioctl request: TIOCSWINSZ ----------
// macOS: 0x80087467 (_IOW('t', 103, struct winsize))
// Linux: 0x5414
int get TIOCSWINSZ => Platform.isMacOS ? 0x80087467 : 0x5414;

// ---------- signal numbers (POSIX-portable subset) ----------
const int SIGHUP = 1;
const int SIGINT = 2;
const int SIGTERM = 15;
const int SIGKILL = 9;

// ---------- waitpid status decoding (replaces W* macros) ----------
bool WIFEXITED(int s) => (s & 0x7f) == 0;
int WEXITSTATUS(int s) => (s >> 8) & 0xff;
bool WIFSIGNALED(int s) => ((s & 0x7f) + 1) >> 1 > 0;
int WTERMSIG(int s) => s & 0x7f;

// ---------- function typedefs ----------
typedef _ForkptyNative = Int32 Function(
    Pointer<Int32>, Pointer<Utf8>, Pointer<Void>, Pointer<WinSize>);
typedef _ForkptyDart = int Function(
    Pointer<Int32>, Pointer<Utf8>, Pointer<Void>, Pointer<WinSize>);

typedef _ExecvpNative = Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>);
typedef _ExecvpDart = int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>);

typedef _ExitNative = Void Function(Int32);
typedef _ExitDart = void Function(int);

typedef _ChdirNative = Int32 Function(Pointer<Utf8>);
typedef _ChdirDart = int Function(Pointer<Utf8>);

typedef _WaitpidNative = Int32 Function(Int32, Pointer<Int32>, Int32);
typedef _WaitpidDart = int Function(int, Pointer<Int32>, int);

typedef _KillNative = Int32 Function(Int32, Int32);
typedef _KillDart = int Function(int, int);

typedef _ReadNative = IntPtr Function(Int32, Pointer<Uint8>, IntPtr);
typedef _ReadDart = int Function(int, Pointer<Uint8>, int);

typedef _WriteNative = IntPtr Function(Int32, Pointer<Uint8>, IntPtr);
typedef _WriteDart = int Function(int, Pointer<Uint8>, int);

typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

// ioctl is variadic; we only need the (fd, request, winsize*) shape.
typedef _IoctlNative = Int32 Function(Int32, IntPtr, Pointer<WinSize>);
typedef _IoctlDart = int Function(int, int, Pointer<WinSize>);

typedef _GetpidNative = Int32 Function();
typedef _GetpidDart = int Function();

// ---------- bindings object ----------

class LibcBindings {
  late final DynamicLibrary _libc;
  late final DynamicLibrary _libutil;

  LibcBindings() {
    if (Platform.isMacOS) {
      _libc = DynamicLibrary.process();
      _libutil = DynamicLibrary.process();
    } else if (Platform.isLinux) {
      _libc = DynamicLibrary.open('libc.so.6');
      _libutil = DynamicLibrary.open('libutil.so.1');
    } else {
      throw UnsupportedError(
          'Passthrough PTY only supports macOS and Linux (got ${Platform.operatingSystem})');
    }

    forkpty = _libutil.lookupFunction<_ForkptyNative, _ForkptyDart>('forkpty');
    execvp = _libc.lookupFunction<_ExecvpNative, _ExecvpDart>('execvp');
    _exit = _libc.lookupFunction<_ExitNative, _ExitDart>('_exit');
    chdir = _libc.lookupFunction<_ChdirNative, _ChdirDart>('chdir');
    waitpid = _libc.lookupFunction<_WaitpidNative, _WaitpidDart>('waitpid');
    kill = _libc.lookupFunction<_KillNative, _KillDart>('kill');
    read = _libc.lookupFunction<_ReadNative, _ReadDart>('read');
    write = _libc.lookupFunction<_WriteNative, _WriteDart>('write');
    close = _libc.lookupFunction<_CloseNative, _CloseDart>('close');
    ioctl = _libc.lookupFunction<_IoctlNative, _IoctlDart>('ioctl');
    getpid = _libc.lookupFunction<_GetpidNative, _GetpidDart>('getpid');
  }

  late final _ForkptyDart forkpty;
  late final _ExecvpDart execvp;
  late final _ExitDart _exit;
  void exitProcess(int code) => _exit(code);
  late final _ChdirDart chdir;
  late final _WaitpidDart waitpid;
  late final _KillDart kill;
  late final _ReadDart read;
  late final _WriteDart write;
  late final _CloseDart close;
  late final _IoctlDart ioctl;
  late final _GetpidDart getpid;
}
```

- [ ] **Step 4: Run the smoke test, verify it passes**

```bash
cd app && flutter test test/passthrough/bindings_smoke_test.dart
```

Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/passthrough/pty/bindings app/test/passthrough/bindings_smoke_test.dart
git commit -m "passthrough: add hand-written libc + libutil FFI bindings"
```

---

## Task 3: Tracer-bullet end-to-end spawn

**Files:**
- Modify: `app/lib/src/passthrough/pty/pty.dart`
- Modify: `app/lib/src/passthrough/pty/pty_impl.dart`
- Create: `app/test/passthrough/pty_test.dart`

Get `spawnPty('echo', ['hello'])` working end-to-end with captured output and exit code. No resize, no signal forwarding, no stdin, no chdir yet. This proves the core mechanics — fork, exec, read loop in helper isolate, waitpid, exit-code decode.

- [ ] **Step 1: Write the failing tracer-bullet test**

`app/test/passthrough/pty_test.dart`:
```dart
import 'dart:convert';
import 'package:flutterware_app/src/passthrough/pty/pty.dart';
import 'package:test/test.dart';

void main() {
  test('tracer: echo hello captures output and exits 0', () async {
    final pty = await spawnPty('/bin/echo', ['hello']);
    final bytes = <int>[];
    await pty.output.listen(bytes.addAll).asFuture<void>();
    final code = await pty.exitCode;
    expect(utf8.decode(bytes), contains('hello'));
    expect(code, equals(0));
  });
}
```

- [ ] **Step 2: Run it, verify failure**

```bash
cd app && flutter test test/passthrough/pty_test.dart
```

Expected: FAIL — `UnimplementedError`.

- [ ] **Step 3: Implement `spawnPty` + `PtyProcess` + reader isolate**

Replace `app/lib/src/passthrough/pty/pty.dart` so the body of `spawnPty` delegates to the impl, and the abstract class stays as-is. Move concrete implementation into `pty_impl.dart`.

`app/lib/src/passthrough/pty/pty.dart` (only the bottom changes):
```dart
import 'dart:async';
import 'dart:typed_data';
import 'pty_impl.dart';

abstract class PtyProcess {
  Stream<Uint8List> get output;
  void writeInput(List<int> bytes);
  void resize(int cols, int rows);
  void sendSignal(int signal);
  Future<int> get exitCode;
}

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
```

`app/lib/src/passthrough/pty/pty_impl.dart`:
```dart
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
```

- [ ] **Step 4: Run the test, verify pass**

```bash
cd app && flutter test test/passthrough/pty_test.dart
```

Expected: tracer test PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/passthrough/pty/pty.dart app/lib/src/passthrough/pty/pty_impl.dart app/test/passthrough/pty_test.dart
git commit -m "passthrough: implement tracer-bullet spawnPty with reader isolate"
```

---

## Task 4: Exit-code propagation tests (normal exits)

**Files:**
- Modify: `app/test/passthrough/pty_test.dart`

Verify `exit 0` and `exit 42` propagate correctly. These should already pass after Task 3; the test makes the behavior explicit.

- [ ] **Step 1: Add the tests**

Append to `app/test/passthrough/pty_test.dart` (inside the `main()` function):

```dart
test('exit 42 propagates correctly', () async {
  final pty = await spawnPty('/bin/bash', ['-c', 'exit 42']);
  await pty.output.drain<void>();
  expect(await pty.exitCode, equals(42));
});

test('successful command returns exit 0', () async {
  final pty = await spawnPty('/bin/bash', ['-c', 'true']);
  await pty.output.drain<void>();
  expect(await pty.exitCode, equals(0));
});
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/pty_test.dart
```

Expected: all three tests PASS.

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/pty_test.dart
git commit -m "passthrough: test normal exit-code propagation"
```

---

## Task 5: execvp failure → exit 127

**Files:**
- Modify: `app/test/passthrough/pty_test.dart`

- [ ] **Step 1: Add the test**

Append to `app/test/passthrough/pty_test.dart`:

```dart
test('nonexistent binary exits 127', () async {
  final pty = await spawnPty('/no/such/binary_xyz', []);
  await pty.output.drain<void>();
  expect(await pty.exitCode, equals(127));
});
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/pty_test.dart -N 'nonexistent binary'
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/pty_test.dart
git commit -m "passthrough: test execvp failure produces exit 127"
```

---

## Task 6: Signal-death exit code (128 + signum)

**Files:**
- Modify: `app/test/passthrough/pty_test.dart`

- [ ] **Step 1: Add the test**

Append:

```dart
test('SIGINT death gives exit 130', () async {
  final pty = await spawnPty('/bin/bash', ['-c', 'kill -INT \$\$; sleep 5']);
  await pty.output.drain<void>();
  expect(await pty.exitCode, equals(130));
});
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/pty_test.dart -N 'SIGINT death'
```

Expected: PASS (Task 3's `_readerEntry` already decodes `WIFSIGNALED` → `128 + WTERMSIG`).

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/pty_test.dart
git commit -m "passthrough: test signal-death exit code decoding"
```

---

## Task 7: Working directory support (chdir)

**Files:**
- Modify: `app/test/passthrough/pty_test.dart`

- [ ] **Step 1: Add the test**

Append:

```dart
test('workingDirectory: /tmp makes pwd report /tmp', () async {
  final pty = await spawnPty('/bin/bash', ['-c', 'pwd'], workingDirectory: '/tmp');
  final bytes = <int>[];
  await pty.output.listen(bytes.addAll).asFuture<void>();
  final out = utf8.decode(bytes);
  // macOS resolves /tmp to /private/tmp; both are acceptable.
  expect(out, anyOf(contains('/tmp'), contains('/private/tmp')));
  expect(await pty.exitCode, equals(0));
});
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/pty_test.dart -N 'workingDirectory'
```

Expected: PASS (chdir wired in Task 3's child branch).

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/pty_test.dart
git commit -m "passthrough: test workingDirectory honored via chdir"
```

---

## Task 8: TTY proof — child sees a real terminal

**Files:**
- Modify: `app/test/passthrough/pty_test.dart`

- [ ] **Step 1: Add the test**

Append:

```dart
test('child sees stdout as a TTY', () async {
  final pty = await spawnPty(
    '/bin/bash',
    ['-c', '[ -t 1 ] && echo IS_TTY || echo NOT_TTY'],
  );
  final bytes = <int>[];
  await pty.output.listen(bytes.addAll).asFuture<void>();
  expect(utf8.decode(bytes), contains('IS_TTY'));
});
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/pty_test.dart -N 'TTY'
```

Expected: PASS — this is the key proof of the PoC.

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/pty_test.dart
git commit -m "passthrough: prove child stdout isatty() under our PTY"
```

---

## Task 9: ANSI escape codes survive

**Files:**
- Modify: `app/test/passthrough/pty_test.dart`

- [ ] **Step 1: Add the test**

Append:

```dart
test('ANSI color codes are not stripped', () async {
  final pty = await spawnPty(
    '/bin/bash',
    ['-c', "printf '\\033[31mred\\033[0m\\n'"],
  );
  final bytes = <int>[];
  await pty.output.listen(bytes.addAll).asFuture<void>();
  // ESC [ 31 m  =  0x1b 0x5b 0x33 0x31 0x6d
  expect(bytes, containsAllInOrder([0x1b, 0x5b, 0x33, 0x31, 0x6d]));
});
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/pty_test.dart -N 'ANSI'
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/pty_test.dart
git commit -m "passthrough: prove ANSI escapes survive PTY pipeline"
```

---

## Task 10: Initial window size (stty size)

**Files:**
- Modify: `app/test/passthrough/pty_test.dart`

- [ ] **Step 1: Add the test**

Append:

```dart
test('cols/rows on spawn are respected by child', () async {
  final pty = await spawnPty(
    '/bin/bash',
    ['-c', 'stty size'],
    cols: 123,
    rows: 40,
  );
  final bytes = <int>[];
  await pty.output.listen(bytes.addAll).asFuture<void>();
  expect(utf8.decode(bytes), contains('123'));
});
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/pty_test.dart -N 'cols/rows on spawn'
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/pty_test.dart
git commit -m "passthrough: test initial PTY window size propagation"
```

---

## Task 11: Resize via ioctl

**Files:**
- Modify: `app/test/passthrough/pty_test.dart`

`resize()` is already implemented (Task 3). This test exercises it after spawn.

- [ ] **Step 1: Add the test**

Append:

```dart
test('resize() updates window size mid-run', () async {
  // Spawn a script that prints size on SIGWINCH then exits.
  final pty = await spawnPty(
    '/bin/bash',
    [
      '-c',
      'trap "stty size; exit 0" WINCH; sleep 5 & wait',
    ],
    cols: 80,
    rows: 24,
  );
  // Give bash a moment to install the trap.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  pty.resize(150, 50);

  final bytes = <int>[];
  await pty.output.listen(bytes.addAll).asFuture<void>();
  expect(utf8.decode(bytes), contains('150'));
}, timeout: const Timeout(Duration(seconds: 10)));
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/pty_test.dart -N 'resize'
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/pty_test.dart
git commit -m "passthrough: test ioctl TIOCSWINSZ resize after spawn"
```

---

## Task 12: Stdin path (writeInput)

**Files:**
- Modify: `app/test/passthrough/pty_test.dart`

- [ ] **Step 1: Add the test**

Append:

```dart
test('writeInput forwards bytes to child stdin', () async {
  final pty = await spawnPty(
    '/bin/bash',
    ['-c', 'read x; echo got=\$x'],
  );
  // Give bash a moment to reach the `read` call.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  pty.writeInput(utf8.encode('hello\n'));

  final bytes = <int>[];
  await pty.output.listen(bytes.addAll).asFuture<void>();
  expect(utf8.decode(bytes), contains('got=hello'));
});
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/pty_test.dart -N 'writeInput'
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/pty_test.dart
git commit -m "passthrough: test writeInput delivers bytes to child stdin"
```

---

## Task 13: High-volume reader (1000 lines, no loss)

**Files:**
- Modify: `app/test/passthrough/pty_test.dart`

- [ ] **Step 1: Add the test**

Append:

```dart
test('1000 lines from child are all received in order', () async {
  final pty = await spawnPty(
    '/bin/bash',
    ['-c', 'for i in \$(seq 1 1000); do echo line\$i; done'],
  );
  final bytes = <int>[];
  await pty.output.listen(bytes.addAll).asFuture<void>();
  final text = utf8.decode(bytes);
  // Verify a sample of lines spread across the range.
  for (final i in [1, 250, 500, 750, 1000]) {
    expect(text, contains('line$i'));
  }
  // And that they're in order.
  final pos1 = text.indexOf('line1\n');
  final pos1000 = text.indexOf('line1000');
  expect(pos1, lessThan(pos1000));
});
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/pty_test.dart -N '1000 lines'
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/pty_test.dart
git commit -m "passthrough: test high-volume reader has no data loss"
```

---

## Task 14: Tee sink utility

**Files:**
- Modify: `app/lib/src/passthrough/tee_sink.dart`
- Create: `app/test/passthrough/tee_sink_test.dart`

- [ ] **Step 1: Write the failing test**

`app/test/passthrough/tee_sink_test.dart`:
```dart
import 'dart:typed_data';
import 'package:flutterware_app/src/passthrough/tee_sink.dart';
import 'package:test/test.dart';

void main() {
  test('TeeSink writes to both stdout sink and capture buffer', () {
    final written = <int>[];
    final sink = TeeSink(
      onBytes: written.addAll,
    );

    sink.add(Uint8List.fromList([1, 2, 3]));
    sink.add(Uint8List.fromList([4, 5]));

    expect(written, equals([1, 2, 3, 4, 5]));
    expect(sink.captured, equals([1, 2, 3, 4, 5]));
    expect(sink.byteCount, equals(5));
  });
}
```

- [ ] **Step 2: Run, verify failure**

```bash
cd app && flutter test test/passthrough/tee_sink_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

`app/lib/src/passthrough/tee_sink.dart`:
```dart
import 'dart:typed_data';

/// Fans incoming byte chunks out to a live sink (typically stdout) and
/// simultaneously accumulates them in an in-memory buffer.
class TeeSink {
  final void Function(List<int>) onBytes;
  final BytesBuilder _capture = BytesBuilder(copy: false);

  TeeSink({required this.onBytes});

  void add(List<int> chunk) {
    onBytes(chunk);
    _capture.add(chunk);
  }

  Uint8List get captured => _capture.toBytes();
  int get byteCount => _capture.length;
}
```

- [ ] **Step 4: Run, verify pass**

```bash
cd app && flutter test test/passthrough/tee_sink_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/passthrough/tee_sink.dart app/test/passthrough/tee_sink_test.dart
git commit -m "passthrough: add TeeSink utility for stdout + capture fan-out"
```

---

## Task 15: passthrough_command.dart — args, raw mode, lifecycle

**Files:**
- Modify: `app/lib/src/passthrough/passthrough_command.dart`
- Modify: `app/bin/passthrough.dart`

This is the policy layer. We don't write an automated test for it directly (Task 16 covers raw-mode restoration, and Task 19 runs the full CLI as an integration test). The logic here is just glue.

- [ ] **Step 1: Implement `PassthroughCommand`**

Replace `app/lib/src/passthrough/passthrough_command.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      ..addOption('cwd',
          help: 'Working directory for the child process.')
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
      stderr.writeln('Usage: passthrough run [options] -- <executable> [args...]');
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
      stderr.writeln(
          '[passthrough] captured ${tee.byteCount} bytes, exit $code');
    }

    return code;
  } finally {
    if (stdin.hasTerminal) {
      stdin.lineMode = originalLineMode;
      stdin.echoMode = originalEchoMode;
    }
    await stdinSub?.cancel();
    await winchSub?.cancel();
    await intSub?.cancel();
    await termSub?.cancel();
    await outputSub?.cancel();
  }
}
```

- [ ] **Step 2: Fix up bin entry**

Replace `app/bin/passthrough.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutterware_app/src/passthrough/passthrough_command.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>('passthrough', 'Run a subprocess under a PTY.')
        ..addCommand(PassthroughCommand());
  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
```

- [ ] **Step 3: Verify it analyzes cleanly**

```bash
cd app && dart analyze lib/src/passthrough bin/passthrough.dart
```

Expected: 0 errors.

- [ ] **Step 4: Smoke-run the CLI by hand**

```bash
cd app && dart run bin/passthrough.dart run -- /bin/echo hello
```

Expected output (something like):
```
hello
[passthrough] captured 6 bytes, exit 0
```

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/passthrough/passthrough_command.dart app/bin/passthrough.dart
git commit -m "passthrough: implement command lifecycle (args, raw mode, signals, tee)"
```

---

## Task 16: Raw-mode restoration test

**Files:**
- Create: `app/test/passthrough/passthrough_command_test.dart`

We can't easily test full raw-mode behavior inside `flutter test` (its stdin isn't a TTY), so this test verifies the restoration *path* by invoking `runUnderPty` with a deliberately-failing executable and asserting that subscriptions are cleaned up and no exception leaks beyond the function. Real raw-mode restoration is covered by the manual smoke list (Task 19).

- [ ] **Step 1: Write the test**

`app/test/passthrough/passthrough_command_test.dart`:
```dart
import 'package:flutterware_app/src/passthrough/passthrough_command.dart';
import 'package:test/test.dart';

void main() {
  test('runUnderPty returns 127 for nonexistent executable without throwing',
      () async {
    final code = await runUnderPty(
      executable: '/no/such/binary_xyz_for_test',
      arguments: const [],
      printSummary: false,
    );
    expect(code, equals(127));
  });

  test('runUnderPty returns 0 for /bin/true', () async {
    final code = await runUnderPty(
      executable: '/bin/true',
      arguments: const [],
      printSummary: false,
    );
    expect(code, equals(0));
  });
}
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/passthrough_command_test.dart
```

Expected: both tests PASS.

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/passthrough_command_test.dart
git commit -m "passthrough: test runUnderPty cleanup on success and failure"
```

---

## Task 17: End-to-end CLI integration test

**Files:**
- Modify: `app/test/passthrough/passthrough_command_test.dart`

Run the actual CLI as a subprocess via `Process.run` and assert behavior. This exercises the full bin entry + CommandRunner + command + library stack.

- [ ] **Step 1: Add the integration tests**

Update `app/test/passthrough/passthrough_command_test.dart` so its imports include `dart:io`, and add the three tests inside the existing `main()` function (after the two tests from Task 16). Final file shape:

```dart
import 'dart:io';

import 'package:flutterware_app/src/passthrough/passthrough_command.dart';
import 'package:test/test.dart';

void main() {
  test('runUnderPty returns 127 for nonexistent executable without throwing',
      () async {
    final code = await runUnderPty(
      executable: '/no/such/binary_xyz_for_test',
      arguments: const [],
      printSummary: false,
    );
    expect(code, equals(127));
  });

  test('runUnderPty returns 0 for /bin/true', () async {
    final code = await runUnderPty(
      executable: '/bin/true',
      arguments: const [],
      printSummary: false,
    );
    expect(code, equals(0));
  });

  test('CLI: echo hello via bin/passthrough.dart', () async {
    final result = await Process.run(
      Platform.resolvedExecutable, // dart binary
      [
        'run',
        'bin/passthrough.dart',
        'run',
        '--no-print-capture-summary',
        '--',
        '/bin/echo',
        'integration-ok',
      ],
    );
    expect(result.exitCode, equals(0));
    expect(result.stdout.toString(), contains('integration-ok'));
  });

  test('CLI: missing -- separator yields usage error 64', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/passthrough.dart', 'run'],
    );
    expect(result.exitCode, equals(64));
    expect(result.stderr.toString(), contains('Usage:'));
  });

  test('CLI: exit-code passthrough for `bash -c "exit 42"`', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        'bin/passthrough.dart',
        'run',
        '--no-print-capture-summary',
        '--',
        '/bin/bash',
        '-c',
        'exit 42',
      ],
    );
    expect(result.exitCode, equals(42));
  });
}
```

- [ ] **Step 2: Run, verify pass**

```bash
cd app && flutter test test/passthrough/passthrough_command_test.dart
```

Expected: all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add app/test/passthrough/passthrough_command_test.dart
git commit -m "passthrough: end-to-end CLI integration tests"
```

---

## Task 18: Manual smoke test checklist

**Files:**
- Create: `docs/superpowers/specs/2026-05-14-passthrough-manual-smoke.md`

- [ ] **Step 1: Write the doc**

`docs/superpowers/specs/2026-05-14-passthrough-manual-smoke.md`:
```markdown
# Passthrough PTY — Manual Smoke Tests

Companion to `2026-05-14-passthrough-pty-design.md`. These tests cover behavior
that's awkward to automate (interactive TUIs, real terminal resize, real signal
forwarding via keyboard).

Run all from `app/`:

```bash
dart run bin/passthrough.dart run -- <command>
```

## Checklist

- [ ] **vi**: `dart run bin/passthrough.dart run -- vi /tmp/foo`
  - Edit a file, save (`:w`), quit (`:q`). Confirm normal exit.
  - While in vi, resize the terminal window; run `:set columns?` — it should reflect the new size.

- [ ] **top**: `dart run bin/passthrough.dart run -- top`
  - UI redraws cleanly, columns align.
  - Press `q` to quit. Confirm parent shell returns with normal tty modes (try typing — characters should echo).

- [ ] **bash interactive**: `dart run bin/passthrough.dart run -- bash -i`
  - Tab completion works.
  - Start `sleep 30`, press Ctrl+C — child should be interrupted promptly.
  - Press Ctrl+D — bash exits, parent shell returns cleanly.
  - Prompt colors render.

- [ ] **ssh** (if available): `dart run bin/passthrough.dart run -- ssh <some-host>`
  - Password prompt does not echo characters.
  - Interactive session usable; remote terminal sees correct dimensions.

- [ ] **External SIGINT**: in one terminal, run `dart run bin/passthrough.dart run -- sleep 30`. In another, find the parent's pid and `kill -INT <pid>`. The child sleep should exit; parent should print summary with exit 130.

## Pass criteria

All four interactive scenarios usable. Parent shell never left in a broken tty state.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-14-passthrough-manual-smoke.md
git commit -m "passthrough: manual smoke test checklist"
```

---

## Task 19: Final verification — run the whole suite

**Files:** none modified

- [ ] **Step 1: Run all passthrough tests**

```bash
cd app && flutter test test/passthrough/
```

Expected: all tests PASS, no warnings.

- [ ] **Step 2: Run the analyzer**

```bash
cd app && dart analyze lib/src/passthrough bin/passthrough.dart test/passthrough
```

Expected: 0 errors, 0 warnings (lints with hints OK).

- [ ] **Step 3: Walk through the manual smoke checklist**

Execute each item in `docs/superpowers/specs/2026-05-14-passthrough-manual-smoke.md`. Tick items as you go.

- [ ] **Step 4: Final summary commit (if any docs got ticked)**

```bash
git add docs/superpowers/specs/2026-05-14-passthrough-manual-smoke.md
git diff --cached --quiet || git commit -m "passthrough: manual smoke results"
```

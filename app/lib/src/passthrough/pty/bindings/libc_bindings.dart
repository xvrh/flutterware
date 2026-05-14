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

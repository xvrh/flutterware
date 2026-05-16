// ignore_for_file: non_constant_identifier_names, camel_case_types, constant_identifier_names, library_private_types_in_public_api
//
// Rationale: this file mirrors libc one-to-one for readability against `man`
// pages. POSIX names are SCREAMING_CASE for signals and constants; the private
// FFI typedefs (e.g. _SpawnDart) are deliberately scoped to this file to keep
// the public surface small.

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

// ---------- open(2) flags ----------
const int O_RDWR = 0x0002;
// O_NOCTTY differs between platforms.
int get O_NOCTTY => Platform.isMacOS ? 0x20000 : 0x100;

// ---------- posix_spawn attribute flags ----------
// POSIX_SPAWN_SETSID makes the child a new session leader, so that opening the
// PTY slave (without O_NOCTTY) acquires it as the child's controlling terminal.
int get POSIX_SPAWN_SETSID => Platform.isMacOS ? 0x0400 : 0x80;

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

// ioctl is variadic in C. On Apple Silicon (arm64), variadic args go on the
// stack, not in registers — so we MUST mark the trailing arg with VarArgs or
// the kernel reads garbage. Linux x86_64 happens to work either way, but this
// is the portably correct declaration.
typedef _IoctlNative = Int32 Function(
    Int32, IntPtr, VarArgs<(Pointer<WinSize>,)>);
typedef _IoctlDart = int Function(int, int, Pointer<WinSize>);

typedef _IntFromIntNative = Int32 Function(Int32);
typedef _IntFromIntDart = int Function(int);

// open(2): declared with the 2-arg (no O_CREAT) form — the variadic mode
// argument is only consulted when creating a file, which we never do here.
typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);

typedef _PtsnameNative = Pointer<Utf8> Function(Int32);
typedef _PtsnameDart = Pointer<Utf8> Function(int);

// posix_spawnp(pid*, file, file_actions*, attrp*, argv[], envp[])
typedef _SpawnNative = Int32 Function(
    Pointer<Int32>,
    Pointer<Utf8>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>);
typedef _SpawnDart = int Function(Pointer<Int32>, Pointer<Utf8>, Pointer<Void>,
    Pointer<Void>, Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>);

typedef _OpaqueInitNative = Int32 Function(Pointer<Void>);
typedef _OpaqueInitDart = int Function(Pointer<Void>);

typedef _FaAddopenNative = Int32 Function(
    Pointer<Void>, Int32, Pointer<Utf8>, Int32, Uint32);
typedef _FaAddopenDart = int Function(
    Pointer<Void>, int, Pointer<Utf8>, int, int);

typedef _FaAddupNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _FaAddupDart = int Function(Pointer<Void>, int, int);

typedef _FaAddcloseNative = Int32 Function(Pointer<Void>, Int32);
typedef _FaAddcloseDart = int Function(Pointer<Void>, int);

typedef _FaAddchdirNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _FaAddchdirDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _AttrSetflagsNative = Int32 Function(Pointer<Void>, Int16);
typedef _AttrSetflagsDart = int Function(Pointer<Void>, int);

typedef _GetpidNative = Int32 Function();
typedef _GetpidDart = int Function();

// ---------- bindings object ----------

class LibcBindings {
  late final DynamicLibrary _libc;

  LibcBindings() {
    if (Platform.isMacOS) {
      _libc = DynamicLibrary.process();
    } else if (Platform.isLinux) {
      _libc = DynamicLibrary.open('libc.so.6');
    } else {
      throw UnsupportedError(
          'Passthrough PTY only supports macOS and Linux (got ${Platform.operatingSystem})');
    }

    waitpid = _libc.lookupFunction<_WaitpidNative, _WaitpidDart>('waitpid');
    kill = _libc.lookupFunction<_KillNative, _KillDart>('kill');
    read = _libc.lookupFunction<_ReadNative, _ReadDart>('read');
    write = _libc.lookupFunction<_WriteNative, _WriteDart>('write');
    close = _libc.lookupFunction<_CloseNative, _CloseDart>('close');
    openFile = _libc.lookupFunction<_OpenNative, _OpenDart>('open');
    ioctl = _libc.lookupFunction<_IoctlNative, _IoctlDart>('ioctl');

    posixOpenpt = _libc
        .lookupFunction<_IntFromIntNative, _IntFromIntDart>('posix_openpt');
    grantpt =
        _libc.lookupFunction<_IntFromIntNative, _IntFromIntDart>('grantpt');
    unlockpt =
        _libc.lookupFunction<_IntFromIntNative, _IntFromIntDart>('unlockpt');
    ptsname = _libc.lookupFunction<_PtsnameNative, _PtsnameDart>('ptsname');

    posixSpawnp =
        _libc.lookupFunction<_SpawnNative, _SpawnDart>('posix_spawnp');
    faInit = _libc.lookupFunction<_OpaqueInitNative, _OpaqueInitDart>(
        'posix_spawn_file_actions_init');
    faDestroy = _libc.lookupFunction<_OpaqueInitNative, _OpaqueInitDart>(
        'posix_spawn_file_actions_destroy');
    faAddopen = _libc.lookupFunction<_FaAddopenNative, _FaAddopenDart>(
        'posix_spawn_file_actions_addopen');
    faAdddup2 = _libc.lookupFunction<_FaAddupNative, _FaAddupDart>(
        'posix_spawn_file_actions_adddup2');
    faAddclose = _libc.lookupFunction<_FaAddcloseNative, _FaAddcloseDart>(
        'posix_spawn_file_actions_addclose');
    faAddchdir = _libc.lookupFunction<_FaAddchdirNative, _FaAddchdirDart>(
        'posix_spawn_file_actions_addchdir_np');
    attrInit = _libc.lookupFunction<_OpaqueInitNative, _OpaqueInitDart>(
        'posix_spawnattr_init');
    attrDestroy = _libc.lookupFunction<_OpaqueInitNative, _OpaqueInitDart>(
        'posix_spawnattr_destroy');
    attrSetflags = _libc.lookupFunction<_AttrSetflagsNative, _AttrSetflagsDart>(
        'posix_spawnattr_setflags');
    getpid = _libc.lookupFunction<_GetpidNative, _GetpidDart>('getpid');
  }

  late final _WaitpidDart waitpid;
  late final _KillDart kill;
  late final _ReadDart read;
  late final _WriteDart write;
  late final _CloseDart close;
  late final _OpenDart openFile;
  late final _IoctlDart ioctl;

  late final _IntFromIntDart posixOpenpt;
  late final _IntFromIntDart grantpt;
  late final _IntFromIntDart unlockpt;
  late final _PtsnameDart ptsname;

  late final _SpawnDart posixSpawnp;
  late final _OpaqueInitDart faInit;
  late final _OpaqueInitDart faDestroy;
  late final _FaAddopenDart faAddopen;
  late final _FaAddupDart faAdddup2;
  late final _FaAddcloseDart faAddclose;
  late final _FaAddchdirDart faAddchdir;
  late final _OpaqueInitDart attrInit;
  late final _OpaqueInitDart attrDestroy;
  late final _AttrSetflagsDart attrSetflags;
  late final _GetpidDart getpid;
}

# Passthrough PTY — Proof-of-Concept Design

**Date:** 2026-05-14
**Scope:** Phase 1 only — prove that a Dart CLI can run a subprocess under a real pseudo-terminal, tee its output, forward stdin and signals, and propagate the exit code. Transport to the Flutterware GUI and persistence (database-backed run history) are explicitly out of scope.

## Goal

Build a `passthrough` CLI command that spawns a child process such that:

- The child's stdout/stderr appear to it as a real TTY (`isatty()` returns true, colors render, spinners work).
- The parent reads every byte the child writes — forwarding it live to the parent's own stdout *and* buffering it for later use.
- The user's keyboard input reaches the child unbuffered (raw mode), so interactive tools like `vi`, `top`, and shells work.
- Terminal resize (SIGWINCH) and interrupt (SIGINT, SIGTERM) are forwarded to the child.
- The child's exit code is propagated to the parent's exit code.

The deliverable is a working command plus an automated test suite and a small manual smoke-test checklist that together constitute a "solid proof" the PTY mechanics are correct.

## Non-goals (Phase 1)

- Windows / ConPTY support.
- Streaming captured output to the Flutterware GUI or any external consumer.
- Persisting run history to a database.
- Splitting stdout vs stderr. PTYs combine them by design.
- Memory-bounded capture. The PoC buffers all output in memory; a follow-up phase will replace this with a streaming consumer when GUI integration lands.
- Per-spawn environment-variable override. The child inherits the parent's environment.
- Concurrent passthrough invocations as a tested feature. The library design supports them (one helper isolate per spawn) but they aren't part of the proof.

## Approach decision

Three approaches were considered for obtaining a PTY in Dart:

1. **Existing pub.dev packages** — `pty` (0.1.1, 2020, low adoption, missing `resize` and signal APIs), `dart_pty` (abandoned, half-baked), `flutter_pty` (well-designed but requires the Flutter engine; won't load from `dart run`).
2. **Shell out to `script(1)`** — disqualified by the BSD/util-linux flag split. macOS BSD `script` has no `-c` or `-e`, making clean stdin forwarding and exit-code propagation painful.
3. **Direct Dart FFI to `forkpty(3)`** — ~500 lines, no runtime dependency beyond libc/libutil, full control over every capability on the requirements list.

**Decision: approach 3 (direct FFI).** The pub.dev options are a trap — the only well-maintained one (`flutter_pty`) is Flutter-only; the others are stale and missing capabilities we need. `script(1)` is non-portable. FFI gives us everything we need with code we own.

For phase 1 we stay on plain `ffigen` + `DynamicLibrary` — no custom C, no native assets, no build hooks. `forkpty` lives in `libSystem` on macOS and `libutil.so.1` on Linux; both are reachable via `DynamicLibrary`. Native assets become worth introducing only if we later add a C shim (not required for the proof).

## File layout

```
app/
├─ bin/
│  └─ passthrough.dart                    # PoC sibling entry — CommandRunner with one command
└─ lib/src/passthrough/
   ├─ passthrough_command.dart            # args parsing, terminal setup, top-level glue
   ├─ pty/
   │  ├─ pty.dart                         # public surface: PtyProcess, spawnPty()
   │  ├─ bindings/
   │  │  ├─ libc_bindings.dart            # ffigen output (forkpty, ioctl, waitpid, ...)
   │  │  └─ ffigen.yaml                   # ffigen config, committed for reproducibility
   │  └─ pty_impl.dart                    # high-level wrapper over the bindings
   └─ tee_sink.dart                       # multiplexes PTY output → stdout + BytesBuilder
```

The entry point is a sibling bin (`app/bin/passthrough.dart`), not a subcommand of the existing `flutterware.dart` runner. This keeps the PoC invokable without the GUI bootstrap logic in `_AppCommand`. Once the proof passes, folding the command into the main runner is a small follow-up.

## Module boundaries

- **`pty/`** knows nothing about CLI args, raw mode, or capture buffers. It exposes a `PtyProcess` you can read, write, resize, and signal.
- **`passthrough_command.dart`** owns all terminal-side policy: raw mode, SIGWINCH wiring, tee-to-stdout, capture buffer, exit-code translation.
- **`tee_sink.dart`** is a small utility that fans one byte stream into stdout and a `BytesBuilder`.

### Public surface of `pty.dart`

```dart
class PtyProcess {
  Stream<Uint8List> get output;          // combined stdout+stderr from PTY master
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
});
```

`workingDirectory` is honored by calling `chdir` in the child between fork and exec. If `cols` or `rows` is `null`, `spawnPty` reads `stdout.terminalColumns` and `stdout.terminalLines` at call time and uses those. Custom environment is not supported in phase 1.

## PTY mechanics

### Symbols bound via ffigen

| Symbol | Header | Library | Purpose |
|---|---|---|---|
| `forkpty` | `<util.h>` (mac) / `<pty.h>` (linux) | libSystem / libutil.so.1 | Allocate PTY pair, fork, attach slave to child stdio |
| `execvp` | `<unistd.h>` | libc | Replace child process image |
| `_exit` | `<unistd.h>` | libc | Bail out of child if `execvp` or `chdir` fails |
| `chdir` | `<unistd.h>` | libc | Set child working directory (post-fork, pre-exec) |
| `waitpid` | `<sys/wait.h>` | libc | Reap child, retrieve packed exit status |
| `kill` | `<signal.h>` | libc | Forward SIGINT/SIGTERM to child |
| `read`, `write`, `close` | `<unistd.h>` | libc | I/O on master fd |
| `ioctl` | `<sys/ioctl.h>` | libc | TIOCSWINSZ to set PTY window size |
| `tcgetattr`, `tcsetattr` | `<termios.h>` | libc | Snapshot parent termios into the PTY |

### Library loading

```dart
final DynamicLibrary _libc = Platform.isMacOS
    ? DynamicLibrary.process()              // libSystem already in process
    : DynamicLibrary.open('libc.so.6');     // Linux glibc (musl also works)

final DynamicLibrary _libutil = Platform.isMacOS
    ? DynamicLibrary.process()              // forkpty lives in libSystem
    : DynamicLibrary.open('libutil.so.1');  // Linux: separate .so
```

### Spawn sequence (`pty_impl.dart`)

1. Build a NULL-terminated `Pointer<Pointer<Char>>` argv (allocated via `calloc`).
2. Snapshot parent termios via `tcgetattr(STDIN_FILENO=0, …)` so the child PTY starts with the user's local modes.
3. Build a `winsize` struct from `stdout.terminalColumns` / `terminalLines` (or caller-provided `cols`/`rows`).
4. Call `forkpty(&master, NULL, &termios, &winsize)`:
   - Returns `-1` → throw `PtyException("forkpty: …")`.
   - Returns `0` → **child branch.** If `workingDirectory != null`, call `chdir(workingDirectory)`; on failure call `_exit(127)`. Then call `execvp(executable, argv)`; if it returns, call `_exit(127)`.
   - Returns `>0` → parent branch, with `master` (master fd) and `pid`.
5. Free argv.
6. Spawn the reader/waiter isolate (see below).
7. Return a `PtyProcess` wrapping `master`, `pid`, and the isolate's `ReceivePort`.

### Fork+exec safety

After `fork()`, only async-signal-safe libc calls are legal in the child until `exec`. We are disciplined about this: the only calls in the child branch are `chdir` (async-signal-safe), `execvp` (async-signal-safe), and `_exit` (async-signal-safe). No Dart callbacks, no Dart allocations. `forkpty` itself does its internal setup (`setsid`, `TIOCSCTTY`, `dup2`, `close`) async-signal-safely.

This is the same pattern used by `node-pty`, Python's `pty` module, and the existing Dart `pty` package. Standard and correct.

### Window resize

```dart
void resize(int cols, int rows) {
  final ws = calloc<winsize>()
    ..ref.ws_col = cols
    ..ref.ws_row = rows;
  _ioctl(master, TIOCSWINSZ, ws.cast());
  calloc.free(ws);
}
```

`TIOCSWINSZ` is `0x80087467` on macOS and `0x5414` on Linux. `ffigen` picks up the platform-correct value from headers automatically.

### Exit-code decoding

`waitpid` returns a packed status. The `W*` macros are CPP, so `ffigen` won't generate them — we hand-write:

```dart
bool _wifexited(int s)   => (s & 0x7f) == 0;
int  _wexitstatus(int s) => (s >> 8) & 0xff;
bool _wifsignaled(int s) => ((s & 0x7f) + 1) >> 1 > 0;
int  _wtermsig(int s)    => s & 0x7f;
```

Translation rules:
- `WIFEXITED` → return `WEXITSTATUS(status)`.
- `WIFSIGNALED` → return `128 + WTERMSIG(status)` (standard shell convention).
- Otherwise → return `1`.

## Concurrency model

```
                       ┌─────────────────────────────────────────┐
                       │  Main isolate                            │
                       │  ─ stdin (raw mode) ──► write(master_fd) │
                       │  ─ SIGWINCH       ──► ioctl(TIOCSWINSZ)  │
                       │  ─ SIGINT / SIGTERM ──► kill(pid, sig)   │
                       │                                          │
                       │  receives bytes ◄─┐    receives exit ◄─┐ │
                       └───────────────────┼─────────────────────┼─┘
                                           │ SendPort            │
                       ┌───────────────────┴─────────────────────┴─┐
                       │  PtyReaderIsolate                          │
                       │   loop:                                    │
                       │     n = read(master, buf, 8192)            │
                       │     if n > 0: send(bytesView)              │
                       │     if n <= 0: break                       │
                       │   waitpid(pid, &status, 0)                 │
                       │   send(_ExitEvent(decoded_code))           │
                       └────────────────────────────────────────────┘
```

- **One helper isolate per spawn**, doing the blocking `read` loop and then the final `waitpid`. They're sequential by nature (master closes around child exit), so one isolate is sufficient.
- **Writes happen on the main isolate.** Stdin chunks are small and infrequent. `write(master_fd, …)`, `ioctl(TIOCSWINSZ)`, and `kill` are single fast syscalls — no need to push them off the main isolate.
- **No non-blocking + polling** scheme. Dart's public API doesn't cleanly support registering an arbitrary fd with the event loop; an isolate with blocking `read` is correct and simpler.
- **Backpressure** is not addressed in phase 1. PTY master has a ~4KB kernel buffer; if main isolate drains slowly, `SendPort.send` queues messages. Adequate for TUI output. A credit-based throttle can be added later if streaming gigabytes.
- **Crash cleanup** is automatic: if the parent dies, the master fd closes, the kernel sends SIGHUP to the child's session, and the child exits.

## CLI surface

### Invocation

```
dart run bin/passthrough.dart -- <executable> [args...]
dart run bin/passthrough.dart --cwd /some/path -- <executable> [args...]
```

`--` separates passthrough flags from the child invocation. Everything after `--` is passed verbatim to `spawnPty` — no shell, no interpretation.

### Flags

- `--cwd <dir>` — sets `workingDirectory` (→ `chdir` in child).
- `--print-capture-summary` (default on) — after the child exits, write to **parent stderr** something like `[passthrough] captured 14823 bytes, exit 0`. Makes the capture proof visible without polluting the captured stream itself.
- `-h` / `--help` — provided by `CommandRunner`.

Everything else (writing capture to a file, JSON metadata output, machine-readable summaries) is deferred until GUI integration.

## Lifecycle of a passthrough run

The body of `passthrough_command.dart`'s `run()`:

1. Parse args. Extract the child invocation after `--`.
2. Validate parent stdin/stdout are TTYs by checking `stdin.hasTerminal` and `stdout.hasTerminal`. If either is false, print a one-line warning to parent stderr (`[passthrough] warning: parent stdin/stdout is not a TTY, interactive features may not work`) but continue — passthrough still functions for piped input/output, the proof is just weaker.
3. Snapshot parent `stdin.lineMode` and `stdin.echoMode`.
4. `try`:
   1. Set stdin to raw mode (`lineMode = false`, `echoMode = false`).
   2. `spawnPty(exe, args, workingDirectory: cwd, cols, rows)`.
   3. Wire `ProcessSignal.sigwinch.watch()` → `pty.resize(currentCols, currentRows)`.
   4. Wire `ProcessSignal.sigint.watch()` and `ProcessSignal.sigterm.watch()` → `pty.sendSignal(SIGINT/SIGTERM)`. The parent does **not** exit on Ctrl+C; the child receives the signal and decides. Note: in raw mode, a keyboard Ctrl+C is delivered as a raw `0x03` byte through stdin to the PTY, where the slave's tty layer turns it into SIGINT for the child. The Dart signal handlers cover the out-of-band case (e.g. `kill -INT <parent-pid>` from another terminal). Both paths reach the child.
   5. `stdin.listen(bytes => pty.writeInput(bytes))`.
   6. `pty.output.listen(bytes => { stdout.add(bytes); capture.add(bytes); })`.
   7. `exitCode = await pty.exitCode`.
5. `finally`:
   - Restore parent stdin's line/echo modes.
   - Cancel signal and stdin subscriptions.
6. If `--print-capture-summary`, write summary to stderr.
7. Return `exitCode` (CommandRunner propagates it to process exit code).

### Raw-mode discipline

Putting stdin in raw mode means keystrokes flow through unbuffered and parent-side echo is off — the child's PTY tty layer is responsible for echoing. The `finally` block is essential: if anything throws, the user's shell must not be left with line/echo off. We also handle SIGTERM gracefully (via the signal subscription) so a `kill -TERM` to the parent triggers the same restore. SIGKILL is uncatchable, but the OS cleans up the child via SIGHUP through the closing controlling terminal.

## Error handling

| Condition | Behavior |
|---|---|
| `forkpty` returns `-1` | Throw `PtyException` with `strerror(errno)`. Parent terminal mode restored by `finally`. |
| `chdir` fails in child | Child calls `_exit(127)`; parent observes via `waitpid` and returns 127. |
| `execvp` returns in child | Same — `_exit(127)`. |
| `read` on master returns 0 | Reader isolate breaks loop, proceeds to `waitpid`. |
| `read` returns -1 with errno != EINTR | Reader isolate breaks loop, proceeds to `waitpid`. Error logged on parent stderr. |
| Parent crash | Master fd closes, kernel SIGHUPs child, child exits naturally. |

## Verification plan

The proof has three components: automated tests, manual smoke tests, and a small sanity benchmark.

### Automated tests (`app/test/passthrough/`)

Each test spawns a real child through the PTY library and asserts on captured bytes and exit code. Run with `dart test`.

| # | Spawn | Assert | Proves |
|---|---|---|---|
| 1 | `bash -c "[ -t 1 ] && echo IS_TTY || echo NOT_TTY"` | captured contains `IS_TTY` | Child sees a real TTY |
| 2 | `bash -c "printf '\\e[31mred\\e[0m\\n'"` | captured contains `\x1b[31m` | ANSI not stripped |
| 3 | `bash -c "tput cols"` after `resize(123, 40)` | captured contains `123` | `TIOCSWINSZ` propagates |
| 4 | `bash -c "read x; echo got=\$x"` + `writeInput("hello\n")` | captured contains `got=hello` | Stdin path works |
| 5 | `bash -c "exit 42"` | exitCode == 42 | Exit-code propagation |
| 6 | `bash -c "kill -INT \$\$; sleep 1"` | exitCode == 130 | Signal-death translation |
| 7 | `pwd` with `workingDirectory: '/tmp'` | captured starts with `/tmp` | `chdir` runs before `execvp` |
| 8 | `bash -c "for i in $(seq 1 1000); do echo line\$i; done"` | all 1000 lines, in order | Reader keeps up, no loss |
| 9 | `nonexistent_binary_xyz` | exitCode == 127 | `execvp` failure path |
| 10 | After a throwing spawn | parent stdin restored to lineMode/echoMode true | `try/finally` discipline holds |

The tee is verified implicitly: anything asserted on `capture` is also bytes that were written to stdout. We don't assert on real stdout (would conflict with `dart test`'s own stdout); snapshotting the `BytesBuilder` is sufficient.

### Manual smoke tests

These can't easily be automated but matter for "solid". Documented in a companion `manual-smoke.md` alongside this spec.

- `vi /tmp/foo` — edit, save, quit cleanly. Resize the terminal mid-edit; confirm `:set columns?` reflects new size.
- `top` — UI redraws, columns right, `q` quits, parent shell returns with normal tty modes.
- `bash` interactively — tab completion works, Ctrl+C interrupts a running `sleep`, Ctrl+D exits, prompt colors render.
- `ssh somehost` — no-echo password prompt works, interactive session usable.

Passing all four is the bar for declaring the proof a success.

### Sanity benchmark

`bash -c "yes | head -c 10000000"` (10 MB of `y\n`) through passthrough vs through plain `Process.start`. We don't expect PTY to be faster, but it shouldn't be >10× slower either. Sanity check, not a gate.

## Future phases (informational, not part of this spec)

- **Phase 2:** Stream captured output to a consumer (likely `RemoteLogClient`) so the Flutterware GUI can render live output. Replace the unbounded `BytesBuilder` with a streaming sink.
- **Phase 3:** Persist run history (command, args, cwd, env, start/end timestamps, exit code, output) to a local database so past runs are browsable in the GUI.
- **Phase 4:** Fold the passthrough command into the main `flutterware.dart` `CommandRunner`. Retire the sibling bin entry.
- **Phase 5:** Windows support via ConPTY. Out of scope for the Unix proof.

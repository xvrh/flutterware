# Sub-project 0 — SDK Wrap Point Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap the `flutter`/`dart` scripts an IDE invokes so every run is intercepted, classified, observed, and can have a `--dart-define` injected — degrading to plain passthrough on any failure.

**Architecture:** A per-project SDK *mirror facade* (`<project>/flutterware/sdk/`) whose `bin/flutter`/`bin/dart` are bash shims and whose other entries symlink the pristine SDK. The shims do a cheap pure-bash fast path (marker walk-up, classify, audit-log); *interesting* runs hand off to a compiled Dart `flutterware wrap run` command that rewrites argv to inject a `--dart-define`, runs the real binary under a PTY (interactive) or pipe (`--machine`/IDE) transport, and captures output to a local sink.

**Tech Stack:** Dart (the `flutterware_app` package), `package:args` CommandRunner, bash, the phase-1 `passthrough` PTY (`app/lib/src/passthrough/`).

**Spec:** `docs/superpowers/specs/2026-05-15-subproject-0-sdk-wrap-point-design.md`
**Finding:** `docs/superpowers/specs/2026-05-15-subproject-0-ide-launch-finding.md`

---

## File Structure

Created under the `flutterware_app` package (`app/`):

- `app/lib/src/wrap/dart_define.dart` — argv rewrite to inject a `--dart-define`.
- `app/lib/src/wrap/project_resolution.dart` — project root + worktree identity.
- `app/lib/src/wrap/session_sink.dart` — local observation sink.
- `app/lib/src/wrap/transport.dart` — PTY vs pipe passthrough.
- `app/lib/src/wrap/run_command.dart` — the `run` command (heavy-path orchestration).
- `app/lib/src/wrap/shim_template.dart` — the bash shim as a string + renderer.
- `app/lib/src/wrap/installer.dart` — builds the mirror facade.
- `app/lib/src/wrap/install_command.dart` — the `install` command.
- `app/bin/wrap.dart` — standalone CLI entry (`CommandRunner` with `run` + `install`).
- `app/test/wrap/*_test.dart` — one test file per unit.
- `examples/example/lib/main.dart` — modified: the probe widget.

Modified:

- `app/lib/src/passthrough/passthrough_command.dart` — `runUnderPty` gains an optional `captureSink`.

---

## Task 0: Setup

**Files:** none.

- [ ] **Step 1: Resolve workspace dependencies**

Run: `dart tool/pub_get_all_projects.dart`
Expected: completes without error (the pre-commit format hook needs resolved deps).

- [ ] **Step 2: Confirm the wrap test directory**

Run: `mkdir -p app/test/wrap && ls app/test/wrap`
Expected: empty directory exists.

---

## Task 1: dart-define injection

**Files:**
- Create: `app/lib/src/wrap/dart_define.dart`
- Test: `app/test/wrap/dart_define_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutterware_app/src/wrap/dart_define.dart';
import 'package:test/test.dart';

void main() {
  test('inserts the define immediately after the subcommand token', () {
    final out = injectDartDefine(
      ['--no-color', 'run', '--machine', 'lib/main.dart'],
      key: 'FW_MARKER',
      value: 'tok123',
    );
    expect(out, [
      '--no-color',
      'run',
      '--dart-define=FW_MARKER=tok123',
      '--machine',
      'lib/main.dart',
    ]);
  });

  test('appends the define when there is no non-flag token', () {
    final out = injectDartDefine(['--version'], key: 'FW_MARKER', value: 't');
    expect(out, ['--version', '--dart-define=FW_MARKER=t']);
  });

  test('handles a bare subcommand with no flags', () {
    final out = injectDartDefine(['test'], key: 'K', value: 'v');
    expect(out, ['test', '--dart-define=K=v']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/wrap/dart_define_test.dart`
Expected: FAIL — `dart_define.dart` / `injectDartDefine` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
/// Returns a copy of [args] with `--dart-define=<key>=<value>` inserted
/// immediately after the subcommand token (the first non-flag argument,
/// e.g. `run` in `flutter run`). If there is no non-flag token, the define
/// is appended at the end.
List<String> injectDartDefine(
  List<String> args, {
  required String key,
  required String value,
}) {
  final define = '--dart-define=$key=$value';
  final idx = args.indexWhere((a) => !a.startsWith('-'));
  if (idx == -1) return [...args, define];
  return [...args.sublist(0, idx + 1), define, ...args.sublist(idx + 1)];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/wrap/dart_define_test.dart`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/wrap/dart_define.dart app/test/wrap/dart_define_test.dart
git commit -m "Add dart-define argv injection for the SDK wrap point"
```

---

## Task 2: Project & worktree resolution

**Files:**
- Create: `app/lib/src/wrap/project_resolution.dart`
- Test: `app/test/wrap/project_resolution_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';
import 'package:flutterware_app/src/wrap/project_resolution.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wrap_proj'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('findProjectRoot walks up to the flutter_version marker', () {
    File(p.join(tmp.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    final nested = Directory(p.join(tmp.path, 'a', 'b'))
      ..createSync(recursive: true);
    final root = findProjectRoot(nested);
    expect(root?.resolveSymbolicLinksSync(),
        equals(tmp.resolveSymbolicLinksSync()));
  });

  test('findProjectRoot returns null when there is no marker', () {
    final nested = Directory(p.join(tmp.path, 'a'))..createSync();
    expect(findProjectRoot(nested), isNull);
  });

  test('resolveWorktreeName reads the gitdir pointer from a .git file', () {
    File(p.join(tmp.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    File(p.join(tmp.path, '.git')).writeAsStringSync(
        'gitdir: /repo/.git/worktrees/feature-x\n');
    expect(resolveWorktreeName(tmp), equals('feature-x'));
  });

  test('resolveWorktreeName falls back to the dir name for a main checkout',
      () {
    File(p.join(tmp.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    Directory(p.join(tmp.path, '.git')).createSync();
    expect(resolveWorktreeName(tmp), equals(p.basename(tmp.path)));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/wrap/project_resolution_test.dart`
Expected: FAIL — `project_resolution.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'dart:io';
import 'package:path/path.dart' as p;

/// A resolved flutterware project and the worktree the invocation is in.
class ProjectContext {
  final Directory projectRoot;
  final String worktreeName;
  ProjectContext(this.projectRoot, this.worktreeName);
}

/// Walks up from [start] looking for a `flutter_version` marker file.
/// Returns the directory that contains it, or null if none is found.
Directory? findProjectRoot(Directory start) {
  var dir = start.absolute;
  while (true) {
    if (File(p.join(dir.path, 'flutter_version')).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Resolves the worktree name for [projectRoot]. A linked worktree has a
/// `.git` *file* with a `gitdir:` pointer; the last path segment of that
/// pointer is the worktree name. A main checkout has a `.git` *directory*.
String resolveWorktreeName(Directory projectRoot) {
  final gitPath = p.join(projectRoot.path, '.git');
  if (FileSystemEntity.isDirectorySync(gitPath)) {
    return p.basename(projectRoot.path);
  }
  final gitFile = File(gitPath);
  if (gitFile.existsSync()) {
    final content = gitFile.readAsStringSync().trim();
    const prefix = 'gitdir:';
    if (content.startsWith(prefix)) {
      return p.basename(content.substring(prefix.length).trim());
    }
  }
  return p.basename(projectRoot.path);
}

/// Resolves the [ProjectContext] for an invocation made from [start],
/// or null if [start] is not inside a flutterware project.
ProjectContext? resolveProject(Directory start) {
  final root = findProjectRoot(start);
  if (root == null) return null;
  return ProjectContext(root, resolveWorktreeName(root));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/wrap/project_resolution_test.dart`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/wrap/project_resolution.dart app/test/wrap/project_resolution_test.dart
git commit -m "Add project root and worktree resolution for the SDK wrap point"
```

---

## Task 3: Session sink

**Files:**
- Create: `app/lib/src/wrap/session_sink.dart`
- Test: `app/test/wrap/session_sink_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutterware_app/src/wrap/session_sink.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wrap_sink'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('newSessionId yields a non-empty filesystem-safe id', () {
    final id = newSessionId();
    expect(id, isNotEmpty);
    expect(id, isNot(contains('/')));
    expect(id, isNot(contains(':')));
  });

  test('SessionSink creates a per-session dir and writes output + meta',
      () async {
    final sink = SessionSink(tmp, 'sess-1');
    final out = sink.openOutput();
    out.add('hello'.codeUnits);
    await out.flush();
    await out.close();
    sink.writeMeta({'exitCode': 0, 'worktree': 'main'});

    final dir = p.join(tmp.path, 'sessions', 'sess-1');
    expect(File(p.join(dir, 'output.log')).readAsStringSync(), 'hello');
    final meta = jsonDecode(File(p.join(dir, 'meta.json')).readAsStringSync());
    expect(meta['exitCode'], 0);
    expect(meta['worktree'], 'main');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/wrap/session_sink_test.dart`
Expected: FAIL — `session_sink.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// A filesystem-safe, reasonably unique id for one intercepted session.
String newSessionId() {
  final ts = DateTime.now()
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '-');
  return '$ts-$pid';
}

/// The local, provisional observation sink for one interesting run.
/// Lives at `<flutterwareDir>/sessions/<sessionId>/`. Sub-project 1
/// replaces this with the daemon + SQLite DB.
class SessionSink {
  final Directory dir;

  SessionSink(Directory flutterwareDir, String sessionId)
      : dir = Directory(
            p.join(flutterwareDir.path, 'sessions', sessionId)) {
    dir.createSync(recursive: true);
  }

  /// Opens the captured-output file for streaming writes.
  IOSink openOutput() => File(p.join(dir.path, 'output.log')).openWrite();

  /// Writes the session metadata as pretty-printed JSON.
  void writeMeta(Map<String, Object?> meta) {
    File(p.join(dir.path, 'meta.json'))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(meta));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/wrap/session_sink_test.dart`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/wrap/session_sink.dart app/test/wrap/session_sink_test.dart
git commit -m "Add local session sink for the SDK wrap point"
```

---

## Task 4: Transport (PTY + pipe passthrough)

**Files:**
- Modify: `app/lib/src/passthrough/passthrough_command.dart` (`runUnderPty` gains `captureSink`)
- Create: `app/lib/src/wrap/transport.dart`
- Test: `app/test/wrap/transport_test.dart`

- [ ] **Step 1: Add a capture sink to `runUnderPty`**

In `app/lib/src/passthrough/passthrough_command.dart`, add a parameter to
`runUnderPty` and fan PTY output into it. Change the signature:

```dart
Future<int> runUnderPty({
  required String executable,
  required List<String> arguments,
  String? workingDirectory,
  bool printSummary = true,
  IOSink? captureSink,
}) async {
```

and change the `TeeSink` construction from `TeeSink(onBytes: stdout.add)` to:

```dart
    tee = TeeSink(onBytes: (chunk) {
      stdout.add(chunk);
      captureSink?.add(chunk);
    });
```

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:io';
import 'package:flutterware_app/src/wrap/transport.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wrap_tx'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('runIntercepted captures child output and returns its exit code',
      () async {
    final file = File(p.join(tmp.path, 'cap.log'));
    final sink = file.openWrite();
    final code = await runIntercepted(
      executable: '/bin/echo',
      arguments: const ['hello-wrap-transport'],
      captureSink: sink,
    );
    await sink.flush();
    await sink.close();
    expect(code, 0);
    expect(file.readAsStringSync(), contains('hello-wrap-transport'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('runIntercepted propagates a non-zero exit code', () async {
    final sink = File(p.join(tmp.path, 'c2.log')).openWrite();
    final code = await runIntercepted(
      executable: '/bin/bash',
      arguments: const ['-c', 'exit 7'],
      captureSink: sink,
    );
    await sink.flush();
    await sink.close();
    expect(code, 7);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd app && flutter test test/wrap/transport_test.dart`
Expected: FAIL — `transport.dart` does not exist.

- [ ] **Step 4: Write minimal implementation**

```dart
import 'dart:async';
import 'dart:io';

import '../passthrough/passthrough_command.dart';

/// Runs [executable] with [arguments], streaming I/O to the parent and
/// teeing all output into [captureSink].
///
/// Uses a PTY when the parent stdin is a terminal (an interactive CLI run),
/// and plain pipes otherwise (an IDE / `--machine` run, whose stdin/stdout
/// carry the daemon JSON-RPC protocol). Neither mode parses the stream.
Future<int> runIntercepted({
  required String executable,
  required List<String> arguments,
  required IOSink captureSink,
  String? workingDirectory,
}) async {
  if (stdin.hasTerminal) {
    return runUnderPty(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      printSummary: false,
      captureSink: captureSink,
    );
  }
  return _runPiped(
    executable: executable,
    arguments: arguments,
    workingDirectory: workingDirectory,
    captureSink: captureSink,
  );
}

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

  final stdinSub = stdin.listen(
    proc.stdin.add,
    onDone: () => proc.stdin.close().catchError((_) {}),
    onError: (_) {},
  );

  final outDone = Completer<void>();
  final errDone = Completer<void>();
  proc.stdout.listen(
    (chunk) {
      stdout.add(chunk);
      captureSink.add(chunk);
    },
    onDone: outDone.complete,
  );
  proc.stderr.listen(
    (chunk) {
      stderr.add(chunk);
      captureSink.add(chunk);
    },
    onDone: errDone.complete,
  );

  final code = await proc.exitCode;
  await outDone.future;
  await errDone.future;
  await stdinSub.cancel();
  return code;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/wrap/transport_test.dart test/passthrough/passthrough_command_test.dart`
Expected: PASS — transport tests pass and the existing passthrough tests still pass (the `captureSink` change is backward compatible).

- [ ] **Step 6: Commit**

```bash
git add app/lib/src/wrap/transport.dart app/lib/src/passthrough/passthrough_command.dart app/test/wrap/transport_test.dart
git commit -m "Add PTY/pipe transport for intercepted runs"
```

---

## Task 5: The `run` command + CLI entry

**Files:**
- Create: `app/lib/src/wrap/run_command.dart`
- Create: `app/bin/wrap.dart`
- Test: `app/test/wrap/run_command_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Locate the `dart` executable (see passthrough_command_test for why).
String _resolveDart() {
  if (Platform.resolvedExecutable.endsWith('/dart')) {
    return Platform.resolvedExecutable;
  }
  final r = Process.runSync('/usr/bin/which', ['dart']);
  if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
    return (r.stdout as String).trim();
  }
  throw StateError('Could not locate dart');
}

void main() {
  final dart = _resolveDart();
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('wrap_run');
    File(p.join(project.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    Directory(p.join(project.path, '.git')).createSync();
  });
  tearDown(() => project.deleteSync(recursive: true));

  test('interesting run is captured into a session dir with meta', () async {
    final result = await Process.run(
      dart,
      [
        'run', 'bin/wrap.dart', 'run',
        '--real', '/bin/echo', '--kind', 'flutter',
        '--', 'run', 'captured-payload',
      ],
      workingDirectory: project.path,
    );
    expect(result.exitCode, 0);
    final sessions = Directory(p.join(project.path, '.flutterware', 'sessions'));
    expect(sessions.existsSync(), isTrue);
    final dirs = sessions.listSync().whereType<Directory>().toList();
    expect(dirs, hasLength(1));
    final out = File(p.join(dirs.single.path, 'output.log')).readAsStringSync();
    expect(out, contains('captured-payload'));
    expect(out, contains('--dart-define=FW_MARKER='));
    expect(File(p.join(dirs.single.path, 'meta.json')).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('degrades to a plain run when not inside a flutterware project',
      () async {
    final outside = Directory.systemTemp.createTempSync('wrap_outside');
    addTearDown(() => outside.deleteSync(recursive: true));
    final result = await Process.run(
      dart,
      [
        'run', 'bin/wrap.dart', 'run',
        '--real', '/bin/echo', '--kind', 'flutter',
        '--', 'run', 'still-runs',
      ],
      workingDirectory: outside.path,
    );
    expect(result.exitCode, 0);
    expect(result.stdout.toString(), contains('still-runs'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/wrap/run_command_test.dart`
Expected: FAIL — `bin/wrap.dart` does not exist.

- [ ] **Step 3: Write the `run` command**

Create `app/lib/src/wrap/run_command.dart`:

```dart
import 'dart:io';

import 'package:args/command_runner.dart';

import 'dart_define.dart';
import 'project_resolution.dart';
import 'session_sink.dart';
import 'transport.dart';

/// Heavy-path command for an *interesting* intercepted run.
///
/// Invoked by the generated bash shim as:
///   wrap run --real <binary> --kind <flutter|dart> -- <original args...>
///
/// Rewrites argv to inject `--dart-define=FW_MARKER=<token>`, runs the real
/// binary under the transport, and captures output to a local session sink.
/// Any failure degrades to a plain run of the real binary.
class RunCommand extends Command<int> {
  @override
  final name = 'run';
  @override
  final description = 'Run an intercepted flutter/dart invocation.';

  RunCommand() {
    argParser
      ..addOption('real', help: 'Absolute path to the real binary.')
      ..addOption('kind', help: 'flutter or dart.');
  }

  @override
  Future<int> run() async {
    final real = argResults!['real'] as String?;
    final original = argResults!.rest;
    if (real == null || real.isEmpty) {
      stderr.writeln('[wrap] missing --real');
      return 64;
    }
    try {
      final ctx = resolveProject(Directory.current);
      if (ctx == null) return _degrade(real, original);

      final token = newSessionId();
      final injected =
          injectDartDefine(original, key: 'FW_MARKER', value: token);

      final flutterwareDir =
          Directory('${ctx.projectRoot.path}/.flutterware');
      final sink = SessionSink(flutterwareDir, token);
      final out = sink.openOutput();

      final code = await runIntercepted(
        executable: real,
        arguments: injected,
        captureSink: out,
      );

      await out.flush();
      await out.close();
      sink.writeMeta({
        'sessionId': token,
        'worktree': ctx.worktreeName,
        'kind': argResults!['kind'],
        'argvOriginal': original,
        'argvInjected': injected,
        'marker': token,
        'exitCode': code,
      });
      return code;
    } catch (e) {
      stderr.writeln('[wrap] degraded to plain run: $e');
      return _degrade(real, original);
    }
  }

  /// Plain spawn of the real binary with the original argv — the guiding
  /// principle: the user's command always runs.
  Future<int> _degrade(String real, List<String> original) async {
    final proc = await Process.start(
      real,
      original,
      mode: ProcessStartMode.inheritStdio,
    );
    return proc.exitCode;
  }
}
```

- [ ] **Step 4: Write the CLI entry**

Create `app/bin/wrap.dart`:

```dart
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutterware_app/src/wrap/run_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>(
    'wrap',
    'flutterware SDK wrap point.',
  )..addCommand(RunCommand());
  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/wrap/run_command_test.dart`
Expected: PASS — 2 tests. The first writes a session dir whose `output.log`
contains both the payload and the injected `--dart-define=FW_MARKER=` (because
the fake real binary is `/bin/echo`, which echoes its rewritten argv).

- [ ] **Step 6: Commit**

```bash
git add app/lib/src/wrap/run_command.dart app/bin/wrap.dart app/test/wrap/run_command_test.dart
git commit -m "Add the wrap run command and CLI entry"
```

---

## Task 6: Shim template + renderer

**Files:**
- Create: `app/lib/src/wrap/shim_template.dart`
- Test: `app/test/wrap/shim_template_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutterware_app/src/wrap/shim_template.dart';
import 'package:test/test.dart';

void main() {
  test('renderShim bakes in the real binary, kind, and wrap exe', () {
    final shim = renderShim(
      realBinary: '/sdk/bin/flutter',
      kind: 'flutter',
      wrapExe: '/cache/wrap',
    );
    expect(shim, startsWith('#!/usr/bin/env bash'));
    expect(shim, contains('REAL="/sdk/bin/flutter"'));
    expect(shim, contains('KIND="flutter"'));
    expect(shim, contains('WRAP_EXE="/cache/wrap"'));
    // The marker walk-up and classification must be present.
    expect(shim, contains('flutter_version'));
    expect(shim, contains('run|test'));
    expect(shim, contains('wrap-audit.log'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/wrap/shim_template_test.dart`
Expected: FAIL — `shim_template.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
/// The bash shim installed as `<mirror>/bin/flutter` and `<mirror>/bin/dart`.
/// `@REAL@`, `@KIND@`, `@WRAP_EXE@` are replaced at install time.
///
/// Fast path is pure bash: marker walk-up, classification, one audit-log
/// line. Only *interesting* runs hand off to the compiled wrap executable.
const _shimTemplate = r'''#!/usr/bin/env bash
# flutterware wrap shim — generated; do not edit.
set -u
REAL="@REAL@"
KIND="@KIND@"
WRAP_EXE="@WRAP_EXE@"

# 1. Walk up for the flutter_version marker.
root=""
d="$PWD"
while :; do
  if [ -f "$d/flutter_version" ]; then root="$d"; break; fi
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done
[ -z "$root" ] && exec "$REAL" "$@"

# 2. First non-flag argument (the subcommand).
sub=""
for a in "$@"; do
  case "$a" in
    -*) ;;
    *) sub="$a"; break ;;
  esac
done

# 3. Classify (probe default — replaced by config.dart in sub-project 3).
cls="noise"
if [ "$KIND" = "flutter" ]; then
  case "$sub" in
    run|test) cls="interesting" ;;
  esac
fi

# 4. Audit log — one line per invocation, every kind.
fwdir="$root/.flutterware"
mkdir -p "$fwdir" 2>/dev/null || true
printf '%s\t%s\t%s\t%s\t%s %s\n' \
  "$(date +%Y-%m-%dT%H:%M:%S)" "$PWD" "$KIND" "$cls" "$KIND" "$*" \
  >>"$fwdir/wrap-audit.log" 2>/dev/null || true

# 5. Dispatch. Interesting -> the wrap exe; anything else / missing exe -> real.
if [ "$cls" = "interesting" ] && [ -x "$WRAP_EXE" ]; then
  exec "$WRAP_EXE" run --real "$REAL" --kind "$KIND" -- "$@"
fi
exec "$REAL" "$@"
''';

/// Renders the shim with the given absolute paths baked in.
String renderShim({
  required String realBinary,
  required String kind,
  required String wrapExe,
}) =>
    _shimTemplate
        .replaceAll('@REAL@', realBinary)
        .replaceAll('@KIND@', kind)
        .replaceAll('@WRAP_EXE@', wrapExe);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/wrap/shim_template_test.dart`
Expected: PASS — 1 test.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/wrap/shim_template.dart app/test/wrap/shim_template_test.dart
git commit -m "Add the bash wrap shim template and renderer"
```

---

## Task 7: Installer + `install` command

**Files:**
- Create: `app/lib/src/wrap/installer.dart`
- Create: `app/lib/src/wrap/install_command.dart`
- Modify: `app/bin/wrap.dart` (register `InstallCommand`)
- Test: `app/test/wrap/installer_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';
import 'package:flutterware_app/src/wrap/installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Directory sdk;
  late Directory project;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wrap_inst');
    // A fake "shared SDK".
    sdk = Directory(p.join(tmp.path, 'sharedsdk'))..createSync();
    Directory(p.join(sdk.path, 'bin'))..createSync();
    Directory(p.join(sdk.path, 'bin', 'cache')).createSync();
    File(p.join(sdk.path, 'bin', 'flutter')).writeAsStringSync('#real\n');
    File(p.join(sdk.path, 'bin', 'dart')).writeAsStringSync('#real\n');
    File(p.join(sdk.path, 'bin', 'internal')).writeAsStringSync('x\n');
    File(p.join(sdk.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
    project = Directory(p.join(tmp.path, 'project'))..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('installMirror builds a facade: real bin/, symlinked entries, shims',
      () {
    final mirror = installMirror(
      sharedSdk: sdk,
      projectRoot: project,
      wrapExe: '/cache/wrap',
    );
    expect(mirror.path, p.join(project.path, 'flutterware', 'sdk'));

    // Top-level non-bin entries are symlinks to the shared SDK.
    expect(FileSystemEntity.isLinkSync(p.join(mirror.path, 'pubspec.yaml')),
        isTrue);
    // bin/ is a real directory.
    expect(FileSystemEntity.isDirectorySync(p.join(mirror.path, 'bin')),
        isTrue);
    expect(FileSystemEntity.isLinkSync(p.join(mirror.path, 'bin')), isFalse);
    // bin/cache and bin/internal are symlinks.
    expect(FileSystemEntity.isLinkSync(p.join(mirror.path, 'bin', 'cache')),
        isTrue);
    // bin/flutter and bin/dart are real shim files, not symlinks.
    final flutterShim = File(p.join(mirror.path, 'bin', 'flutter'));
    expect(FileSystemEntity.isLinkSync(flutterShim.path), isFalse);
    expect(flutterShim.readAsStringSync(), contains('KIND="flutter"'));
    expect(File(p.join(mirror.path, 'bin', 'dart')).readAsStringSync(),
        contains('KIND="dart"'));
  });

  test('installMirror is idempotent — re-running rebuilds cleanly', () {
    installMirror(sharedSdk: sdk, projectRoot: project, wrapExe: '/c/wrap');
    final mirror = installMirror(
        sharedSdk: sdk, projectRoot: project, wrapExe: '/c/wrap');
    expect(File(p.join(mirror.path, 'bin', 'flutter')).existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/wrap/installer_test.dart`
Expected: FAIL — `installer.dart` does not exist.

- [ ] **Step 3: Write the installer**

Create `app/lib/src/wrap/installer.dart`:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;

import 'shim_template.dart';

/// Builds the per-project SDK mirror facade at `<projectRoot>/flutterware/sdk/`.
///
/// Every entry of [sharedSdk] is symlinked into the mirror, except `bin/`,
/// which is a real directory whose `flutter`/`dart` are generated shims and
/// whose other entries are symlinks. The mirror is rebuilt from scratch on
/// every call (idempotent). Returns the mirror directory.
Directory installMirror({
  required Directory sharedSdk,
  required Directory projectRoot,
  required String wrapExe,
}) {
  final mirror =
      Directory(p.join(projectRoot.path, 'flutterware', 'sdk'));
  if (mirror.existsSync()) mirror.deleteSync(recursive: true);
  mirror.createSync(recursive: true);

  final mirrorBin = Directory(p.join(mirror.path, 'bin'))..createSync();

  // Top-level SDK entries (skip `bin`) -> symlinks.
  for (final entry in sharedSdk.listSync()) {
    final name = p.basename(entry.path);
    if (name == 'bin') continue;
    Link(p.join(mirror.path, name)).createSync(entry.path);
  }

  // bin/ entries (skip the two wrapped binaries) -> symlinks.
  final sharedBin = Directory(p.join(sharedSdk.path, 'bin'));
  for (final entry in sharedBin.listSync()) {
    final name = p.basename(entry.path);
    if (name == 'flutter' || name == 'dart') continue;
    Link(p.join(mirrorBin.path, name)).createSync(entry.path);
  }

  // The two shims.
  _writeShim(
    file: File(p.join(mirrorBin.path, 'flutter')),
    realBinary: p.join(sharedBin.path, 'flutter'),
    kind: 'flutter',
    wrapExe: wrapExe,
  );
  _writeShim(
    file: File(p.join(mirrorBin.path, 'dart')),
    realBinary: p.join(sharedBin.path, 'dart'),
    kind: 'dart',
    wrapExe: wrapExe,
  );

  return mirror;
}

void _writeShim({
  required File file,
  required String realBinary,
  required String kind,
  required String wrapExe,
}) {
  file.writeAsStringSync(renderShim(
    realBinary: realBinary,
    kind: kind,
    wrapExe: wrapExe,
  ));
  // chmod +x.
  Process.runSync('chmod', ['+x', file.path]);
}
```

- [ ] **Step 4: Run the installer test to verify it passes**

Run: `cd app && flutter test test/wrap/installer_test.dart`
Expected: PASS — 2 tests.

- [ ] **Step 5: Write the `install` command**

Create `app/lib/src/wrap/install_command.dart`:

```dart
import 'dart:io';

import 'package:args/command_runner.dart';

import 'installer.dart';

/// Builds the per-project SDK mirror facade. Sub-project 0 assumes a shared
/// SDK already exists; this command wraps it.
class InstallCommand extends Command<int> {
  @override
  final name = 'install';
  @override
  final description = 'Install the SDK mirror facade for a project.';

  InstallCommand() {
    argParser
      ..addOption('sdk', help: 'Path to the existing shared Flutter SDK.')
      ..addOption('project', help: 'Path to the project root.')
      ..addOption('wrap-exe',
          help: 'Path to the compiled wrap executable to bake into shims.');
  }

  @override
  Future<int> run() async {
    final sdk = argResults!['sdk'] as String?;
    final project = argResults!['project'] as String?;
    final wrapExe = argResults!['wrap-exe'] as String?;
    if (sdk == null || project == null || wrapExe == null) {
      stderr.writeln('[wrap] install requires --sdk, --project, --wrap-exe');
      return 64;
    }
    final mirror = installMirror(
      sharedSdk: Directory(sdk),
      projectRoot: Directory(project),
      wrapExe: wrapExe,
    );
    stdout.writeln('Installed SDK mirror at ${mirror.path}');
    return 0;
  }
}
```

- [ ] **Step 6: Register the command**

In `app/bin/wrap.dart`, add the import and register the command. The file
becomes:

```dart
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutterware_app/src/wrap/install_command.dart';
import 'package:flutterware_app/src/wrap/run_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>(
    'wrap',
    'flutterware SDK wrap point.',
  )
    ..addCommand(RunCommand())
    ..addCommand(InstallCommand());
  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
```

- [ ] **Step 7: Run all wrap tests to verify they pass**

Run: `cd app && flutter test test/wrap/`
Expected: PASS — all wrap unit tests.

- [ ] **Step 8: Commit**

```bash
git add app/lib/src/wrap/installer.dart app/lib/src/wrap/install_command.dart app/bin/wrap.dart app/test/wrap/installer_test.dart
git commit -m "Add the SDK mirror installer and install command"
```

---

## Task 8: End-to-end shim integration test

Tests the *bash* layer — marker walk-up, classification, audit log, dispatch,
degradation — using test doubles for the real binary and the wrap exe.

**Files:**
- Test: `app/test/wrap/shim_integration_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'dart:io';
import 'package:flutterware_app/src/wrap/shim_template.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late File shim;
  late File realMarker;
  late File wrapMarker;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wrap_shim');
    // A "real binary" double that records it was called and echoes argv.
    realMarker = File(p.join(tmp.path, 'real.called'));
    final fakeReal = File(p.join(tmp.path, 'fake_real'))
      ..writeAsStringSync(
          '#!/usr/bin/env bash\necho "real:$*" >>"${realMarker.path}"\n');
    Process.runSync('chmod', ['+x', fakeReal.path]);
    // A "wrap exe" double — note it must accept the `run ... -- ...` argv.
    wrapMarker = File(p.join(tmp.path, 'wrap.called'));
    final fakeWrap = File(p.join(tmp.path, 'fake_wrap'))
      ..writeAsStringSync(
          '#!/usr/bin/env bash\necho "wrap:$*" >>"${wrapMarker.path}"\n');
    Process.runSync('chmod', ['+x', fakeWrap.path]);

    shim = File(p.join(tmp.path, 'flutter'))
      ..writeAsStringSync(renderShim(
        realBinary: fakeReal.path,
        kind: 'flutter',
        wrapExe: fakeWrap.path,
      ));
    Process.runSync('chmod', ['+x', shim.path]);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ProcessResult invoke(List<String> args, {required Directory cwd}) =>
      Process.runSync(shim.path, args, workingDirectory: cwd.path);

  test('no marker -> straight to the real binary, no audit log', () {
    final cwd = Directory(p.join(tmp.path, 'plain'))..createSync();
    invoke(['run'], cwd: cwd);
    expect(realMarker.existsSync(), isTrue);
    expect(wrapMarker.existsSync(), isFalse);
  });

  test('interesting run (flutter run) is dispatched to the wrap exe', () {
    final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
    File(p.join(proj.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    invoke(['--no-color', 'run', '--machine'], cwd: proj);
    expect(wrapMarker.existsSync(), isTrue);
    expect(wrapMarker.readAsStringSync(), contains('run --real'));
    final audit =
        File(p.join(proj.path, '.flutterware', 'wrap-audit.log'));
    expect(audit.readAsStringSync(), contains('interesting'));
  });

  test('noise (flutter pub get) goes to the real binary, audited as noise', () {
    final proj = Directory(p.join(tmp.path, 'proj2'))..createSync();
    File(p.join(proj.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    invoke(['pub', 'get'], cwd: proj);
    expect(realMarker.existsSync(), isTrue);
    expect(wrapMarker.existsSync(), isFalse);
    final audit =
        File(p.join(proj.path, '.flutterware', 'wrap-audit.log'));
    expect(audit.readAsStringSync(), contains('noise'));
  });

  test('interesting run degrades to real when the wrap exe is missing', () {
    final proj = Directory(p.join(tmp.path, 'proj3'))..createSync();
    File(p.join(proj.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    // Re-render the shim pointing at a non-existent wrap exe.
    shim.writeAsStringSync(renderShim(
      realBinary: File(p.join(tmp.path, 'fake_real')).path,
      kind: 'flutter',
      wrapExe: '/no/such/wrap_exe',
    ));
    Process.runSync('chmod', ['+x', shim.path]);
    invoke(['run'], cwd: proj);
    expect(realMarker.existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `cd app && flutter test test/wrap/shim_integration_test.dart`
Expected: PASS — 4 tests. (The shim template from Task 6 already implements
this behaviour; this task adds the coverage that locks it in.)

- [ ] **Step 3: Commit**

```bash
git add app/test/wrap/shim_integration_test.dart
git commit -m "Add end-to-end integration test for the wrap shim"
```

---

## Task 9: The probe app

**Files:**
- Modify: `examples/example/lib/main.dart`

- [ ] **Step 1: Add the probe widget**

In `examples/example/lib/main.dart`, add a top-level constant after the imports:

```dart
const _fwMarker = String.fromEnvironment('FW_MARKER', defaultValue: '<none>');
```

Then, inside `_MyHomePageState.build`, add a `Text` as the first child of the
`ListView` (before `Text('Language: ...')`):

```dart
          Text('FW_MARKER: $_fwMarker',
              key: const Key('fw-marker'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
```

- [ ] **Step 2: Verify the example still analyzes**

Run: `cd examples/example && flutter analyze`
Expected: No new analysis errors.

- [ ] **Step 3: Commit**

```bash
git add examples/example/lib/main.dart
git commit -m "Add FW_MARKER probe widget to the example app"
```

---

## Task 10: Manual smoke test

**Files:**
- Create: `docs/superpowers/specs/2026-05-15-subproject-0-manual-smoke.md`

- [ ] **Step 1: Write the smoke-test doc**

Create `docs/superpowers/specs/2026-05-15-subproject-0-manual-smoke.md` with
this content:

````markdown
# Sub-project 0 — Manual Smoke Test

Validates the SDK wrap point against a real IDE. Run after the automated
plan tasks pass.

## Setup

1. Compile the wrap executable:
   ```sh
   cd app && dart compile exe bin/wrap.dart -o build/wrap
   ```
2. Mark the example project: write its Flutter version into a marker file:
   ```sh
   flutter --version | head -1   # note the version
   echo "<version>" > examples/example/flutter_version
   ```
3. Install the mirror facade:
   ```sh
   cd app && dart run bin/wrap.dart install \
     --sdk "$(dirname "$(dirname "$(which flutter)")")" \
     --project ../examples/example \
     --wrap-exe "$(pwd)/build/wrap"
   ```
   This creates `examples/example/flutterware/sdk/`.

## Checks

### A. CLI interception
- `cd examples/example/.. ` then run `flutterware/sdk/bin/flutter run -d macos`
  from `examples/example`.
- Expect: a `examples/example/.flutterware/sessions/<id>/` directory with
  `output.log` and `meta.json`; `meta.json` shows the injected marker.
- Expect: `examples/example/.flutterware/wrap-audit.log` has an `interesting`
  line for the run.

### B. IDE interception (IntelliJ)
- Point IntelliJ's Flutter SDK at `examples/example/flutterware/sdk`
  (a non-hidden path — IntelliJ accepts it).
- Do **not** set `FW_MARKER` in the run configuration (the wrap injects it).
- Run the example app from IntelliJ. Hot reload once. Stop.
- Expect: the running app shows `FW_MARKER: <session id>` (not `<none>`) —
  confirming the injected `--dart-define` reached `String.fromEnvironment`.
- Expect: a new `interesting` session in the audit log and a session dir.
- Expect: hot reload, stop, and the debugger still work.

### C. IDE interception (VS Code) — same as B with the Dart-Code extension.

### D. Noise latency
- Watch the audit log while the IDE is open; confirm `dart`/`flutter`
  noise invocations are classified `noise` and the IDE is not visibly slowed.

### E. Degradation
- Temporarily rename `app/build/wrap`; run `flutter run` through the mirror;
  confirm the real command still runs (degraded to plain exec).

## Result

Record pass/fail per check. A negative result (the wrap breaks an IDE
workflow, or noise is misclassified) is a valid finding that escalates to the
parent architecture.
````

- [ ] **Step 2: Run the full automated suite once more**

Run: `cd app && flutter test test/wrap/ test/passthrough/`
Expected: PASS — all wrap and passthrough tests.

- [ ] **Step 3: Run the workspace formatter**

Run: `dart tool/prepare_submit.dart`
Expected: completes; if it reformats files, include them in the commit.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-05-15-subproject-0-manual-smoke.md
git commit -m "Add manual smoke test for the SDK wrap point"
```

---

## Self-Review

- **Spec coverage:** mirror facade (Task 7), non-hidden mirror path
  `flutterware/sdk/` (Task 7 `installMirror`), bash fast-path shims with
  marker walk-up + classification + audit log (Tasks 6, 8), `flutterware wrap`
  heavy path (Task 5), dart-define argv injection (Task 1), PTY/pipe transport
  (Task 4), project/worktree resolution (Task 2), session sink under
  `.flutterware/` (Task 3), graceful degradation (Tasks 5, 8), probe app
  (Task 9), installer (Task 7), test plan automated + manual (Tasks 1-8, 10).
  All spec sections map to tasks.
- **Placeholder scan:** no TBD/TODO; every code step has complete code.
- **Type consistency:** `injectDartDefine`, `resolveProject`/`ProjectContext`,
  `SessionSink`/`newSessionId`, `runIntercepted`, `RunCommand`, `renderShim`,
  `installMirror`, `InstallCommand` — names used identically across tasks.
  `runUnderPty`'s new `captureSink` parameter is used consistently in Task 4.

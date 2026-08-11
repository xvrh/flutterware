import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/worktrees/watchers.dart';
import 'package:path/path.dart' as p;

const _debounce = Duration(milliseconds: 100);
const _floor = Duration(seconds: 2);

/// Every directory the watcher asked for, and a way to make each one speak.
///
/// The filesystem is real — `start` skips a directory that is not there, and
/// that check is worth exercising — but the *events* are ours, because what
/// this file is about is when a burst becomes one refresh.
class _Fixture {
  _Fixture(this.root);

  final Directory root;
  final watched = <({String path, bool recursive})>[];
  final controllers = <String, StreamController<String>>{};
  final failures = <String>[];

  String get git => p.join(root.path, 'main', '.git');
  String get agents => p.join(root.path, 'claude', 'projects');

  /// Stands in for `~/.flutterware/run`. Passed explicitly by every test, so a
  /// unit test never ends up watching the developer's own run directory — and
  /// never creates one on a machine that has none.
  String get runDir => p.join(root.path, 'run');

  Stream<String> watch(String path, {required bool recursive}) {
    watched.add((path: path, recursive: recursive));
    return (controllers[path] = StreamController<String>.broadcast()).stream;
  }

  /// Something changed at [path], reported by whichever watch covers it.
  void change(String directory, String name) =>
      controllers[directory]!.add(p.join(directory, name));
}

void main() {
  late Directory root;
  late _Fixture fixture;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw-watchers-test');
    fixture = _Fixture(root);
    for (var dir in [
      p.join(fixture.git, 'worktrees'),
      p.join(fixture.git, 'refs', 'heads'),
      fixture.agents,
      fixture.runDir,
    ]) {
      Directory(dir).createSync(recursive: true);
    }
  });

  tearDown(() => root.deleteSync(recursive: true));

  WorktreeWatcher build({
    String? agentRoot,
    String? runDir,
    DateTime Function()? now,
  }) => WorktreeWatcher(
    repoRoot: p.join(root.path, 'main'),
    agentRoot: agentRoot ?? fixture.agents,
    runDir: runDir ?? fixture.runDir,
    debounce: _debounce,
    minInterval: _floor,
    watch: fixture.watch,
    now: now,
    onFailure: (what, error) => fixture.failures.add(what),
  );

  /// Runs [body] on a fake clock, with the watcher's own clock wired to it —
  /// otherwise the floor between signals would be measured against a wall clock
  /// that never moved.
  void withClock(void Function(WorktreeWatcher watcher, FakeAsync async) body) {
    fakeAsync((async) {
      var start = DateTime(2026, 8, 10, 14, 30);
      var watcher = build(now: () => start.add(async.elapsed))..start();
      body(watcher, async);
      unawaited(watcher.dispose());
      async.flushTimers();
    });
  }

  test('watches five directories, and recurses only where it must', () {
    build().start();

    expect(fixture.watched, hasLength(5));
    var byPath = {
      for (var w in fixture.watched)
        p.relative(w.path, from: root.path): w.recursive,
    };
    expect(byPath, {
      // Flat: recursing here would mean reporting every packfile under
      // `objects/` for the life of the window.
      'main/.git': false,
      'main/.git/worktrees': true,
      // Recursive because `claude/thing` is a *directory* under refs/heads —
      // the one that would silently watch nothing on this repository.
      'main/.git/refs/heads': true,
      'claude/projects': true,
      // Flat: the stack caches are direct children, and the run dir has
      // subdirectories nothing here cares about.
      'run': false,
    });
  });

  test('a burst of writes is one signal', () {
    withClock((watcher, async) {
      var signals = <WorktreeChange>[];
      watcher.changes.listen(signals.add);

      // One commit, as git actually writes it.
      fixture.change(p.join(fixture.git, 'refs', 'heads'), 'claude/thing');
      fixture.change(p.join(fixture.git, 'worktrees'), 'linked/index');
      fixture.change(fixture.git, 'ORIG_HEAD');
      async.flushMicrotasks();

      async.elapse(_debounce ~/ 2);
      expect(signals, isEmpty, reason: 'still settling');

      async.elapse(_debounce);
      expect(signals, [WorktreeChange.git]);
    });
  });

  test('a writer that never stops still yields, on the floor', () {
    withClock((watcher, async) {
      var signals = <WorktreeChange>[];
      watcher.changes.listen(signals.add);

      // An agent mid-answer: a line every 50 ms, for ten seconds. With a
      // debounce alone this never finds a quiet moment and the screen would
      // never update at all.
      for (var i = 0; i < 200; i++) {
        fixture.change(fixture.agents, 'a-repo/session.jsonl');
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 50));
      }

      expect(
        signals.length,
        // 10 s of writing at a 2 s floor: five, plus or minus where the
        // debounce lands in the first window.
        inInclusiveRange(4, 6),
        reason: '200 writes must not be 200 refreshes',
      );
      expect(signals, everyElement(WorktreeChange.agent));
    });
  });

  test('an agent flood never asks git anything', () {
    withClock((watcher, async) {
      var signals = <WorktreeChange>[];
      watcher.changes.listen(signals.add);

      for (var i = 0; i < 50; i++) {
        fixture.change(fixture.agents, 'a-repo/session.jsonl');
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));
      }

      // The whole reason the two kinds are separate: this is the difference
      // between reading a file and spawning fourteen `git status` calls, every
      // two seconds, for as long as anybody is working.
      expect(signals, isNot(contains(WorktreeChange.git)));
    });
  });

  test('the two kinds do not queue behind each other', () {
    withClock((watcher, async) {
      var signals = <WorktreeChange>[];
      watcher.changes.listen(signals.add);

      fixture.change(fixture.agents, 'a-repo/session.jsonl');
      fixture.change(p.join(fixture.git, 'worktrees'), 'linked/index');
      async.flushMicrotasks();
      async.elapse(_debounce * 2);

      expect(signals, containsAll([WorktreeChange.agent, WorktreeChange.git]));
    });
  });

  group('the run dir', () {
    test('a stack cache write is a stack signal, and only that', () {
      withClock((watcher, async) {
        var signals = <WorktreeChange>[];
        watcher.changes.listen(signals.add);

        fixture.change(fixture.runDir, 'stack-0123456789abcdef.json');
        async.flushMicrotasks();
        async.elapse(_debounce * 2);

        expect(signals, [WorktreeChange.stack]);
      });
    });

    test('a server writing its log all day is not a change at all', () {
      // **The one watch that needs a filter.** `~/.flutterware/run` is shared
      // scratch: measured on this machine, a directory holding 123 files
      // produced 679 events in thirty seconds while a server was logging —
      // 676 of them `.log` writes and 3 of them stack caches. Without the
      // filter, every log line a running server emits would be a worktree
      // change, coalesced or not.
      withClock((watcher, async) {
        var signals = <WorktreeChange>[];
        watcher.changes.listen(signals.add);

        for (var i = 0; i < 200; i++) {
          fixture.change(fixture.runDir, 'a1b2c3d4.log');
          fixture.change(fixture.runDir, 'devices.json');
          fixture.change(fixture.runDir, 'app-99.json');
          // And the watched directory itself, which macOS reports alongside
          // the per-file events — observed, not guessed. Its basename is the
          // directory's, so the filter drops it like everything else.
          fixture.controllers[fixture.runDir]!.add(fixture.runDir);
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 50));
        }

        expect(signals, isEmpty);
      });
    });

    test('the real filesystem reaches the filter', () async {
      // **The one test here that uses a real watch.** Everything else injects
      // its events, because what those are about is timing. This one is about
      // the filter, which reads the *basename* of whatever the platform hands
      // over — and a platform that coalesced a burst into one event naming the
      // directory rather than the file would drop every stack write silently.
      // Measured on macOS beforehand: a 30 s sample carried per-file paths, so
      // this pins that rather than trusting it.
      var watcher = WorktreeWatcher(
        repoRoot: p.join(root.path, 'main'),
        agentRoot: fixture.agents,
        runDir: fixture.runDir,
        debounce: const Duration(milliseconds: 10),
      )..start();
      addTearDown(watcher.dispose);

      // `firstWhere`, not `first`: registering a watch makes macOS emit an
      // event naming the watched *directory* on every one of the five, so the
      // first signal out of a freshly started watcher belongs to whichever
      // registered first. Those are dropped here by the same basename filter,
      // which is the property being tested.
      var seen = watcher.changes
          .firstWhere((c) => c == WorktreeChange.stack)
          .timeout(const Duration(seconds: 15));
      // Written after the watch is up, and twice, since the first event on a
      // fresh FSEvents stream can be swallowed while it registers.
      for (var i = 0; i < 2; i++) {
        File(
          p.join(fixture.runDir, 'stack-0123456789abcdef.json'),
        ).writeAsStringSync('{"state":"up","checkedAt":"2026-08-11T12:00:00"}');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      expect(await seen, WorktreeChange.stack);
    });

    test('a stack flood never asks git anything either', () {
      withClock((watcher, async) {
        var signals = <WorktreeChange>[];
        watcher.changes.listen(signals.add);

        // Every ten seconds is what a polling session actually writes; this is
        // fifty times faster, and it still cannot reach git.
        for (var i = 0; i < 50; i++) {
          fixture.change(fixture.runDir, 'stack-0123456789abcdef.json');
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 100));
        }

        expect(signals, isNot(contains(WorktreeChange.git)));
        expect(
          signals.length,
          // 5 s of writing against a 2 s floor.
          inInclusiveRange(2, 4),
          reason: '50 writes must not be 50 refreshes',
        );
      });
    });
  });

  test("git's own lock files are not a change", () {
    withClock((watcher, async) {
      var signals = <WorktreeChange>[];
      watcher.changes.listen(signals.add);

      fixture.change(fixture.git, 'index.lock');
      fixture.change(p.join(fixture.git, 'refs', 'heads'), 'main.lock');
      async.flushMicrotasks();
      async.elapse(_debounce * 3);

      expect(signals, isEmpty);
    });
  });

  test('a directory that is not a repository is not watched at all', () {
    var watcher = WorktreeWatcher(
      repoRoot: p.join(root.path, 'not-a-repo'),
      agentRoot: fixture.agents,
      runDir: fixture.runDir,
      watch: fixture.watch,
    )..start();
    addTearDown(watcher.dispose);

    // Not even the agent root: every session on the machine, watched for a
    // list of one directory that git cannot report anything about.
    expect(fixture.watched, isEmpty);
  });

  test('a directory that is not there is skipped, not fatal', () {
    build(agentRoot: p.join(root.path, 'nowhere')).start();

    expect(fixture.watched, hasLength(4));
    expect(
      fixture.watched.any((w) => w.path.endsWith('refs/heads')),
      isTrue,
      reason: 'the git watches still stand',
    );
  });

  test('a watch that fails costs liveness and nothing else', () async {
    var watcher = WorktreeWatcher(
      repoRoot: p.join(root.path, 'main'),
      agentRoot: fixture.agents,
      runDir: fixture.runDir,
      debounce: _debounce,
      watch: (path, {required recursive}) => path.endsWith('projects')
          ? throw const FileSystemException('too many open files')
          : fixture.watch(path, recursive: recursive),
      onFailure: (what, error) => fixture.failures.add(what),
    )..start();
    addTearDown(watcher.dispose);

    expect(fixture.failures, ['agent sessions']);
    expect(
      fixture.watched.length,
      4,
      reason: 'the git and stack watches were established anyway',
    );
  });

  test('starting twice does not double the watches', () {
    build()
      ..start()
      ..start();
    expect(fixture.watched, hasLength(5));
  });

  test('disposing stops the signal that was already pending', () {
    fakeAsync((async) {
      var watcher = build()..start();
      var signals = <WorktreeChange>[];
      watcher.changes.listen(signals.add);

      fixture.change(fixture.git, 'HEAD');
      async.flushMicrotasks();
      unawaited(watcher.dispose());
      async.elapse(_debounce * 3);
      async.flushTimers();

      expect(signals, isEmpty);
    });
  });
}

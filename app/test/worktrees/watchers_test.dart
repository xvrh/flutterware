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
    ]) {
      Directory(dir).createSync(recursive: true);
    }
  });

  tearDown(() => root.deleteSync(recursive: true));

  WorktreeWatcher build({String? agentRoot, DateTime Function()? now}) =>
      WorktreeWatcher(
        repoRoot: p.join(root.path, 'main'),
        agentRoot: agentRoot ?? fixture.agents,
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

  test('watches four directories, and recurses only where it must', () {
    build().start();

    expect(fixture.watched, hasLength(4));
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
      watch: fixture.watch,
    )..start();
    addTearDown(watcher.dispose);

    // Not even the agent root: every session on the machine, watched for a
    // list of one directory that git cannot report anything about.
    expect(fixture.watched, isEmpty);
  });

  test('a directory that is not there is skipped, not fatal', () {
    build(agentRoot: p.join(root.path, 'nowhere')).start();

    expect(fixture.watched, hasLength(3));
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
      3,
      reason: 'the git watches were established anyway',
    );
  });

  test('starting twice does not double the watches', () {
    build()
      ..start()
      ..start();
    expect(fixture.watched, hasLength(4));
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

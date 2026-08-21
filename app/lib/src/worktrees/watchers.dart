/// Makes the explorer live, without a polling timer anywhere.
///
/// Four directories cover fourteen worktrees. A linked worktree's HEAD and
/// index are not in the checkout — they live in `<main>/.git/worktrees/<name>/`
/// — so one recursive watch there sees every linked checkout at once. Branches
/// are shared, so one watch on `refs/heads/` sees every commit from anywhere.
///
/// Verified end to end on a scratch repository (2026-08-10) — not "which
/// files git wrote", but which of these watches actually *fired*, with real
/// `Directory.watch` streams and a linked worktree on a slashed branch:
///
/// | operation | watch that fired |
/// |---|---|
/// | commit, in the linked worktree | `refs/heads`, `worktrees` |
/// | `git add`, in the linked worktree | `worktrees` |
/// | branch switch, in the linked worktree | `refs/heads`, `worktrees` |
/// | commit, in the **main** checkout | `refs/heads`, `.git` flat |
/// | editing a file | **nothing** |
/// | `git worktree add` | `refs/heads`, `worktrees` |
///
/// Every watch earns its place — the flat `.git` one is what covers the main
/// checkout's own index, and is the only one that fires for it. Two further
/// things fall out of that table which are easy to get wrong:
///
/// - **`refs/heads` must be watched recursively.** The commit landed on
///   `refs/heads/claude/slashed` — a branch with a `/` in it is a *directory*
///   under `refs/heads`, and a non-recursive watch would have seen nothing at
///   all on this repository, where every branch is named `claude/…`. It is the
///   sort of miss that looks like "watching does not work on my machine".
/// - **Editing a file touches nothing at all**, which is the real gap:
///   dirty counts cannot be event-driven, and watching fourteen working trees
///   recursively is exactly the cost this design exists to avoid. Dirty
///   refreshes on visibility and on demand. It is also the least urgent cell —
///   it changes when *you* type, and you know that you typed.
///
/// [WorkingTreeWatcher] is that gap's scoped exception, for the one screen
/// where the file being edited *is* the subject.
///
/// Never `.git` recursively. `objects/` churns on every fetch, and a watch
/// that recursed into it would spend the day reporting packfiles. The top level
/// is watched flat, which is enough for the main checkout's own HEAD and index.
///
/// ## Why the two kinds are separate
///
/// A [WorktreeChange.git] event means re-running git. A [WorktreeChange.agent]
/// event means reading files — a `stat` and a 64 KB tail per worktree, no
/// subprocesses. They arrive at wildly different rates: an agent mid-answer
/// appends to its session file continuously, and if that drove the git sweep,
/// a window sitting in the background would spawn fourteen `git status` calls
/// every couple of seconds for as long as anybody was working. So the kinds
/// coalesce separately and the listener refreshes only what moved.
///
/// [WorktreeChange.stack] is the third, and the cheapest: one small JSON read
/// per worktree, no subprocesses either.
///
/// ## The run dir needs a filter, and it is the only watch that does
///
/// `~/.flutterware/run` is shared scratch — every daemon writes a `<key>.log`
/// and a `<key>.lock` there, and a measured directory held 123 files of which
/// 88 were logs and locks. Watching it whole would report a running server's
/// every log line as a worktree change. So this watch takes an [_Accept]
/// predicate and keeps only `stack-*`, which is the one thing in there that
/// says anything about a checkout.
///
/// Measured, because the filter is the whole reason this is affordable.
/// Thirty seconds on a directory holding 123 files, with a server logging and
/// a stack being probed:
///
/// | | events in 30 s |
/// |---|---|
/// | everything the run dir emitted | 679 |
/// | `.log` writes from one running server | 676 |
/// | `stack-*` caches | 3 |
///
/// Unfiltered, that is a server's every log line arriving as a worktree
/// change. Filtered, it is three — which the coalescer then turns into at most
/// one refresh every [minInterval], each costing one small file read per
/// worktree and no subprocesses at all.
///
/// The filter also catches something the platform does that is easy to miss:
/// macOS emits an event naming the watched directory itself, both when the
/// watch registers and alongside the per-file events. Its basename is the
/// directory's, so it never looks like a stack file.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/directory_watch.dart';
import '../utils/run_dir.dart';

export '../utils/directory_watch.dart' show WatchDirectory;

/// What moved. See the note above on why this is not one signal.
enum WorktreeChange {
  /// A commit, a staging change, a branch switch, or a worktree appearing.
  git,

  /// An agent session file was written.
  agent,

  /// A dev stack's cached reading was rewritten — by another window, or by
  /// `fw run dev_stack start` in a terminal.
  ///
  /// Rarer than it sounds, and that is by design. A stack is only probed
  /// while one of its surfaces is mounted, so sitting on the explorer produces
  /// no writes at all. What this catches is the case nothing else can: the
  /// state changing while you are looking at a screen that is not the one
  /// changing it.
  stack,
}

/// Whether a changed path is worth waking anything for.
typedef _Accept = bool Function(String path);

class WorktreeWatcher {
  WorktreeWatcher({
    required this.repoRoot,
    String? agentRoot,
    this.runDir,
    this.debounce = const Duration(milliseconds: 300),
    this.minInterval = const Duration(seconds: 2),
    WatchDirectory? watch,
    DateTime Function()? now,
    this.onFailure,
  }) : agentRoot = agentRoot ?? defaultAgentRoot(),
       _watch = watch ?? watchDirectoryPaths,
       _now = now ?? DateTime.now;

  /// The **main** checkout. Every git watch is under its `.git`, including the
  /// state of worktrees that live somewhere else entirely.
  final String repoRoot;

  final String agentRoot;

  /// `~/.flutterware/run` when null — resolved in [start] rather than here,
  /// because [flutterwareRunDir] *creates* the directory and a constructor
  /// should not leave one behind on a machine that never watches anything.
  final String? runDir;

  /// How long a burst is allowed to settle. One commit is several writes.
  final Duration debounce;

  /// The floor between two signals of the same kind.
  ///
  /// This is what an agent mid-answer runs into: it appends to its session file
  /// steadily, so the debounce alone would never find a quiet moment and the
  /// screen would either never update or update on every line. With a floor,
  /// a continuous writer produces one refresh every [minInterval] and nothing
  /// in between.
  final Duration minInterval;

  final WatchDirectory _watch;
  final DateTime Function() _now;

  /// Told when a watch could not be established. Liveness, never correctness —
  /// see [start].
  final void Function(String what, Object error)? onFailure;

  Stream<WorktreeChange> get changes => _changes.stream;
  final _changes = StreamController<WorktreeChange>.broadcast();

  final _subscriptions = <StreamSubscription<String>>[];
  late final _coalescers = {
    for (var kind in WorktreeChange.values)
      kind: Coalescer(
        debounce: debounce,
        minInterval: minInterval,
        now: _now,
        fire: () {
          if (!_changes.isClosed) _changes.add(kind);
        },
      ),
  };

  /// `~/.claude/projects` — the same directory [ClaudeAgentProbe] reads, watched
  /// whole rather than per session, because which file is current changes.
  static String defaultAgentRoot() {
    var home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return p.join(home, '.claude', 'projects');
  }

  /// Begins watching. Idempotent, and **never throws**.
  ///
  /// A directory that is not there, a platform that refuses, a system out of
  /// inotify watches: each of those costs one live signal and nothing else. The
  /// screen still refreshes when it appears and when the button is pressed, so
  /// the failure mode is the behaviour this feature had last week.
  void start() {
    if (_started) return;
    _started = true;

    var git = p.join(repoRoot, '.git');
    // **Nothing at all when this is not a repository.** Discovery falls back to
    // "one worktree, the directory you are in" for a project that is not under
    // git, and there the agent watch would be the only one left: a recursive
    // watch over every agent session on the machine, kept for a list of one
    // entry that nothing can change. It is also what keeps a test that pumps
    // the shell against a fabricated path from watching the developer's home
    // directory.
    if (!Directory(git).existsSync()) return;

    _add('the main checkout', git, recursive: false, kind: WorktreeChange.git);
    _add(
      'linked worktrees',
      p.join(git, 'worktrees'),
      recursive: true,
      kind: WorktreeChange.git,
    );
    _add(
      'branches',
      p.join(git, 'refs', 'heads'),
      // See the class comment: `claude/thing` is a directory here.
      recursive: true,
      kind: WorktreeChange.git,
    );
    _add(
      'agent sessions',
      agentRoot,
      recursive: true,
      kind: WorktreeChange.agent,
    );
    _add(
      'dev stacks',
      runDir ?? flutterwareRunDir(),
      // Flat: the cache files are direct children, and the run dir has
      // subdirectories nothing here cares about.
      recursive: false,
      kind: WorktreeChange.stack,
      accept: (path) => p.basename(path).startsWith('stack-'),
    );
  }

  var _started = false;

  void _add(
    String what,
    String path, {
    required bool recursive,
    required WorktreeChange kind,
    _Accept? accept,
  }) {
    try {
      if (!Directory(path).existsSync()) return;
      _subscriptions.add(
        _watch(path, recursive: recursive).listen(
          (changed) {
            // `index.lock` and `refs/heads/x.lock` are git's own scaffolding
            // and always accompany the real write. Ignoring them halves the
            // events without losing one.
            if (changed.endsWith('.lock')) return;
            if (accept != null && !accept(changed)) return;
            _coalescers[kind]!.poke();
          },
          onError: (Object error) => onFailure?.call(what, error),
          cancelOnError: true,
        ),
      );
    } catch (e) {
      onFailure?.call(what, e);
    }
  }

  Future<void> dispose() async {
    for (var coalescer in _coalescers.values) {
      coalescer.cancel();
    }
    for (var subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    await _changes.close();
  }
}

/// One checkout's **working tree**, watched recursively — the scoped exception
/// to the rule above, and the only reason the changes screen is live.
///
/// [WorktreeWatcher] deliberately watches no working tree at all: fourteen
/// recursive watches is the cost the explorer's design exists to avoid, and a
/// dirty count that is a minute stale is not worth them. The changes screen
/// inverts every term of that trade — **one** checkout, watched only while the
/// screen is on it, and the file an agent just wrote *is* the subject. A screen
/// you have to press refresh on to see what an agent did is one you stop
/// trusting.
///
/// Measured on this repository (2026-08-11), a 2.3 GB checkout, with real
/// `Directory.watch` streams:
///
/// | operation | this watch |
/// |---|---|
/// | write to a file, at any depth | **fires** |
/// | `touch` — mtime only, no write | nothing |
/// | create or delete a file | **fires** |
/// | `git status` | nothing |
/// | `git add`, `git commit` | nothing |
/// | 3,000 files written under `build/` | 9,002 events |
///
/// Three things in that table decide the design:
///
/// - **Arming it is free.** `watch()` returned in 5 ms over 2.3 GB and events
///   arrived immediately: FSEvents does not walk the tree, so "the checkout is
///   huge" is not a reason to hesitate.
/// - **`touch` firing nothing is correct, not a miss.** An mtime that moves
///   without a byte changing does not move the diff either.
/// - **Staging and committing are invisible here**, because a linked
///   worktree's HEAD and index live in `<main>/.git/worktrees/<name>/`. That is
///   *already* watched, repository-wide, by [WorktreeWatcher] — so this class
///   deliberately does not watch git at all, and the screen listens to both.
///   Adding a git watch here would be a second watch on the same directory for
///   the same event.
///
/// `.git` is filtered out, which matters most for the *main* checkout,
/// where it sits inside the tree being watched. `objects/` churns on every
/// fetch, and recursing into it would spend the day reporting packfiles — the
/// same rule, and the same reason, as the class above.
///
/// The cost this does not dodge: 3,000 build outputs are 9,002 events, and
/// nothing here can tell they were all gitignored without asking git. The
/// [minInterval] floor is the only bound there is.
class WorkingTreeWatcher {
  WorkingTreeWatcher({
    required this.worktreePath,
    this.debounce = const Duration(milliseconds: 300),
    this.minInterval = const Duration(seconds: 5),
    WatchDirectory? watch,
    DateTime Function()? now,
    this.onFailure,
  }) : _watch = watch ?? watchDirectoryPaths,
       _now = now ?? DateTime.now;

  final String worktreePath;

  /// How long a burst is allowed to settle. One save is several writes.
  final Duration debounce;

  /// The floor between two fires. See [WorktreeWatcher.minInterval]: an agent
  /// writing continuously never offers a quiet moment, so a debounce alone
  /// would either never fire or fire on every write.
  ///
  /// Longer than the explorer's, because a fire here costs incomparably
  /// more: that one re-reads a small file per worktree, this one spawns an
  /// isolate and half a dozen git subprocesses including the whole `git diff`.
  ///
  /// It is also nearly free to lengthen. After any quiet moment the floor has
  /// already elapsed, so a save still lands in [debounce] — this bounds only
  /// the *continuous* writer, which is the `build/` case it exists for and the
  /// one case where re-probing at speed buys nothing.
  final Duration minInterval;

  final WatchDirectory _watch;
  final DateTime Function() _now;

  /// Told when the watch could not be established. Liveness, never
  /// correctness — the screen still refreshes on arrival and on the button.
  final void Function(Object error)? onFailure;

  Stream<void> get changes => _watcher.changes;

  /// Whether a watch is actually established. False before [start], and after
  /// a [start] that could not — which the screen says out loud, because a live
  /// screen that has silently stopped being live is the failure worth naming.
  bool get isWatching => _watcher.isWatching;

  /// The timing rules and the plumbing are [DirectoryWatch]'s; what belongs to
  /// *this* class is the filter and the floor, which are the two things a
  /// checkout needs and a plain directory does not.
  late final _git = p.join(worktreePath, '.git');
  late final _watcher = DirectoryWatch(
    directory: worktreePath,
    accept: (changed) {
      if (changed == _git || p.isWithin(_git, changed)) return false;
      return !changed.endsWith('.lock');
    },
    debounce: debounce,
    minInterval: minInterval,
    watch: _watch,
    now: _now,
    onFailure: onFailure,
  );

  /// Begins watching. Idempotent, and **never throws** — a checkout that has
  /// been deleted under us, or a system out of watches, costs one live signal
  /// and nothing else.
  void start() => _watcher.start();

  Future<void> dispose() => _watcher.dispose();
}

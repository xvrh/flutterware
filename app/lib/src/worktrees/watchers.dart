/// Makes the explorer live, without a polling timer anywhere.
///
/// **Four directories cover fourteen worktrees.** A linked worktree's HEAD and
/// index are not in the checkout — they live in `<main>/.git/worktrees/<name>/`
/// — so one recursive watch there sees every linked checkout at once. Branches
/// are shared, so one watch on `refs/heads/` sees every commit from anywhere.
///
/// **Verified end to end on a scratch repository (2026-08-10)** — not "which
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
/// - **Editing a file touches nothing at all**, which is the honest gap:
///   dirty counts cannot be event-driven, and watching fourteen working trees
///   recursively is exactly the cost this design exists to avoid. Dirty
///   refreshes on visibility and on demand. It is also the least urgent cell —
///   it changes when *you* type, and you know that you typed.
///
/// **Never `.git` recursively.** `objects/` churns on every fetch, and a watch
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
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// What moved. See the note above on why this is not one signal.
enum WorktreeChange {
  /// A commit, a staging change, a branch switch, or a worktree appearing.
  git,

  /// An agent session file was written.
  agent,
}

/// How a directory is watched: a stream of **paths that changed**, nothing more.
///
/// Injectable, so the timing rules below — the part worth pinning down — can be
/// tested without a filesystem. Paths rather than `FileSystemEvent` for two
/// reasons: it is all this uses (any event means "look again"), and dart:io's
/// event classes have private constructors, so a test could not have made one.
typedef WatchDirectory =
    Stream<String> Function(String path, {required bool recursive});

class WorktreeWatcher {
  WorktreeWatcher({
    required this.repoRoot,
    String? agentRoot,
    this.debounce = const Duration(milliseconds: 300),
    this.minInterval = const Duration(seconds: 2),
    WatchDirectory? watch,
    DateTime Function()? now,
    this.onFailure,
  }) : agentRoot = agentRoot ?? defaultAgentRoot(),
       _watch = watch ?? _watchDirectory,
       _now = now ?? DateTime.now;

  /// The **main** checkout. Every git watch is under its `.git`, including the
  /// state of worktrees that live somewhere else entirely.
  final String repoRoot;

  final String agentRoot;

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
      kind: _Coalescer(
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
  }

  var _started = false;

  void _add(
    String what,
    String path, {
    required bool recursive,
    required WorktreeChange kind,
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

  static Stream<String> _watchDirectory(
    String path, {
    required bool recursive,
  }) => Directory(path).watch(recursive: recursive).map((event) => event.path);
}

/// Debounce with a floor: settles a burst, and never fires faster than
/// [minInterval] however hard it is poked.
class _Coalescer {
  _Coalescer({
    required this.debounce,
    required this.minInterval,
    required this.fire,
    required this.now,
  });

  final Duration debounce;
  final Duration minInterval;
  final void Function() fire;
  final DateTime Function() now;

  var _pending = false;
  Timer? _timer;
  DateTime? _firedAt;

  void poke() {
    _pending = true;
    if (_timer != null) return;

    var wait = debounce;
    if (_firedAt case var at?) {
      var remaining = minInterval - now().difference(at);
      if (remaining > wait) wait = remaining;
    }
    _timer = Timer(wait, () {
      _timer = null;
      if (!_pending) return;
      _pending = false;
      _firedAt = now();
      fire();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

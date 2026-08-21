import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/run_dir.dart';
import '../utils/run_git.dart';

/// The other side of a comparison, on disk.
///
/// A build fixture, not state. It is a `git worktree add --detach` at one
/// commit, shared by every worktree and every comparison on the machine, and
/// it may be deleted at any moment: what survives a comparison is the shot
/// cache, which is content-addressed and does not care where the pictures were
/// rendered from.
///
/// Shared per commit rather than per comparison, which is the whole
/// arithmetic: five agents branched off one master sha have one base between
/// them, it is checked out once, resolved once, and rendered once.
class BaseCheckout {
  const BaseCheckout({
    required this.path,
    required this.sha,
    required this.created,
  });

  /// The checkout's root.
  final String path;

  final String sha;

  /// Whether this call is what put it there. False means it was already on
  /// disk from an earlier comparison — the case worth optimising for, since it
  /// is every comparison after the first against a given base.
  final bool created;

  /// Where base checkouts live, and the reason they are all under one root:
  /// they are real git worktrees, so `git worktree list` reports them and the
  /// explorer would otherwise show a row for each. One known prefix is all it
  /// takes to filter them back out — see [isBasePath].
  static String get defaultRoot => p.join(flutterwareDir(), 'bases');

  /// Whether [path] is a base checkout rather than something a person made.
  ///
  /// Used by the worktree explorer, which lists every worktree git reports:
  /// without this, comparing against master puts a detached checkout named
  /// after a sha in a screen whose whole purpose is *which one was I in*.
  static bool isBasePath(String path, {String? root}) =>
      p.isWithin(root ?? defaultRoot, p.canonicalize(path));

  /// Whether [sha]'s checkout already exists resolved — the marker is written
  /// only after `pub get` succeeded, so this is "reusable", not merely "there".
  ///
  /// A stat, so a panel can say what a run will cost before anything is paid.
  static bool isReady(String sha, {String? cacheRoot}) =>
      File(p.join(cacheRoot ?? defaultRoot, sha, _marker)).existsSync();

  /// The checkout of [sha], creating it if nothing has yet.
  ///
  /// [resolve] is called once per fresh checkout and is where `pub get` goes.
  /// It is a callback rather than a step here because this file knows about
  /// git and nothing else — and because a test should not have to resolve a
  /// package graph to prove that a directory gets reused.
  ///
  /// A [resolve] that throws leaves nothing behind: the checkout is removed,
  /// so the next attempt starts clean rather than finding a directory that
  /// exists but has no `.dart_tool` in it.
  static Future<BaseCheckout> ensure({
    required String repoRoot,
    required String sha,
    required String cacheRoot,
    Future<void> Function(String checkout)? resolve,
  }) async {
    var path = p.join(cacheRoot, sha);
    Directory(cacheRoot).createSync(recursive: true);
    // One creator per sha at a time, across processes — the directory is
    // shared by every worktree on the machine by design, and without the
    // lock a second comparison arriving mid-`resolve` saw a directory with
    // no marker, called it a corpse, and force-removed it out from under the
    // first's `pub get`. The lock lives *beside* the checkout because the
    // recovery path deletes the checkout; blocking is the point: the loser
    // waits out the winner's resolve, then finds the marker and reuses.
    var gate = _inProcess[path] ?? Future<void>.value();
    var done = Completer<void>();
    var turn = gate.then((_) => done.future);
    _inProcess[path] = turn;
    try {
      // The OS lock is advisory *per process* — two ensures inside one GUI
      // would both acquire it — so the in-process queue above serializes
      // those, and the file lock serializes everybody else.
      await gate;
      var lock = File(
        p.join(cacheRoot, '$sha.lock'),
      ).openSync(mode: FileMode.write);
      try {
        await lock.lock(FileLock.blockingExclusive);
        return await _ensureLocked(
          repoRoot: repoRoot,
          sha: sha,
          path: path,
          resolve: resolve,
        );
      } finally {
        // Closing releases the lock.
        lock.closeSync();
      }
    } finally {
      done.complete();
      if (identical(_inProcess[path], turn)) {
        unawaited(_inProcess.remove(path));
      }
    }
  }

  static final _inProcess = <String, Future<void>>{};

  static Future<BaseCheckout> _ensureLocked({
    required String repoRoot,
    required String sha,
    required String path,
    required Future<void> Function(String checkout)? resolve,
  }) async {
    // Checked under the lock: the common case after losing the race is that
    // the winner just wrote it.
    var marker = File(p.join(path, _marker));
    if (marker.existsSync()) {
      return BaseCheckout(path: path, sha: sha, created: false);
    }
    // A directory with no marker is a checkout that died between `worktree
    // add` and `resolve` — half-resolved, and worse than nothing, because
    // every later run would reuse it.
    if (Directory(path).existsSync()) {
      await _remove(repoRoot: repoRoot, path: path);
    }

    var added = await runGit([
      '-C',
      repoRoot,
      'worktree',
      'add',
      '--detach',
      path,
      sha,
    ]);
    if (added.exitCode != 0) {
      // The commonest failure is a registration left behind by a checkout
      // somebody deleted by hand, which makes git refuse a path it still
      // believes in. Pruning costs a stat per registered worktree.
      await runGit(['-C', repoRoot, 'worktree', 'prune']);
      added = await runGit([
        '-C',
        repoRoot,
        'worktree',
        'add',
        '--detach',
        path,
        sha,
      ]);
      if (added.exitCode != 0) {
        throw BaseCheckoutError(
          'could not check out $sha to compare against: ${added.stderr}',
        );
      }
    }

    try {
      await resolve?.call(path);
    } catch (_) {
      await _remove(repoRoot: repoRoot, path: path);
      rethrow;
    }
    // Written last, and that ordering is the whole reliability story: the
    // marker means "checked out *and* resolved", so a run killed anywhere
    // before this line leaves a directory that the next run throws away
    // rather than trusts.
    marker.writeAsStringSync(sha);
    return BaseCheckout(path: path, sha: sha, created: true);
  }

  /// Removes this checkout and its registration.
  ///
  /// Nothing calls this on a schedule yet. It exists because the class is built
  /// on the claim that a base is disposable, and a claim with no way to dispose
  /// cannot be checked.
  Future<void> dispose({required String repoRoot}) =>
      _remove(repoRoot: repoRoot, path: path);

  static Future<void> _remove({
    required String repoRoot,
    required String path,
  }) async {
    var removed = await runGit([
      '-C',
      repoRoot,
      'worktree',
      'remove',
      '--force',
      path,
    ]);
    if (removed.exitCode == 0) return;
    // git refuses a path it never registered, which is exactly the state a
    // half-created checkout is in. The directory still has to go.
    var directory = Directory(path);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    await runGit(['-C', repoRoot, 'worktree', 'prune']);
  }

  /// Named with a leading dot so it cannot be mistaken for the project's own
  /// file, and left out of `.gitignore` deliberately: this checkout is
  /// detached and nobody commits from it.
  static const _marker = '.flutterware-base';
}

class BaseCheckoutError implements Exception {
  BaseCheckoutError(this.message);

  final String message;

  @override
  String toString() => message;
}

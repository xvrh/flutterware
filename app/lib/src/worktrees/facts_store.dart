/// What the explorer remembers between launches.
///
/// **Deliberately not "every fact".** Only two things are worth persisting: an
/// answer that can never change, and an answer that cost a network round trip.
/// Everything else is cheaper to recompute than to invalidate correctly — dirty
/// state is ~25 ms per worktree and an agent probe is a `stat` — and a cache
/// that stores it would spend its life being wrong about it.
///
/// - **Branch diffs** are keyed by `<base sha>..<head sha>`. Two commits have
///   exactly one diff between them, forever, so the entry never needs
///   invalidating — it needs *evicting*, which is a different and much easier
///   problem.
/// - **Pull requests** are keyed by branch and stamped, because there is no
///   cheap key for "has the PR changed" and 890 ms is too long to pay on every
///   glance.
///
/// Lives outside the repository: this is machine state, and a cache written
/// into the checkout would turn up in the dirty count it is there to report.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../utils/run_dir.dart';
import 'facts.dart';

/// One remembered branch diff.
class CachedDiff {
  const CachedDiff({
    required this.shape,
    required this.ahead,
    required this.behind,
  });

  final ChangeShape shape;
  final int ahead;
  final int behind;

  Map<String, Object?> toJson() => {
    'shape': shape.toJson(),
    'ahead': ahead,
    'behind': behind,
  };

  static CachedDiff fromJson(Map<String, Object?> json) => CachedDiff(
    shape: ChangeShape.fromJson(
      (json['shape']! as Map).cast<String, Object?>(),
    ),
    ahead: json['ahead']! as int,
    behind: json['behind']! as int,
  );
}

class WorktreeFactsStore {
  WorktreeFactsStore._(this.file, this._diffs, this._opened);

  /// Opens the store for the repository rooted at [repoRoot].
  ///
  /// **Never throws.** A corrupt or unreadable cache is an empty cache: the
  /// whole point of this file is to save time, and a startup that fails because
  /// its optional cache did not parse would be a strictly worse program than one
  /// with no cache at all.
  ///
  /// [at] overrides where the cache lives — for tests, which must not write into
  /// the developer's real `~/.flutterware` to check that a cache round-trips.
  static WorktreeFactsStore open(String repoRoot, {File? at}) {
    var file = at ?? File(fileFor(repoRoot));
    var diffs = <String, CachedDiff>{};
    var opened = <String, DateTime>{};
    try {
      if (file.existsSync()) {
        var json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        for (var entry in (json['diffs'] as Map? ?? {}).entries) {
          diffs['${entry.key}'] = CachedDiff.fromJson(
            (entry.value as Map).cast<String, Object?>(),
          );
        }
        for (var entry in (json['opened'] as Map? ?? {}).entries) {
          var at = DateTime.tryParse('${entry.value}');
          if (at != null) opened['${entry.key}'] = at;
        }
      }
    } catch (_) {
      // Unreadable, half-written, or written by a future version.
    }
    return WorktreeFactsStore._(file, diffs, opened);
  }

  /// `~/.flutterware/<sha1 of the repo root>/worktrees.json`.
  ///
  /// Hashed rather than spelled out for the same reason the launcher's install
  /// directory is: a path is not a filename, and two checkouts of one project
  /// must not collide.
  static String fileFor(String repoRoot) => p.join(
    flutterwareDir(),
    sha1.convert(utf8.encode(p.canonicalize(repoRoot))).toString(),
    'worktrees.json',
  );

  final File file;
  final Map<String, CachedDiff> _diffs;
  final Map<String, DateTime> _opened;

  static String diffKey(String baseSha, String headSha) => '$baseSha..$headSha';

  CachedDiff? diff(String baseSha, String headSha) =>
      _diffs[diffKey(baseSha, headSha)];

  void putDiff(String baseSha, String headSha, CachedDiff diff) =>
      _diffs[diffKey(baseSha, headSha)] = diff;

  /// When you last opened this worktree in flutterware — one of the clocks
  /// [ActivityFacts] takes the maximum of, and the only one nothing else knows.
  DateTime? openedAt(String worktreePath) => _opened[worktreePath];

  void markOpened(String worktreePath, DateTime at) =>
      _opened[worktreePath] = at;

  /// Drops diffs beyond [keep], oldest-inserted first.
  ///
  /// An entry is never *wrong* — a sha pair has one diff forever — so this is
  /// eviction, not invalidation. Without it the file grows by one entry per
  /// commit per branch and never shrinks.
  void evict({int keep = 500}) {
    if (_diffs.length <= keep) return;
    var excess = _diffs.length - keep;
    for (var key in _diffs.keys.take(excess).toList()) {
      _diffs.remove(key);
    }
  }

  /// **Never throws**, for the same reason [open] does not: failing to write an
  /// optional cache must not fail the command that produced it.
  void save() {
    try {
      evict();
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'diffs': {
            for (var entry in _diffs.entries) entry.key: entry.value.toJson(),
          },
          'opened': {
            for (var entry in _opened.entries)
              entry.key: entry.value.toIso8601String(),
          },
        }),
      );
    } catch (_) {
      // A read-only home, a full disk. The facts are still correct in memory.
    }
  }
}

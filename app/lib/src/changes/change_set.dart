/// One worktree's delta, and the bounds that keep drawing it from freezing a
/// window.
///
/// Pure Dart — `fw` links this.
library;

import 'dart:typed_data';

import 'changes_config_cache.dart';
import 'patch_index.dart';
import 'ranking.dart';

/// The bounds. Every one is checked **before** the work it bounds, and every
/// one is visible when it bites: a screen that quietly drops files is worse
/// than one that refuses, because you cannot tell which it did.
class ChangesLimits {
  /// Past this the patch is not indexed at all and the file list comes from
  /// `--numstat` instead.
  ///
  /// 3.6 MB was the worst case reachable in this repository, so this is not a
  /// tuned number — it is chosen to be obviously above anything real, so that
  /// hitting it means something is *wrong* rather than something is big.
  static const wholePatchBytes = 64 * 1024 * 1024;

  /// Past this a file is listed and counted but not expandable.
  static const filePatchBytes = 512 * 1024;
}

/// Where the base came from. The header shows this, because the one thing
/// worse than no base is the wrong one presented as fact.
enum BaseSource {
  /// `origin/HEAD`, then `main`, then `master`.
  inferred,

  /// Named by the project's `ChangesConfig`.
  configured,

  /// None of the above resolved. Nothing is diffed against a guess.
  none,
}

/// Why the patch was not indexed.
class ChangesRefusal {
  const ChangesRefusal({required this.patchBytes});

  final int patchBytes;

  @override
  String toString() =>
      'the diff is ${(patchBytes / (1024 * 1024)).toStringAsFixed(1)} MB, past '
      'the ${ChangesLimits.wholePatchBytes ~/ (1024 * 1024)} MB the viewer '
      'will index. Showing the file list only.';
}

/// An untracked path, exactly as git reported it.
///
/// **A directory is one entry and is never walked.** git's default untracked
/// mode reports the topmost wholly-untracked directory and stops there, which
/// is what keeps a stray `build/` — 30,000 files, and un-ignored the moment you
/// switch to a branch whose `.gitignore` does not cover it — from becoming
/// 30,000 rows. Nothing here counts what is inside: counting *is* the walk
/// being avoided.
class UntrackedEntry {
  const UntrackedEntry(this.path, {this.reason}) : isDirectory = false;
  const UntrackedEntry.directory(this.path) : isDirectory = true, reason = null;

  final String path;
  final bool isDirectory;

  /// The attention rule that pinned this path, or null. Never set for a
  /// directory — see `attentionForUntracked`.
  final String? reason;

  bool get isPinned => reason != null;

  UntrackedEntry withReason(String? reason) =>
      isDirectory ? this : UntrackedEntry(path, reason: reason);

  Map<String, Object?> toJson() => {
    'path': path,
    if (isDirectory) 'directory': true,
    'why': ?reason,
  };
}

/// Everything the changes screen and `fw changes` read.
class ChangeSet {
  const ChangeSet({
    required this.worktreePath,
    required this.patch,
    required this.base,
    required this.baseSource,
    this.mergeBase,
    this.head,
    this.uncommitted = const {},
    this.untracked = const [],
    this.refusal,
    this.files,
    Ranking? ranking,
    this.configState = ChangesConfigState.none,
    this.attentionConfigured = false,
    // ignore: prefer_initializing_formals
  }) : _ranking = ranking;

  final String worktreePath;

  /// The branch the delta is measured from, or null when none resolved.
  final String? base;
  final BaseSource baseSource;

  /// The commit the delta starts at — `merge-base(base, HEAD)`.
  final String? mergeBase;
  final String? head;

  /// The patch, indexed. [PatchIndex.empty] when [refusal] is set, or when
  /// there is nothing to compare against.
  final PatchIndex patch;

  /// Overrides [PatchIndex.files] when the patch was refused and the list came
  /// from `--numstat` instead. Null in the normal case.
  final List<FileChange>? files;

  /// Paths whose delta is **not all committed**. An attribute of a file, not a
  /// mode — an agent's most interesting work is the work it has not committed.
  final Set<String> uncommitted;

  final List<UntrackedEntry> untracked;

  final ChangesRefusal? refusal;

  /// How much the ranking rules are worth believing. Only [ChangesConfigState]
  /// `.stale` says anything on screen.
  final ChangesConfigState configState;

  /// Whether the project declared any `attention:` globs at all.
  ///
  /// **Distinct from "nothing was pinned".** There are no built-in attention
  /// rules — flutterware cannot know what matters in somebody else's
  /// repository — so a project that has never written any gets an empty
  /// *Important* tab and no explanation, which reads as a feature that does not
  /// work. This is what lets that tab say how to write one. A project that
  /// *has* rules and matched none of them is told only that: two silences, and
  /// telling them apart is the whole reason this field exists.
  final bool attentionConfigured;

  final Ranking? _ranking;

  /// Which files are worth looking at first, and why.
  ///
  /// Computed by the probe, on the isolate that already did the reading rather
  /// than on the one that has to paint at 60 Hz.
  ///
  /// **Every file is in here, in one tier or another.** A ranking that can lose
  /// a file is a ranking nobody can trust.
  Ranking get ranking =>
      _ranking ??
      Ranking([
        for (var file in changed)
          RankedFile(file: file, tier: RankTier.ordinary),
      ]);

  List<FileChange> get changed => files ?? patch.files;

  int get added => changed.fold(0, (sum, f) => sum + f.added);
  int get removed => changed.fold(0, (sum, f) => sum + f.removed);

  bool get isEmpty => changed.isEmpty && untracked.isEmpty;

  /// Largest first, with **deletions promoted**: `D −88` is the line most worth
  /// seeing and a plain churn sort buries it under three larger edits.
  List<FileChange> get ranked => [...changed]..sort(_byWeight);

  /// One tier's files, in the same order.
  ///
  /// Ordering is per tier rather than across the list, because the tiers are
  /// drawn separately — the pinned files are their own tab, and a 900-line
  /// file has no business leading it on size alone.
  List<RankedFile> ordered(RankTier tier) => [
    for (var it in ranking.files)
      if (it.tier == tier) it,
  ]..sort((a, b) => _byWeight(a.file, b.file));

  static int _byWeight(FileChange a, FileChange b) {
    var byKind = _rank(b.status).compareTo(_rank(a.status));
    return byKind != 0 ? byKind : b.lines.compareTo(a.lines);
  }

  static int _rank(ChangeStatus status) =>
      status == ChangeStatus.deleted ? 1 : 0;

  /// Whether [other] would draw the same screen.
  ///
  /// **Deliberately not `==`.** A [ChangeSet] is not a value — it carries half
  /// a megabyte of patch and a lazily decoded view of it — and nothing wants it
  /// as a map key. This asks the one question the live screen has: *did the
  /// answer move?* The live watcher re-probes every time an agent saves, and
  /// most of those saves land in a `build/` directory git ignores, so most
  /// re-probes produce this exact set again. Keeping the previous object then
  /// means the decoded text of every expanded hunk survives, and the screen
  /// does not rebuild at all.
  ///
  /// **The patch bytes are compared, in full.** Measured on this machine: 188 µs
  /// for the 473 KB of a 53-file branch, which is a ninth of a frame, at most
  /// once every two seconds. Hashing it in the isolate would be faster and
  /// would put a digest nobody else wants into the model.
  ///
  /// Equal bytes make [changed] equal by construction — the file list is
  /// indexed *from* them — so only what is not derived from the patch is
  /// compared beside it. [files] is the exception: when the patch was refused
  /// that list came from `--numstat` instead, and the bytes are empty.
  bool sameAnswerAs(ChangeSet other) {
    if (identical(this, other)) return true;
    if (worktreePath != other.worktreePath ||
        base != other.base ||
        baseSource != other.baseSource ||
        mergeBase != other.mergeBase ||
        head != other.head ||
        configState != other.configState ||
        refusal?.patchBytes != other.refusal?.patchBytes) {
      return false;
    }
    if (uncommitted.length != other.uncommitted.length ||
        !uncommitted.containsAll(other.uncommitted)) {
      return false;
    }
    if (untracked.length != other.untracked.length) return false;
    for (var i = 0; i < untracked.length; i++) {
      var a = untracked[i], b = other.untracked[i];
      if (a.path != b.path ||
          a.isDirectory != b.isDirectory ||
          a.reason != b.reason) {
        return false;
      }
    }
    if (!_sameBytes(patch.bytes, other.patch.bytes)) return false;
    // Only reachable when the patch was refused; otherwise this is the same
    // list read twice.
    if (files != null || other.files != null) {
      var mine = changed, theirs = other.changed;
      if (mine.length != theirs.length) return false;
      for (var i = 0; i < mine.length; i++) {
        if (mine[i].path != theirs[i].path ||
            mine[i].status != theirs[i].status ||
            mine[i].added != theirs[i].added ||
            mine[i].removed != theirs[i].removed) {
          return false;
        }
      }
    }
    // The ranking is not derived from the patch: the rules live in a config
    // outside the checkout, so a set that is otherwise identical can be ranked
    // differently by the time it is read again.
    var mine = ranking.files, theirs = other.ranking.files;
    if (mine.length != theirs.length) return false;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i].file.path != theirs[i].file.path ||
          mine[i].tier != theirs[i].tier ||
          mine[i].reason != theirs[i].reason) {
        return false;
      }
    }
    return true;
  }

  /// Which paths read differently here than in [previous].
  ///
  /// **What an agent is doing right now**, and it costs nothing extra: the live
  /// screen already compares every re-probe against the last one to decide
  /// whether to redraw, so the paths that moved fall out of the same pass.
  ///
  /// A file's own patch bytes are compared, not its counts — an edit that swaps
  /// one line for another of the same length moves neither `+n` nor `−n`, and
  /// is exactly the sort of thing you want to have noticed.
  Set<String> movedFrom(ChangeSet previous) {
    var before = {for (var file in previous.changed) file.path: file};
    var moved = <String>{};
    for (var file in changed) {
      var was = before.remove(file.path);
      if (was == null ||
          was.status != file.status ||
          was.added != file.added ||
          was.removed != file.removed ||
          !_sameSlice(previous.patch, was, patch, file)) {
        moved.add(file.path);
      }
    }
    // A file that left the delta has moved too, though nothing on screen can
    // hold it — the caller keeps a session-long set and this stops it lying.
    moved.addAll(before.keys);

    var untrackedNow = {for (var entry in untracked) entry.path};
    var untrackedWas = {for (var entry in previous.untracked) entry.path};
    moved
      ..addAll(untrackedNow.difference(untrackedWas))
      ..addAll(untrackedWas.difference(untrackedNow));
    return moved;
  }

  static bool _sameSlice(
    PatchIndex a,
    FileChange fa,
    PatchIndex b,
    FileChange fb,
  ) {
    var lengthA = fa.byteEnd - fa.byteStart;
    if (lengthA != fb.byteEnd - fb.byteStart) return false;
    for (var i = 0; i < lengthA; i++) {
      if (a.bytes[fa.byteStart + i] != b.bytes[fb.byteStart + i]) return false;
    }
    return true;
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
    'worktree': worktreePath,
    'base': base,
    'baseSource': baseSource.name,
    'mergeBase': ?mergeBase,
    'head': ?head,
    'files': changed.length,
    'added': added,
    'removed': removed,
    'refused': ?refusal?.toString(),
    if (configState == ChangesConfigState.stale) 'configStale': true,
    'changed': [
      for (var file in changed)
        {
          'path': file.path,
          'from': ?file.oldPath,
          'status': file.status.name,
          'added': file.added,
          'removed': file.removed,
          if (file.isBinary) 'binary': true,
          if (uncommitted.contains(file.path)) 'uncommitted': true,
          if (file.patchBytes > ChangesLimits.filePatchBytes)
            'tooLargeToExpand': true,
          if (ranking.forPath(file.path) case var it?
              when it.tier != RankTier.ordinary) ...{
            'tier': it.tier.name,
            'why': ?it.reason,
          },
          'hunks': [
            for (var hunk in file.hunks)
              {
                'oldStart': hunk.oldStart,
                'oldCount': hunk.oldCount,
                'newStart': hunk.newStart,
                'newCount': hunk.newCount,
                'added': hunk.added,
                'removed': hunk.removed,
                'context': ?hunk.context,
              },
          ],
        },
    ],
    'untracked': [for (var entry in untracked) entry.toJson()],
  };
}

/// One worktree's delta, and the bounds that keep drawing it from freezing a
/// window.
///
/// Pure Dart — `fw` links this.
library;

// The byte comparison the scenario captures also use — one implementation,
// shared through the package the app already builds on.
// ignore: implementation_imports
import 'package:flutterware/src/bytes.dart';

import 'changes_config_cache.dart';
import 'patch_index.dart';
import 'ranking.dart';

/// The bounds. Every one is checked *before* the work it bounds, and every
/// one is visible when it bites: a screen that quietly drops files is worse
/// than one that refuses, because you cannot tell which it did.
class ChangesLimits {
  /// Past this a file is listed and counted but not expandable.
  static const filePatchBytes = 512 * 1024;

  /// Past this a file's own text — rendered markdown, an untracked file's
  /// lines — is not read for the viewer. The same order of magnitude as
  /// [filePatchBytes], because it bounds the same thing: how much becomes
  /// Dart strings for one screen.
  static const textContentBytes = 512 * 1024;

  /// Past this an image is not decoded for the viewer. Far looser than the
  /// text bound — image bytes never become strings, and a 4 MB screenshot is
  /// an ordinary asset — but a bound all the same, because decode memory is
  /// width × height and nothing else on this screen scales with it.
  static const imageContentBytes = 20 * 1024 * 1024;
}

/// Where the base came from. The header shows this, because the one thing
/// worse than no base is the wrong one presented as fact.
enum BaseSource {
  /// `origin/HEAD`, then `main`, then `master`.
  inferred,

  /// Named by the project's `ChangesConfig`.
  configured,

  /// None of the above resolved. Nothing is diffed against an unresolved
  /// base.
  none,
}

/// An untracked path, exactly as git reported it.
///
/// A directory is one entry and is never walked. git's default untracked
/// mode reports the topmost wholly-untracked directory and stops there, which
/// is what keeps a stray `build/` — 30,000 files, and un-ignored the moment you
/// switch to a branch whose `.gitignore` does not cover it — from becoming
/// 30,000 rows. Nothing here counts what is inside: counting *is* the walk
/// being avoided.
class UntrackedEntry {
  const UntrackedEntry(this.path, {this.reason, this.stamp})
    : isDirectory = false;
  const UntrackedEntry.directory(this.path)
    : isDirectory = true,
      reason = null,
      stamp = null;

  final String path;
  final bool isDirectory;

  /// The attention rule that pinned this path, or null. Never set for a
  /// directory — see `attentionForUntracked`.
  final String? reason;

  /// What a stat knows about this file's content — see [untrackedStamp].
  ///
  /// Null for a directory, which is never stat'ed, and for a file that was
  /// gone by the time the probe reached it.
  final String? stamp;

  bool get isPinned => reason != null;

  UntrackedEntry withReason(String? reason) =>
      isDirectory ? this : UntrackedEntry(path, reason: reason, stamp: stamp);

  UntrackedEntry withStamp(String? stamp) =>
      isDirectory ? this : UntrackedEntry(path, reason: reason, stamp: stamp);

  Map<String, Object?> toJson() => {
    'path': path,
    if (isDirectory) 'directory': true,
    'why': ?reason,
  };
}

/// What a stat knows about an untracked file's content, as a fingerprint.
///
/// **A stat, never a read.** An untracked file's bytes are on disk rather than
/// in the patch, and reading every one of them on every probe is precisely the
/// read this whole design refuses. Size and the microsecond of the last write
/// is what is affordable, and it is the same pair `FileContentStore` already
/// treats as the identity of those bytes — so *is this the same file* and *did
/// it move since I commented* answer to one fact rather than to two.
///
/// What it claims is therefore *this file was written since*, not *its bytes
/// differ*. That is the same grade of claim the tracked side makes: a digest
/// over a file's slice of the patch moves when any part of the file moves,
/// whether or not the commented lines did. See [ReviewComment.fileDigest].
///
/// **Tagged**, and the tag is load-bearing. This is compared against a sha1 of
/// a patch slice for the same path the moment that path is staged, and *the
/// file became tracked* is not *the file changed* — so the two kinds are
/// recognisable, and [sameDigestKind] is what stops a `git add` from lighting
/// up every note on a new file.
String untrackedStamp({required int size, required DateTime modified}) =>
    '$_diskPrefix$size:${modified.microsecondsSinceEpoch}';

/// Whether two fingerprints are of the same kind, and so comparable at all.
///
/// Different kinds mean the path crossed between untracked and tracked, which
/// is a change of *what git knows*, not of the file. Nothing is claimed.
bool sameDigestKind(String a, String b) =>
    a.startsWith(_diskPrefix) == b.startsWith(_diskPrefix);

const _diskPrefix = 'disk:';

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

  /// The patch, indexed. [PatchIndex.empty] when there is nothing to compare
  /// against.
  final PatchIndex patch;

  /// Overrides [PatchIndex.files]. Null in the normal case, where the list is
  /// indexed from the patch bytes — set only by tests, which describe a delta
  /// without authoring a patch to index.
  final List<FileChange>? files;

  /// Paths whose delta is **not all committed**. An attribute of a file, not a
  /// mode — an agent's most interesting work is the work it has not committed.
  final Set<String> uncommitted;

  final List<UntrackedEntry> untracked;

  /// How much the ranking rules are worth believing. Only [ChangesConfigState]
  /// `.stale` says anything on screen.
  final ChangesConfigState configState;

  /// Whether the project declared any `attention:` globs at all.
  ///
  /// Distinct from "nothing was pinned". There are no built-in attention rules
  /// — flutterware cannot know what matters in a given repository — so a
  /// project that has never written any gets an empty *Important* tab and no
  /// explanation, which reads as a feature that does not work. This is what
  /// lets that tab say how to write one. A project that *has* rules and matched
  /// none of them is told only that: telling those two silences apart is why
  /// this field exists.
  final bool attentionConfigured;

  final Ranking? _ranking;

  /// Which files are worth looking at first, and why.
  ///
  /// Computed by the probe, on the isolate that already did the reading rather
  /// than on the one that has to paint at 60 Hz.
  ///
  /// Every file is in here, in one tier or another. A ranking that can lose a
  /// file cannot be trusted.
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
  /// Deliberately not `==`. A [ChangeSet] is not a value — it carries half
  /// a megabyte of patch and a lazily decoded view of it — and nothing wants it
  /// as a map key. This asks the one question the live screen has: *did the
  /// answer move?* The live watcher re-probes every time an agent saves, and
  /// most of those saves land in a `build/` directory git ignores, so most
  /// re-probes produce this exact set again. Keeping the previous object then
  /// means the decoded text of every expanded hunk survives, and the screen
  /// does not rebuild at all.
  ///
  /// The patch bytes are compared, in full. Measured on this machine: 188 µs
  /// for the 473 KB of a 53-file branch, which is a ninth of a frame, at most
  /// once every two seconds. Hashing it in the isolate would be faster and
  /// would put a digest nothing else needs into the model.
  ///
  /// Equal bytes make [changed] equal by construction — the file list is
  /// indexed *from* them — so only what is not derived from the patch is
  /// compared beside it. [files] is the exception: when it is injected the
  /// bytes are empty.
  bool sameAnswerAs(ChangeSet other) {
    if (identical(this, other)) return true;
    if (worktreePath != other.worktreePath ||
        base != other.base ||
        baseSource != other.baseSource ||
        mergeBase != other.mergeBase ||
        head != other.head ||
        configState != other.configState) {
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
          a.reason != b.reason ||
          // **The stamp is compared, so an in-place overwrite is an answer
          // that moved.** It used to not be: rewriting an untracked file
          // changes neither the patch bytes nor the list of paths, so this said
          // *nothing happened* and the screen kept the previous set. The bodies
          // survived on `readAt` alone, and anything reading the set itself —
          // the drift a note claims — could not see the write at all.
          a.stamp != b.stamp) {
        return false;
      }
    }
    if (!sameBytes(patch.bytes, other.patch.bytes)) return false;
    // Only reachable when [files] was injected; otherwise this is the same
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

  Map<String, Object?> toJson() => {
    'worktree': worktreePath,
    'base': base,
    'baseSource': baseSource.name,
    'mergeBase': ?mergeBase,
    'head': ?head,
    'files': changed.length,
    'added': added,
    'removed': removed,
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

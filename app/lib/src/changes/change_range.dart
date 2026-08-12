/// Which part of the branch's history the screen is showing.
///
/// **A range, never a set**, and the whole design is in that word. git hands
/// you a diff between *two trees*; every contiguous run of commits is two
/// trees, and a selection with a gap in it is none — "c1 and c3, not c2" can
/// only be a *composed* patch, in which a file both touched appears twice and
/// the hunk headers name lines in a tree nobody is looking at. So the picker
/// takes one row or one run, and every state it can reach is a real
/// `git diff`. See
/// `docs/superpowers/specs/2026-08-12-changes-v2-range-and-highlighting.md`.
///
/// Pure Dart — `fw` links this, and the arithmetic below deserves tests that
/// need no repository.
library;

/// One commit between the base and HEAD.
///
/// Read with `--first-parent`, which is what makes [ChangeRange] arithmetic
/// sound: the left side of a run is *the row below its oldest commit*, and that
/// is only well defined for a linear list. A branch that merged something in is
/// still a line of its own commits, which is what a person means by "the
/// commits on this branch"; the merged-in branch's own commits are not it.
class CommitEntry {
  const CommitEntry({
    required this.sha,
    required this.shortSha,
    required this.subject,
    required this.author,
    this.at,
  });

  final String sha;
  final String shortSha;
  final String subject;
  final String author;

  /// Committer date, or null when git handed back something unparseable.
  final DateTime? at;

  Map<String, Object?> toJson() => {
    'sha': sha,
    'short': shortSha,
    'subject': subject,
    'author': author,
    'at': ?at?.toIso8601String(),
  };
}

/// A contiguous run of `[merge-base, cₙ … c₁, working tree]`.
///
/// [from] is **exclusive** and [to] is **inclusive**, which is exactly what
/// `git diff <from> <to>` means, so nothing here has to translate. The two
/// nulls are the two ends of the history and are what make [everything] the
/// same object as "no range picked yet":
///
/// | from | to | what it shows | the call |
/// | --- | --- | --- | --- |
/// | null | null | everything (the v1 delta) | `git diff <merge-base>` |
/// | `HEAD` | null | uncommitted work only | `git diff HEAD` |
/// | `c₂` | null | c₃…HEAD and the working tree | `git diff c₂` |
/// | `c₁` | `c₄` | c₂…c₄ | `git diff c₁ c₄` |
/// | `c₂` | `c₃` | c₃ alone | `git diff c₂ c₃` |
///
/// The last row is what makes a radio enough: **a single commit is a range of
/// one**, so there is nothing a set could express that this cannot, except the
/// selection git has no answer for.
class ChangeRange {
  const ChangeRange({this.from, this.to});

  /// The commit **before** the first one in the range. Null means the merge
  /// base — the left edge of the whole delta.
  final String? from;

  /// The last commit in the range. Null means the working tree, and so
  /// includes every commit after [from] as well as the uncommitted work.
  final String? to;

  /// The v1 delta: merge-base to the files on disk.
  static const everything = ChangeRange();

  bool get isEverything => from == null && to == null;

  /// Whether the right edge is the working tree.
  ///
  /// **Four things on the screen turn on this**, and each of them is a claim
  /// that stops being true when it is false: untracked files are in no commit,
  /// the `uncommitted` badge is a comparison against `HEAD`, a file watch
  /// cannot move a range of frozen commits, and the diff describes files as
  /// they *were* rather than as they are.
  bool get endsAtWorkingTree => to == null;

  /// What `git diff` is given, with [mergeBase] standing in for the left edge.
  ///
  /// Null when there is nothing to diff against at all — a repository with no
  /// commit — which the caller reports rather than papers over.
  List<String>? argumentsFrom(String? mergeBase) {
    var left = from ?? mergeBase;
    if (left == null) return null;
    return [left, ?to];
  }

  /// The range as the address writes it, and back.
  ///
  /// Only the two shas, because everything else about a range is derived from
  /// the commit list the probe reads anyway. [everything] writes nothing, which
  /// is what keeps the default address the one it has always been.
  Map<String, String> toParams() => {'from': ?from, 'to': ?to};

  static ChangeRange fromParams(Map<String, String> params) =>
      ChangeRange(from: params['from'], to: params['to']);

  @override
  bool operator ==(Object other) =>
      other is ChangeRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => isEverything
      ? 'ChangeRange.everything'
      : 'ChangeRange(${from ?? 'merge-base'}…${to ?? 'working tree'})';
}

/// The commits [range] covers, out of [commits] (newest first).
///
/// Empty for a range that is only the working tree. **Not the same as "what
/// changed"** — it is what the picker has ticked, which is what a label has to
/// name.
List<CommitEntry> commitsIn(ChangeRange range, List<CommitEntry> commits) {
  var start = range.to == null
      ? 0
      : commits.indexWhere((c) => c.sha == range.to);
  // A `to` that names nothing in the list — a stale address, a rebased branch
  // — covers nothing rather than everything. Silently widening a range that
  // was written down narrower is the one direction that misleads.
  if (start < 0) return const [];
  var end = range.from == null
      ? commits.length
      : commits.indexWhere((c) => c.sha == range.from);
  if (end < 0) end = commits.length;
  return commits.sublist(start, end);
}

/// The range covering exactly [commit], out of [commits] (newest first).
///
/// The left side is the row below it, or the merge base when it is the oldest
/// — which is the one piece of arithmetic the picker does, and the reason the
/// list is read `--first-parent`.
ChangeRange rangeOf(CommitEntry commit, List<CommitEntry> commits) {
  var at = commits.indexWhere((c) => c.sha == commit.sha);
  if (at < 0) return ChangeRange.everything;
  return ChangeRange(
    from: at + 1 < commits.length ? commits[at + 1].sha : null,
    to: commit.sha,
  );
}

/// The range spanning [a] through [b], whichever way round they were clicked.
///
/// Either may be the working tree, spelled as a null commit — which is what
/// makes *since this commit* a shift-click onto the top row rather than a
/// second control.
ChangeRange rangeBetween(
  CommitEntry? a,
  CommitEntry? b,
  List<CommitEntry> commits,
) {
  if (a == null && b == null) {
    // Both ends are the working tree: uncommitted work alone.
    return ChangeRange(from: commits.isEmpty ? null : _head(commits));
  }
  if (a == null || b == null) {
    var commit = a ?? b!;
    var at = commits.indexWhere((c) => c.sha == commit.sha);
    if (at < 0) return ChangeRange.everything;
    return ChangeRange(
      from: at + 1 < commits.length ? commits[at + 1].sha : null,
    );
  }
  var first = commits.indexWhere((c) => c.sha == a.sha);
  var second = commits.indexWhere((c) => c.sha == b.sha);
  if (first < 0 || second < 0) return ChangeRange.everything;
  var newest = first < second ? first : second;
  var oldest = first < second ? second : first;
  return ChangeRange(
    from: oldest + 1 < commits.length ? commits[oldest + 1].sha : null,
    to: commits[newest].sha,
  );
}

String _head(List<CommitEntry> commits) => commits.first.sha;

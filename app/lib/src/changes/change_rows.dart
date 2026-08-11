/// The screen's two lists, each flattened to one row per drawable line.
///
/// **An index and a body, never one list doing both.** They used to be the
/// same list: file rows that expanded to inject their own diff between
/// themselves and the next file. That made the thing you navigate with and the
/// thing you read the same surface, and every complaint about this screen came
/// out of it — clicking a name scrolled instead of opening, a live re-index
/// moved the lines you were reading, and getting to the next file meant
/// scrolling through the last one's diff.
///
/// So [buildImportantRows] and [buildUntrackedRows] are the left column's two
/// flat lists and [buildFileRows] is the right pane. The body stays flat and
/// virtualised for the same reason as before: a file is thousands of diff
/// lines, and only a flat list stays smooth at that size — which needs every
/// row addressable by index without building the ones above it.
///
/// What makes that affordable is [HunkSpan.displayLines]: a hunk's header says
/// how many lines it will draw, so the row list is built from **metadata
/// alone** and the patch text is decoded only for the hunks actually on screen.
/// Scroll extents are therefore right before anything is read, and expanding a
/// file does not make the scrollbar jump as its content arrives.
///
/// Pure Dart — no widgets here, so the flattening is testable without pumping.
library;

import 'change_set.dart';
import 'patch_index.dart';
import 'ranking.dart';

/// One drawable row.
sealed class ChangeRow {
  const ChangeRow();
}

/// A heading. One survives: `Untracked`, at the foot of the *All* tab. The
/// others became tab labels, and a tab label carries its own count.
final class SectionRow extends ChangeRow {
  const SectionRow(this.label);

  final String label;
}

/// A file's own row in the index: status, name, counts, ruler.
final class FileRow extends ChangeRow {
  const FileRow(
    this.file, {
    required this.selected,
    required this.uncommitted,
    this.reason,
  });

  final FileChange file;

  /// Whether this is the file the right pane is showing.
  final bool selected;
  final bool uncommitted;

  /// The rule that pinned or demoted this file, in the words it was written
  /// in. Null for the ordinary case, which is most files.
  final String? reason;
}

/// The `@@` line of an expanded hunk, plus the context git guessed.
final class HunkRow extends ChangeRow {
  const HunkRow(this.file, this.hunk);

  final FileChange file;
  final HunkSpan hunk;
}

/// One line of a hunk, addressed by its position **within that hunk** so the
/// text can be decoded lazily and thrown away on collapse.
final class DiffLineRow extends ChangeRow {
  const DiffLineRow(this.file, this.hunk, this.index);

  final FileChange file;
  final HunkSpan hunk;

  /// Zero-based, counting only the lines this hunk draws.
  final int index;
}

/// Why a file's body is not shown even though it is expanded.
final class FileNoticeRow extends ChangeRow {
  const FileNoticeRow(this.file, this.message);

  final FileChange file;
  final String message;
}

/// An untracked path, exactly as git reported it.
final class UntrackedRow extends ChangeRow {
  const UntrackedRow(this.entry, {this.selected = false});
  final UntrackedEntry entry;
  final bool selected;
}

/// The **Important** tab: every file a rule pinned, flat and all of it open.
///
/// **Two tabs, not a band above a tree.** The band was tried and rejected in
/// use: it made the top of the index a place where the ranking's answer and the
/// directory structure argued for the same column, and it was still there
/// taking space on the branches where it said nothing. A tab hides the alert
/// half the time — that is the real cost, and it is paid back by the tab
/// *label*, which carries the count and so says there is something to look at
/// without being opened.
///
/// No headings in here. The tab is the heading, and there is only one kind of
/// row, which is the point: this is the short list, in rank order, and it never
/// collapses anything.
///
/// [visible] is null when nothing is filtering.
List<ChangeRow> buildImportantRows(
  ChangeSet set, {
  String? selected,
  Set<String>? visible,
}) {
  var rows = <ChangeRow>[];

  for (var ranked in set.ordered(RankTier.attention)) {
    if (visible != null && !visible.contains(ranked.file.path)) continue;
    rows.add(
      FileRow(
        ranked.file,
        selected: ranked.file.path == selected,
        uncommitted: set.uncommitted.contains(ranked.file.path),
        reason: ranked.reason,
      ),
    );
  }

  // An untracked file that matched a rule belongs here even though it has no
  // diff — see `attentionForUntracked`. The motivating case is a file an agent
  // wrote thirty seconds ago and has not staged, which is exactly the thing
  // this tab exists to surface.
  for (var entry in set.untracked) {
    if (!entry.isPinned) continue;
    if (visible != null && !visible.contains(entry.path)) continue;
    rows.add(UntrackedRow(entry, selected: entry.path == selected));
  }

  return rows;
}

/// The **All** tab's flat tail: the untracked paths, under one heading.
///
/// Everything tracked is in the tree above it — see [treeFiles]. Untracked
/// entries cannot join it: git reports the topmost wholly-untracked *directory*
/// and does not descend, so `build/` is one entry standing for a subtree nobody
/// has walked, and folding that into a directory tree would claim a shape that
/// was never read.
///
/// **Pinned ones are listed here too.** All means all: a tab that quietly drops
/// the four files the other tab is about is a tab whose count disagrees with
/// the header, which is the same bug the tree had when pins were held out of it.
List<ChangeRow> buildUntrackedRows(
  ChangeSet set, {
  String? selected,
  Set<String>? visible,
}) {
  var kept = [
    for (var entry in set.untracked)
      if (visible == null || visible.contains(entry.path)) entry,
  ];
  if (kept.isEmpty) return const [];
  return [
    const SectionRow('Untracked'),
    for (var entry in kept)
      UntrackedRow(entry, selected: entry.path == selected),
  ];
}

/// The files the **tree** holds: every one of them.
///
/// **Pinned files are in here too**, which they were not at first. Leaving them
/// out to avoid "listing a file twice" made the tree an *incomplete map*: its
/// directory counts came out one short for every pin, so the header said 53
/// files over a tree that totalled 52, and browsing to `CLAUDE.md` could not
/// find it. A quietly wrong count is worse than a repetition.
///
/// The Important tab is a **view onto** this tree, not a removal from it — the
/// way a problems panel lists files that are also in the file explorer. The
/// tree marks a pinned file where it lives.
/// **Every tier, in tier order** — `RankTier.values` rather than a list spelled
/// out here, which is what it used to be when one of the three was held back.
/// A hand-written enumeration is how a tier added later goes missing from the
/// tree, and a tree that can lose a file is what this whole file argues against.
List<FileChange> treeFiles(ChangeSet set, {Set<String>? visible}) => [
  for (var tier in RankTier.values)
    for (var ranked in set.ordered(tier))
      if (visible == null || visible.contains(ranked.file.path)) ranked.file,
];

/// The **body**: one file's diff, and nothing else.
///
/// Every reason a body is withheld says so in place. A file that opens to
/// nothing, with no explanation, reads as a bug in the viewer.
List<ChangeRow> buildFileRows(FileChange file) {
  if (file.isBinary) {
    return [FileNoticeRow(file, 'Binary file — no lines to show.')];
  }
  if (file.patchBytes > ChangesLimits.filePatchBytes) {
    return [
      FileNoticeRow(
        file,
        "This file's diff is ${(file.patchBytes / 1024).round()} KB — past "
        'what the viewer expands. Open it in your editor.',
      ),
    ];
  }
  if (file.hunks.isEmpty) {
    return [
      FileNoticeRow(file, 'No text changed — only the path or the mode.'),
    ];
  }
  return [
    for (var hunk in file.hunks) ...[
      HunkRow(file, hunk),
      for (var i = 0; i < hunk.displayLines; i++) DiffLineRow(file, hunk, i),
    ],
  ];
}

/// Paths containing [query], case-insensitively.
///
/// A substring rather than a glob: the box is for *finding* a file among fifty,
/// not for expressing a rule. Rules live in `tool/flutterware.dart` and get to
/// be globs there, where they are written once and read by a parser.
///
/// Takes paths rather than [FileChange]s so an **untracked** entry can be
/// found too. It could not be, which meant typing `scratch` hid the very file
/// you were looking for.
Set<String> pathsMatching(Iterable<String> paths, String query) {
  var needle = query.trim().toLowerCase();
  if (needle.isEmpty) return paths.toSet();
  return {
    for (var path in paths)
      if (path.toLowerCase().contains(needle)) path,
  };
}

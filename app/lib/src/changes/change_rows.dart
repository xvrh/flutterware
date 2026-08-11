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
/// So [buildIndexRows] is the left column and [buildFileRows] is the right
/// pane. Both stay flat and virtualised for the same reason as before: a file
/// is thousands of diff lines, and only a flat list stays smooth at that size —
/// which needs every row addressable by index without building the ones above
/// it.
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

/// A heading — `Look here first`, `Changes`, `Untracked`.
final class SectionRow extends ChangeRow {
  const SectionRow(this.label, {this.detail});

  final String label;

  /// The counts that belong to this section, or null.
  final String? detail;
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

/// The index's **flat parts**: what is pinned, what is noise, what is
/// untracked. Everything else is in the tree.
///
/// **The split is the answer to two orderings of one set of files.** *Look here
/// first* is an alert and has to be seen without being asked for, so it is a
/// short band at the top, in rank order. Everything else is navigation, and
/// navigation wants structure, so it is a directory tree below — ordered by
/// weight, so the ranking is still doing its work inside it. A tab would have
/// been the other way to reconcile them, and it hides the alert half the time.
///
/// [visible] is null when nothing is filtering.
List<ChangeRow> buildIndexRows(
  ChangeSet set, {
  String? selected,
  Set<String>? visible,
  bool noiseOpen = false,
}) {
  var rows = <ChangeRow>[];

  void addFile(RankedFile ranked) => rows.add(
    FileRow(
      ranked.file,
      selected: ranked.file.path == selected,
      uncommitted: set.uncommitted.contains(ranked.file.path),
      reason: ranked.reason,
    ),
  );

  List<RankedFile> kept(RankTier tier) => [
    for (var ranked in set.ordered(tier))
      if (visible == null || visible.contains(ranked.file.path)) ranked,
  ];

  var attention = kept(RankTier.attention);

  // An untracked file that matched a rule belongs in the pinned section even
  // though it has no diff — see `attentionForUntracked`. Filtering hides it
  // like anything else.
  var pinnedUntracked = [
    for (var entry in set.untracked)
      if (entry.isPinned && (visible == null || visible.contains(entry.path)))
        entry,
  ];

  if (attention.isNotEmpty || pinnedUntracked.isNotEmpty) {
    rows.add(
      SectionRow(
        'Look here first',
        detail: _counts(attention, pinnedUntracked.length),
      ),
    );
    attention.forEach(addFile);
    for (var entry in pinnedUntracked) {
      rows.add(UntrackedRow(entry, selected: entry.path == selected));
    }
  }
  // **The ordinary files are not here.** They are the tree's, which is the
  // whole point of putting one back: a flat list of fifty-three basenames says
  // nothing about the shape of the branch.
  //
  // Neither is the noise drawer any more: it is a lens at the top of the pane,
  // where you look, rather than a row below fifty others — which is where the
  // original one sat, and slice 4 had already found that a control below the
  // fold labels a distinction nobody can see.

  // The pinned ones are drawn above; listing them twice would make the branch
  // look bigger than it is.
  var rest = [
    for (var entry in set.untracked)
      if (!entry.isPinned) entry,
  ];
  var keptRest = [
    for (var entry in rest)
      if (visible == null || visible.contains(entry.path)) entry,
  ];
  if (keptRest.isNotEmpty) {
    rows.add(const SectionRow('Untracked'));
    for (var entry in keptRest) {
      rows.add(UntrackedRow(entry, selected: entry.path == selected));
    }
  }

  return rows;
}

/// The files the **tree** holds: everything that is not pinned, plus the noise
/// once its drawer is open.
///
/// Pinned files are deliberately not in it. They are drawn above, and a file in
/// both places makes the branch look bigger than it is — the same rule the
/// untracked section has followed since the first slice.
List<FileChange> treeFiles(
  ChangeSet set, {
  Set<String>? visible,
  bool noiseOpen = false,
}) => [
  for (var tier in [RankTier.ordinary, if (noiseOpen) RankTier.noise])
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

String _counts(List<RankedFile> files, int untracked) {
  var total = files.length + untracked;
  var added = files.fold(0, (sum, r) => sum + r.file.added);
  var removed = files.fold(0, (sum, r) => sum + r.file.removed);
  // The +/- covers what has a delta. An untracked file has none against the
  // base, so it is counted as a file and contributes no lines.
  return '$total ${total == 1 ? 'file' : 'files'} +$added -$removed';
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

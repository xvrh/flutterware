/// The screen's list, flattened to one row per drawable line.
///
/// **A single `ListView.builder` over one list, not a list of expanding
/// cards.** A branch with a file expanded is thousands of diff lines, and the
/// only structure that stays smooth at that size is a flat, virtualised list —
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

  /// What this row **is**, independently of where it sits in the list.
  ///
  /// The live screen re-indexes whenever the checkout moves, and an agent
  /// creating one file renumbers every row below it. Index is therefore not
  /// identity: `ListView` given only indices throws away the element at row 40
  /// and rebuilds a different one there, and the scroll offset — which is
  /// pixels, not rows — leaves you reading something you were not reading.
  /// Keyed by this instead, the list can find the row you were on wherever it
  /// moved to.
  ///
  /// A hunk keys on its line numbers, so a hunk that moved *within* its file is
  /// a different row. That is the honest answer: its content moved too.
  String get anchorKey;
}

/// A heading — `Look here first`, `Changes`, `Untracked`.
final class SectionRow extends ChangeRow {
  const SectionRow(this.label, {this.detail});

  final String label;

  /// The counts that belong to this section, or null.
  final String? detail;

  @override
  String get anchorKey => 'section:$label';
}

/// A file's own row: status, path, counts, ruler, and the expander.
final class FileRow extends ChangeRow {
  const FileRow(
    this.file, {
    required this.expanded,
    required this.uncommitted,
    this.reason,
  });

  final FileChange file;
  final bool expanded;
  final bool uncommitted;

  /// The rule that pinned or demoted this file, in the words it was written
  /// in. Null for the ordinary case, which is most files.
  final String? reason;

  @override
  String get anchorKey => 'file:${file.path}';
}

/// The collapsed noise tier: **one row standing in for N files**.
///
/// A row rather than a filter, because the count is the information. `31
/// low-signal files` says the branch is mostly generated code; hiding them
/// silently says the branch is small, which is a different and false claim.
final class NoiseDrawerRow extends ChangeRow {
  const NoiseDrawerRow({
    required this.files,
    required this.added,
    required this.removed,
    required this.open,
  });

  final int files;
  final int added;
  final int removed;
  final bool open;

  @override
  String get anchorKey => 'noise';
}

/// The `@@` line of an expanded hunk, plus the context git guessed.
final class HunkRow extends ChangeRow {
  const HunkRow(this.file, this.hunk);

  final FileChange file;
  final HunkSpan hunk;

  @override
  String get anchorKey => 'hunk:${file.path}:${hunk.oldStart}:${hunk.newStart}';
}

/// One line of a hunk, addressed by its position **within that hunk** so the
/// text can be decoded lazily and thrown away on collapse.
final class DiffLineRow extends ChangeRow {
  const DiffLineRow(this.file, this.hunk, this.index);

  final FileChange file;
  final HunkSpan hunk;

  /// Zero-based, counting only the lines this hunk draws.
  final int index;

  @override
  String get anchorKey =>
      'line:${file.path}:${hunk.oldStart}:${hunk.newStart}:$index';
}

/// Why a file's body is not shown even though it is expanded.
final class FileNoticeRow extends ChangeRow {
  const FileNoticeRow(this.file, this.message);

  final FileChange file;
  final String message;

  @override
  String get anchorKey => 'notice:${file.path}';
}

/// An untracked path, exactly as git reported it.
final class UntrackedRow extends ChangeRow {
  const UntrackedRow(this.entry);
  final UntrackedEntry entry;

  @override
  String get anchorKey => 'untracked:${entry.path}';
}

/// Both halves of a pinned section: files with a diff, and untracked paths
/// that matched a rule and have none.

/// Flattens [set] into rows, given what is expanded and what the filter kept.
///
/// [visible] is null when nothing is filtering. Filtering removes rows here —
/// the churn map dims instead, which is where whole-branch context is kept.
List<ChangeRow> buildRows(
  ChangeSet set, {
  required Set<String> expanded,
  Set<String>? visible,
  bool noiseOpen = false,
}) {
  var rows = <ChangeRow>[];

  void addFile(RankedFile ranked) {
    var file = ranked.file;
    var isExpanded = expanded.contains(file.path);
    rows.add(
      FileRow(
        file,
        expanded: isExpanded,
        uncommitted: set.uncommitted.contains(file.path),
        reason: ranked.reason,
      ),
    );
    if (!isExpanded) return;

    // Every reason a body is withheld says so in place. A file that expands to
    // nothing, with no explanation, reads as a bug in the viewer.
    if (file.isBinary) {
      rows.add(FileNoticeRow(file, 'Binary file — no lines to show.'));
      return;
    }
    if (file.patchBytes > ChangesLimits.filePatchBytes) {
      rows.add(
        FileNoticeRow(
          file,
          "This file's diff is "
          '${(file.patchBytes / 1024).round()} KB — past what the viewer '
          'expands. Open it in your editor.',
        ),
      );
      return;
    }
    if (file.hunks.isEmpty) {
      rows.add(
        FileNoticeRow(file, 'No text changed — only the path or the mode.'),
      );
      return;
    }

    for (var hunk in file.hunks) {
      rows.add(HunkRow(file, hunk));
      for (var i = 0; i < hunk.displayLines; i++) {
        rows.add(DiffLineRow(file, hunk, i));
      }
    }
  }

  List<RankedFile> kept(RankTier tier) => [
    for (var ranked in set.ordered(tier))
      if (visible == null || visible.contains(ranked.file.path)) ranked,
  ];

  var attention = kept(RankTier.attention);
  var ordinary = kept(RankTier.ordinary);
  var noise = kept(RankTier.noise);

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
      rows.add(UntrackedRow(entry));
    }
  }
  if (ordinary.isNotEmpty) {
    // **A heading only when there is a section above to separate from.** With
    // nothing pinned, a lone `Changes` sits at the top of the list with its
    // counterpart — the drawer — thirty rows below the fold, so it labels a
    // distinction nobody can see. The drawer names itself; this does not have
    // to name it twice.
    if (attention.isNotEmpty || pinnedUntracked.isNotEmpty) {
      rows.add(const SectionRow('Changes'));
    }
    ordinary.forEach(addFile);
  }
  if (noise.isNotEmpty) {
    rows.add(
      NoiseDrawerRow(
        files: noise.length,
        added: noise.fold(0, (sum, r) => sum + r.file.added),
        removed: noise.fold(0, (sum, r) => sum + r.file.removed),
        open: noiseOpen,
      ),
    );
    if (noiseOpen) noise.forEach(addFile);
  }

  // The pinned ones are drawn above; listing them twice would make the branch
  // look bigger than it is.
  var rest = [
    for (var entry in set.untracked)
      if (!entry.isPinned) entry,
  ];
  if (rest.isNotEmpty && visible == null) {
    rows.add(const SectionRow('Untracked'));
    for (var entry in rest) {
      rows.add(UntrackedRow(entry));
    }
  }

  return rows;
}

String _counts(List<RankedFile> files, int untracked) {
  var total = files.length + untracked;
  var added = files.fold(0, (sum, r) => sum + r.file.added);
  var removed = files.fold(0, (sum, r) => sum + r.file.removed);
  // The +/- covers what has a delta. An untracked file has none against the
  // base, so it is counted as a file and contributes no lines.
  return '$total ${total == 1 ? 'file' : 'files'} +$added -$removed';
}

/// The rows the changes list draws.
///
/// Each one is deliberately **cheap and of a predictable height**: they are
/// built inside a virtualised list, so anything that measures text or reflows a
/// subtree per row shows up as jank while scrolling a four-thousand-line file.
library;

import 'package:flutter/material.dart';

import '../ui/syntax.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';
import 'change_set.dart';
import 'diff_lines.dart';
import 'hunk_syntax.dart';
import 'patch_index.dart';

/// A file's row **in the index**: what happened to it, and how much.
///
/// Sized for a 320 px column, not a window: name on the first line where the
/// eye scans, **the directory on its own line under it**, counts hard right.
/// The full-width version this replaces put the whole path on one line with a
/// ruler and two 46 px count columns, which is a row that only reads at 1200 px.
///
/// **The directory is not a note.** It was, briefly, and it was the last of
/// them — after `uncommitted`, after `binary` — in one `·`-joined line, which
/// made *where a file lives* the first thing ellipsised away. Three lines of a
/// list like that and you cannot tell `app/lib/src/changes/ranking.dart` from
/// `test/changes/ranking.dart`. It gets its own line; the flags get theirs, and
/// only when there are any.
class IndexFileRow extends StatelessWidget {
  const IndexFileRow({
    required this.file,
    required this.selected,
    required this.uncommitted,
    required this.onTap,
    this.reason,
    this.showDirectory = true,
    this.pinned = false,
    super.key,
  });

  final FileChange file;

  /// Whether the right pane is showing this file.
  final bool selected;
  final bool uncommitted;
  final VoidCallback onTap;

  /// False inside the tree, where the row's position already says where the
  /// file is and repeating the path is the noise the tree exists to remove.
  /// True in the *Important* tab, which is flat and has no other way to say
  /// it.
  final bool showDirectory;

  /// Draws the flag an attention rule earned this file. Set inside the tree,
  /// where a pin has to be visible in passing. Not in the *Important* tab,
  /// which is all pins and would only be marking every row.
  final bool pinned;

  /// Why this file was pinned or demoted, in the words the rule was written in.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var slash = file.path.lastIndexOf('/');
    var name = slash < 0 ? file.path : file.path.substring(slash + 1);
    var directory = slash < 0 ? '' : file.path.substring(0, slash);

    return Tappable.builder(
      onTap: onTap,
      builder: (context, hovered) => Container(
        decoration: BoxDecoration(
          color: selected
              ? colors.accentSoft
              : hovered
              ? colors.hoverOverlay
              : Colors.transparent,
          // A 2 px edge rather than a badge: it is scannable down a column of
          // forty rows and costs the text no width at all.
          border: pinned
              ? Border(left: BorderSide(color: colors.accent, width: 2))
              : null,
        ),
        padding: EdgeInsets.only(
          left: pinned ? FwSpacing.md - 2 : FwSpacing.md,
          right: FwSpacing.md,
          top: FwSpacing.sm,
          bottom: FwSpacing.sm,
        ),
        // **Baselines, not box tops.** Three different type sizes sit on this
        // row — the status letter, the name, the counts — and
        // `CrossAxisAlignment.start` aligns the tops of their boxes, which for
        // two different ascents is not the same line. It is a two-pixel error
        // that nobody can name and everybody can see. `Column` reports its
        // first child's baseline, so aligning on it puts the letter and the
        // counts on the *name's* line, which is the one being read.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // **The letter says it, the tooltip spells it.** One character in a
            // colour is a legend a reader has to have been taught; `A` and `R`
            // are the two nobody guesses.
            Tooltip(
              message: _word(file.status),
              child: SizedBox(
                width: 12,
                child: Text(
                  _letter(file.status),
                  style: context.type.bodySmall.copyWith(color: _tone(colors)),
                ),
              ),
            ),
            const Gap(FwSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: context.type.bodySmall,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                  if (showDirectory && directory.isNotEmpty)
                    Text(
                      directory,
                      style: context.type.micro.copyWith(color: colors.mut2),
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  if (_notes.isNotEmpty)
                    Text(
                      _notes.join(' · '),
                      style: context.type.micro.copyWith(color: colors.mut3),
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                ],
              ),
            ),
            const Gap(FwSpacing.sm),
            // **One line.** Stacked, `+309` over `-22` reads as a count that
            // wrapped rather than as two halves of one figure — and the row is
            // already two or three lines tall without help.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '+${file.added}',
                  style: context.type.micro.copyWith(color: colors.grn),
                ),
                if (file.removed > 0) ...[
                  const Gap(FwSpacing.xs),
                  Text(
                    '-${file.removed}',
                    style: context.type.micro.copyWith(color: colors.red),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A third line, and only when there is something to put on it. The
  /// directory is deliberately **not** among these — that is what put it last
  /// in a `·`-joined string behind `uncommitted`, where it was the first thing
  /// to be ellipsised away.
  List<String> get _notes => [
    // **The rule first.** A row that was pinned has to say what pinned it or
    // the pin is magic, and magic is what people learn to ignore.
    ?reason,
    // A rename says where it came from: `R` alone is a status nobody can act
    // on, and the index is where you decide whether to look.
    if (file.oldPath case var it?) 'from $it',
    if (uncommitted) 'uncommitted',
    if (file.isBinary) 'binary',
  ];

  Color _tone(FwPalette colors) => switch (file.status) {
    ChangeStatus.added => colors.grn,
    ChangeStatus.deleted => colors.red,
    ChangeStatus.renamed => colors.amber,
    ChangeStatus.modified => colors.mut,
  };

  static String _letter(ChangeStatus status) => switch (status) {
    ChangeStatus.added => 'A',
    ChangeStatus.modified => 'M',
    ChangeStatus.deleted => 'D',
    ChangeStatus.renamed => 'R',
  };

  static String _word(ChangeStatus status) => statusWord(status);
}

/// How a status reads in words — the index's tooltip and the body's header say
/// the same one, because two spellings of four states is four chances to
/// disagree.
String statusWord(ChangeStatus status) => switch (status) {
  ChangeStatus.added => 'added',
  ChangeStatus.deleted => 'deleted',
  ChangeStatus.renamed => 'renamed',
  ChangeStatus.modified => 'modified',
};

/// The `@@` line, drawn from the span rather than from the patch text — which
/// is what lets it appear before the hunk it heads has been decoded.
class HunkHeaderLine extends StatelessWidget {
  const HunkHeaderLine({required this.hunk, super.key});

  final HunkSpan hunk;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      color: colors.panel2,
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.xxs,
      ),
      child: Row(
        children: [
          Text(
            '@@ -${hunk.oldStart},${hunk.oldCount} '
            '+${hunk.newStart},${hunk.newCount} @@',
            style: diffTextStyle(context).copyWith(color: colors.mut3),
          ),
          if (hunk.context case var it?) ...[
            const Gap(FwSpacing.md),
            Expanded(
              child: Text(
                it,
                style: diffTextStyle(context).copyWith(color: colors.mut2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of an expanded hunk, decoded on demand.
///
/// **The header is a prediction; the content is the truth.** Row extents come
/// from `HunkSpan.displayLines`, which is arithmetic on the `@@` counts — that
/// is what lets the list size itself before decoding anything. A patch whose
/// header disagrees with its body (truncated mid-hunk, or written by something
/// that is not git) would otherwise index past the end of the decoded lines and
/// crash *while scrolling*, which is the least excusable place to crash.
///
/// So the shortfall is drawn, not swallowed: silently rendering nothing would
/// leave a gap that reads as a viewer bug rather than as a bad patch.
class HunkLineView extends StatelessWidget {
  const HunkLineView({
    required this.lines,
    required this.hunk,
    required this.index,
    this.tokens,
    super.key,
  });

  final HunkLineCache lines;
  final HunkSpan hunk;
  final int index;

  /// Where this line's colours come from, or null for a file nothing here
  /// reads. **Asked for per row, computed per hunk** — the first row of a hunk
  /// to be built pays for the whole hunk and every row after it is a lookup.
  final HunkTokenCache? tokens;

  @override
  Widget build(BuildContext context) {
    var decoded = lines.linesFor(hunk);
    if (index >= decoded.length) {
      return DiffLineView(
        line: DiffLine(
          kind: DiffLineKind.meta,
          text: index == decoded.length
              ? r'\ this hunk ended before its header said it would'
              : '',
        ),
      );
    }
    return DiffLineView(
      line: decoded[index],
      tokens: tokens?.forHunk(hunk).at(index),
    );
  }
}

/// One line of a diff.
///
/// **Tinted by kind, and marked by a glyph.** The tint alone would fail for the
/// ~8% of men with red-green colour blindness, and the glyph alone would make a
/// block of additions hard to see at a glance; together neither is load-bearing
/// on its own.
///
/// **Syntax colour is a third channel and does not compete with those two.**
/// What says *added* is the row's wash and the `+`; what the tokens say is
/// which word is a keyword. So the row keeps its tint, and a token the
/// highlighter had no opinion about keeps the row's own ink rather than being
/// forced to a neutral.
class DiffLineView extends StatelessWidget {
  const DiffLineView({required this.line, this.tokens, super.key});

  final DiffLine line;

  /// This line's coloured runs, or null for a file nothing here reads — in
  /// which case the text is drawn exactly as it was before any of this existed.
  final List<Token>? tokens;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var (background, marker, tone) = switch (line.kind) {
      DiffLineKind.added => (
        colors.grn.withValues(alpha: 0.12),
        '+',
        colors.grn,
      ),
      DiffLineKind.removed => (
        colors.red.withValues(alpha: 0.12),
        '-',
        colors.red,
      ),
      DiffLineKind.meta => (Colors.transparent, '', colors.mut3),
      DiffLineKind.context => (Colors.transparent, ' ', colors.mut3),
    };
    var style = diffTextStyle(context);

    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Gutter(line.oldNumber, colors.mut3, style),
          _Gutter(line.newNumber, colors.mut3, style),
          const Gap(FwSpacing.sm),
          SizedBox(
            width: 10,
            child: Text(marker, style: style.copyWith(color: tone)),
          ),
          Expanded(
            child: switch (tokens) {
              // **The same `Text`, given spans instead of a string.** Not a
              // different widget for the coloured case: the row's height, its
              // clipping and its never-wrapping are the properties that keep a
              // virtualised list smooth, and two widgets is two places to lose
              // one of them.
              var it? when line.kind != DiffLineKind.meta => Text.rich(
                TextSpan(children: spansFor(context, it, style: style)),
                style: style,
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
              _ => Text(
                line.text,
                style: line.kind == DiffLineKind.meta
                    ? style.copyWith(
                        color: colors.mut3,
                        fontStyle: FontStyle.italic,
                      )
                    : style,
                // **Never wrapped.** A wrapped line changes a row's height, and
                // a virtualised list whose rows change height as they are built
                // is one whose scrollbar jumps under your hand. Long lines
                // clip; the list scrolls horizontally as a whole.
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Gutter extends StatelessWidget {
  const _Gutter(this.number, this.color, this.style);

  final int? number;
  final Color color;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    child: Text(
      number?.toString() ?? '',
      textAlign: TextAlign.right,
      style: style.copyWith(color: color),
    ),
  );
}

/// An untracked path, exactly as git reported it.
class IndexUntrackedRow extends StatelessWidget {
  const IndexUntrackedRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final UntrackedEntry entry;
  final bool selected;

  /// Null for a directory, which is the one row here that opens nothing: there
  /// is no diff behind it and reading it would be the walk this avoids.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var slash = entry.path.lastIndexOf('/');
    var name = slash < 0 ? entry.path : entry.path.substring(slash + 1);
    var notes = [
      ?entry.reason,
      if (entry.isDirectory)
        // **Never a file count.** Counting is the directory walk that keeping
        // this to one row exists to avoid.
        'directory, not scanned'
      else
        'not tracked yet',
      // Not for a directory: its own path is already drawn in full above, and
      // repeating the parent under it reads as two different places.
      if (slash > 0 && !entry.isDirectory) entry.path.substring(0, slash),
    ];

    return Tappable.builder(
      onTap: onTap,
      builder: (context, hovered) => Container(
        decoration: BoxDecoration(
          color: selected
              ? colors.accentSoft
              : hovered && onTap != null
              ? colors.hoverOverlay
              : Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.md,
          vertical: FwSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // **git's own letter, and it is the one nobody reads.** `A`/`M`/`D`
            // are guessable from the word they start; `?` stands for a question
            // git is asking rather than an answer, so it says so on hover.
            Tooltip(
              message: entry.isDirectory
                  ? 'Untracked — git is not tracking anything in this '
                        'directory yet'
                  : 'Untracked — git is not tracking this file yet, so there '
                        'is no other side to diff it against',
              child: SizedBox(
                width: 12,
                child: Text(
                  '?',
                  style: context.type.bodySmall.copyWith(color: colors.mut3),
                ),
              ),
            ),
            const Gap(FwSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.isDirectory ? entry.path : name,
                    style: context.type.bodySmall.copyWith(
                      // A pinned path is being read, not skimmed past.
                      color: entry.isPinned ? null : colors.mut,
                    ),
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                  Text(
                    notes.join(' · '),
                    style: context.type.micro.copyWith(color: colors.mut2),
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one place the diff's typeface is decided.
///
/// Monospace, because a diff is columns: an indent that does not line up with
/// the line above it is a diff you cannot read.
TextStyle diffTextStyle(BuildContext context) => context.type.micro.copyWith(
  fontFamily: 'monospace',
  fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
  height: 1.5,
);

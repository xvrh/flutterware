/// The rows the changes list draws.
///
/// Each one is deliberately **cheap and of a predictable height**: they are
/// built inside a virtualised list, so anything that measures text or reflows a
/// subtree per row shows up as jank while scrolling a four-thousand-line file.
library;

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'change_set.dart';
import 'diff_lines.dart';
import 'hunk_ruler.dart';
import 'patch_index.dart';

/// A file's own row: what happened to it, where the change sits, and how much.
class ChangeFileRow extends StatelessWidget {
  const ChangeFileRow({
    required this.file,
    required this.expanded,
    required this.uncommitted,
    required this.isCurrent,
    required this.onTap,
    this.reason,
    super.key,
  });

  final FileChange file;
  final bool expanded;
  final bool uncommitted;
  final bool isCurrent;
  final VoidCallback onTap;

  /// Why this file was pinned or demoted, in the words the rule was written in.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isCurrent ? colors.accentSoft : Colors.transparent,
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: 14,
              color: colors.mut3,
            ),
            const Gap(FwSpacing.xs),
            SizedBox(
              width: 14,
              child: Text(
                _letter(file.status),
                style: context.type.micro.copyWith(color: _tone(colors)),
              ),
            ),
            const Gap(FwSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.path,
                    style: context.type.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_notes.isNotEmpty)
                    Text(
                      _notes.join(' · '),
                      style: context.type.micro.copyWith(color: colors.mut2),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Gap(FwSpacing.md),
            HunkRuler(file: file),
            const Gap(FwSpacing.md),
            SizedBox(
              width: 46,
              child: Text(
                '+${file.added}',
                textAlign: TextAlign.right,
                style: context.type.micro.copyWith(color: colors.grn),
              ),
            ),
            SizedBox(
              width: 46,
              child: Text(
                '-${file.removed}',
                textAlign: TextAlign.right,
                style: context.type.micro.copyWith(color: colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> get _notes => [
    // **The rule first.** A row that was pinned has to say what pinned it or
    // the pin is magic, and magic is what people learn to ignore.
    ?reason,
    // A rename says where it came from: `R` alone is a status nobody can act on.
    if (file.oldPath case var it?) 'from $it',
    if (uncommitted) 'uncommitted',
    if (file.isBinary) 'binary',
    if (file.hunks.length == 1)
      '1 hunk'
    else if (file.hunks.length > 1)
      '${file.hunks.length} hunks',
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
}

/// The noise tier, standing behind one row.
///
/// **A drawer, not a filter.** The count is the information: `31 low-signal
/// files` says this branch is mostly generated code, and hiding them silently
/// would say it is a small branch — a different claim, and a false one. One
/// click opens it, and the header's file count includes them either way.
class NoiseDrawerLine extends StatelessWidget {
  const NoiseDrawerLine({
    required this.files,
    required this.added,
    required this.removed,
    required this.open,
    required this.onTap,
    super.key,
  });

  final int files;
  final int added;
  final int removed;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          FwSpacing.lg,
          FwSpacing.lg,
          FwSpacing.lg,
          FwSpacing.sm,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.md,
          vertical: FwSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.hoverOverlay,
          borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        ),
        child: Row(
          children: [
            Icon(
              open ? Icons.expand_more : Icons.chevron_right,
              size: 14,
              color: colors.mut3,
            ),
            const Gap(FwSpacing.xs),
            Expanded(
              child: Text(
                '$files low-signal ${files == 1 ? 'file' : 'files'}',
                style: context.type.bodySmall.copyWith(color: colors.mut),
              ),
            ),
            Text(
              '+$added',
              style: context.type.micro.copyWith(color: colors.mut2),
            ),
            const Gap(FwSpacing.sm),
            Text(
              '-$removed',
              style: context.type.micro.copyWith(color: colors.mut2),
            ),
          ],
        ),
      ),
    );
  }
}

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
    super.key,
  });

  final HunkLineCache lines;
  final HunkSpan hunk;
  final int index;

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
    return DiffLineView(line: decoded[index]);
  }
}

/// One line of a diff.
///
/// **Tinted by kind, and marked by a glyph.** The tint alone would fail for the
/// ~8% of men with red-green colour blindness, and the glyph alone would make a
/// block of additions hard to see at a glance; together neither is load-bearing
/// on its own.
class DiffLineView extends StatelessWidget {
  const DiffLineView({required this.line, super.key});

  final DiffLine line;

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
            child: Text(
              line.text,
              style: line.kind == DiffLineKind.meta
                  ? style.copyWith(
                      color: colors.mut3,
                      fontStyle: FontStyle.italic,
                    )
                  : style,
              // **Never wrapped.** A wrapped line changes a row's height, and a
              // virtualised list whose rows change height as they are built is
              // one whose scrollbar jumps under your hand. Long lines clip; the
              // list scrolls horizontally as a whole.
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
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
class UntrackedFileLine extends StatelessWidget {
  const UntrackedFileLine({required this.entry, super.key});

  final UntrackedEntry entry;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.xs,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(
              '?',
              style: context.type.micro.copyWith(color: colors.mut3),
            ),
          ),
          const Gap(FwSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.path,
                  style: context.type.bodySmall.copyWith(
                    // A pinned path is being read, not skimmed past.
                    color: entry.isPinned ? null : colors.mut,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.reason case var it?)
                  Text(
                    '$it · not tracked yet',
                    style: context.type.micro.copyWith(color: colors.mut2),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // **Never a file count.** Counting is the directory walk that keeping
          // this to one row exists to avoid.
          if (entry.isDirectory)
            Text(
              'directory, not scanned',
              style: context.type.micro.copyWith(color: colors.mut3),
            ),
        ],
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

/// The widgets a review is made of: a comment in the diff, the box you write
/// one in, and a comment's row in the index.
///
/// Kept out of `diff_view.dart` because those rows are load-bearing for the
/// virtualised list — cheap, fixed-height, never wrapping — and every widget
/// here is the opposite of that on purpose. A comment wraps; that is what a
/// comment is. Separating them is what keeps the constraint legible where it
/// still applies.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/tappable.dart';
import '../ui/theme.dart';
import 'diff_view.dart' show diffTextStyle;
import 'review_comment.dart';

/// The composer's field, so a test and the drive tools can reach it. Its hint
/// is not a target: it belongs to the decoration, and tapping where it is drawn
/// is refused as covered.
const reviewComposerKey = Key('review-composer');

/// How many quoted lines a thread shows before it stops.
///
/// A span is whatever you shift-clicked, and forty lines of quote would push
/// the note itself off the screen — the quote is the note's evidence, not its
/// subject. Beyond this the rest is counted rather than drawn; the handoff
/// still carries every line.
const _quoteLimit = 6;

/// A comment as it appears in the diff, under the line it is about.
///
/// **The left edge is the accent bar**, the same 2 px device the index uses for
/// a pinned file: at a glance down a long diff it says *somebody wrote here*
/// without needing to be read.
///
/// **It shows what it captured.** The quote is the whole design — a note
/// carries the code it was written about so the agent may keep editing while
/// you type — and for one release it was the one thing on this screen you could
/// not see: written into the comment, rendered only in the handoff markdown.
/// A note about a line the agent has since deleted looked exactly like a note
/// about whatever now sits there, which is the failure mode carrying the quote
/// exists to prevent.
class ReviewThread extends StatelessWidget {
  const ReviewThread({
    required this.comment,
    required this.onDelete,
    this.drifted = false,
    this.highlighted = false,
    this.onEdit,
    super.key,
  });

  final ReviewComment comment;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  /// Whether the file moved after this was written.
  final bool drifted;

  /// Just arrived here from the index. Held for a moment and then dropped —
  /// the index row you clicked and the thread you landed on are otherwise two
  /// unconnected things in a diff of four thousand rows.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.fromLTRB(
        FwSpacing.xxl,
        FwSpacing.sm,
        FwSpacing.xxl,
        FwSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: highlighted ? colors.accentSoft : colors.panel2,
        border: Border(left: BorderSide(color: colors.accent, width: 2)),
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(context.radii.radiusSmall),
          bottomRight: Radius.circular(context.radii.radiusSmall),
        ),
      ),
      padding: const EdgeInsets.all(FwSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconFor(comment.anchor),
                size: FwIconSize.xs,
                color: colors.mut3,
              ),
              const Gap(FwSpacing.sm),
              // The short form: the file's name is in the header six pixels
              // above this, and the whole path twice is the same sentence said
              // twice.
              Flexible(
                child: Text(
                  comment.anchor.shortLabel,
                  style: context.type.micro.copyWith(color: colors.mut2),
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const Gap(FwSpacing.md),
              Text(
                clockOf(comment.createdAt),
                style: context.type.micro.copyWith(color: colors.mut3),
              ),
              const Spacer(),
              if (onEdit case var edit?) _Action(label: 'Edit', onTap: edit),
              const Gap(FwSpacing.md),
              _Action(label: 'Delete', onTap: onDelete),
            ],
          ),
          if (comment.quote.isNotEmpty) ...[
            const Gap(FwSpacing.sm),
            ReviewQuote(comment.quote),
          ],
          const Gap(FwSpacing.sm),
          // **Selectable.** The first thing anybody does with a note they wrote
          // for an agent is take a piece of it somewhere else.
          SelectableText(
            comment.body,
            style: context.type.bodySmall.copyWith(color: colors.ink),
          ),
          if (drifted) ...[
            const Gap(FwSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.circle, size: 6, color: colors.amber),
                ),
                const Gap(FwSpacing.sm),
                Expanded(
                  child: Text(
                    'This file changed after you commented. The code you '
                    'quoted is kept as it was.',
                    style: context.type.micro.copyWith(color: colors.mut2),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The code a note carries, drawn the way the diff draws it.
///
/// [diffTextStyle] rather than a mono face of its own: this is a slice of the
/// file three rows above it, and two typefaces for the same bytes would read as
/// two different things. Lines clip instead of wrapping, for the same reason
/// they do in the diff — a wrapped quote is one whose indentation lies.
class ReviewQuote extends StatelessWidget {
  const ReviewQuote(this.lines, {this.limit = _quoteLimit, super.key});

  final List<String> lines;
  final int limit;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var shown = lines.take(limit).toList();
    var rest = lines.length - shown.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: FwSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var line in shown)
            Text(
              line,
              style: diffTextStyle(context).copyWith(color: colors.mut),
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          if (rest > 0)
            Text(
              '…and $rest more ${rest == 1 ? 'line' : 'lines'}',
              style: context.type.micro.copyWith(color: colors.mut3),
            ),
        ],
      ),
    );
  }
}

/// A note that has just been deleted, and can still be taken back.
///
/// **The delete is not written yet.** It stands in the deleted note's place
/// until the window closes, and only then does the tombstone reach the log —
/// so taking it back costs nothing and restores the note exactly, in the
/// position it held. Delete was a single click on a 10.5 px text link beside
/// Edit, against an append-only log with no way back.
class ReviewUndoStrip extends StatelessWidget {
  const ReviewUndoStrip({
    required this.onUndo,
    this.inset = FwSpacing.xxl,
    super.key,
  });

  final VoidCallback onUndo;
  final double inset;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      margin: EdgeInsets.fromLTRB(inset, FwSpacing.sm, inset, FwSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: FwSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          Icon(Icons.delete_outline, size: FwIconSize.sm, color: colors.mut3),
          const Gap(FwSpacing.sm),
          Expanded(
            child: Text(
              'Comment deleted',
              style: context.type.micro.copyWith(color: colors.mut2),
            ),
          ),
          _Action(label: 'Undo', onTap: onUndo, strong: true),
        ],
      ),
    );
  }
}

IconData _iconFor(ReviewAnchor anchor) => switch (anchor) {
  LineAnchor() => Icons.code,
  FileAnchor() => Icons.description_outlined,
  ReviewWide() => Icons.rate_review_outlined,
};

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onTap,
    this.strong = false,
  });

  final String label;
  final VoidCallback onTap;

  /// Accent whether or not the pointer is on it — for the one action in a row
  /// that is being offered rather than merely available.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable.builder(
      onTap: onTap,
      builder: (context, hovered) => Text(
        label,
        style: context.type.micro.copyWith(
          color: strong || hovered ? colors.accent : colors.mut3,
        ),
      ),
    );
  }
}

/// The box you write a comment in.
///
/// **It states its anchor and what it captured**, in that order, above the
/// text. That one line is the entire staleness contract, put where you accept
/// it rather than in a doc nobody opens: *these three lines, as they are now,
/// travel with what you are about to write.*
///
/// The text itself is held by the caller — see [controller] — because this
/// lives inside a virtualised list and a composer scrolled past its cache
/// extent is a composer that was disposed. Owning the controller upstream is
/// what makes that a redraw rather than a loss.
class ReviewComposer extends StatefulWidget {
  const ReviewComposer({
    required this.anchor,
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
    this.quotedLines = 0,
    this.editing = false,
    this.inset = FwSpacing.xxl,
    super.key,
  });

  final ReviewAnchor anchor;
  final TextEditingController controller;

  /// How many lines of code travel with this comment. Zero for a file or
  /// review anchor, which quote nothing.
  final int quotedLines;

  /// Whether this is rewriting an existing comment rather than adding one.
  final bool editing;

  /// How far in from the sides. The body's diff can afford the full gutter;
  /// the 320 px index cannot, and the composer for a whole-review note lives
  /// there.
  final double inset;

  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  State<ReviewComposer> createState() => _ReviewComposerState();
}

class _ReviewComposerState extends State<ReviewComposer> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The composer appears because you asked for it, so it is where you are
    // about to type. Anything else costs a click nobody would understand.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var lines = widget.quotedLines;
    var notes = [
      widget.anchor.label,
      if (lines > 0) '$lines ${lines == 1 ? 'line' : 'lines'} captured',
    ];

    return Container(
      margin: EdgeInsets.fromLTRB(
        widget.inset,
        FwSpacing.sm,
        widget.inset,
        FwSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.panel2,
        border: Border.all(color: colors.accent),
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      padding: const EdgeInsets.all(FwSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notes.join(' · '),
            style: context.type.micro.copyWith(color: colors.mut2),
            overflow: TextOverflow.ellipsis,
          ),
          const Gap(FwSpacing.sm),
          // **Both shortcuts are bound here rather than on the screen**, so
          // they cannot fire while the focus is somewhere else — Esc in
          // particular, which elsewhere on this screen clears the filter.
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  widget.onSubmit,
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  widget.onSubmit,
              const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
            },
            child: TextField(
              key: reviewComposerKey,
              controller: widget.controller,
              focusNode: _focus,
              style: context.type.bodySmall,
              maxLines: null,
              minLines: 3,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'What should the agent change here?',
                hintStyle: context.type.bodySmall.copyWith(color: colors.mut3),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(FwSpacing.sm),
              ),
            ),
          ),
          const Gap(FwSpacing.sm),
          Row(
            children: [
              // **The hint gives way, the buttons never do.** At 480 px — the
              // right pane in a narrow window — this row overflowed by 83 px
              // and took *Add comment* off the edge with it, which is the one
              // control the composer exists for.
              //
              // Below that it is shortened rather than ellipsised, and then
              // dropped: `Esc to disc…` is not a shorter way of saying the
              // shortcut, it is a way of not saying it while still taking the
              // room. The composer opens in a 320 px column too — that is
              // where a whole-review note is written.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    var hint = switch (constraints.maxWidth) {
                      > 180 => '⌘↵ to add · Esc to discard',
                      > 80 => '⌘↵ to add',
                      _ => '',
                    };
                    return Text(
                      hint,
                      style: context.type.micro.copyWith(color: colors.mut3),
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    );
                  },
                ),
              ),
              _Action(label: 'Cancel', onTap: widget.onCancel),
              const Gap(FwSpacing.lg),
              Tappable.builder(
                onTap: widget.onSubmit,
                builder: (context, hovered) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FwSpacing.lg,
                    vertical: FwSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: hovered ? colors.accentDark : colors.accent,
                    borderRadius: BorderRadius.circular(
                      context.radii.radiusSmall,
                    ),
                  ),
                  child: Text(
                    widget.editing ? 'Save' : 'Add comment',
                    style: context.type.micro.copyWith(
                      color: colors.primaryOnMenu,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A comment's row in the index.
///
/// **Numbered.** The list is what you hand off, in this order, and a number is
/// what lets you say *the third one* to the agent afterwards — the one thing
/// the anchor cannot do when three comments sit on one file.
class ReviewIndexRow extends StatelessWidget {
  const ReviewIndexRow({
    required this.number,
    required this.comment,
    required this.selected,
    required this.onTap,
    this.drifted = false,
    super.key,
  });

  final int number;
  final ReviewComment comment;
  final bool selected;
  final bool drifted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable.builder(
      onTap: onTap,
      builder: (context, hovered) => Container(
        color: selected
            ? colors.accentSoft
            : hovered
            ? colors.hoverOverlay
            : null,
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.md,
          vertical: FwSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 16,
              child: Text(
                '$number',
                style: context.type.micro.copyWith(color: colors.mut3),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // **The directory gives way first.** `path_glob.dart:3` is
                  // what tells two rows apart at a glance; the six segments in
                  // front of it are what an ellipsis should eat, and putting
                  // the whole path in one `Text` ellipsised the name instead.
                  Row(
                    children: [
                      if (comment.anchor.directory case var it?)
                        Flexible(
                          child: Text(
                            it,
                            style: context.type.micro.copyWith(
                              color: colors.mut3,
                            ),
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                      Flexible(
                        child: Text(
                          comment.anchor.shortLabel,
                          style: context.type.micro.copyWith(
                            color: colors.mut2,
                          ),
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                      if (drifted) ...[
                        const Gap(FwSpacing.xs),
                        Icon(Icons.circle, size: 6, color: colors.amber),
                      ],
                    ],
                  ),
                  const Gap(FwSpacing.xxs),
                  // Two lines of the note, not one: the first line of a review
                  // comment is often the setup and the second is the ask.
                  Text(
                    comment.body,
                    style: context.type.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // **One line of what it is about.** Three notes on one file
                  // read as three copies of that filename otherwise; the line
                  // of code under each is what tells them apart without
                  // opening any of them.
                  if (_firstCode(comment.quote) case var line?) ...[
                    const Gap(FwSpacing.xxs),
                    Text(
                      line,
                      style: diffTextStyle(
                        context,
                      ).copyWith(color: colors.mut3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The first line of the quote with anything on it, trimmed of the
  /// indentation that would otherwise spend the whole row's width.
  static String? _firstCode(List<String> quote) {
    for (var line in quote) {
      var trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}

/// A handed-off batch, collapsed to one row.
class ReviewBatchRow extends StatelessWidget {
  const ReviewBatchRow({required this.batch, required this.onCopy, super.key});

  final ReviewBatch batch;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var count = batch.comments.length;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: FwSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            '$count ${count == 1 ? 'comment' : 'comments'}',
            style: context.type.bodySmall.copyWith(color: colors.mut),
          ),
          const Gap(FwSpacing.md),
          Expanded(
            child: Text(
              [
                clockOf(batch.handedOffAt),
                if (batch.savedTo case var path?) path else batch.route,
              ].join(' · '),
              style: context.type.micro.copyWith(color: colors.mut3),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          _Action(label: 'Copy', onTap: onCopy),
        ],
      ),
    );
  }
}

/// Wall-clock, to the minute. A note's own time — not a duration and not a
/// date, because everything on this screen was written in the session you are
/// still in.
String clockOf(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

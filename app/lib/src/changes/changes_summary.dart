/// **Which files, ranked** — the explorer's third rung.
///
/// The row's changes cell answers *how big*; the expanded detail answers *where
/// the work went*, by bucket; this answers *which files*; and the changes
/// screen answers *what the diff says*.
///
/// A popover rather than more detail, and the split is not arbitrary. **The
/// detail is a set**: expanded rows stay expanded because comparing checkouts
/// is the whole point of the explorer, and buckets survive that — `app 78% ·
/// lib 15%` reads down a column. **A file list does not.** Nobody compares two
/// ranked file lists side by side, and four expanded rows each carrying six
/// paths turns the list into a page. So buckets are comparable and live in the
/// detail; files are singular and live here.
///
/// > **The same probe as the screen, corrected 2026-08-11 by measuring.** The
/// > design had this rendering from a `ChangeHeadline` cached in `CachedDiff`,
/// > to keep the popover free. Two things killed that. The first is that
/// > `CachedDiff` is keyed by `(base_sha, head_sha)` and is therefore
/// > **committed-only** — so a worktree whose agent has not committed yet would
/// > open an empty popover above a changes screen full of work, which is §1's
/// > mistake wearing a different hat. The second is the measurement: on the
/// > largest checkout here (228 files, +36k) the whole patch costs **20 ms**
/// > while the five metadata calls a lighter probe would need cost **70 ms** —
/// > process spawn dominates, not diffing, exactly as §3 says. There was no
/// > cheaper probe to build. So this holds a [ChangesController] and renders
/// > the same [ChangeSet] the screen does, which also means the two can never
/// > disagree about what is pinned.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../worktrees/facts.dart';
import 'change_set.dart';
import 'changes_controller.dart';
import 'patch_index.dart';
import 'ranking.dart';

/// The popover's root, so a test can scope to it.
const changesSummaryKey = Key('changes-summary');

/// One worktree's ranked file list, in about 420 px.
class ChangesSummaryCard extends StatefulWidget {
  const ChangesSummaryCard({
    required this.worktreePath,
    this.repoRoot,
    this.git,
    this.onOpen,
    this.load,
    super.key,
  });

  final String worktreePath;

  /// Keys the cached `ChangesConfig`, so a closed checkout ranks by the
  /// project's real rules. See `changes_config_cache.dart`.
  final String? repoRoot;

  /// What the row already knows, drawn **before the probe returns**.
  ///
  /// A popover that opens on a spinner has told you nothing you were not
  /// already looking at. This is the same fact the cell beside it drew.
  final Fact<GitFacts>? git;

  /// Opens the full changes screen.
  final VoidCallback? onOpen;

  /// Injected for tests, which must neither spawn an isolate nor need a
  /// repository.
  final Future<ChangeSet> Function(String path)? load;

  /// How many rows each section draws before it stops.
  ///
  /// **Small on purpose.** This is a glance, not a list — the answer to "is
  /// there anything here I should stop for". Anything longer is the screen's
  /// job, and the link to it is right there.
  static const pinnedCap = 4;
  static const biggestCap = 6;

  @override
  State<ChangesSummaryCard> createState() => _ChangesSummaryCardState();
}

/// What the pinned section draws, once the caps are applied.
///
/// **One function, two readers.** The list and the tally below it have to agree
/// about which untracked entries were already shown, and deriving that twice —
/// or writing it down during one build and reading it in the next — is how they
/// come to disagree by a frame.
({List<RankedFile> files, List<UntrackedEntry> untracked}) _pinnedOf(
  ChangeSet set,
) {
  var files = set
      .ordered(RankTier.attention)
      .take(ChangesSummaryCard.pinnedCap)
      .toList();
  var untracked = [
    for (var entry in set.untracked)
      if (entry.isPinned) entry,
  ].take(ChangesSummaryCard.pinnedCap - files.length).toList();
  return (files: files, untracked: untracked);
}

class _ChangesSummaryCardState extends State<ChangesSummaryCard> {
  late final ChangesController _changes;

  @override
  void initState() {
    super.initState();
    _changes = ChangesController(
      worktreePath: widget.worktreePath,
      repoRoot: widget.repoRoot,
      load: widget.load,
    )..addListener(_onChanged);
    unawaited(_changes.refresh());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _changes
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var set = _changes.value;

    return Container(
      key: changesSummaryKey,
      width: 420,
      // **Capped, and scrollable past it.** Nothing bounds a popover's height —
      // the overlay is the window — so four pinned rows carrying reasons plus
      // six more would grow the card until it ran off the screen. The `Flexible`
      // below only means something once there is a ceiling for it to give way
      // against.
      constraints: const BoxConstraints(maxHeight: 380),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        border: Border.all(color: colors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(set: set, git: widget.git, isLoading: _changes.isLoading),
          Divider(height: 1, color: colors.line),
          Flexible(
            child: SingleChildScrollView(
              child: _Body(set: set, failure: _changes.failure),
            ),
          ),
          if (set case var it?) _UntrackedTally(it),
          Divider(height: 1, color: colors.line),
          _Footer(onOpen: widget.onOpen),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.set,
    required this.git,
    required this.isLoading,
  });

  final ChangeSet? set;
  final Fact<GitFacts>? git;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var style = context.type.bodySmall;

    // The probe's answer when there is one, the row's when there is not. They
    // measure different ranges — the cell is committed-only — so the numbers
    // can move once it lands, which is honest: the bigger one includes the work
    // an agent has not committed.
    var files = set?.changed.length ?? git?.value?.changes?.files;
    var added = set?.added ?? git?.value?.changes?.added;
    var removed = set?.removed ?? git?.value?.changes?.removed;
    var uncommitted = set == null
        ? git?.value?.dirty
        : set!.changed.where((f) => set!.uncommitted.contains(f.path)).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.lg,
        FwSpacing.md,
        FwSpacing.lg,
        FwSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: FwSpacing.sm,
                  children: [
                    Text(
                      files == null
                          ? '—'
                          : '$files file${files == 1 ? '' : 's'}',
                      style: style,
                    ),
                    if (added != null)
                      Text('+$added', style: style.copyWith(color: colors.grn)),
                    if (removed != null)
                      Text(
                        '-$removed',
                        style: style.copyWith(color: colors.red),
                      ),
                    if (uncommitted != null && uncommitted > 0)
                      Text(
                        '· $uncommitted uncommitted',
                        style: style.copyWith(color: colors.amber),
                      ),
                  ],
                ),
              ),
              // Only while the lists are still filling in, and never instead of
              // the header — the numbers above are already true.
              if (isLoading)
                SizedBox.square(
                  dimension: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.mut3,
                  ),
                ),
            ],
          ),
          const Gap(FwSpacing.xxs),
          Text(switch (set?.baseSource) {
            null => 'base ${git?.value?.base ?? '—'}',
            BaseSource.none => 'no base branch',
            BaseSource.configured => 'base ${set!.base} (configured)',
            BaseSource.inferred => 'base ${set!.base} (inferred)',
          }, style: context.type.micro.copyWith(color: colors.mut2)),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.set, required this.failure});

  final ChangeSet? set;
  final Object? failure;

  @override
  Widget build(BuildContext context) {
    if (failure != null && set == null) {
      return _Quiet('Could not read this checkout: $failure');
    }
    if (set == null) {
      return const _Quiet('Reading the files…');
    }

    var it = set!;
    if (it.isEmpty) {
      return _Quiet('Nothing changed against ${it.base ?? 'the base'}.');
    }

    var pinned = _pinnedOf(it);
    var shownPinned = pinned.files;
    var shownUntracked = pinned.untracked;
    var biggest = it.ordered(RankTier.ordinary);
    var shownBiggest = biggest.take(ChangesSummaryCard.biggestCap).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shownPinned.isNotEmpty || shownUntracked.isNotEmpty) ...[
          const _SectionLabel('LOOK HERE FIRST'),
          for (var ranked in shownPinned)
            _FileLine(
              file: ranked.file,
              reason: ranked.reason,
              uncommitted: it.uncommitted.contains(ranked.file.path),
            ),
          for (var entry in shownUntracked)
            _UntrackedLine(path: entry.path, reason: entry.reason),
        ],
        if (shownBiggest.isNotEmpty) ...[
          // **`BIGGEST` rather than `CHANGES`.** The section is a sample, not
          // the set, and a heading that claimed otherwise would make the `…N
          // more` below it read like a rendering accident.
          _SectionLabel(
            shownPinned.isEmpty && shownUntracked.isEmpty
                ? 'BIGGEST'
                : 'BIGGEST OF THE REST',
          ),
          for (var ranked in shownBiggest)
            _FileLine(
              file: ranked.file,
              uncommitted: it.uncommitted.contains(ranked.file.path),
            ),
          if (biggest.length > shownBiggest.length)
            _Quiet('… ${biggest.length - shownBiggest.length} more'),
        ],
      ],
    );
  }
}

/// What the two lists left out, **pinned below them rather than after them**.
///
/// A summary line, not list content: it is true of the whole delta, like the
/// header. Inside the scrolling body it was the first thing a long branch
/// pushed out of sight — found by capping the card's height and looking at it.
///
/// One line now that the low-signal tally is gone. Still its own widget, and
/// still outside the scroll view, because *where* it sits is the finding.
class _UntrackedTally extends StatelessWidget {
  const _UntrackedTally(this.set);

  final ChangeSet set;

  @override
  Widget build(BuildContext context) {
    var untracked = set.untracked.length - _pinnedOf(set).untracked.length;
    if (untracked <= 0) return const SizedBox.shrink();

    return _Quiet('$untracked untracked', color: context.colors.mut3);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FwSpacing.lg,
      FwSpacing.md,
      FwSpacing.lg,
      FwSpacing.xs,
    ),
    child: Text(label, style: context.type.micro),
  );
}

/// How wide a file name may get before it gives way instead of the directory.
const _nameMaxWidth = 220.0;

/// One file: status, path, counts, and the rule that pinned it.
///
/// **The name comes first and the directory follows it, dimmed.** A 420 px
/// popover cannot hold `app/lib/src/motion/timeline.dart`, and the tail is the
/// half that identifies the file — a plain `overflow: ellipsis` cuts exactly
/// the wrong end and leaves four rows all reading `app/lib/src/mot…`.
///
/// Drawing the directory first and letting *it* ellipsize was the first
/// attempt, and looking at it killed it twice over. The truncation looked
/// random — `app/lib/src/motion/` fitted whole on one row while the shorter
/// `docs/sup…` was cut on the next, because a `Spacer` and the directory's
/// `Flexible` both had flex 1 and split the free space between them. And even
/// fixed, it left the names on a ragged left edge, which is the column you
/// actually scan. Name first is what an editor's breadcrumb does, and for the
/// same reason.
class _FileLine extends StatelessWidget {
  const _FileLine({required this.file, required this.uncommitted, this.reason});

  final FileChange file;
  final bool uncommitted;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var slash = file.path.lastIndexOf('/');
    var directory = slash < 0 ? '' : file.path.substring(0, slash + 1);
    var name = slash < 0 ? file.path : file.path.substring(slash + 1);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 12,
                child: Text(
                  _letter(file.status),
                  style: context.type.micro.copyWith(color: _tone(colors)),
                ),
              ),
              const Gap(FwSpacing.xs),
              // **Unflexed, so it takes the width it needs.** A `Flexible`
              // here shares the free space with the directory by flex factor,
              // which truncates the name even when the row is half empty —
              // exactly the failure this layout exists to avoid, seen once in
              // each direction before it was right. The cap is the backstop for
              // a pathological name, and nothing normal reaches it.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _nameMaxWidth),
                child: Text(
                  name,
                  style: context.type.bodySmall,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              if (directory.isNotEmpty) ...[
                const Gap(FwSpacing.sm),
                // Everything left over — the only flexible child, so it is the
                // one that gives way when the row runs out.
                Expanded(
                  child: Text(
                    directory,
                    style: context.type.micro.copyWith(color: colors.mut3),
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              ] else
                const Spacer(),
              const Gap(FwSpacing.sm),
              // Fixed widths, so the two count columns line up down the card.
              SizedBox(
                width: 42,
                child: Text(
                  '+${file.added}',
                  textAlign: TextAlign.right,
                  style: context.type.micro.copyWith(color: colors.grn),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '-${file.removed}',
                  textAlign: TextAlign.right,
                  style: context.type.micro.copyWith(color: colors.red),
                ),
              ),
            ],
          ),
          if (reason != null || uncommitted)
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                [?reason, if (uncommitted) 'uncommitted'].join(' · '),
                style: context.type.micro.copyWith(color: colors.mut3),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

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

/// A pinned path that is not tracked yet — a file an agent wrote and has not
/// staged, which is the moment an attention rule exists for.
class _UntrackedLine extends StatelessWidget {
  const _UntrackedLine({required this.path, required this.reason});

  final String path;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var slash = path.lastIndexOf('/');
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 12,
                child: Text(
                  '?',
                  style: context.type.micro.copyWith(color: colors.mut3),
                ),
              ),
              const Gap(FwSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _nameMaxWidth),
                child: Text(
                  slash < 0 ? path : path.substring(slash + 1),
                  style: context.type.bodySmall,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              if (slash >= 0) ...[
                const Gap(FwSpacing.sm),
                Expanded(
                  child: Text(
                    path.substring(0, slash + 1),
                    style: context.type.micro.copyWith(color: colors.mut3),
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              [?reason, 'not tracked yet'].join(' · '),
              style: context.type.micro.copyWith(color: colors.mut3),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.difference_outlined, size: 13, color: colors.accent),
            const Gap(FwSpacing.sm),
            Expanded(
              child: Text(
                'Open changes',
                style: context.type.bodySmall.copyWith(color: colors.accent),
              ),
            ),
            Text('⌘⇧D', style: context.type.micro.copyWith(color: colors.mut3)),
          ],
        ),
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FwSpacing.lg,
      FwSpacing.sm,
      FwSpacing.lg,
      FwSpacing.sm,
    ),
    child: Text(
      text,
      style: context.type.micro.copyWith(color: color ?? context.colors.mut2),
    ),
  );
}

/// Which part of the branch's history the screen shows, as a control.
///
/// **A radio, not checkboxes**, and see [ChangeRange] for why: git answers with
/// a diff between two trees, so a set with a gap in it has no answer and a
/// checkbox is set semantics over a thing that is not a set. Click a row for
/// that row alone; shift-click a second for the run between them. Every state
/// this can reach is a real `git diff`, so there is nothing here that warns,
/// greys out, or takes back a tick it just accepted.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/popover.dart';
import '../ui/popover_menu.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';
import 'change_set.dart';

/// The popover's root, so a test can scope to it.
const rangePickerKey = Key('changes-range-picker');

/// The chip that opens it.
const rangeTriggerKey = Key('changes-range-trigger');

/// One row, by the sha it stands for — `worktree` for the working tree and
/// `everything` for the whole delta, neither of which is a commit.
Key rangeRowKey(String id) => ValueKey('changes-range-row.$id');

/// How the current range reads in the summary line.
///
/// **The base sentence, with more in it.** `base master (inferred)` already
/// answers *what am I looking at, against what*; a narrowed range is the same
/// question with a different answer, which is why it replaces that text rather
/// than sitting beside it — and why the chip *is* that text rather than a
/// second control next to it.
///
/// [withBase] is false under the comparison strip, which states the base for
/// all three tabs. There the unnarrowed chip says only `Everything`: the same
/// fact spelled twice, six pixels apart, is a difference a reader has to work
/// out is not one.
String rangeLabel(ChangeSet set, {bool withBase = true}) {
  if (set.range.isEverything) {
    // `no base` is said either way: it is not a duplicate of the strip's
    // `against <base>` — it is the reason every count beside it is smaller than
    // it looks, and the one state where the two halves of this screen can be
    // answering different questions.
    if (set.baseSource == BaseSource.none) return 'no base';
    if (!withBase) return 'Everything';
    return switch (set.baseSource) {
      BaseSource.none => 'no base',
      BaseSource.configured => 'base ${set.base} (configured)',
      BaseSource.inferred => 'base ${set.base} (inferred)',
    };
  }
  var covered = set.rangeCommits;
  if (set.range.endsAtWorkingTree) {
    return covered.isEmpty
        ? 'uncommitted only'
        : '${_commitCount(covered.length)} + uncommitted';
  }
  if (covered.length == 1) return 'commit ${covered.single.shortSha}';
  if (covered.isEmpty) return 'a range this branch no longer has';
  return '${_commitCount(covered.length)} · '
      '${covered.last.shortSha}…${covered.first.shortSha}';
}

String _commitCount(int n) => n == 1 ? '1 commit' : '$n commits';

/// The trigger and the list.
///
/// Stateless about the *selection* — that lives in the address, via the screen
/// — and stateful only about the shift-click anchor, which is an interaction
/// and belongs to the control.
class RangePicker extends StatefulWidget {
  const RangePicker({
    required this.set,
    required this.onRange,
    this.withBase = true,
    this.enabled = true,
    super.key,
  });

  final ChangeSet set;
  final ValueChanged<ChangeRange> onRange;

  /// Whether the unnarrowed label names the base — see [rangeLabel].
  final bool withBase;

  /// False while the first read is in flight, when there is no history to pick
  /// from yet.
  final bool enabled;

  @override
  State<RangePicker> createState() => _RangePickerState();
}

class _RangePickerState extends State<RangePicker> {
  /// The row a shift-click extends from: a commit, or null for the working
  /// tree — the same spelling [rangeBetween] takes, so *since this commit* is
  /// a shift-click onto the top row rather than a control of its own.
  ///
  /// **It has to outlive the popover**, which is the thing this got wrong
  /// first: picking a row closes the list, so an anchor cleared on close made
  /// *click one, reopen, shift-click another* — the only way the gesture can
  /// be performed — behave as a second plain click. Caught by the test, not by
  /// reading it.
  ///
  /// Nothing is hidden by keeping it: the anchor is always inside the current
  /// range, and the range's rows are the lit ones.
  CommitEntry? _anchor;
  var _hasAnchor = false;

  void _pick(
    PopoverController controller,
    CommitEntry? commit, {
    required bool extend,
  }) {
    var commits = widget.set.commits;
    if (extend && _hasAnchor) {
      widget.onRange(rangeBetween(_anchor, commit, commits));
    } else {
      _anchor = commit;
      _hasAnchor = true;
      widget.onRange(
        commit == null
            ? ChangeRange(from: commits.isEmpty ? null : commits.first.sha)
            : rangeOf(commit, commits),
      );
    }
    controller.close();
  }

  @override
  Widget build(BuildContext context) {
    var set = widget.set;
    // **Nothing below is marked while *Everything* is.** Every commit is
    // technically inside the whole delta, so marking them all made the top row
    // indistinguishable from a run that happened to span the branch — and a
    // list where every row is lit is a list that has stopped saying anything.
    // Picking the oldest commit and shift-clicking the working tree *is*
    // `everything`, and lands back on the top row, which is the honest answer.
    var covered = set.range.isEverything
        ? const <String>{}
        : {for (var commit in set.rangeCommits) commit.sha};

    return Popover(
      anchor: (context, controller) => _Trigger(
        label: rangeLabel(set, withBase: widget.withBase),
        narrowed: !set.range.isEverything,
        open: controller.isOpen,
        onTap: widget.enabled ? controller.toggle : null,
      ),
      content: (context, controller) => PopoverMenuSurface(
        minWidth: 300,
        maxWidth: 420,
        child: Column(
          key: rangePickerKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Gap(FwSpacing.xs),
                    _Row(
                      id: 'everything',
                      title: 'Everything',
                      detail: set.base == null
                          ? 'the whole delta'
                          : 'against ${set.base}',
                      on: set.range.isEverything,
                      onTap: (_) {
                        // Never an anchor: *everything* is the absence of a
                        // range, so a shift-click after it has nothing to
                        // extend from and is a plain click.
                        _hasAnchor = false;
                        widget.onRange(ChangeRange.everything);
                        controller.close();
                      },
                    ),
                    Divider(height: 1, color: context.colors.line2),
                    // **The working tree is row n+1, not a mode.** It is the
                    // end of the same list, which is what makes *uncommitted
                    // only* a click and *since this commit* a shift-click onto
                    // it.
                    _Row(
                      id: 'worktree',
                      title: 'Uncommitted work',
                      detail: 'the files on disk',
                      on:
                          !set.range.isEverything &&
                          set.range.endsAtWorkingTree,
                      onTap: (extend) =>
                          _pick(controller, null, extend: extend),
                    ),
                    for (var commit in set.commits.take(ChangesLimits.commits))
                      _Row(
                        id: commit.sha,
                        title: commit.subject,
                        detail: '${commit.shortSha} · ${commit.author}',
                        on: covered.contains(commit.sha),
                        onTap: (extend) =>
                            _pick(controller, commit, extend: extend),
                      ),
                    if (set.commits.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          FwSpacing.lg,
                          FwSpacing.md,
                          FwSpacing.lg,
                          FwSpacing.md,
                        ),
                        child: Text(
                          'Nothing is committed on this branch yet.',
                          style: context.type.bodySmall.copyWith(
                            color: context.colors.mut2,
                          ),
                        ),
                      ),
                    if (set.commitsTruncated)
                      _Note(
                        'Only the newest ${ChangesLimits.commits} commits are '
                        'listed. Everything still shows the whole delta.',
                      ),
                    const Gap(FwSpacing.xs),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: context.colors.line2),
            const _Note('Shift-click a second row for the run between them.'),
          ],
        ),
      ),
    );
  }
}

/// The chip in the summary line.
class _Trigger extends StatelessWidget {
  const _Trigger({
    required this.label,
    required this.narrowed,
    required this.open,
    required this.onTap,
  });

  final String label;

  /// Whether the range is anything other than the whole delta. A narrowed
  /// screen has to look narrowed from across the room — every count beside
  /// this chip is smaller than the branch's, and nothing else says so.
  final bool narrowed;

  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var tone = narrowed ? colors.accent : colors.mut2;
    return Tappable.builder(
      key: rangeTriggerKey,
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.sm,
          vertical: 1,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.radii.radiusSmall),
          color: narrowed
              ? colors.accentSoft
              : hovered || open
              ? colors.hoverOverlay
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: context.type.bodySmall.copyWith(color: tone)),
            const Gap(FwSpacing.xs),
            Icon(Icons.expand_more, size: 13, color: tone),
          ],
        ),
      ),
    );
  }
}

/// One selectable row. [onTap] is told whether shift was held.
class _Row extends StatelessWidget {
  const _Row({
    required this.id,
    required this.title,
    required this.detail,
    required this.on,
    required this.onTap,
  });

  final String id;
  final String title;
  final String detail;
  final bool on;
  final ValueChanged<bool> onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable.builder(
      key: rangeRowKey(id),
      // `HardwareKeyboard` rather than a `RawGestureDetector` with modifiers:
      // the tap is one gesture whose meaning depends on a key held while it
      // happens, which is exactly what the keyboard's own state answers.
      onTap: () =>
          onTap(HardwareKeyboard.instance.logicalKeysPressed.any(_isShift)),
      builder: (context, hovered) => Container(
        color: on
            ? colors.accentSoft
            : hovered
            ? colors.hoverOverlay
            : null,
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.sm,
        ),
        child: Row(
          children: [
            // A dot rather than a checkbox, because a checkbox is a promise
            // this control does not make.
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: FwSpacing.md),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? colors.accent : Colors.transparent,
                border: on ? null : Border.all(color: colors.line),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.type.bodySmall,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                  Text(
                    detail,
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

  static bool _isShift(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.shift;
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

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
      style: context.type.micro.copyWith(color: context.colors.mut2),
    ),
  );
}

import 'dart:async';

import 'package:flutterware/comparison_report.dart';
import 'package:flutter/material.dart';

import '../../capture/settle.dart';
import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../comparison_controller.dart';
import '../rules.dart';
import '../shot_store.dart';
import 'finding_body.dart';
import 'shot_image.dart';
import 'stage.dart';
import 'state_chip.dart';

const previewsTabKey = Key('comparison.previews');

Key previewRowKey(String id) => ValueKey('comparison.preview.$id');

/// The previews half: every entry on the left, two frames on the right.
///
/// Master and detail rather than a wall of thumbnails. A catalog is
/// hundreds of entries and a comparison is interested in the handful that
/// moved; a grid spends its whole area on the ones that did not, and gives the
/// two frames you actually care about a hundred pixels each.
class PreviewsTab extends StatefulWidget {
  const PreviewsTab({
    super.key,
    required this.half,
    required this.store,
    required this.settle,
    required this.selected,
    required this.onSelect,
    this.header,
  });

  final ComparisonHalf half;
  final ShotStore store;

  /// Where the frame decode declares itself, so a capture waits for it.
  final SettleRegistry settle;

  /// The entry id the address names, or null.
  final String? selected;
  final ValueChanged<String> onSelect;

  /// The half's verdict, drawn above the list — and **not** above a pushed
  /// page, which is about one step rather than about the half.
  final Widget? header;

  @override
  State<PreviewsTab> createState() => _PreviewsTabState();
}

class _PreviewsTabState extends State<PreviewsTab> {
  late final _shots = ShotPair(widget.store);
  // The default answers both first questions at once: side by side shows what
  // each frame is, and its head half carries the diff's boxes for where to
  // look.
  var _mode = StageMode.sideBySide;

  @override
  void initState() {
    super.initState();
    _shots.addListener(_onShots);
    // **Listened to, not diffed.** `ComparisonHalf.rows` is mutated in place,
    // so `didUpdateWidget` compares a list against itself and can never see a
    // row arrive: the first load ran against an empty list, found nothing, and
    // nothing ever asked again — a stage that said "neither side rendered"
    // over two frames sitting in the cache.
    widget.half.addListener(_onRows);
    widget.settle.add(_shots);
    _loadSelected();
  }

  @override
  void didUpdateWidget(PreviewsTab old) {
    super.didUpdateWidget(old);
    if (!identical(old.half, widget.half)) {
      old.half.removeListener(_onRows);
      widget.half.addListener(_onRows);
    }
    if (old.selected != widget.selected) _loadSelected();
  }

  void _onRows() {
    if (mounted) _loadSelected();
  }

  void _onShots() {
    if (mounted) setState(() {});
  }

  ComparedItem? get _current {
    var rows = widget.half.rows;
    if (rows.isEmpty) return null;
    // **The first finding, not the first row.** A list ranked worst-first opens
    // on the thing most likely to be a mistake, which is the whole reason it is
    // ranked.
    return rows.firstWhere(
      (row) => row.id == widget.selected,
      orElse: () => rows.firstWhere(
        (row) => row.state.isFinding,
        orElse: () => rows.first,
      ),
    );
  }

  void _loadSelected() {
    var shots = _current?.shots;
    unawaited(_shots.load(baseKey: shots?.base, headKey: shots?.head));
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var current = _current;

    var body = Row(
      key: previewsTabKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: colors.line)),
            ),
            child: _Index(
              half: widget.half,
              selected: current?.id,
              onSelect: widget.onSelect,
            ),
          ),
        ),
        Expanded(
          child: current == null
              ? const SizedBox.shrink()
              : _Detail(
                  item: current,
                  shots: _shots,
                  mode: _mode,
                  onMode: (mode) => setState(() => _mode = mode),
                ),
        ),
      ],
    );

    // Above the list, not above the tab: a pushed step page replaces this
    // whole subtree, and a header describing the half has no business over a
    // page describing one step.
    if (widget.header == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.header!,
        Divider(height: 1, color: colors.line),
        Expanded(child: body),
      ],
    );
  }

  @override
  void dispose() {
    widget.half.removeListener(_onRows);
    widget.settle.remove(_shots);
    _shots
      ..removeListener(_onShots)
      ..dispose();
    super.dispose();
  }
}

/// Every entry, worst first.
///
/// Findings first, then the rest under a divider. A list that hides what it
/// looked at cannot be told from a list that did not look — and the entries
/// that came out identical are still the answer to "did you check this one".
class _Index extends StatelessWidget {
  const _Index({
    required this.half,
    required this.selected,
    required this.onSelect,
  });

  final ComparisonHalf half;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    var rules = RuleSet(half.rules);
    var findings = [
      for (var row in half.rows)
        if (row.state.isFinding && !rules.hidesAll(row)) row,
    ];
    // Demoted, not deleted. The comparison design already settled this shape
    // for `skipped` rows — a row that is missing tells a reader nothing — and
    // a row a *rule* removed is the same claim made about the reader instead
    // of about the tool.
    var hidden = [
      for (var row in half.rows)
        if (row.state.isFinding && rules.hidesAll(row)) row,
    ];
    var quiet = [
      for (var row in half.rows)
        if (!row.state.isFinding) row,
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.sm),
      children: [
        for (var row in findings)
          _IndexRow(
            item: row,
            selected: row.id == selected,
            onTap: () => onSelect(row.id),
          ),
        if (findings.isEmpty && hidden.isEmpty && !half.isRunning)
          Padding(
            padding: const EdgeInsets.all(FwSpacing.xl),
            child: Text(
              'Nothing changed.',
              style: context.type.body.copyWith(color: context.colors.mut),
            ),
          ),
        // The rows still owed a verdict, so the list has its full shape from
        // the moment the plan lands and only the answers arrive late.
        if (half.pending.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.xl,
              FwSpacing.lg,
              FwSpacing.xl,
              FwSpacing.sm,
            ),
            child: Text(
              'STILL RENDERING · ${half.pending.length}',
              style: context.type.micro.copyWith(color: context.colors.mut),
            ),
          ),
          for (var id in half.pending) _PendingRow(id),
        ],
        if (hidden.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.xl,
              FwSpacing.lg,
              FwSpacing.xl,
              FwSpacing.sm,
            ),
            child: Text(
              '${hidden.length} HIDDEN BY YOUR RULES',
              style: context.type.micro.copyWith(color: context.colors.mut),
            ),
          ),
          for (var row in hidden)
            _IndexRow(
              item: row,
              selected: row.id == selected,
              onTap: () => onSelect(row.id),
            ),
        ],
        if (quiet.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.xl,
              FwSpacing.lg,
              FwSpacing.xl,
              FwSpacing.sm,
            ),
            child: Text(
              '${quiet.length} UNCHANGED',
              style: context.type.micro.copyWith(color: context.colors.mut),
            ),
          ),
          for (var row in quiet)
            _IndexRow(
              item: row,
              selected: row.id == selected,
              onTap: () => onSelect(row.id),
            ),
        ],
      ],
    );
  }
}

/// A row whose verdict has not landed yet. Not tappable — there is nothing
/// behind it until its diff arrives, and then it becomes a real row.
class _PendingRow extends StatelessWidget {
  const _PendingRow(this.id);

  final String id;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var hash = id.indexOf('#');
    var name = hash < 0 ? id : id.substring(hash + 1);
    var file = hash < 0 ? '' : id.substring(0, hash);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.xl,
        vertical: FwSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: context.type.body.copyWith(color: colors.mut),
                  overflow: TextOverflow.ellipsis,
                ),
                if (file.isNotEmpty)
                  Text(
                    file,
                    style: context.type.micro.copyWith(color: colors.mut2),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const Gap(FwSpacing.sm),
          Text(
            'rendering…',
            style: context.type.micro.copyWith(color: colors.mut2),
          ),
        ],
      ),
    );
  }
}

class _IndexRow extends StatelessWidget {
  const _IndexRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ComparedItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var hash = item.id.indexOf('#');
    var name = hash < 0 ? item.id : item.id.substring(hash + 1);
    var file = hash < 0 ? '' : item.id.substring(0, hash);

    return Tappable(
      key: previewRowKey(item.id),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.xl,
          vertical: FwSpacing.sm,
        ),
        color: selected ? colors.accent.withValues(alpha: 0.10) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: context.type.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (file.isNotEmpty)
                    Text(
                      file,
                      style: context.type.micro.copyWith(color: colors.mut),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Gap(FwSpacing.sm),
            // Named, not coloured. The row already carries a `StateChip`, and
            // the events pane's channel palette collides with it on the two
            // colours that carry meaning — green is `added` and `analytics`,
            // amber is `changed` and `db`. Colour stays for state.
            if (item.state.isFinding) ...[
              Text(
                item.channelsFired.join(' · '),
                style: context.type.micro.copyWith(color: colors.mut),
              ),
              const Gap(FwSpacing.sm),
              StateChip(item.state),
            ],
          ],
        ),
      ),
    );
  }
}

/// One entry: the stage, and what the other channels found under it.
class _Detail extends StatelessWidget {
  const _Detail({
    required this.item,
    required this.shots,
    required this.mode,
    required this.onMode,
  });

  final ComparedItem item;
  final ShotPair shots;
  final StageMode mode;
  final ValueChanged<StageMode> onMode;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FwSpacing.xl,
            FwSpacing.lg,
            FwSpacing.xl,
            FwSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(child: Text(item.id, style: context.type.bodyStrong)),
              StateChip(item.state),
            ],
          ),
        ),
        if (item.note case var note?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.xl,
              0,
              FwSpacing.xl,
              FwSpacing.sm,
            ),
            child: Text(
              note,
              style: context.type.caption.copyWith(color: colors.red),
            ),
          ),
        FindingBody(
          item: item,
          shots: shots,
          mode: mode,
          onMode: onMode,
          // A skipped entry has no pictures and never will: nothing was
          // rendered *on purpose*, which is not a failed decode and owes the
          // reader a sentence rather than a spinner.
          whenNotRendered: item.state == ComparedState.skipped
              ? const _NotRendered()
              : null,
        ),
      ],
    );
  }
}

/// The skipped entry's pane — the same sentence the scenarios half earned for
/// its "Not replayed" state, said for a render.
class _NotRendered extends StatelessWidget {
  const _NotRendered();

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all, size: FwIconSize.lg, color: colors.mut2),
            const Gap(FwSpacing.md),
            Text('Not re-rendered', style: context.type.bodyStrong),
            const Gap(FwSpacing.sm),
            Text(
              'Nothing that decides its pixels changed between the two sides '
              '— not a file in its import closure, not an asset, not a '
              'lockfile — so both sides would have drawn the same frame and '
              'neither was rendered.',
              textAlign: TextAlign.center,
              style: context.type.caption.copyWith(color: colors.mut),
            ),
          ],
        ),
      ),
    );
  }
}

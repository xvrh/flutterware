import 'package:flutterware/comparison_report.dart';
import 'package:flutter/material.dart';

import '../../ui/count_badge.dart';
import '../../ui/theme.dart';

/// What *kind* of change this branch made, above both panes.
///
/// **Not the counts.** The receipt strip directly above already says
/// `7 changed · 9 unchanged`, and drawing them twice was the first thing
/// building this got wrong — worse, the two disagreed, because a scenario
/// half counts flows in the list and the channels live on the steps inside
/// them: three numbers with two meanings on one screen. So this says only
/// what the receipt cannot — which channels spoke, which stayed silent, and
/// what the findings are mostly made of.
///
/// **Full width, in the header slot**, because the files tab already puts
/// `0 files +0 -0` there and because a verdict is about both panes. Drawn
/// inside the 320px index instead, the chips wrap to a second row, the shape
/// line truncates and it costs the list ~110px of height. Design:
/// `docs/superpowers/specs/2026-08-30-comparison-ui-pass-design.md` §1.
///
/// **Counted over findings, never over every row.** A comparison is hundreds
/// of rows and a handful of findings, so everything here is O(findings) by
/// construction — the same reason `ComparisonIndex.ok` is a scan rather than a
/// built list.
class ComparisonVerdict extends StatelessWidget {
  const ComparisonVerdict({
    super.key,
    required this.findings,
    required this.unit,
    this.newCount,
  });

  /// The things whose channels are counted. For the scenario half these are
  /// its **steps**, not its flows: a flow's verdict is a roll-up, and the
  /// channels live underneath it.
  final List<ComparedItem> findings;

  /// What one of [findings] is called, singular — `step`, `entry`.
  ///
  /// The counts here are over these and the receipt strip's are over what the
  /// list shows, so the noun is the thing that keeps a reader from reading one
  /// as the other.
  final String unit;

  /// How many rows the list shows were not in the previous comparison. Null
  /// before there has ever been one, which is not the same as zero and must
  /// not read as it.
  final int? newCount;

  static const _channels = ['pixels', 'tree', 'texts', 'events'];

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;

    var fired = <String, int>{};
    for (var item in findings) {
      for (var channel in item.channelsFired) {
        fired[channel] = (fired[channel] ?? 0) + 1;
      }
    }
    var quiet = [
      for (var channel in _channels)
        if (!fired.containsKey(channel)) channel,
    ];
    var shapes = foldChannelDeltas([for (var item in findings) item.deltas]);

    if (fired.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.xl,
        FwSpacing.md,
        FwSpacing.xl,
        FwSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `Wrap`, not `Row`: this header is as wide as the window, and a
          // window can be narrow. The files tab's own strip learned this the
          // hard way and says so in its docstring.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: FwSpacing.sm,
            runSpacing: FwSpacing.xs,
            children: [
              for (var channel in _channels)
                if (fired[channel] case var count?)
                  _ChannelCount(label: channel, count: count, unit: unit),
              if (newCount case var count? when count > 0)
                Text(
                  '$count new since the last comparison',
                  style: context.type.caption.copyWith(color: colors.amber),
                ),
            ],
          ),
          if (findings.isNotEmpty && quiet.isNotEmpty) ...[
            const Gap(FwSpacing.xs),
            // The strongest line the comparison can print, and no chip can
            // say it: every finding here was invisible to a screenshot.
            Text(
              'nothing moved on ${_list(quiet)}',
              style: context.type.caption.copyWith(color: colors.mut),
            ),
          ],
          if (shapes.isNotEmpty && shapes.first.repeated) ...[
            const Gap(FwSpacing.xs),
            _Shape(shapes.first, unit: unit),
          ],
        ],
      ),
    );
  }

  /// `pixels, tree or texts` — the last join is a word, because this is read
  /// as a sentence rather than scanned as a list.
  static String _list(List<String> names) => switch (names.length) {
    0 => '',
    1 => names.single,
    _ => '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}',
  };
}

/// What the comparison is mostly made of, when it is mostly made of one thing.
///
/// Drawn only when the top shape actually repeats: on a branch whose findings
/// are all different, this line would be one finding pretending to be a
/// summary.
class _Shape extends StatelessWidget {
  const _Shape(this.row, {required this.unit});

  final FoldedDelta row;
  final String unit;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var delta = row.delta;
    var name = [?delta.subchannel, ?delta.subject, ?delta.property].join(' · ');
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            style: context.type.caption.copyWith(color: colors.mut),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Gap(FwSpacing.sm),
        CountBadge(row.count, active: false),
        const Gap(FwSpacing.sm),
        Text(
          'in ${row.items} $unit${row.items == 1 ? '' : 's'}',
          style: context.type.micro.copyWith(color: colors.mut),
        ),
      ],
    );
  }
}

/// A channel that had something to say, and how many findings it was.
///
/// Not a control yet — v1 is read-only, and a chip that looks pressable and
/// is not is worse than one that does not. The shape is the one the toggle
/// will take, so v1.5 changes its behaviour rather than its drawing.
class _ChannelCount extends StatelessWidget {
  const _ChannelCount({
    required this.label,
    required this.count,
    required this.unit,
  });

  final String label;
  final int count;
  final String unit;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.radii.radius),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label · $count $unit${count == 1 ? '' : 's'}',
            style: context.type.micro.copyWith(color: colors.ink2),
          ),
        ],
      ),
    );
  }
}

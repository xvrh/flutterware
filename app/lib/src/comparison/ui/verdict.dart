import 'package:flutterware/comparison_report.dart';
import 'package:flutter/material.dart';

import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../rules.dart';

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
    this.rules = const [],
    this.onToggle,
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

  /// What this reader has excluded. Every one of them is drawn, struck
  /// through, carrying the count it is suppressing — a rule you cannot see is
  /// a rule that lies to you on the next comparison.
  final List<ComparisonRule> rules;

  /// Null draws the chips as labels rather than as controls, which is what v1
  /// did: a chip that looks pressable and is not is worse than one that does
  /// not.
  final ValueChanged<ComparisonRule>? onToggle;

  static const _channels = ['pixels', 'tree', 'texts', 'events'];

  /// Subchannel keys are prefixed so one map can hold both without a
  /// subchannel named `tree` ever colliding with the channel called `tree`.
  static const _subPrefix = 'events/';

  static List<String> _facetsOf(ChannelDelta delta) => [
    delta.channel,
    if (delta.subchannel case var sub?) '$_subPrefix$sub',
  ];

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;

    var set = RuleSet(rules);

    // Counted twice on purpose. `fired` is what a reader can still see, and is
    // what the chips read; `total` ignores every rule, and is what an excluded
    // chip has to show — a chip reading `0` is one nobody would ever turn back
    // on, which `CountBadge`'s own doc is about.
    var fired = <String, int>{};
    var total = <String, int>{};
    var hidden = 0;
    for (var item in findings) {
      var seen = <String>{};
      var seenAll = <String>{};
      for (var delta in item.deltas) {
        seenAll.addAll(_facetsOf(delta));
        if (!set.hides(delta)) seen.addAll(_facetsOf(delta));
      }
      for (var key in seenAll) {
        total[key] = (total[key] ?? 0) + 1;
      }
      for (var key in seen) {
        fired[key] = (fired[key] ?? 0) + 1;
      }
      if (set.hidesAll(item)) hidden++;
    }

    var quiet = [
      for (var channel in _channels)
        if (!total.containsKey(channel)) channel,
    ];
    // Pixels are excluded from the fold on purpose. A pixel delta has no
    // subject and no field — its property is the word `changed` — so every
    // one of them groups together and the row comes out claiming *the same
    // field moved in 6 of 6 entries · changed*, which is nonsense wearing a
    // number. The percentage on each row is what says how much moved.
    var shapes = foldChannelDeltas([
      for (var item in findings)
        [
          for (var delta in set.visible(item))
            if (delta.channel != 'pixels') delta,
        ],
    ]);
    // Every subchannel the events channel actually produced, most-said first.
    // `system` is the whole reason this exists: it was 11 of 11 findings here
    // and 192 of 293 event differences on a consumer's suite, and it is a
    // *sub*channel, so a chip row that stops at `events` cannot reach it.
    var subchannels = [
      for (var key in total.keys)
        if (key.startsWith(_subPrefix)) key,
    ]..sort((a, b) => (total[b] ?? 0).compareTo(total[a] ?? 0));

    if (total.isEmpty) return const SizedBox.shrink();
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
                if (total[channel] case var count?)
                  _ChannelCount(
                    label: channel,
                    count: fired[channel] ?? 0,
                    hiddenCount: count,
                    unit: unit,
                    excluded: set.has('channel', channel),
                    onToggle: onToggle == null
                        ? null
                        : () =>
                              onToggle!(ComparisonRule.on('channel', channel)),
                  ),
              for (var key in subchannels)
                _ChannelCount(
                  label: key.substring(_subPrefix.length),
                  count: fired[key] ?? 0,
                  hiddenCount: total[key]!,
                  unit: unit,
                  excluded: set.has(
                    'subchannel',
                    key.substring(_subPrefix.length),
                  ),
                  onToggle: onToggle == null
                      ? null
                      : () => onToggle!(
                          ComparisonRule.on(
                            'subchannel',
                            key.substring(_subPrefix.length),
                          ),
                        ),
                ),
              if (newCount case var count? when count > 0)
                Text(
                  '$count new since the last comparison',
                  style: context.type.caption.copyWith(color: colors.amber),
                ),
            ],
          ),
          if (hidden > 0) ...[
            const Gap(FwSpacing.xs),
            Text(
              '$hidden $unit${hidden == 1 ? '' : 's'} hidden by '
              '${rules.length} rule${rules.length == 1 ? '' : 's'}',
              style: context.type.caption.copyWith(color: colors.amber),
            ),
          ],
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
            _Shape(shapes.first, unit: unit, of: findings.length),
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
/// What most of the findings turned out to be, said as a sentence.
///
/// This read `system · flutter/textinput TextInput.setClient ·
/// data.arguments[1].autofill.uniqueIdentifier ⟨11⟩ in 11 steps` — three
/// identifiers glued with dots and two numbers that were the same number.
/// Nothing in it told a reader what to conclude, which is the whole job of a
/// line in a summary.
///
/// So: the claim first, in words, and the identifiers after the dash where
/// they are reference rather than message. The proportion is the point — *all
/// of them* and *4 of 11* are different situations and a bare count says
/// neither.
class _Shape extends StatelessWidget {
  const _Shape(this.row, {required this.unit, required this.of});

  final FoldedDelta row;
  final String unit;

  /// How many findings there are in total — the denominator that turns a
  /// count into a proportion.
  final int of;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var how = row.items >= of
        ? 'all $of $unit${of == 1 ? '' : 's'}'
        : '${row.items} of $of';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'the same field moved in $how'),
          TextSpan(
            text: ' — ${_where(row.delta)}',
            style: TextStyle(color: colors.mut3),
          ),
        ],
      ),
      style: context.type.caption.copyWith(color: colors.mut),
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Which field, in the shortest form that still identifies it.
  ///
  /// The property is trimmed to its last two segments the way
  /// `ChannelLines` already trims a tree path to its last two names, and for
  /// the same reason: `data.arguments[1].autofill.uniqueIdentifier` is a wire
  /// path whose first half is plumbing, and `autofill.uniqueIdentifier` is the
  /// half anybody could name.
  static String _where(ChannelDelta delta) {
    return [
      ?delta.subject,
      if (delta.property case var property?) _tail(property),
    ].join(' · ');
  }

  static String _tail(String property) {
    var parts = property.split('.');
    return parts.length <= 2
        ? property
        : parts.sublist(parts.length - 2).join('.');
  }
}

/// A channel or subchannel, its count, and whether it is being looked at.
///
/// An excluded chip is struck through and keeps the count it is **hiding**,
/// not the zero it is showing: *"Off recedes rather than disappears — the
/// count is still the reason a reader would turn it back on."*
class _ChannelCount extends StatelessWidget {
  const _ChannelCount({
    required this.label,
    required this.count,
    required this.hiddenCount,
    required this.unit,
    required this.excluded,
    this.onToggle,
  });

  final String label;

  /// How many are visible under the rules in force.
  final int count;

  /// How many there are when nothing is excluded.
  final int hiddenCount;

  final String unit;
  final bool excluded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var shown = excluded ? hiddenCount : count;
    // A channel emptied *by a rule* is not a channel that was silent, and the
    // two must not read alike: `events · 0 steps` in full ink asserts the
    // events channel found nothing, when what happened is that everything it
    // found was on a subchannel this reader excluded.
    var emptied = !excluded && count == 0 && hiddenCount > 0;
    var chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: excluded ? colors.panel2 : null,
        borderRadius: BorderRadius.circular(context.radii.radius),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (excluded) ...[
            Text('−', style: context.type.micro.copyWith(color: colors.mut)),
            const Gap(FwSpacing.xs),
          ],
          Text(
            '$label · $shown $unit${shown == 1 ? '' : 's'}',
            style: context.type.micro.copyWith(
              color: excluded || emptied ? colors.mut : colors.ink2,
              decoration: excluded ? TextDecoration.lineThrough : null,
            ),
          ),
          if (excluded) ...[
            const Gap(FwSpacing.xs),
            Icon(Icons.close, size: 11, color: colors.mut),
          ],
        ],
      ),
    );
    if (onToggle == null) return chip;
    return Tooltip(
      message: excluded ? 'Show $label again' : 'Stop showing $label',
      waitDuration: const Duration(milliseconds: 400),
      child: Tappable(onTap: onToggle, child: chip),
    );
  }
}

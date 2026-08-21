import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../channels.dart';
import '../tree_diff.dart';

/// The tree, the texts and the events, as prose.
///
/// What the percentage cannot say. A pixel fraction tells you something
/// moved and roughly how much of the screen; it never tells you that a padding
/// went from 12 to 20, and that line is usually the whole finding.
class ChannelLines extends StatelessWidget {
  const ChannelLines(this.item, {super.key});

  final ComparedItem item;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(FwSpacing.xl),
        children: [
          if (item.tree?.changed ?? false) ...[
            Text('TREE', style: context.type.micro.copyWith(color: colors.mut)),
            const Gap(FwSpacing.xs),
            for (var delta in item.tree!.diff.deltas.take(20))
              _Line(_describe(delta)),
            if (item.tree!.diff.deltas.length > 20)
              _Line('… ${item.tree!.diff.deltas.length - 20} more'),
            const Gap(FwSpacing.lg),
          ],
          if (item.texts case var texts?) ...[
            Text('TEXT', style: context.type.micro.copyWith(color: colors.mut)),
            const Gap(FwSpacing.xs),
            for (var text in texts.removed) _Line('- $text', color: colors.red),
            for (var text in texts.added) _Line('+ $text', color: colors.grn),
            const Gap(FwSpacing.lg),
          ],
          if (item.events case var events?) ...[
            Text(
              'ON THE WAY HERE',
              style: context.type.micro.copyWith(color: colors.mut),
            ),
            const Gap(FwSpacing.xs),
            for (var event in events.removed)
              _Line('- $event', color: colors.red),
            for (var event in events.added)
              _Line('+ $event', color: colors.grn),
          ],
        ],
      ),
    );
  }

  /// A delta in the words a reader would use.
  ///
  /// The path is trimmed to its last two names: the whole thing is every widget
  /// from the entry's root down, which is a line of chrome per finding before
  /// anything that changed. The full path stays in `index.json`.
  static String _describe(TreeDelta delta) {
    var parts = delta.path.split(' › ');
    var tail = (parts.length <= 2 ? parts : parts.sublist(parts.length - 2))
        .join(' › ');
    return switch (delta.kind) {
      TreeDeltaKind.added => '+ $tail',
      TreeDeltaKind.removed => '- $tail',
      _ => '$tail  ${delta.property}  ${delta.base} → ${delta.head}',
    };
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: SelectableText(
      text,
      style: context.type.caption.copyWith(color: color),
    ),
  );
}

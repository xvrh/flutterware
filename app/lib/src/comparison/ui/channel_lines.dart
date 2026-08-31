import 'package:flutterware/comparison_report.dart';
import 'package:flutter/material.dart';

import '../../ui/theme.dart';

/// What moved, on every channel that had something to say.
///
/// **What the percentage cannot say.** A pixel fraction says something moved
/// and roughly how much of the screen; it never says that a padding went from
/// 12 to 20, and that line is usually the whole finding.
///
/// This was a footnote — a flat list of pre-formatted strings under the two
/// frames — and on four of the seven shapes of finding it is now the subject
/// of the page. Read as one it does not hold up: every delta was one opaque
/// string, so `200 → 500` sat in the same grey as the address that merely
/// located it, nothing aligned, and a double space had to work as a column
/// separator. A delta has three parts and is drawn as three now: **what
/// moved**, **from and to**, and **where** — in that order, because the first
/// two are the news and the third is the address.
class ChannelLines extends StatelessWidget {
  const ChannelLines(this.item, {super.key});

  final ComparedItem item;

  /// How many rows one channel draws before it stops and says how many it cut.
  ///
  /// One number for all three, where the tree took 20 and the events channel
  /// inherited the model's 50 — two cap regimes on one screen, expressed two
  /// ways.
  static const _max = 24;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var tree = [
      for (var delta in item.tree?.diff.deltas ?? const <TreeDelta>[])
        if (delta.kind != TreeDeltaKind.shifted) delta,
    ];
    // Folded like the events channel, and sorted so like sits with like: a
    // step whose network, database and log all moved was interleaving them in
    // capture order, which is the order nobody reads in.
    var events =
        foldChannelDeltas([
          [
            for (var delta in item.deltas)
              if (delta.channel == 'events' &&
                  delta.property != 'added' &&
                  delta.property != 'removed')
                delta,
          ],
        ])..sort((a, b) {
          var by = (a.delta.subchannel ?? '').compareTo(
            b.delta.subchannel ?? '',
          );
          return by != 0
              ? by
              : (a.delta.subject ?? '').compareTo(b.delta.subject ?? '');
        });

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(FwSpacing.xl),
        children: [
          if (tree.isNotEmpty) ...[
            _Header('TREE', dropped: tree.length - _max),
            for (var delta in tree.take(_max))
              switch (delta.kind) {
                TreeDeltaKind.added => _Gone(
                  '+ ${_where(delta.path)}',
                  added: true,
                ),
                TreeDeltaKind.removed => _Gone('- ${_where(delta.path)}'),
                _ => _Moved(
                  what: delta.property ?? '',
                  base: delta.base,
                  head: delta.head,
                  where: _where(delta.path),
                ),
              },
            const Gap(FwSpacing.lg),
          ],
          if (item.texts case var texts?) ...[
            _Header('TEXT', dropped: 0),
            for (var text in texts.removed) _Gone('- $text'),
            for (var text in texts.added) _Gone('+ $text', added: true),
            const Gap(FwSpacing.lg),
          ],
          if (item.events case var found?) ...[
            _Header(
              'ON THE WAY HERE',
              dropped: found.deltasDropped + (events.length - _max),
            ),
            for (var event in found.removed) _Gone('- $event'),
            for (var event in found.added) _Gone('+ $event', added: true),
            for (var row in events.take(_max))
              _Moved(
                // When the title is what moved it is already the `base`
                // column, and naming the event by it as well printed one long
                // statement twice on one line.
                what: row.delta.property == 'title'
                    ? 'title'
                    : shortProperty(row.delta.property ?? ''),
                base: row.delta.base,
                head: row.delta.head,
                where: row.delta.property == 'title'
                    ? row.delta.subchannel ?? ''
                    : '${row.delta.subchannel} ${row.delta.subject}',
                times: row.repeated ? row.count : null,
              ),
          ],
        ],
      ),
    );
  }

  /// A tree path trimmed to its last two names: the whole thing is every
  /// widget from the root down, which is a line of chrome per finding before
  /// anything that changed. The full path stays in `index.json`.
  static String _where(String path) {
    var parts = path.split(' › ');
    return (parts.length <= 2 ? parts : parts.sublist(parts.length - 2)).join(
      ' › ',
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label, {required this.dropped});

  final String label;
  final int dropped;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: FwSpacing.xs),
    child: Row(
      children: [
        Text(
          label,
          style: context.type.micro.copyWith(color: context.colors.mut),
        ),
        if (dropped > 0) ...[
          const Gap(FwSpacing.sm),
          Text(
            '$dropped more not shown',
            style: context.type.micro.copyWith(color: context.colors.mut3),
          ),
        ],
      ],
    ),
  );
}

/// One field that moved: what, from and to, and then where.
///
/// The values carry the page's ink and the address recedes, because
/// `200 → 500` is the finding and `network POST /login` is only where to go
/// and look for it. Everything used to be one grey.
class _Moved extends StatelessWidget {
  const _Moved({
    required this.what,
    required this.base,
    required this.head,
    required this.where,
    this.times,
  });

  final String what;
  final String? base;
  final String? head;
  final String where;
  final int? times;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: what,
              style: TextStyle(color: colors.mut, fontWeight: FontWeight.w600),
            ),
            const TextSpan(text: '   '),
            TextSpan(
              text: '$base → $head',
              style: TextStyle(color: colors.ink),
            ),
            if (times case var count?)
              TextSpan(
                text: '  × $count',
                style: TextStyle(color: colors.mut3),
              ),
            TextSpan(
              text: '   ·   $where',
              style: TextStyle(color: colors.mut3),
            ),
          ],
        ),
        style: context.type.caption,
      ),
    );
  }
}

/// Something that came or went, which has no *from and to* to show.
class _Gone extends StatelessWidget {
  const _Gone(this.text, {this.added = false});

  final String text;
  final bool added;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: SelectableText(
      text,
      style: context.type.caption.copyWith(
        color: added ? context.colors.grn : context.colors.red,
      ),
    ),
  );
}

/// A field path trimmed to its last two segments.
///
/// The same rule the verdict strip uses, in one place rather than two: the
/// strip was saying `autofill.uniqueIdentifier` while the line under it said
/// `data.arguments[1].autofill.uniqueIdentifier`, which is one fact wearing
/// two names on one screen. The first half of that path is wire plumbing.
String shortProperty(String property) {
  var parts = property.split('.');
  return parts.length <= 2
      ? property
      : parts.sublist(parts.length - 2).join('.');
}

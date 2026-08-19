import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart' show Tone;

import '../../inspect/inspect_dock.dart';
import '../../lints/model/classification.dart';
import '../../lints/model/options_scan.dart';
import '../../lints/model/rule_catalog.dart';
import '../../ui/action_button.dart';
import '../../ui/empty_state.dart';
import '../../ui/error_state.dart';
import '../../ui/loading_state.dart';
import '../../ui/panel_header.dart';
import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../native_plugin.dart';
import 'lints_core.dart';

const _controlHeight = 32.0;
const _rowHeight = 48.0;

class LintsPlugin extends NativePlugin<LintsCore> {
  LintsPlugin(super.core);

  @override
  String? get busyWith {
    if (core.isPricing) return 'pricing lint rules';
    if (core.classification == null && core.error == null) {
      return 'scanning lint options';
    }
    return null;
  }

  @override
  Widget buildPanel(BuildContext context) => _LintsPanel(plugin: this);
}

class _LintsPanel extends StatefulWidget {
  const _LintsPanel({required this.plugin});

  final LintsPlugin plugin;

  @override
  State<_LintsPanel> createState() => _LintsPanelState();
}

class _LintsPanelState extends State<_LintsPanel> {
  var _tab = LintBucket.unevaluated;
  var _query = '';
  var _sort = _Sort.newest;

  /// Selected options file, or null for the whole-repo union.
  String? _scope;

  LintsCore get _core => widget.plugin.core;

  @override
  void initState() {
    super.initState();
    _core.track();
  }

  // A config reload swaps the core under a mounted panel; tracking only in
  // initState goes permanently cold.
  @override
  void didUpdateWidget(covariant _LintsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _core.track();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.plugin,
      builder: (context, _) {
        var classification = _core.classification;
        if (classification == null) {
          var error = _core.error;
          if (error != null) {
            return ErrorState(
              title: 'Could not scan the lint options',
              message: error,
              onRetry: () => _core.reload(),
            );
          }
          return const LoadingState(title: 'Scanning options files…');
        }
        return _body(context, classification);
      },
    );
  }

  Widget _body(BuildContext context, LintsClassification classification) {
    var scan = _core.scan!;
    var scope = scan.files.firstWhereOrNull((f) => f.path == _scope);
    var buckets = _Buckets.of(classification, scope);
    var rows = _visibleRows(buckets.inBucket(_tab));
    var colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FwPanelHeader(
          'Lints',
          subtitle: _subtitle(classification),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: FwSpacing.md,
            children: [
              TextButton(
                onPressed: () => _core.reload(),
                child: const Text('Rescan'),
              ),
              FwActionButton(
                label: 'Price rules',
                primary: true,
                tooltip:
                    'One dart analyze run with every unevaluated rule on — '
                    'counts what each would flag today',
                onPressed: classification.hasCatalog && !_core.isPricing
                    ? () async {
                        await _core.price();
                      }
                    : null,
              ),
            ],
          ),
        ),
        if (_core.pricingError case var error?) _ErrorBar(message: error),
        if (!classification.hasCatalog)
          _Advisory(
            message:
                'No rule catalog for Dart ${_core.dartVersion ?? '?'} yet — '
                'the first fetch needs the network. Local buckets still '
                'stand; nothing can be called unevaluated without it.',
          ),
        _Stats(classification: classification, core: _core),
        _FilesStrip(
          files: scan.files,
          selected: _scope,
          onSelect: (path) => setState(() => _scope = path),
        ),
        InspectTabStrip(
          tabs: [
            for (var bucket in LintBucket.values)
              InspectDockTab(
                id: bucket.name,
                label: _tabLabel(bucket),
                badge: buckets.inBucket(bucket).length,
                body: (_) => const SizedBox.shrink(),
              ),
          ],
          current: _tab.name,
          onSelect: (id) => setState(() => _tab = LintBucket.values.byName(id)),
        ),
        Container(
          decoration: BoxDecoration(
            color: colors.panel2,
            border: Border(bottom: BorderSide(color: colors.line)),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.xl,
            vertical: FwSpacing.md,
          ),
          child: Row(
            spacing: FwSpacing.md,
            children: [
              _SearchField(
                value: _query,
                onChanged: (value) => setState(() => _query = value),
              ),
              const Spacer(),
              if (_tab == LintBucket.unevaluated)
                for (var sort in _Sort.values)
                  _SortChip(
                    sort: sort,
                    selected: _sort == sort,
                    onTap: () => setState(() => _sort = sort),
                  ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? EmptyState(
                  title: _query.isEmpty
                      ? _emptyTitle(_tab)
                      : 'Nothing matches "$_query"',
                )
              : _RuleList(
                  rows: rows,
                  bucket: _tab,
                  prices: _core.pricing?.counts,
                  onOpen: (row) => _openDialog(context, row),
                ),
        ),
        _PricingFoot(core: _core),
      ],
    );
  }

  List<String> _subtitle(LintsClassification classification) {
    var version = _core.dartVersion;
    return [
      if (version != null) 'Dart ${version.split('-').first}',
      if (classification.hasCatalog) '${classification.universe} rules known',
    ];
  }

  String _tabLabel(LintBucket bucket) => switch (bucket) {
    LintBucket.enabled => 'Enabled',
    LintBucket.dismissed => 'Dismissed',
    LintBucket.mentioned => 'Mentioned',
    LintBucket.unevaluated => 'Unevaluated',
  };

  String _emptyTitle(LintBucket bucket) => switch (bucket) {
    LintBucket.unevaluated => 'Every rule here has been evaluated',
    LintBucket.enabled => 'Nothing enabled',
    LintBucket.dismissed => 'Nothing dismissed',
    LintBucket.mentioned => 'No commented-out rules',
  };

  List<ClassifiedLint> _visibleRows(Iterable<ClassifiedLint> rows) {
    var query = _query.trim().toLowerCase();
    var visible = [
      for (var row in rows)
        if (query.isEmpty ||
            row.name.contains(query) ||
            (row.rule?.description.toLowerCase().contains(query) ?? false))
          row,
    ];
    if (_tab == LintBucket.unevaluated) {
      var pricing = _core.pricing;
      switch (_sort) {
        case _Sort.newest:
          visible.sort(compareBySinceDesc);
        case _Sort.price:
          visible.sort((a, b) {
            var pa = pricing?.counts[a.name];
            var pb = pricing?.counts[b.name];
            if (pa != pb) {
              if (pa == null) return 1;
              if (pb == null) return -1;
              return pa.compareTo(pb);
            }
            return compareBySinceDesc(a, b);
          });
        case _Sort.az:
          visible.sort((a, b) => a.name.compareTo(b.name));
      }
    } else {
      visible.sort((a, b) => a.name.compareTo(b.name));
    }
    return visible;
  }

  void _openDialog(BuildContext context, ClassifiedLint row) {
    showDialog<void>(
      context: context,
      builder: (context) => _RuleDialog(row: row, core: _core),
    );
  }
}

enum _Sort {
  newest('Newest'),
  price('Cheapest'),
  az('A–Z');

  const _Sort(this.label);

  final String label;
}

/// The classification restricted to one options file, or the union when
/// [scope] is null.
///
/// Per-file semantics reuse the union objects (they carry the catalog info)
/// but re-bucket them: a rule dismissed at the root and unmentioned in a
/// severed vendored file is *unevaluated there*.
class _Buckets {
  final Map<LintBucket, List<ClassifiedLint>> _byBucket;

  _Buckets._(this._byBucket);

  List<ClassifiedLint> inBucket(LintBucket bucket) =>
      _byBucket[bucket] ?? const [];

  static _Buckets of(
    LintsClassification classification,
    LintOptionsFile? scope,
  ) {
    if (scope == null) {
      return _Buckets._({
        for (var bucket in LintBucket.values)
          bucket: classification.inBucket(bucket).toList(),
      });
    }
    var buckets = <LintBucket, List<ClassifiedLint>>{
      for (var bucket in LintBucket.values) bucket: [],
    };
    var enabled = scope.enabled;
    var ignored = {
      for (var entry in scope.severityOverrides.entries)
        if (entry.value == 'ignore') entry.key,
    };
    for (var rule in classification.rules) {
      LintBucket bucket;
      if (enabled.contains(rule.name)) {
        bucket = LintBucket.enabled;
      } else if (scope.effective.containsKey(rule.name) ||
          ignored.contains(rule.name)) {
        bucket = LintBucket.dismissed;
      } else if (scope.commentedOut.contains(rule.name)) {
        bucket = LintBucket.mentioned;
      } else if (rule.rule?.isActive ?? false) {
        bucket = LintBucket.unevaluated;
      } else {
        continue;
      }
      buckets[bucket]!.add(rule);
    }
    return _Buckets._(buckets);
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.classification, required this.core});

  final LintsClassification classification;
  final LintsCore core;

  @override
  Widget build(BuildContext context) {
    var pricing = core.pricing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.xl,
        FwSpacing.lg,
        FwSpacing.xl,
        0,
      ),
      child: Wrap(
        spacing: FwSpacing.md,
        runSpacing: FwSpacing.md,
        children: [
          _StatTile(
            label: 'Unevaluated',
            value: '${classification.count(LintBucket.unevaluated)}',
            hero: true,
          ),
          _StatTile(
            label: 'Enabled',
            value: '${classification.count(LintBucket.enabled)}',
          ),
          _StatTile(
            label: 'Dismissed',
            value: '${classification.count(LintBucket.dismissed)}',
          ),
          _StatTile(
            label: 'Mentioned',
            value: '${classification.count(LintBucket.mentioned)}',
          ),
          if (pricing != null)
            _StatTile(label: 'Free wins', value: '${pricing.freeWins}'),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.hero = false,
  });

  final String label;
  final String value;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      width: 120,
      padding: const EdgeInsets.all(FwSpacing.lg),
      decoration: BoxDecoration(
        color: hero ? colors.accentSoft : colors.bg,
        border: Border.all(color: hero ? Colors.transparent : colors.line),
        borderRadius: BorderRadius.circular(context.radii.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: context.type.heading.copyWith(
              color: hero ? colors.accent : null,
            ),
          ),
          Text(
            label.toUpperCase(),
            style: context.type.micro.copyWith(
              color: hero ? colors.accent : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilesStrip extends StatelessWidget {
  const _FilesStrip({
    required this.files,
    required this.selected,
    required this.onSelect,
  });

  final List<LintOptionsFile> files;
  final String? selected;
  final void Function(String? path) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.xl,
        vertical: FwSpacing.lg,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: FwSpacing.sm,
          children: [
            _FileCard(
              title: 'Whole repo',
              detail: '${files.length} options files · union view',
              selected: selected == null,
              onTap: () => onSelect(null),
            ),
            for (var file in files)
              _FileCard(
                title: file.path,
                mono: true,
                detail: file.hasInclude
                    ? '→ ${file.includeChain.join(' → ')}'
                    : 'no include',
                warn: !file.hasInclude ? 'inherits nothing' : null,
                error: file.includeErrors.isNotEmpty
                    ? 'unresolved include'
                    : null,
                selected: selected == file.path,
                onTap: () => onSelect(file.path),
              ),
          ],
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.mono = false,
    this.warn,
    this.error,
  });

  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;
  final bool mono;
  final String? warn;
  final String? error;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radii.radius),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft2 : colors.panel2,
          border: Border.all(color: selected ? colors.accent : colors.line),
          borderRadius: BorderRadius.circular(context.radii.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: FwSpacing.sm,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: mono
                        ? context.type.mono.copyWith(
                            fontWeight: FontWeight.w600,
                          )
                        : context.type.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (warn case var warn?) _WarnChip(label: warn),
                if (error case var error?)
                  _WarnChip(label: error, tone: Tone.error),
              ],
            ),
            Text(
              detail,
              style: context.type.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _WarnChip extends StatelessWidget {
  const _WarnChip({required this.label, this.tone = Tone.warn});

  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var color = tone == Tone.error ? colors.red : colors.warningText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.xs),
      decoration: BoxDecoration(
        color: colors.statusFill(color),
        borderRadius: BorderRadius.circular(context.radii.micro),
      ),
      child: Text(label, style: context.type.micro.copyWith(color: color)),
    );
  }
}

class _RuleList extends StatelessWidget {
  const _RuleList({
    required this.rows,
    required this.bucket,
    required this.prices,
    required this.onOpen,
  });

  final List<ClassifiedLint> rows;
  final LintBucket bucket;
  final Map<String, int>? prices;
  final void Function(ClassifiedLint row) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemExtent: _rowHeight,
      itemCount: rows.length,
      itemBuilder: (context, index) => _RuleRow(
        row: rows[index],
        bucket: bucket,
        prices: prices,
        onOpen: onOpen,
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.row,
    required this.bucket,
    required this.prices,
    required this.onOpen,
  });

  final ClassifiedLint row;
  final LintBucket bucket;
  final Map<String, int>? prices;
  final void Function(ClassifiedLint row) onOpen;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    int? price;
    if (bucket == LintBucket.unevaluated) price = prices?[row.name];
    var rule = row.rule;
    return Tappable(
      onTap: () => onOpen(row),
      child: Container(
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: FwSpacing.xl),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line2)),
        ),
        child: Row(
          spacing: FwSpacing.lg,
          children: [
            SizedBox(
              width: 36,
              child: Text(
                rule?.sinceDartSdk ?? '',
                style: context.type.caption.copyWith(
                  color: colors.mut2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: FwSpacing.sm,
                    children: [
                      Flexible(
                        child: Text(
                          row.name,
                          style: context.type.mono.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (rule?.state == 'experimental')
                        const _WarnChip(label: 'EXP'),
                      if (rule != null &&
                          (rule.state == 'deprecated' ||
                              rule.state == 'removed'))
                        _WarnChip(label: rule.state, tone: Tone.error),
                    ],
                  ),
                  if (rule?.description case var description?)
                    Text(
                      description,
                      style: context.type.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            ..._trailing(context, price),
          ],
        ),
      ),
    );
  }

  List<Widget> _trailing(BuildContext context, int? price) {
    var colors = context.colors;
    switch (bucket) {
      case LintBucket.unevaluated:
        return [
          if (row.rule?.fixStatus == 'hasFix')
            Text(
              'fix',
              style: context.type.caption.copyWith(color: colors.grn),
            ),
          if (price != null) _PricePill(price: price),
        ];
      case LintBucket.enabled:
        return [
          Text(
            row.enabledVia ?? '',
            style: context.type.caption,
            overflow: TextOverflow.ellipsis,
          ),
        ];
      case LintBucket.dismissed:
        return [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              row.comment != null
                  ? '# ${row.comment}'
                  : 'no comment — dismissed without a why',
              style: context.type.caption.copyWith(fontStyle: FontStyle.italic),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ];
      case LintBucket.mentioned:
        return [Text('commented out', style: context.type.caption)];
    }
  }
}

class _PricePill extends StatelessWidget {
  const _PricePill({required this.price});

  final int price;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var color = price == 0 ? colors.grn : colors.warningText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
      decoration: BoxDecoration(
        color: colors.statusFill(color),
        borderRadius: BorderRadius.circular(context.radii.pill),
      ),
      child: Text(
        price == 0 ? '0 · free' : '$price',
        style: context.type.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _PricingFoot extends StatelessWidget {
  const _PricingFoot({required this.core});

  final LintsCore core;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var pricing = core.pricing;
    String text;
    if (core.isPricing) {
      text = 'Pricing — one dart analyze run over the repo…';
    } else if (pricing == null) {
      text =
          'Not priced yet — "Price rules" reports what every unevaluated '
          'rule would flag today, in one analyzer run.';
    } else {
      var elapsed = (pricing.elapsed.inMilliseconds / 1000).toStringAsFixed(1);
      text =
          'Priced ${_ago(pricing.at)} · ${elapsed}s · '
          '${pricing.freeWins} free wins'
          '${core.pricingIsStale ? ' · stale — the rule set changed' : ''}';
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.xl,
        vertical: FwSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.panel2,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        spacing: FwSpacing.sm,
        children: [
          if (core.isPricing)
            SizedBox(
              width: FwIconSize.xs,
              height: FwIconSize.xs,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            ),
          Expanded(child: Text(text, style: context.type.caption)),
        ],
      ),
    );
  }

  String _ago(DateTime at) {
    var delta = DateTime.now().difference(at);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inDays < 1) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.xl,
        vertical: FwSpacing.sm,
      ),
      color: colors.red.withValues(alpha: .12),
      child: SelectableText(
        message,
        style: context.type.bodySmall.copyWith(color: colors.red),
      ),
    );
  }
}

class _Advisory extends StatelessWidget {
  const _Advisory({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.xl,
        vertical: FwSpacing.sm,
      ),
      color: colors.amber.withValues(alpha: .10),
      child: Row(
        spacing: FwSpacing.sm,
        children: [
          Icon(
            Icons.info_outline,
            size: FwIconSize.sm,
            color: colors.warningText,
          ),
          Expanded(
            child: Text(
              message,
              style: context.type.bodySmall.copyWith(color: colors.warningText),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kills every `InputDecoration` border state: the app's
/// `inputDecorationTheme` sets `enabledBorder`/`focusedBorder`, which beat
/// `border`, so the wrapping container owns the whole look.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.value, required this.onChanged});

  final String value;
  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      width: 260,
      height: _controlHeight,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
      child: Row(
        spacing: FwSpacing.sm,
        children: [
          Icon(Icons.search, size: FwIconSize.sm, color: colors.mut2),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: context.type.bodySmall,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Filter rules…',
                hintStyle: context.type.bodySmall.copyWith(color: colors.mut2),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.sort,
    required this.selected,
    required this.onTap,
  });

  final _Sort sort;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radii.pill),
      child: Container(
        height: 24,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : null,
          border: Border.all(
            color: selected ? Colors.transparent : colors.line,
          ),
          borderRadius: BorderRadius.circular(context.radii.pill),
        ),
        child: Text(
          sort.label,
          style: context.type.caption.copyWith(
            color: selected ? colors.accent : colors.mut,
            fontWeight: selected ? FontWeight.w600 : null,
          ),
        ),
      ),
    );
  }
}

class _RuleDialog extends StatelessWidget {
  const _RuleDialog({required this.row, required this.core});

  final ClassifiedLint row;
  final LintsCore core;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var rule = row.rule;
    var price = core.pricing?.counts[row.name];
    return Dialog(
      backgroundColor: colors.bg,
      insetPadding: const EdgeInsets.all(FwSpacing.xxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(FwSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.name,
                      style: context.type.mono.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Tappable(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      Icons.close,
                      size: FwIconSize.md,
                      color: colors.mut,
                    ),
                  ),
                ],
              ),
              const Gap(FwSpacing.sm),
              Wrap(
                spacing: FwSpacing.sm,
                runSpacing: FwSpacing.xs,
                children: [
                  _Chip(label: row.bucket.name),
                  if (rule != null) ...[
                    _Chip(label: 'since Dart ${rule.sinceDartSdk}'),
                    if (rule.state != 'stable') _Chip(label: rule.state),
                    _Chip(label: _fixLabel(rule.fixStatus)),
                    for (var category in rule.categories)
                      _Chip(label: category),
                  ],
                  if (price != null)
                    _Chip(
                      label: price == 0
                          ? '0 issues today — free win'
                          : '$price issues today',
                      tone: price == 0 ? Tone.good : Tone.warn,
                    ),
                ],
              ),
              const Gap(FwSpacing.lg),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (rule != null && rule.details.isNotEmpty)
                        ..._renderDetails(context, rule.details)
                      else if (rule != null)
                        Text(rule.description, style: context.type.body),
                      if (rule != null && rule.incompatible.isNotEmpty) ...[
                        const Gap(FwSpacing.lg),
                        _sectionLabel(context, 'Incompatible with'),
                        const Gap(FwSpacing.xs),
                        _Incompatible(rule: rule, core: core),
                      ],
                      const Gap(FwSpacing.lg),
                      _sectionLabel(context, 'Where it stands'),
                      const Gap(FwSpacing.xs),
                      _WhereItStands(row: row, core: core),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fixLabel(String fixStatus) => switch (fixStatus) {
    'hasFix' => 'has quick fix',
    'needsFix' => 'fix planned',
    'noFix' => 'no quick fix',
    _ => fixStatus,
  };

  Widget _sectionLabel(BuildContext context, String label) => Text(
    label.toUpperCase(),
    style: context.type.micro.copyWith(color: context.colors.mut2),
  );

  /// The `details` field is markdown with fenced code examples. This renders
  /// the two shapes that matter — paragraphs and code fences — and leaves the
  /// rest as text; it is documentation to read, not to typeset.
  List<Widget> _renderDetails(BuildContext context, String details) {
    var colors = context.colors;
    var widgets = <Widget>[];
    var fence = RegExp(r'```\w*\n([\s\S]*?)```');
    var cursor = 0;
    void addText(String text) {
      var trimmed = text.trim();
      if (trimmed.isEmpty) return;
      for (var paragraph in trimmed.split(RegExp(r'\n{2,}'))) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.md),
            child: Text(
              paragraph.replaceAll(RegExp(r'\*\*|`'), ''),
              style: context.type.body,
            ),
          ),
        );
      }
    }

    for (var match in fence.allMatches(details)) {
      addText(details.substring(cursor, match.start));
      widgets.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: FwSpacing.md),
          padding: const EdgeInsets.all(FwSpacing.md),
          decoration: BoxDecoration(
            color: colors.panel,
            border: Border.all(color: colors.line),
            borderRadius: BorderRadius.circular(context.radii.radiusSmall),
          ),
          child: Text(match.group(1)!.trimRight(), style: context.type.mono),
        ),
      );
      cursor = match.end;
    }
    addText(details.substring(cursor));
    return widgets;
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.tone});

  final String label;
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var color = switch (tone) {
      Tone.good => colors.grn,
      Tone.warn => colors.warningText,
      Tone.error => colors.red,
      _ => colors.mut,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
      decoration: BoxDecoration(
        color: tone == null ? colors.panel : colors.statusFill(color),
        border: Border.all(
          color: tone == null ? colors.line : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(context.radii.pill),
      ),
      child: Text(
        label,
        style: context.type.caption.copyWith(
          color: color,
          fontWeight: tone == null ? null : FontWeight.w600,
        ),
      ),
    );
  }
}

class _Incompatible extends StatelessWidget {
  const _Incompatible({required this.rule, required this.core});

  final LintRule rule;
  final LintsCore core;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var classification = core.classification;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var name in rule.incompatible)
          Builder(
            builder: (context) {
              var other = classification?.rules.firstWhereOrNull(
                (r) => r.name == name,
              );
              var conflicts = other?.bucket == LintBucket.enabled;
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: name, style: context.type.mono),
                    if (conflicts)
                      TextSpan(
                        text:
                            '  — enabled in this repo: turning this rule on '
                            'means turning that one off',
                        style: context.type.caption.copyWith(color: colors.red),
                      ),
                  ],
                ),
                style: context.type.bodySmall,
              );
            },
          ),
      ],
    );
  }
}

class _WhereItStands extends StatelessWidget {
  const _WhereItStands({required this.row, required this.core});

  final ClassifiedLint row;
  final LintsCore core;

  @override
  Widget build(BuildContext context) {
    var scan = core.scan;
    if (scan == null) return const SizedBox.shrink();
    var lines = <Widget>[];
    for (var file in scan.files) {
      var parts = <String>[];
      var mention = file.mentions[row.name];
      var decision = file.effective[row.name];
      if (mention != null) {
        parts.add(mention.enabled ? 'enabled here' : 'disabled here');
        if (mention.comment != null) parts.add('# ${mention.comment}');
      } else if (decision != null) {
        parts.add('${decision.enabled ? 'on' : 'off'} via ${decision.via}');
      }
      if (file.severityOverrides[row.name] == 'ignore') {
        parts.add('severity: ignore');
      }
      if (file.commentedOut.contains(row.name)) parts.add('commented out');
      if (parts.isEmpty) continue;
      lines.add(
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.xs),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: file.path, style: context.type.mono),
                TextSpan(
                  text: '  ${parts.join(' · ')}',
                  style: context.type.caption,
                ),
              ],
            ),
            style: context.type.bodySmall,
          ),
        ),
      );
    }
    if (lines.isEmpty) {
      return Text(
        'Mentioned in none of the ${scan.files.length} options files.',
        style: context.type.bodyMuted,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }
}

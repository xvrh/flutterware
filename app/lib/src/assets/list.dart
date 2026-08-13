import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart' show fuzzyMatch;
import 'package:path/path.dart' as p;

import '../ui/matched_text.dart';
import '../ui/theme.dart';
import 'model/asset_catalog.dart';
import 'model/asset_scan.dart';

/// The left half: every key in the bundle, filtered.
///
/// A view — it takes the scan's data and hands back a selection. What it owns
/// is the filter, which is nobody else's business: a search box is not state
/// worth putting in an address, because it names no place.
class AssetListView extends StatefulWidget {
  const AssetListView({
    super.key,
    required this.own,
    required this.fromPackages,
    required this.problems,
    required this.selected,
    required this.onSelect,
    this.initialQuery = '',
  });

  final List<ResolvedAsset> own;
  final List<AssetOwner> fromPackages;
  final List<AssetProblem> problems;

  /// The asset key currently open, if any.
  final String? selected;

  final ValueChanged<String> onSelect;

  /// What the filter starts with. Empty in the app; a catalog demo sets it so
  /// the matched-character highlighting is on screen rather than one keystroke
  /// away from it.
  final String initialQuery;

  @override
  State<AssetListView> createState() => _AssetListViewState();
}

class _AssetListViewState extends State<AssetListView> {
  late final _search = TextEditingController(text: widget.initialQuery);
  AssetKind? _kind;
  var _problemsOnly = false;
  final _expanded = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The same matcher the command palette ranks with, so a query that finds an
  /// asset here finds it there.
  bool _matches(String key) {
    if (_search.text.trim().isEmpty) return true;
    return fuzzyMatch(_search.text.trim(), key) != null;
  }

  List<ResolvedAsset> _filter(List<ResolvedAsset> assets) => [
    for (var asset in assets)
      if (_matches(asset.key) &&
          (_kind == null || assetKindOf(asset.key) == _kind))
        asset,
  ];

  @override
  Widget build(BuildContext context) {
    var own = _filter(widget.own);
    var problems = [
      for (var problem in widget.problems)
        if (_matches(problem.declaration)) problem,
    ];

    return Column(
      children: [
        _filters(context),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: FwSpacing.xl),
            children: [
              if (problems.isNotEmpty) ...[
                _SectionHeader(
                  'Problems',
                  count: problems.length,
                  tone: context.colors.amber,
                ),
                for (var problem in problems)
                  _ProblemRow(problem: problem, query: _search.text),
              ],
              if (!_problemsOnly) ...[
                if (own.isNotEmpty)
                  _SectionHeader('In this package', count: own.length),
                for (var asset in own)
                  _AssetRow(
                    asset: asset,
                    selected: asset.key == widget.selected,
                    onTap: () => widget.onSelect(asset.key),
                    query: _search.text,
                  ),
                for (var owner in widget.fromPackages)
                  ..._ownerSection(context, owner),
                if (own.isEmpty && widget.fromPackages.isEmpty)
                  _Empty(searching: _search.text.trim().isNotEmpty),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// A dependency's assets are collapsed until asked for. They are in the
  /// bundle and they are not what you came to look at.
  List<Widget> _ownerSection(BuildContext context, AssetOwner owner) {
    var assets = _filter(owner.assets);
    if (assets.isEmpty) return const [];
    var open = _expanded.contains(owner.package);
    return [
      InkWell(
        onTap: () => setState(() {
          open ? _expanded.remove(owner.package) : _expanded.add(owner.package);
        }),
        child: _SectionHeader(
          'package:${owner.package}',
          count: assets.length,
          detail: formatBytes(owner.bytes),
          leading: Icon(
            open ? Icons.expand_more : Icons.chevron_right,
            size: FwIconSize.sm,
            color: context.colors.mut,
          ),
        ),
      ),
      if (open)
        for (var asset in assets)
          _AssetRow(
            asset: asset,
            selected: asset.key == widget.selected,
            onTap: () => widget.onSelect(asset.key),
            query: _search.text,
          ),
    ];
  }

  Widget _filters(BuildContext context) {
    var colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      padding: const EdgeInsets.all(FwSpacing.md),
      child: Column(
        spacing: FwSpacing.md,
        children: [
          TextField(
            controller: _search,
            style: context.type.body,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filter by key',
              prefixIcon: const Icon(Icons.search, size: FwIconSize.md),
              prefixIconConstraints: const BoxConstraints(minWidth: 32),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: FwIconSize.sm,
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          Row(
            spacing: FwSpacing.xs,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: FwSpacing.xs,
                    children: [
                      for (var kind in _presentKinds)
                        _Chip(
                          label: kind.plural,
                          selected: _kind == kind,
                          onTap: () => setState(
                            () => _kind = _kind == kind ? null : kind,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.problems.isNotEmpty)
                _Chip(
                  label: 'Problems',
                  tone: colors.amber,
                  selected: _problemsOnly,
                  onTap: () => setState(() => _problemsOnly = !_problemsOnly),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Only the kinds this bundle actually has. A filter offering "Media" to a
  /// project with no media is a control that can only disappoint.
  List<AssetKind> get _presentKinds {
    var present = <AssetKind>{
      for (var asset in widget.own) assetKindOf(asset.key),
    };
    return [
      for (var kind in AssetKind.values)
        if (present.contains(kind)) kind,
    ];
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.asset,
    required this.selected,
    required this.onTap,
    this.query = '',
  });

  final ResolvedAsset asset;
  final bool selected;
  final VoidCallback onTap;

  /// What the filter is looking for, so the row can light the characters that
  /// answered it.
  final String query;

  List<int> get _matched => query.trim().isEmpty
      ? const []
      : fuzzyMatch(query.trim(), asset.key)?.matched ?? const [];

  /// Where the directory ends in the key, which is also where the filename's
  /// indexes start.
  int get _nameOffset => asset.key.length - p.basename(asset.key).length;

  List<int> get _matchedInName => [
    for (var index in _matched)
      if (index >= _nameOffset) index - _nameOffset,
  ];

  List<int> get _matchedInDirectory => [
    for (var index in _matched)
      if (index < p.dirname(asset.key).length) index,
  ];

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var variants = asset.variants.length;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? colors.accentSoft : null,
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.md,
          vertical: FwSpacing.sm,
        ),
        child: Row(
          spacing: FwSpacing.md,
          children: [
            Icon(_iconFor(assetKindOf(asset.key)), size: 15, color: colors.mut),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Split rather than ellipsised whole: the filename is what
                  // tells two assets apart and the directory is what they
                  // share, so truncating the key end-first hides the only part
                  // that identifies it. The full key is in the detail pane.
                  //
                  // The match is computed against the whole key and then split
                  // the same way, so a query spanning the slash lights on both
                  // halves rather than on whichever one it happened to land in.
                  MatchedText(
                    p.basename(asset.key),
                    matched: _matchedInName,
                    style: context.type.body,
                  ),
                  // `p.dirname` answers `.` for a key at the root of the
                  // package, and a lone dot under a filename reads as a bug.
                  if (p.dirname(asset.key) != '.')
                    MatchedText(
                      p.dirname(asset.key),
                      matched: _matchedInDirectory,
                      style: context.type.micro,
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatBytes(asset.totalBytes), style: context.type.micro),
                if (variants > 0)
                  Text(
                    '$variants variant${variants == 1 ? '' : 's'}',
                    style: context.type.micro,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProblemRow extends StatelessWidget {
  const _ProblemRow({required this.problem, this.query = ''});

  final AssetProblem problem;
  final String query;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: FwSpacing.sm,
      ),
      child: Row(
        spacing: FwSpacing.md,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: FwIconSize.md,
            color: colors.amber,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MatchedText(
                  problem.declaration,
                  matched: query.trim().isEmpty
                      ? const []
                      : fuzzyMatch(
                              query.trim(),
                              problem.declaration,
                            )?.matched ??
                            const [],
                  style: context.type.body,
                ),
                Text(
                  problem.package == null
                      ? problem.kind.summary
                      : '${problem.kind.summary} (${problem.package})',
                  style: context.type.micro,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
    this.title, {
    required this.count,
    this.detail,
    this.tone,
    this.leading,
  });

  final String title;
  final int count;
  final String? detail;
  final Color? tone;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      color: colors.panel2,
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: FwSpacing.xs,
      ),
      child: Row(
        spacing: FwSpacing.xs,
        children: [
          ?leading,
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.sectionLabel.copyWith(color: tone),
            ),
          ),
          if (detail != null) Text(detail!, style: context.type.micro),
          Text('$count', style: context.type.micro),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var accent = tone ?? colors.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radii.radiusLarge),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.radii.radiusLarge),
          color: selected ? accent.withValues(alpha: 0.15) : colors.panel,
          border: Border.all(color: selected ? accent : colors.line),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.md,
          vertical: FwSpacing.xxs,
        ),
        child: Text(
          label,
          style: context.type.caption.copyWith(
            color: selected ? accent : colors.mut,
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(FwSpacing.xxl),
      child: Center(
        child: Text(
          searching
              ? 'No asset matches that.'
              : 'This package declares no assets.\n'
                    'Add them under `flutter: assets:` in its pubspec.',
          textAlign: TextAlign.center,
          style: context.type.bodyMuted,
        ),
      ),
    );
  }
}

IconData _iconFor(AssetKind kind) => switch (kind) {
  AssetKind.image => Icons.image_outlined,
  AssetKind.vector => Icons.polyline_outlined,
  AssetKind.font => Icons.text_fields,
  AssetKind.media => Icons.movie_outlined,
  AssetKind.data => Icons.data_object,
  AssetKind.other => Icons.insert_drive_file_outlined,
};

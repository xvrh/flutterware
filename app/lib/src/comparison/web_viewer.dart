import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../capture/settle.dart';
import '../ui/empty_state.dart';
import '../ui/theme.dart';
import 'comparison_controller.dart';
import 'index_reader.dart';
import 'shot_store_http.dart';
import 'ui/previews_tab.dart';
import 'ui/scenarios_tab.dart';
import 'ui/state_chip.dart';

/// The exported comparison page.
///
/// A comparison, browsable in a browser: the same tabs, the same five-mode
/// stage and the same merged tree the changes panel draws, over an
/// `index.json` fetched from wherever this was served rather than a runner in
/// this process. Nothing here compares anything — the verdict was computed on
/// the machine that exported the page, and this is what it concluded.
///
/// The same shape as `ScenarioWebViewerApp`, for the same reason: the viewer
/// bundle is data-free, built once, and copied beside whatever `index.json`
/// an export just wrote.
class ComparisonWebViewerApp extends StatelessWidget {
  const ComparisonWebViewerApp({super.key, required this.base});

  /// What `index.json` and every frame path are resolved against — the page's
  /// own URL, so a page moved to another host or a subdirectory still finds
  /// its own files.
  final Uri base;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Comparison',
    theme: appTheme,
    debugShowCheckedModeBanner: false,
    home: ComparisonWebViewer(base: base),
  );
}

class ComparisonWebViewer extends StatefulWidget {
  const ComparisonWebViewer({super.key, required this.base});

  final Uri base;

  @override
  State<ComparisonWebViewer> createState() => _ComparisonWebViewerState();
}

class _ComparisonWebViewerState extends State<ComparisonWebViewer> {
  late final _store = HttpShotStore(widget.base);

  /// Satisfies the tabs' contract; nothing on an exported page captures, so
  /// nobody ever asks it whether the window is quiet.
  final _settle = SettleRegistry();

  ComparisonIndex? _index;
  String? _error;

  /// The two halves the tabs draw, filled once from the file. [HalfStage.done]
  /// from the start: the run this page shows already happened.
  ComparisonHalf? _previews;
  ComparisonHalf? _scenarios;

  String _tab = 'previews';

  /// What the tabs' address would name — the selected row, scenario or step.
  String? _selected;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    String? raw;
    try {
      var response = await http.get(widget.base.resolve('index.json'));
      if (response.statusCode == 200) raw = response.body;
    } catch (_) {}
    if (!mounted) return;
    if (raw == null) {
      setState(() {
        _error =
            'This page could not read its own index.json. A comparison page '
            'has to be served over HTTP — opening index.html from the '
            'filesystem leaves the browser unable to fetch anything beside '
            'it.';
      });
      return;
    }
    try {
      var index = ComparisonIndex.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
      var previews = ComparisonHalf(
        ComparisonHalfKind.previews,
        stage: HalfStage.done,
      )..rows.addAll(index.previewItems);
      var scenarios = ComparisonHalf(
        ComparisonHalfKind.scenarios,
        stage: HalfStage.done,
      )..scenarios.addAll(index.scenarios);
      setState(() {
        _index = index;
        _previews = previews;
        _scenarios = scenarios;
        if (index.previewItems.isEmpty && index.scenarios.isNotEmpty) {
          _tab = 'scenarios';
        }
      });
    } catch (error) {
      setState(() => _error = 'index.json could not be read:\n$error');
    }
  }

  void _select(String tab) => setState(() {
    if (_tab != tab) _selected = null;
    _tab = tab;
  });

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    if (_error case var error?) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(FwSpacing.xl),
            child: SelectableText(error, style: context.type.bodyMuted),
          ),
        ),
      );
    }
    var index = _index;
    if (index == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    var tabs = [
      if (index.previewItems.isNotEmpty) 'previews',
      if (index.scenarios.isNotEmpty || index.scenariosNote != null)
        'scenarios',
    ];

    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(index: index, tabs: tabs, selected: _tab, onSelect: _select),
          const Divider(height: 1),
          Expanded(child: _body(index, tabs)),
        ],
      ),
    );
  }

  Widget _body(ComparisonIndex index, List<String> tabs) {
    if (tabs.isEmpty) {
      return const EmptyState(
        icon: Icons.compare_outlined,
        title: 'Nothing compared',
        message: 'This comparison produced no rows on either half.',
      );
    }
    var tab = tabs.contains(_tab) ? _tab : tabs.first;
    if (tab == 'scenarios' && index.scenarios.isEmpty) {
      return EmptyState(
        icon: Icons.route_outlined,
        title: 'Not compared',
        message: index.scenariosNote ?? 'No scenarios were compared.',
      );
    }
    return tab == 'previews'
        ? PreviewsTab(
            half: _previews!,
            store: _store,
            settle: _settle,
            selected: _selected,
            onSelect: (id) => setState(() => _selected = id),
          )
        : ScenariosTab(
            half: _scenarios!,
            store: _store,
            settle: _settle,
            selected: _selected,
            onSelect: (id) => setState(() => _selected = id),
          );
  }

  @override
  void dispose() {
    _previews?.dispose();
    _scenarios?.dispose();
    super.dispose();
  }
}

/// `[ previews ][ scenarios ]  · chips ·  against master`.
///
/// The changes panel's strip, without the files tab: an exported page has no
/// git to read, so the file diff stays where the repository is.
class _Header extends StatelessWidget {
  const _Header({
    required this.index,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final ComparisonIndex index;
  final List<String> tabs;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: FwSpacing.xl, right: FwSpacing.xl),
      child: Row(
        children: [
          for (var tab in tabs)
            _TabButton(
              label: tab,
              selected: tab == selected,
              onTap: () => onSelect(tab),
            ),
          const Spacer(),
          for (var entry in index.findingCounts.entries)
            Padding(
              padding: const EdgeInsets.only(left: FwSpacing.xs),
              child: StateChip(entry.key, count: entry.value),
            ),
          const Gap(FwSpacing.md),
          Text(
            'against ${index.against}',
            style: context.type.micro.copyWith(color: colors.mut),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.md,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: context.type.body.copyWith(
            color: selected ? colors.ink : colors.mut,
          ),
        ),
      ),
    );
  }
}

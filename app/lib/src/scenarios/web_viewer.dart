import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../address/address_scope.dart';
import '../plugins/native/scenarios_results.dart';
import '../ui/empty_state.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';
import 'artifacts.dart';
import 'artifacts_http.dart';
import 'attachment_view.dart';
import 'flow_view.dart';
import 'step_page.dart';
import 'web_report.dart';
import '../ui/loading_state.dart';

/// The exported scenario page.
///
/// A run, browsable in a browser: the same flow canvas, the same step page and
/// the same inspect dock the panel draws, over a report fetched from wherever
/// this was served rather than a harness in another process. Nothing here
/// talks to a runner — the scenarios ran on the machine that built the page,
/// and this is what they produced.
///
/// See `2026-08-11-scenario-web-export-design.md`. The live variant, where the
/// scenarios re-run in a hidden client iframe, replaces
/// [HttpScenarioArtifacts] and this widget's report future; everything below
/// stays as it is.
class ScenarioWebViewerApp extends StatelessWidget {
  const ScenarioWebViewerApp({super.key, required this.base});

  /// What `report.json` and every artifact path are resolved against — the
  /// page's own URL, so a page moved to another host or a subdirectory still
  /// finds its own files.
  final Uri base;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Scenarios',
    theme: appTheme,
    debugShowCheckedModeBanner: false,
    home: ScenarioWebViewer(base: base),
  );
}

class ScenarioWebViewer extends StatefulWidget {
  const ScenarioWebViewer({super.key, required this.base});

  final Uri base;

  @override
  State<ScenarioWebViewer> createState() => _ScenarioWebViewerState();
}

class _ScenarioWebViewerState extends State<ScenarioWebViewer> {
  late final ScenarioArtifacts _artifacts = HttpScenarioArtifacts(widget.base);

  /// The step page writes its selected node here, exactly as it does in the
  /// panel. Nothing above reads it; it exists so one widget serves both hosts.
  final _address = ValueNotifier(Address());

  final _transform = TransformationController(
    ScenarioFlowView.initialTransform(),
  );

  ScenarioWebReport? _report;
  String? _error;

  /// The scenario on screen, as a position in [ScenarioWebReport.outcomes] —
  /// null until the report arrives, then the first one.
  var _selected = 0;

  /// The step pushed over the flow, by its index within the scenario.
  int? _step;

  /// The attachment pushed over the flow, by its position in [_step]'s list.
  int? _attachment;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _address.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    var raw = await _artifacts.readString(scenarioWebReportFile);
    if (!mounted) return;
    if (raw == null) {
      setState(() {
        _error =
            'This page could not read its own $scenarioWebReportFile. A '
            'scenario page has to be served over HTTP — opening index.html '
            'from the filesystem leaves the browser unable to fetch anything '
            'beside it.';
      });
      return;
    }
    try {
      var report = ScenarioWebReport.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
      setState(() => _report = report);
    } catch (error) {
      setState(
        () => _error = '$scenarioWebReportFile could not be read:\n$error',
      );
    }
  }

  void _open(int index) => setState(() {
    _selected = index;
    _step = null;
    _attachment = null;
    _transform.value = ScenarioFlowView.initialTransform();
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
    var report = _report;
    if (report == null) {
      return const Scaffold(body: LoadingState(title: 'Loading the report…'));
    }

    var outcomes = report.outcomes.toList();
    return AddressRoot(
      address: _address,
      onChanged: (address) => _address.value = address,
      child: ScenarioArtifactsScope(
        artifacts: _artifacts,
        child: Scaffold(
          backgroundColor: colors.bg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(report: report),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 260,
                      child: _ScenarioList(
                        outcomes: outcomes,
                        selected: _selected,
                        onOpen: _open,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: outcomes.isEmpty
                          ? const EmptyState(
                              icon: Icons.route_outlined,
                              title: 'No scenarios',
                              message: 'This run produced nothing to show.',
                            )
                          : _detail(outcomes[_selected]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail((ScenarioRunPackage, ScenarioRunOutcome) selected) {
    var (package, outcome) = selected;
    var device = outcome.device == null ? null : deviceById(outcome.device!);
    var statusFallback = package.axes?['brightness'] == 'dark'
        ? Brightness.light
        : Brightness.dark;

    if (_step case var index?) {
      var step = outcome.steps.firstWhereOrNull((s) => s.index == index);
      if (step != null) {
        if (_attachment case var attachment?
            when attachment >= 0 && attachment < step.attachments.length) {
          return ScenarioAttachmentPage(
            step: step,
            index: attachment,
            background: scenarioAttachmentBackground(
              outcome.steps,
              step,
              step.attachments[attachment],
            ),
            device: device,
            onBack: () => setState(() {
              _step = null;
              _attachment = null;
            }),
            statusFallback: statusFallback,
            appLabel: p.basename(package.path),
          );
        }
        return ScenarioStepPage(
          steps: outcome.steps,
          step: step,
          device: device,
          onBack: () => setState(() => _step = null),
          onOpenStep: (step) => setState(() {
            _step = step.index;
            _attachment = null;
          }),
          statusFallback: statusFallback,
          // Nothing to shorten against: the page has no checkout behind it, so
          // a node's source path is shown as the run recorded it.
          displayRoot: '',
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var error in outcome.errors.take(1)) _ErrorBanner(error.error),
        if (outcome.steps.isEmpty)
          const Expanded(
            child: EmptyState(
              icon: Icons.image_not_supported_outlined,
              title: 'No steps captured',
              message: 'This scenario ran without taking a screenshot.',
            ),
          )
        else
          Expanded(
            child: ScenarioFlowView(
              steps: outcome.steps,
              device: device,
              transform: _transform,
              onOpenStep: (step) => setState(() => _step = step.index),
              onOpenAttachment: (step, attachment) => setState(() {
                _step = step.index;
                _attachment = attachment;
              }),
              appLabel: p.basename(package.path),
              statusFallback: statusFallback,
            ),
          ),
      ],
    );
  }
}

/// What this page is and when it was taken.
class _Header extends StatelessWidget {
  const _Header({required this.report});

  final ScenarioWebReport report;

  @override
  Widget build(BuildContext context) {
    var run = report.run;
    var scenarios = report.outcomes.length;
    var failed = report.outcomes.where((entry) => !entry.$2.ok).length;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(child: Text(report.title, style: context.type.heading)),
          Text(
            [
              '$scenarios ${scenarios == 1 ? 'scenario' : 'scenarios'}',
              if (failed > 0) '$failed failed',
              if (run.axes case var axes? when axes.isNotEmpty)
                axes.entries.map((e) => '${e.key} ${e.value}').join(' · '),
              _when(report.generated),
            ].join('  ·  '),
            style: context.type.caption.copyWith(
              color: failed > 0 ? context.colors.red : context.colors.mut,
            ),
          ),
        ],
      ),
    );
  }

  /// The date, plainly. Not "3 days ago": a page is read long after it is
  /// built, and a relative time computed in the reader's browser against a
  /// build that happened elsewhere is the one form of this that can lie.
  static String _when(DateTime time) {
    var local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// Every scenario, grouped by the file that declares it.
class _ScenarioList extends StatelessWidget {
  const _ScenarioList({
    required this.outcomes,
    required this.selected,
    required this.onOpen,
  });

  final List<(ScenarioRunPackage, ScenarioRunOutcome)> outcomes;
  final int selected;
  final void Function(int) onOpen;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    // The package is named only when there is more than one, so the common
    // single-package page is not indented under a heading that says nothing.
    var packages = {for (var entry in outcomes) entry.$1.path};
    var namePackages = packages.length > 1;

    var rows = <Widget>[];
    String? heading;
    for (var (index, (package, outcome)) in outcomes.indexed) {
      var group = namePackages
          ? '${package.path} · ${outcome.file}'
          : outcome.file;
      if (group != heading) {
        heading = group;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.lg,
              FwSpacing.lg,
              FwSpacing.lg,
              FwSpacing.xs,
            ),
            child: Text(
              group,
              style: context.type.micro.copyWith(color: colors.mut),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
      rows.add(
        Tappable(
          onTap: () => onOpen(index),
          child: Container(
            color: index == selected ? colors.accentSoft : null,
            padding: const EdgeInsets.symmetric(
              horizontal: FwSpacing.lg,
              vertical: FwSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  outcome.skipped
                      ? Icons.remove_circle_outline
                      : outcome.ok
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: FwIconSize.sm,
                  color: outcome.skipped
                      ? colors.mut2
                      : outcome.ok
                      ? colors.grn
                      : colors.red,
                ),
                const Gap(FwSpacing.sm),
                Expanded(
                  child: Text(
                    outcome.name,
                    style: context.type.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (outcome.device case var device?)
                  Text(
                    device,
                    style: context.type.micro.copyWith(color: colors.mut),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return ListView(children: rows);
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      width: double.infinity,
      color: colors.red.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.sm,
      ),
      child: SelectableText(
        message,
        style: context.type.bodySmall.copyWith(color: colors.red),
      ),
    );
  }
}

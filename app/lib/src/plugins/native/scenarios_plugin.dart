import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../address/address_scope.dart';
import '../../ui/empty_state.dart';
import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../native_plugin.dart';
import 'scenarios_address.dart';
import 'scenarios_core.dart';
import 'scenarios_results.dart';

export 'scenarios_core.dart' show ScenariosCore, scenariosPluginId;

/// The GUI half of the scenarios plugin: the scanned list, and the flow page —
/// one scenario's run laid out as its steps, left to right, with the selected
/// step's frame and texts underneath.
///
/// Everything the page shows comes out of [ScenariosCore.panelRunFor]; the
/// panel starts runs and draws state, and that is all it does.
class ScenariosPlugin extends NativePlugin<ScenariosCore> {
  ScenariosPlugin(super.core);

  @override
  String? get busyWith {
    if (core.anyPanelRunning) return 'running scenarios';
    if (core.packages.any(core.isScanning)) return 'scanning scenarios';
    return null;
  }

  @override
  Widget buildPanel(BuildContext context) => _ScenariosPanel(this);
}

/// Owns the subscription: mounting starts the scan, as the laziness rule
/// requires — a package is scanned because its panel is visible.
class _ScenariosPanel extends StatefulWidget {
  const _ScenariosPanel(this.plugin);

  final ScenariosPlugin plugin;

  @override
  State<_ScenariosPanel> createState() => _ScenariosPanelState();
}

class _ScenariosPanelState extends State<_ScenariosPanel> {
  ScenariosCore get _core => widget.plugin.core;

  /// The place the address names, or the first declared package when it names
  /// none — where selecting the plugin off the rail leaves you.
  ScenarioPlace? _resolve() {
    if (scenarioPlace(AddressScope.segments(context)) case var place?) {
      return place;
    }
    var package = _core.packages.firstOrNull;
    return package == null ? null : ScenarioPlace(package);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolve() case var place?) _core.track(place.package);
  }

  @override
  Widget build(BuildContext context) {
    var place = _resolve();
    if (place == null) {
      return Center(
        child: Text(
          'No packages configured for this plugin.\n'
          'Add them in tool/flutterware.dart.',
          textAlign: TextAlign.center,
          style: context.type.bodyMuted,
        ),
      );
    }

    // The plugin already relays core.changes as ChangeNotifier notifications.
    return ListenableBuilder(
      listenable: widget.plugin,
      builder: (context, _) {
        if ((place.file, place.scenario) case (var file?, var scenario?)) {
          return _ScenarioPage(
            _core,
            place.package,
            file: file,
            scenario: scenario,
            step: place.step,
            key: ValueKey('${place.package}/$file#$scenario'),
          );
        }
        return _ScenarioList(
          _core,
          place.package,
          key: ValueKey(place.package),
        );
      },
    );
  }
}

class _ScenarioList extends StatelessWidget {
  const _ScenarioList(this.core, this.package, {super.key});

  final ScenariosCore core;
  final String package;

  @override
  Widget build(BuildContext context) {
    var result = core.scanResultFor(package);
    if (result == null) {
      if (core.scanErrorFor(package) case var error?) {
        return Center(
          child: Text(
            'The scan failed:\n$error',
            textAlign: TextAlign.center,
            style: context.type.bodyMuted,
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (result.scenarios.isEmpty) {
      return Center(
        child: Text(
          'No scenarios in ${core.directoryFor(package)}.\n'
          "Write one with scenario('…', (s) async { … }).",
          textAlign: TextAlign.center,
          style: context.type.bodyMuted,
        ),
      );
    }
    return ListView(
      children: [
        for (var diagnostic in result.diagnostics)
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(diagnostic, style: context.type.bodyMuted),
            dense: true,
          ),
        for (var ref in result.scenarios)
          ListTile(
            leading: const Icon(Icons.route_outlined),
            title: Text(ref.name),
            subtitle: Text('${ref.file}:${ref.line}'),
            onTap: () => AddressScope.write(context).setSegments(
              scenarioSegments(package, file: ref.file, scenario: ref.name),
            ),
          ),
      ],
    );
  }
}

/// One scenario's flow page. Opening it is the demand: a scenario nobody has
/// run yet runs now, and the Run button reruns — against the sources on disk,
/// since the warm runner refreshes first.
class _ScenarioPage extends StatefulWidget {
  const _ScenarioPage(
    this.core,
    this.package, {
    required this.file,
    required this.scenario,
    this.step,
    super.key,
  });

  final ScenariosCore core;
  final String package;
  final String file;
  final String scenario;

  /// The step the address selects, or null for the run's last step.
  final int? step;

  @override
  State<_ScenarioPage> createState() => _ScenarioPageState();
}

class _ScenarioPageState extends State<_ScenarioPage> {
  ScenarioPanelRun? get _run => widget.core.panelRunFor(
    widget.package,
    file: widget.file,
    scenario: widget.scenario,
  );

  void _start() => widget.core.startRun(
    widget.package,
    file: widget.file,
    scenario: widget.scenario,
  );

  @override
  void initState() {
    super.initState();
    if (_run == null) _start();
  }

  void _selectStep(ScenarioRunStep step) {
    AddressScope.write(context).setSegments(
      scenarioSegments(
        widget.package,
        file: widget.file,
        scenario: widget.scenario,
        step: step.index,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var run = _run;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, run),
        const Divider(height: 1),
        Expanded(child: _body(context, run)),
      ],
    );
  }

  Widget _header(BuildContext context, ScenarioPanelRun? run) {
    var colors = context.colors;
    var outcome = run?.outcome;
    var running = run?.running ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.md,
      ),
      child: Row(
        children: [
          Tappable(
            onTap: () =>
                AddressScope.write(context).setSegments([widget.package]),
            child: Icon(Icons.arrow_back, size: 18, color: colors.mut),
          ),
          const Gap(FwSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.scenario,
                  style: context.type.heading,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.file,
                  style: context.type.caption.copyWith(color: colors.mut2),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Gap(FwSpacing.md),
          if (running)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (outcome != null) ...[
            Icon(
              outcome.ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 16,
              color: outcome.ok ? colors.grn : colors.red,
            ),
            const Gap(FwSpacing.xs),
            Text(
              '${outcome.ms} ms',
              style: context.type.caption.copyWith(color: colors.mut2),
            ),
          ],
          const Gap(FwSpacing.lg),
          ElevatedButton.icon(
            onPressed: running ? null : _start,
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Run'),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ScenarioPanelRun? run) {
    var outcome = run?.outcome;
    if (outcome == null) {
      if (run?.error case var error? when !(run?.running ?? false)) {
        return _RunFailure(error);
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const Gap(FwSpacing.lg),
            // The runner narrates its cold start — "building the asset
            // bundle" is a very different wait from a hung harness.
            Text(
              widget.core.runnerLogFor(widget.package) ??
                  'starting the harness…',
              style: context.type.bodyMuted,
            ),
          ],
        ),
      );
    }

    var steps = outcome.steps;
    var selected = widget.step == null
        ? steps.lastOrNull
        : steps.firstWhereOrNull((s) => s.index == widget.step) ??
              steps.lastOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (run?.error case var error?) _ErrorBanner(error),
        for (var error in outcome.errors.take(1)) _ErrorBanner(error.error),
        if (selected == null)
          const Expanded(
            child: EmptyState(
              icon: Icons.image_not_supported_outlined,
              title: 'No steps captured',
              message:
                  'The scenario ran without a screenshot — every tap and '
                  'screen() captures one unless Shots.manual turned that off.',
            ),
          )
        else ...[
          _StepStrip(steps: steps, selected: selected, onSelect: _selectStep),
          const Divider(height: 1),
          Expanded(child: _StepDetail(selected)),
        ],
      ],
    );
  }
}

/// A run that produced nothing to draw — a compile error, usually, which is
/// why the text is selectable and kept whole.
class _RunFailure extends StatelessWidget {
  const _RunFailure(this.error);

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FwSpacing.xxl),
        child: SelectableText(
          error,
          style: context.type.bodySmall.copyWith(color: context.colors.red),
        ),
      ),
    );
  }
}

/// A complaint over a page that still has content under it: a failing
/// scenario's error above its captured steps, or a failed re-run above the
/// previous result.
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
        vertical: FwSpacing.md,
      ),
      child: SelectableText(
        message,
        maxLines: 6,
        style: context.type.bodySmall.copyWith(color: colors.red),
      ),
    );
  }
}

/// The flow: every captured step in run order, left to right. Linear because a
/// scenario is — branching flows come back if scenarios ever grow splits.
class _StepStrip extends StatelessWidget {
  const _StepStrip({
    required this.steps,
    required this.selected,
    required this.onSelect,
  });

  final List<ScenarioRunStep> steps;
  final ScenarioRunStep selected;
  final void Function(ScenarioRunStep) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(FwSpacing.lg),
        itemCount: steps.length,
        separatorBuilder: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FwSpacing.sm),
            child: Icon(
              Icons.arrow_forward,
              size: 14,
              color: context.colors.mut3,
            ),
          ),
        ),
        itemBuilder: (context, index) {
          var step = steps[index];
          return _StepCard(
            step,
            selected: step.index == selected.index,
            onTap: () => onSelect(step),
          );
        },
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard(this.step, {required this.selected, required this.onTap});

  final ScenarioRunStep step;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable(
      onTap: onTap,
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(FwSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : colors.bg,
          border: Border.all(
            color: selected ? colors.accent : colors.line,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(context.radii.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${step.index} · ${step.name ?? 'step'}',
              style: context.type.caption.copyWith(
                color: selected ? colors.ink : colors.mut,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const Gap(FwSpacing.xs),
            Expanded(
              child: Image.file(
                File(step.png),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The selected step, big: the frame on the left, its visible texts on the
/// right. The tree dump joins this side when the inspector slice lands.
class _StepDetail extends StatelessWidget {
  const _StepDetail(this.step);

  final ScenarioRunStep step;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: colors.panel2,
            padding: const EdgeInsets.all(FwSpacing.xl),
            child: Image.file(
              File(step.png),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 260,
          child: ListView(
            padding: const EdgeInsets.all(FwSpacing.lg),
            children: [
              Text('VISIBLE TEXTS', style: context.type.sectionLabel),
              const Gap(FwSpacing.md),
              if (step.texts.isEmpty)
                Text('No visible texts.', style: context.type.bodyMuted)
              else
                for (var text in step.texts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FwSpacing.xs),
                    child: SelectableText(text, style: context.type.bodySmall),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../address/address_scope.dart';
import '../../catalog/devices.dart';
import '../../scenarios/axes.dart';
import '../../scenarios/discovery.dart';
import '../../scenarios/flow_view.dart';
import '../../scenarios/step_page.dart';
import '../../ui/empty_state.dart';
import '../../ui/menu.dart';
import '../../ui/popover.dart';
import '../../ui/popover_menu.dart';
import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../native_plugin.dart';
import 'scenarios_address.dart';
import 'scenarios_core.dart';
import 'scenarios_results.dart';

export 'scenarios_core.dart' show ScenariosCore, scenariosPluginId;

/// The GUI half of the scenarios plugin — dev_studio's proven shape on the
/// shell: the scenario list as a master pane on the left, the selected
/// scenario's run as a full-page flow of device-framed screenshots, and a
/// step pushed over it with a back button.
///
/// Everything the pages show comes out of [ScenariosCore.panelRunFor]; the
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

    // The axes ride the address as plain parameters, above the segments —
    // pick French and an iPhone once, and every scenario you open runs that
    // way. The device defaults to the phone form factor; an unknown one is
    // reported by the page, not repaired here.
    var axes = ScenarioAxes(
      device: switch (AddressScope.param(context, 'device')) {
        var id? when !isDeviceId(id) => defaultScenarioDeviceId,
        var id => resolveScenarioDevice(id),
      },
      language: AddressScope.param(context, 'language'),
      textScale: double.tryParse(
        AddressScope.param(context, 'text-scale') ?? '',
      ),
      brightness: switch (AddressScope.param(context, 'brightness')) {
        'light' => 'light',
        'dark' => 'dark',
        _ => null,
      },
      boldText: AddressScope.param(context, 'bold-text') == 'true',
      highContrast: AddressScope.param(context, 'high-contrast') == 'true',
      invertColors: AddressScope.param(context, 'invert-colors') == 'true',
    );

    // The plugin already relays core.changes as ChangeNotifier notifications.
    return ListenableBuilder(
      listenable: widget.plugin,
      builder: (context, _) {
        Widget detail;
        if ((place.file, place.scenario) case (var file?, var scenario?)) {
          detail = _ScenarioPage(
            _core,
            place.package,
            file: file,
            scenario: scenario,
            step: place.step,
            axes: axes,
            key: ValueKey('${place.package}/$file#$scenario'),
          );
        } else {
          detail = const EmptyState(
            icon: Icons.route_outlined,
            title: 'Pick a scenario',
            message: 'Opening one runs it.',
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 240,
              child: _ScenarioListPane(
                _core,
                place.package,
                selected: place,
                key: ValueKey(place.package),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

/// The master pane: every scenario of the package, grouped by file, the
/// selected one highlighted. Always visible — running a scenario never hides
/// where you are in the suite.
class _ScenarioListPane extends StatelessWidget {
  const _ScenarioListPane(
    this.core,
    this.package, {
    required this.selected,
    super.key,
  });

  final ScenariosCore core;
  final String package;
  final ScenarioPlace selected;

  @override
  Widget build(BuildContext context) {
    var result = core.scanResultFor(package);
    if (result == null) {
      if (core.scanErrorFor(package) case var error?) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(FwSpacing.lg),
            child: Text(
              'The scan failed:\n$error',
              textAlign: TextAlign.center,
              style: context.type.bodyMuted,
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (result.scenarios.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FwSpacing.lg),
          child: Text(
            'No scenarios in ${core.directoryFor(package)}.\n'
            "Write one with scenario('…', (s) async { … }).",
            textAlign: TextAlign.center,
            style: context.type.bodyMuted,
          ),
        ),
      );
    }

    var byFile = <String, List<ScenarioRef>>{};
    for (var ref in result.scenarios) {
      byFile.putIfAbsent(ref.file, () => []).add(ref);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.md),
      children: [
        for (var diagnostic in result.diagnostics)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FwSpacing.lg,
              vertical: FwSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 14,
                  color: context.colors.amber,
                ),
                const Gap(FwSpacing.sm),
                Expanded(child: Text(diagnostic, style: context.type.caption)),
              ],
            ),
          ),
        for (var entry in byFile.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.lg,
              FwSpacing.md,
              FwSpacing.lg,
              FwSpacing.xs,
            ),
            child: Text(
              entry.key,
              style: context.type.sectionLabel,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (var ref in entry.value)
            _ScenarioRow(
              ref,
              selected:
                  selected.file == ref.file && selected.scenario == ref.name,
              onTap: () => AddressScope.write(context).setSegments(
                scenarioSegments(package, file: ref.file, scenario: ref.name),
              ),
            ),
        ],
      ],
    );
  }
}

class _ScenarioRow extends StatelessWidget {
  const _ScenarioRow(this.ref, {required this.selected, required this.onTap});

  final ScenarioRef ref;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable.builder(
      onTap: onTap,
      builder: (context, hovered) => Container(
        color: selected
            ? colors.accentSoft
            : hovered
            ? colors.panel
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.route_outlined,
              size: 14,
              color: selected ? colors.accent : colors.mut2,
            ),
            const Gap(FwSpacing.md),
            Expanded(
              child: Text(
                ref.name,
                overflow: TextOverflow.ellipsis,
                style: context.type.body.copyWith(
                  color: selected ? colors.ink : colors.mut,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One scenario's page. Opening it is the demand: a scenario nobody has run
/// yet runs now, and the Run button reruns — against the sources on disk,
/// since the warm runner refreshes first. The run draws as the flow; a step
/// address pushes [ScenarioStepPage] over it.
class _ScenarioPage extends StatefulWidget {
  const _ScenarioPage(
    this.core,
    this.package, {
    required this.file,
    required this.scenario,
    required this.axes,
    this.step,
    super.key,
  });

  final ScenariosCore core;
  final String package;
  final String file;
  final String scenario;

  /// The axis assignment the address asks for.
  final ScenarioAxes axes;

  /// The step the address pushes, or null for the flow.
  final int? step;

  @override
  State<_ScenarioPage> createState() => _ScenarioPageState();
}

class _ScenarioPageState extends State<_ScenarioPage> {
  /// The flow canvas's pan/zoom, owned here so a pushed step detail and its
  /// back button land exactly where the canvas was.
  final _flowTransform = TransformationController(
    ScenarioFlowView.initialTransform(),
  );

  ScenarioPanelRun? get _run => widget.core.panelRunFor(
    widget.package,
    file: widget.file,
    scenario: widget.scenario,
  );

  void _start() => widget.core.startRun(
    widget.package,
    file: widget.file,
    scenario: widget.scenario,
    axes: widget.axes,
  );

  /// Runs when nothing has, and re-runs when the settled state was made under
  /// different axes than the address now asks for — which is how an axis
  /// picked in the toolbar becomes a fresh run. Compared against the last
  /// *attempt*'s axes, so a failure is not retried in a loop.
  void _maybeRun() {
    var run = _run;
    if (run == null || (!run.running && run.axes != widget.axes)) _start();
  }

  @override
  void initState() {
    super.initState();
    _maybeRun();
  }

  @override
  void didUpdateWidget(_ScenarioPage old) {
    super.didUpdateWidget(old);
    _maybeRun();
  }

  @override
  void dispose() {
    _flowTransform.dispose();
    super.dispose();
  }

  void _openStep(ScenarioRunStep step) {
    AddressScope.write(context).setSegments(
      scenarioSegments(
        widget.package,
        file: widget.file,
        scenario: widget.scenario,
        step: step.index,
      ),
    );
  }

  void _closeStep() {
    AddressScope.write(context).setSegments(
      scenarioSegments(
        widget.package,
        file: widget.file,
        scenario: widget.scenario,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var run = _run;
    var device = run?.axes.device == null
        ? null
        : deviceById(run!.axes.device!);

    // The pushed page: a step, with its back button. Full page — the flow is
    // exactly one back-tap away, per the reference GUI.
    var steps = run?.steps ?? const <ScenarioRunStep>[];
    if (widget.step != null) {
      var step = steps.firstWhereOrNull((s) => s.index == widget.step);
      if (step != null) {
        return ScenarioStepPage(
          steps: steps,
          step: step,
          device: device,
          onBack: _closeStep,
          onOpenStep: _openStep,
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, run),
        _AxesBar(
          axes: widget.axes,
          languages: widget.core.languagesFor(widget.package),
        ),
        const Divider(height: 1),
        // Said out loud rather than repaired, with the accepted values — the
        // reader is often an agent that guessed.
        if (unknownDeviceIn(AddressScope.param(context, 'device'))
            case var bad?)
          _ErrorBanner(
            'No device "$bad" — running as $defaultScenarioDeviceId. '
            'Accepted: ${deviceIds.join(', ')}.',
          ),
        Expanded(child: _body(context, run, device)),
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
          // The escape hatch, for the changes no incremental lane can see:
          // drops the warm harness and cold-starts — fresh bundle, fresh
          // kernel, fresh process.
          Tooltip(
            message: 'Full restart: rebuild assets and kernel, then run',
            child: Tappable(
              onTap: running
                  ? null
                  : () {
                      widget.core.restartRunner(widget.package);
                      _start();
                    },
              child: Icon(Icons.restart_alt, size: 18, color: colors.mut),
            ),
          ),
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

  Widget _body(
    BuildContext context,
    ScenarioPanelRun? run,
    CatalogDevice? device,
  ) {
    var steps = run?.steps ?? const <ScenarioRunStep>[];
    var running = run?.running ?? false;

    if (steps.isEmpty) {
      if (run?.error case var error? when !running) {
        return _RunFailure(error);
      }
      if (running || run == null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const Gap(FwSpacing.lg),
              // The runner narrates its cold start — "building the asset
              // bundle" is a very different wait from a hung harness. Once
              // the first step lands, the flow itself is the progress.
              Text(
                widget.core.runnerLogFor(widget.package) ??
                    'starting the harness…',
                style: context.type.bodyMuted,
              ),
            ],
          ),
        );
      }
      return const EmptyState(
        icon: Icons.image_not_supported_outlined,
        title: 'No steps captured',
        message:
            'The scenario ran without a screenshot — every tap and '
            'screen() captures one unless Shots.manual turned that off.',
      );
    }

    var outcome = run?.outcome;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (run?.error case var error?) _ErrorBanner(error),
        if (outcome != null)
          for (var error in outcome.errors.take(1)) _ErrorBanner(error.error),
        // Drawn from the streamed steps: the flow starts filling in with the
        // first capture, while the scenario is still running.
        Expanded(
          child: ScenarioFlowView(
            steps: steps,
            device: device,
            transform: _flowTransform,
            onOpenStep: _openStep,
          ),
        ),
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

/// The axis assignment, as controls: device, language, accessibility,
/// brightness. **Every control writes the address and holds nothing** — the
/// page notices the address moved and re-runs, so a picked axis and a pasted
/// `?device=` link are the same code path.
///
/// Plain parameters, deliberately above the segments' lifetime: pick French
/// once and every scenario you open runs French, exactly like the catalog's
/// device framing.
class _AxesBar extends StatelessWidget {
  const _AxesBar({required this.axes, required this.languages});

  final ScenarioAxes axes;

  /// The locale tags the project's config declares — the whole language menu.
  final List<String> languages;

  @override
  Widget build(BuildContext context) {
    var device = axes.device == null ? null : deviceById(axes.device!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.lg,
        0,
        FwSpacing.lg,
        FwSpacing.md,
      ),
      // A Wrap rather than a Row: four controls do not fit every panel width,
      // and a second line beats a clipped one.
      child: Wrap(
        spacing: FwSpacing.md,
        runSpacing: FwSpacing.xs,
        children: [
          Menu(
            entries: [
              MenuItem(
                'Default · ${deviceById(defaultScenarioDeviceId)!.label}',
                onSelected: () =>
                    AddressScope.write(context).setParam('device', null),
              ),
              MenuItem(
                'Bare test surface',
                onSelected: () =>
                    AddressScope.write(context).setParam('device', fitDeviceId),
              ),
              for (var group in {for (var d in catalogDevices) d.group}) ...[
                MenuHeader(group),
                for (var d in catalogDevices.where((d) => d.group == group))
                  MenuItem(
                    d.label,
                    shortcut: describeDevice(d),
                    onSelected: () =>
                        AddressScope.write(context).setParam('device', d.id),
                  ),
              ],
            ],
            builder: (context, controller) => _AxisChip(
              label: 'Device',
              value: device?.label ?? 'Bare surface',
              active: axes.device != defaultScenarioDeviceId,
              onTap: controller.toggle,
            ),
          ),
          if (languages.isNotEmpty)
            Menu(
              entries: [
                MenuItem(
                  'Default',
                  onSelected: () =>
                      AddressScope.write(context).setParam('language', null),
                ),
                for (var language in languages)
                  MenuItem(
                    language,
                    onSelected: () => AddressScope.write(
                      context,
                    ).setParam('language', language),
                  ),
              ],
              builder: (context, controller) => _AxisChip(
                label: 'Language',
                value: axes.language ?? 'Default',
                active: axes.language != null,
                onTap: controller.toggle,
              ),
            ),
          Popover(
            side: PopoverSide.bottom,
            align: PopoverAlign.start,
            anchor: (context, controller) => _AxisChip(
              label: 'Accessibility',
              value: _describeAccessibility(axes),
              active: axes.anyAccessibility,
              onTap: controller.toggle,
            ),
            content: (context, controller) => PopoverMenuSurface(
              minWidth: 260,
              maxWidth: 320,
              child: _AccessibilityPanel(axes: axes),
            ),
          ),
          Menu(
            entries: [
              for (var (label, value) in [
                ('Default', null),
                ('Light', 'light'),
                ('Dark', 'dark'),
              ])
                MenuItem(
                  label,
                  onSelected: () =>
                      AddressScope.write(context).setParam('brightness', value),
                ),
            ],
            builder: (context, controller) => _AxisChip(
              label: 'Brightness',
              value: switch (axes.brightness) {
                'dark' => 'Dark',
                'light' => 'Light',
                _ => 'Default',
              },
              active: axes.brightness != null,
              onTap: controller.toggle,
            ),
          ),
        ],
      ),
    );
  }

  static String _describeAccessibility(ScenarioAxes axes) {
    var features = [
      if (axes.boldText) 'bold',
      if (axes.highContrast) 'high contrast',
      if (axes.invertColors) 'invert',
    ];
    var scale = axes.textScale;
    if (scale == null && features.isEmpty) return 'Default';
    var scaleText = 'Text ${((scale ?? 1.0) * 100).round()}%';
    return features.isEmpty ? scaleText : '$scaleText, ${features.join(', ')}';
  }
}

/// The accessibility features, as dev_studio offered them: the text scale
/// stepper and the platform switches. Every row writes the address on the
/// spot — with warm FakeAsync re-runs there is nothing to batch behind an
/// Apply button.
class _AccessibilityPanel extends StatelessWidget {
  const _AccessibilityPanel({required this.axes});

  final ScenarioAxes axes;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var scale = axes.textScale ?? 1.0;
    void setScale(double value) {
      AddressScope.write(context).setParam(
        'text-scale',
        (value - 1.0).abs() < 0.001 ? null : value.toStringAsFixed(2),
      );
    }

    Widget toggle(String label, String param, bool value) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: context.type.body)),
            Checkbox(
              value: value,
              visualDensity: VisualDensity.compact,
              onChanged: (checked) => AddressScope.write(
                context,
              ).setParam(param, (checked ?? false) ? 'true' : null),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(FwSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
          child: Text('ACCESSIBILITY', style: context.type.sectionLabel),
        ),
        const Gap(FwSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.lg,
            vertical: FwSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(child: Text('Text scale', style: context.type.body)),
              Tappable(
                onTap: () => setScale((scale - 0.1).clamp(0.5, 3.0)),
                child: Icon(Icons.remove, size: 16, color: colors.mut),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
                child: Text(
                  '${(scale * 100).round()}%',
                  style: context.type.bodyStrong,
                ),
              ),
              Tappable(
                onTap: () => setScale((scale + 0.1).clamp(0.5, 3.0)),
                child: Icon(Icons.add, size: 16, color: colors.mut),
              ),
            ],
          ),
        ),
        toggle('Bold text', 'bold-text', axes.boldText),
        toggle('High contrast', 'high-contrast', axes.highContrast),
        toggle('Invert colors', 'invert-colors', axes.invertColors),
        const Gap(FwSpacing.md),
      ],
    );
  }
}

/// One axis as a compact dropdown trigger. Accent-tinted when set, so a page
/// running under non-default axes says so at a glance.
class _AxisChip extends StatelessWidget {
  const _AxisChip({
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable(
      onTap: onTap,
      child: Container(
        height: 24,
        padding: const EdgeInsets.only(left: FwSpacing.md, right: FwSpacing.xs),
        decoration: BoxDecoration(
          color: active ? colors.accentSoft : colors.bg,
          border: Border.all(color: active ? colors.accent : colors.line),
          borderRadius: BorderRadius.circular(context.radii.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: context.type.caption.copyWith(color: colors.mut2),
            ),
            Text(
              value,
              style: context.type.caption.copyWith(color: colors.ink),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: colors.mut2),
          ],
        ),
      ),
    );
  }
}

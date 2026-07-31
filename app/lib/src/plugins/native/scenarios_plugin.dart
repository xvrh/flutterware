import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart' show fuzzyMatch;

import '../../address/address_scope.dart';
import '../../catalog/devices.dart';
import '../../scenarios/authoring.dart';
import '../../scenarios/axes.dart';
import '../../scenarios/discovery.dart';
import '../../scenarios/flow_view.dart';
import '../../scenarios/harness_entrypoint.dart';
import '../../scenarios/new_scenario_dialog.dart';
import '../../scenarios/step_page.dart';
import '../../ui/empty_state.dart';
import '../../ui/matched_text.dart';
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

  /// The device last used in each **pool** of scenarios, keyed by the folder
  /// whose `flutter_test_config.dart` governs it (`''` for an ungoverned
  /// one). dev_studio's `_mobileDevice` / `_desktopDevice`, generalised to
  /// however many folders a project has.
  ///
  /// Without it the device is one sticky address parameter: pick an iPhone on
  /// a phone scenario, open a desktop one, and it renders a laptop layout at
  /// 390 points wide — overflow stripes rather than a picture. A pool is
  /// exactly the scope that choice makes sense in, and the folder is its
  /// identity, readable off the filesystem without compiling anything.
  final _deviceByPool = <String, String?>{};

  /// The pool the address's `?device=` currently belongs to, or null before
  /// the first scenario is opened.
  String? _pool;

  /// Memoised because [testConfigFolderFor] stats the disk and the answer
  /// changes only when a config file is added.
  final _poolCache = <(String, String), String>{};

  String _poolFor(String package, String file) =>
      _poolCache.putIfAbsent((package, file), () {
        return testConfigFolderFor(_core.packageRootFor(package), file) ?? '';
      });

  /// Swaps the remembered device when the opened scenario belongs to another
  /// pool: what was on screen is kept under the pool being left, and the pool
  /// being entered gets back whatever it last used — or nothing, which lets
  /// its own profile answer.
  ///
  /// The first pool observed **adopts** the address as it stands, so a pasted
  /// `?device=` link opens on the device it names.
  void _followPool(ScenarioPlace place) {
    if (place.file case var file?) {
      var pool = _poolFor(place.package, file);
      if (pool == _pool) return;
      var current = AddressScope.param(context, 'device');
      if (_pool case var leaving?) {
        _deviceByPool[leaving] = current;
      } else {
        _deviceByPool[pool] = current;
      }
      _pool = pool;
      var wanted = _deviceByPool[pool];
      if (wanted != current) {
        // After the frame: this runs from didChangeDependencies, and the
        // address is somebody else's state.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) AddressScope.write(context).setParam('device', wanted);
        });
      }
    }
  }

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
    if (_resolve() case var place?) {
      _core.track(place.package);
      _followPool(place);
      // Only once a scenario is open: listing compiles the harness, and the
      // page that opens one is about to pay for that anyway.
      if (place.file != null) _core.trackListings(place.package);
    }
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
    // way. No `?device=` stays no device: the scenario's own folder answers
    // that, inside the harness. An unknown one is reported by the page, not
    // repaired here.
    var axes = ScenarioAxes(
      device: switch (AddressScope.param(context, 'device')) {
        var id? when !isDeviceId(id) => null,
        var id => id,
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
class _ScenarioListPane extends StatefulWidget {
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
  State<_ScenarioListPane> createState() => _ScenarioListPaneState();
}

class _ScenarioListPaneState extends State<_ScenarioListPane> {
  /// The filter, owned here and nowhere else. It names no place, so it does
  /// not belong in the address — and the pane is keyed by package, so it
  /// survives opening scenario after scenario and resets when the suite does.
  final _query = TextEditingController();

  ScenariosCore get core => widget.core;
  String get package => widget.package;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Writes a scenario and goes straight to it — which runs it, since opening
  /// a scenario is the demand. The whole point of the button over the command
  /// the hint names: you end up looking at the thing you just made.
  Future<void> _newScenario(BuildContext context) async {
    var result = await showNewScenarioDialog(
      context,
      core: core,
      package: package,
    );
    if (result == null || !context.mounted) return;
    AddressScope.write(context).setSegments(
      scenarioSegments(package, file: result.file, scenario: result.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to narrow until the scan has found something: a filter over a
    // suite of none is a control that can only disappoint.
    var scanned = core.scanResultFor(package)?.scenarios ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ListPaneHeader(
          directory: core.directoryFor(package),
          onNew: () => unawaited(_newScenario(context)),
        ),
        if (scanned.isNotEmpty)
          _FilterField(controller: _query, onChanged: (_) => setState(() {})),
        const Divider(height: 1),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
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
      // The hint is the same string `list` hands an agent — this used to be the
      // only place it was said, which is what made it unfindable from anywhere
      // else. Above it, the thing it describes, as a button: a reader who is in
      // the GUI should not be sent to a terminal to get their first file.
      return SingleChildScrollView(
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () => unawaited(_newScenario(context)),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New scenario'),
            ),
            const Gap(FwSpacing.lg),
            SelectableText(
              'No scenarios in ${core.directoryFor(package)}.\n\n'
              '${scenarioAuthoringHint(core.directoryFor(package))}',
              style: context.type.caption.copyWith(color: context.colors.mut),
            ),
          ],
        ),
      );
    }

    // Every file lives under the configured directory, so the prefix says
    // nothing — the header drops it and the tooltip keeps the whole path. It
    // is also what the filter matches on, for the same reason: nobody types
    // the part every row shares.
    var prefix = '${core.directoryFor(package)}/';
    String sectionLabel(String file) =>
        file.startsWith(prefix) ? file.substring(prefix.length) : file;

    var query = _query.text.trim();
    var filtering = query.isNotEmpty;

    // Null means the file's own name did not answer the query — which is not
    // the same as an empty highlight, so the map keeps the distinction.
    var fileMarks = <String, List<int>?>{};
    List<int>? fileMark(String file) => fileMarks.putIfAbsent(
      file,
      () => filtering ? fuzzyMatch(query, sectionLabel(file))?.matched : null,
    );

    // A file answers for every scenario in it: `checkout_test` keeps the whole
    // group, a scenario's own name keeps just that row. Grouping and scan
    // order are left alone — ranking by score would shuffle the suite out of
    // the shape the reader knows it by.
    var byFile = <String, List<(ScenarioRef, List<int>)>>{};
    for (var ref in result.scenarios) {
      var marks = const <int>[];
      if (filtering) {
        var onName = fuzzyMatch(query, ref.name);
        if (onName == null && fileMark(ref.file) == null) continue;
        marks = onName?.matched ?? const [];
      }
      byFile.putIfAbsent(ref.file, () => []).add((ref, marks));
    }

    if (byFile.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Text(
          'No scenario matches “$query”.',
          style: context.type.caption.copyWith(color: context.colors.mut3),
        ),
      );
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
            child: Tooltip(
              message: entry.key,
              waitDuration: const Duration(milliseconds: 500),
              child: MatchedText(
                sectionLabel(entry.key),
                matched: fileMark(entry.key) ?? const [],
                style: context.type.sectionLabel,
              ),
            ),
          ),
          for (var (ref, marks) in entry.value)
            _ScenarioRow(
              ref,
              matched: marks,
              selected:
                  widget.selected.file == ref.file &&
                  widget.selected.scenario == ref.name,
              onTap: () => AddressScope.write(context).setSegments(
                scenarioSegments(package, file: ref.file, scenario: ref.name),
              ),
            ),
        ],
      ],
    );
  }
}

/// The list pane's header: which directory this suite lives in, and the way to
/// add to it.
///
/// Above every state the pane has — loading, failed, empty, populated — because
/// "write another one" is not a question you only have when there are none.
class _ListPaneHeader extends StatelessWidget {
  const _ListPaneHeader({required this.directory, required this.onNew});

  final String directory;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.lg,
        FwSpacing.sm,
        FwSpacing.sm,
        FwSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: directory,
              waitDuration: const Duration(milliseconds: 500),
              child: Text(
                directory,
                style: context.type.sectionLabel,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Tooltip(
            message: 'New scenario',
            child: Tappable.builder(
              onTap: onNew,
              builder: (context, hovered) => Container(
                padding: const EdgeInsets.all(FwSpacing.xs),
                decoration: BoxDecoration(
                  color: hovered ? colors.panel : Colors.transparent,
                  borderRadius: BorderRadius.circular(context.radii.radius),
                ),
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: hovered ? colors.ink : colors.mut,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One size for both of the field's icon slots, filled or not. An
/// `InputDecorator` sizes itself around its icons, so a clear button that comes
/// and goes with the text takes the field's height with it.
const _iconSlot = BoxConstraints.tightFor(width: 24, height: 22);

/// The filter, as the catalog's tree filter wears it: short, a search glyph, a
/// clear button that only appears once there is something to clear.
///
/// The caller owns the controller and rebuilds on change, which is also what
/// makes the clear button appear — there is no state here worth keeping.
class _FilterField extends StatelessWidget {
  const _FilterField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.md,
        0,
        FwSpacing.md,
        FwSpacing.md,
      ),
      child: SizedBox(
        height: 28,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: context.type.caption.copyWith(color: colors.ink),
          decoration: InputDecoration(
            hintText: 'Filter',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: FwSpacing.md,
            ),
            prefixIcon: Icon(Icons.search, size: 14, color: colors.mut2),
            prefixIconConstraints: _iconSlot,
            suffixIconConstraints: _iconSlot,
            suffixIcon: controller.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: Icon(Icons.close, size: 14, color: colors.mut2),
                    padding: EdgeInsets.zero,
                    constraints: _iconSlot,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _ScenarioRow extends StatelessWidget {
  const _ScenarioRow(
    this.ref, {
    required this.selected,
    required this.onTap,
    this.matched = const [],
  });

  final ScenarioRef ref;
  final bool selected;
  final VoidCallback onTap;

  /// Which characters of the name the filter matched. Empty when it matched
  /// the file instead — the row is on screen for a reason the row cannot show,
  /// and the lit file header above it is where that reason is.
  final List<int> matched;

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
              child: MatchedText(
                ref.name,
                matched: matched,
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
    // Framed by what the run *did*, which for an unspecified device is what
    // its folder answered.
    var device = run?.device == null ? null : deviceById(run!.device!);

    // Dark runs default to light chrome, like a real phone would show.
    var statusFallback = run?.axes.brightness == 'dark'
        ? Brightness.light
        : Brightness.dark;

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
          statusFallback: statusFallback,
          // Source paths in the node detail shorten against the package —
          // the same string the scenario file itself is addressed by.
          displayRoot: widget.core.packageRootFor(widget.package),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, run),
        _AxesBar(
          axes: widget.axes,
          // What the last run resolved an unspecified device to — the only
          // way the panel learns a folder's default, since the profile lives
          // in the guest.
          resolved: run?.device,
          // What this scenario's folder profile offers, once the live listing
          // has landed: the pool goes to the top of the menu, and everything
          // else stays reachable below it.
          offered: widget.core.offeredDevicesFor(widget.package, widget.file),
          languages: widget.core.offeredLanguagesFor(
            widget.package,
            widget.file,
          ),
        ),
        const Divider(height: 1),
        // Said out loud rather than repaired, with the accepted values — the
        // reader is often an agent that guessed.
        if (unknownDeviceIn(AddressScope.param(context, 'device'))
            case var bad?)
          _ErrorBanner(
            'No device "$bad" — running as the folder says instead. '
            'Accepted: ${deviceIds.join(', ')}.',
          ),
        Expanded(child: _body(context, run, device, statusFallback)),
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
          _RunSplitButton(
            enabled: !running,
            onRun: _start,
            // The escape hatch, for the changes no incremental lane can see:
            // drops the warm harness and cold-starts — fresh bundle, fresh
            // kernel, fresh process.
            onFullRestart: () {
              widget.core.restartRunner(widget.package);
              _start();
            },
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ScenarioPanelRun? run,
    Device? device,
    Brightness statusFallback,
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
            statusFallback: statusFallback,
          ),
        ),
      ],
    );
  }
}

/// The primary Run with its overflow: the main segment runs, the arrow opens
/// the rarer choices — today just "Full restart".
class _RunSplitButton extends StatelessWidget {
  const _RunSplitButton({
    required this.enabled,
    required this.onRun,
    required this.onFullRestart,
  });

  final bool enabled;
  final VoidCallback onRun;
  final VoidCallback onFullRestart;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var fg = colors.onPrimary;
    return Container(
      height: 32,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: enabled ? colors.accent : colors.mut3,
        borderRadius: BorderRadius.circular(context.radii.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tappable(
            onTap: enabled ? onRun : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow, size: 16, color: fg),
                  const Gap(FwSpacing.xs),
                  Text('Run', style: context.type.button.copyWith(color: fg)),
                ],
              ),
            ),
          ),
          Container(width: 1, color: fg.withValues(alpha: 0.3)),
          Menu(
            align: PopoverAlign.end,
            entries: [
              MenuItem(
                'Full restart',
                icon: Icons.restart_alt,
                onSelected: enabled ? onFullRestart : null,
              ),
            ],
            builder: (context, controller) => Tappable(
              onTap: enabled ? controller.toggle : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: FwSpacing.xs),
                child: Icon(Icons.arrow_drop_down, size: 18, color: fg),
              ),
            ),
          ),
        ],
      ),
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
  const _AxesBar({
    required this.axes,
    required this.languages,
    this.offered = const [],
    this.resolved,
  });

  final ScenarioAxes axes;

  /// The devices this scenario's folder profile offers, its first one the
  /// default. Empty where no profile governs it, and before the live listing
  /// lands — in which case the menu is the whole table, as it was.
  final List<String> offered;

  /// What the last run made of an unspecified device — the folder profile's
  /// first device, or the global default. Null before the first run, when the
  /// honest answer is that the panel does not know yet.
  final String? resolved;

  /// The locale tags the project's config declares — the whole language menu.
  final List<String> languages;

  @override
  Widget build(BuildContext context) {
    var device = axes.device == null ? null : deviceById(axes.device!);
    var byFolder = resolved == null ? null : deviceById(resolved!);
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
                // Named by what the folder resolved it to, once a run has
                // said — "Default" alone is true but useless.
                byFolder == null ? 'Default' : 'Default · ${byFolder.label}',
                onSelected: () =>
                    AddressScope.write(context).setParam('device', null),
              ),
              MenuItem(
                'Bare test surface',
                onSelected: () =>
                    AddressScope.write(context).setParam('device', fitDeviceId),
              ),
              // The folder's own pool first — the short list somebody meant
              // when they wrote the profile.
              if (offered.isNotEmpty) ...[
                const MenuHeader('This folder'),
                for (var id in offered)
                  if (deviceById(id) case var d?)
                    MenuItem(
                      d.label,
                      shortcut: describeDevice(d),
                      onSelected: () =>
                          AddressScope.write(context).setParam('device', d.id),
                    ),
              ],
              // …then everything, because "show me this phone screen at
              // desktop width" is a real question and a profile is an offer,
              // not a fence.
              for (var group in {for (var d in Devices.all) d.group}) ...[
                MenuHeader(group),
                for (var d in Devices.all.where((d) => d.group == group))
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
              value: switch (axes.device) {
                // Unspecified reads as what it ran as, marked as not yours —
                // the chip lights up only when *you* picked something.
                null =>
                  byFolder == null ? 'Default' : '${byFolder.label} (default)',
                fitDeviceId => 'Bare surface',
                _ => device?.label ?? 'Default',
              },
              active: axes.device != null,
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

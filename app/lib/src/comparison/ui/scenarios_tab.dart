import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../capture/settle.dart';
import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../channels.dart';
import '../comparison_controller.dart';
import '../scenario_comparison.dart';
import '../shot_cache.dart';
import 'channel_lines.dart';
import 'merged_tree.dart';
import 'shot_image.dart';
import 'stage.dart';
import 'state_chip.dart';

const scenariosTabKey = Key('comparison.scenarios');

Key scenarioRowKey(String id) => ValueKey('comparison.scenario.$id');

const stepPageKey = Key('comparison.step-page');
const stepBackKey = Key('comparison.step-back');

/// The scenario half: every flow on the left, the picked flow's merged tree
/// beside it, and a picked *step* pushed over both.
///
/// **A tree where the previews half has a list**, because a preview is one
/// picture and a scenario is a tree of them: without it, picking a step means
/// reading a list of paths with `›` in them, which is the shape the tree exists
/// to replace.
///
/// **And a pushed page where the previews half has a detail pane.** A step's
/// two frames are portrait; a band under the tree is landscape and short, so
/// two of them side by side came out postage-stamp sized in the one place the
/// pictures are the point. The scenarios panel already pushes a step as a full
/// page with a back arrow, and this is the same move — the flow stays one tap
/// away, in the address as much as on screen.
class ScenariosTab extends StatefulWidget {
  const ScenariosTab({
    super.key,
    required this.half,
    required this.cache,
    required this.settle,
    required this.selected,
    required this.onSelect,
  });

  final ComparisonHalf half;
  final ShotCache cache;
  final SettleRegistry settle;

  /// `<file>#<scenario>/<step path>` as the address names it, or null.
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  State<ScenariosTab> createState() => _ScenariosTabState();
}

class _ScenariosTabState extends State<ScenariosTab> {
  late final _shots = ShotPair(widget.cache);
  var _mode = StageMode.sideBySide;

  @override
  void initState() {
    super.initState();
    _shots.addListener(_onShots);
    // Listened to rather than diffed: the half's list is mutated in place, so
    // a widget comparison can never see a row arrive.
    widget.half.addListener(_onRows);
    widget.settle.add(_shots);
    _load();
  }

  @override
  void didUpdateWidget(ScenariosTab old) {
    super.didUpdateWidget(old);
    if (!identical(old.half, widget.half)) {
      old.half.removeListener(_onRows);
      widget.half.addListener(_onRows);
    }
    if (old.selected != widget.selected) _load();
  }

  void _onShots() {
    if (mounted) setState(() {});
  }

  void _onRows() {
    if (mounted) _load();
  }

  /// The address is `<scenario id>/<step path>`; a scenario id has a `#` in it
  /// and a step path does not, so the split is at the first `/` after it.
  (String? scenario, String? step) get _address {
    var selected = widget.selected;
    if (selected == null) return (null, null);
    var hash = selected.indexOf('#');
    var slash = selected.indexOf('/', hash < 0 ? 0 : hash);
    return slash < 0
        ? (selected, null)
        : (selected.substring(0, slash), selected.substring(slash + 1));
  }

  ScenarioComparison? get _scenario {
    var scenarios = widget.half.scenarios;
    if (scenarios.isEmpty) return null;
    var named = _address.$1;
    return scenarios.firstWhere(
      (s) => s.scenario == named,
      // Worst first, so this opens on the flow most likely to be a mistake.
      orElse: () => scenarios.firstWhere(
        (s) => s.state.isFinding,
        orElse: () => scenarios.first,
      ),
    );
  }

  /// The step the address names, and **only** that.
  ///
  /// No falling back to the first finding: a step is a *pushed page* here, so
  /// picking one for you would open it on arrival and hide the flow you came
  /// to read.
  ComparedItem? get _step {
    var named = _address.$2;
    if (named == null) return null;
    return _scenario?.items.firstWhereOrNull((item) => item.id == named);
  }

  void _load() {
    var frames = _scenario?.frames[_step?.id];
    unawaited(_shots.loadFrames(base: frames?.base, head: frames?.head));
  }

  void _select({String? scenario, String? step}) {
    var id = scenario ?? _scenario?.scenario;
    if (id == null) return;
    widget.onSelect(step == null ? id : '$id/$step');
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var scenario = _scenario;
    var step = _step;

    // **Pushed over the flow, not squeezed under it.** A phone frame is
    // portrait; a band along the bottom is landscape and short, so two of them
    // side by side came out postage-stamp sized in the one place the pictures
    // are the whole point. The scenarios panel already answers this — it pushes
    // a step as a full page with a back arrow — and the flow stays one tap
    // away, in the address as well as on screen.
    if (step != null && scenario != null) {
      return _StepPage(
        item: step,
        shots: _shots,
        mode: _mode,
        onMode: (mode) => setState(() => _mode = mode),
        onBack: () => widget.onSelect(scenario.scenario),
      );
    }

    return Row(
      key: scenariosTabKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: colors.line)),
            ),
            child: _Index(
              half: widget.half,
              selected: scenario?.scenario,
              onSelect: (id) => _select(scenario: id),
            ),
          ),
        ),
        if (scenario != null)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(scenario),
                Expanded(
                  child: MergedTree(
                    scenario: scenario,
                    selected: null,
                    onSelect: (id) => _select(step: id),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    widget.half.removeListener(_onRows);
    widget.settle.remove(_shots);
    _shots
      ..removeListener(_onShots)
      ..dispose();
    super.dispose();
  }
}

class _Index extends StatelessWidget {
  const _Index({
    required this.half,
    required this.selected,
    required this.onSelect,
  });

  final ComparisonHalf half;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    var findings = [
      for (var s in half.scenarios)
        if (s.state.isFinding) s,
    ];
    var quiet = [
      for (var s in half.scenarios)
        if (!s.state.isFinding) s,
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.sm),
      children: [
        for (var s in findings)
          _IndexRow(
            scenario: s,
            selected: s.scenario == selected,
            onTap: () => onSelect(s.scenario),
          ),
        if (findings.isEmpty && !half.isRunning)
          Padding(
            padding: const EdgeInsets.all(FwSpacing.xl),
            child: Text(
              'Nothing changed.',
              style: context.type.body.copyWith(color: context.colors.mut),
            ),
          ),
        if (quiet.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.xl,
              FwSpacing.lg,
              FwSpacing.xl,
              FwSpacing.sm,
            ),
            child: Text(
              '${quiet.length} UNCHANGED',
              style: context.type.micro.copyWith(color: context.colors.mut),
            ),
          ),
          for (var s in quiet)
            _IndexRow(
              scenario: s,
              selected: s.scenario == selected,
              onTap: () => onSelect(s.scenario),
            ),
        ],
      ],
    );
  }
}

class _IndexRow extends StatelessWidget {
  const _IndexRow({
    required this.scenario,
    required this.selected,
    required this.onTap,
  });

  final ScenarioComparison scenario;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var hash = scenario.scenario.indexOf('#');
    var name = hash < 0
        ? scenario.scenario
        : scenario.scenario.substring(hash + 1);
    var file = hash < 0 ? '' : scenario.scenario.substring(0, hash);

    return Tappable.builder(
      key: scenarioRowKey(scenario.scenario),
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.xl,
          vertical: FwSpacing.sm,
        ),
        color: selected
            ? colors.accent.withValues(alpha: 0.10)
            : hovered
            ? colors.hoverOverlay
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: context.type.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (file.isNotEmpty)
                    Text(
                      file,
                      style: context.type.micro.copyWith(color: colors.mut),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Gap(FwSpacing.sm),
            if (scenario.state.isFinding) StateChip(scenario.state),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.scenario);

  final ScenarioComparison scenario;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FwSpacing.xl,
      FwSpacing.lg,
      FwSpacing.xl,
      0,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(scenario.scenario, style: context.type.bodyStrong),
        ),
        StateChip(scenario.state),
      ],
    ),
  );
}

/// One step, over the flow: the two frames, and what the other channels found.
class _StepPage extends StatelessWidget {
  const _StepPage({
    required this.item,
    required this.shots,
    required this.mode,
    required this.onMode,
    required this.onBack,
  });

  final ComparedItem item;
  final ShotPair shots;
  final StageMode mode;
  final ValueChanged<StageMode> onMode;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var hasChannels =
        (item.tree?.changed ?? false) ||
        item.texts != null ||
        item.events != null;

    return Column(
      key: stepPageKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FwSpacing.lg,
            FwSpacing.md,
            FwSpacing.xl,
            0,
          ),
          child: Row(
            children: [
              Tappable(
                key: stepBackKey,
                onTap: onBack,
                child: Icon(Icons.arrow_back, size: 18, color: colors.mut),
              ),
              const Gap(FwSpacing.lg),
              Expanded(child: Text(item.id, style: context.type.heading)),
              StateChip(item.state),
            ],
          ),
        ),
        if (item.note case var note?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.xl,
              FwSpacing.xs,
              FwSpacing.xl,
              0,
            ),
            child: Text(
              note,
              style: context.type.caption.copyWith(color: colors.red),
            ),
          ),
        Expanded(
          flex: 5,
          child: shots.settled
              ? ComparisonStage(
                  shots: shots,
                  mode: mode,
                  onMode: onMode,
                  diff: item.pixels?.diff,
                )
              : Center(
                  child: Text(
                    'Loading…',
                    style: context.type.body.copyWith(color: colors.mut),
                  ),
                ),
        ),
        if (hasChannels) Expanded(flex: 2, child: ChannelLines(item)),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../../utils/graphite.dart';
import '../channels.dart';
import '../frame_ref.dart';
import '../scenario_alignment.dart';
import '../scenario_comparison.dart';
import 'shot_image.dart';
import 'state_chip.dart';

const mergedTreeKey = Key('comparison.merged-tree');

Key stepNodeKey(String id) => ValueKey('comparison.step.$id');

/// One scenario's two runs as a single tree.
///
/// **Merged, not side by side**, and that is the whole design of the scenario
/// half. Two flows drawn next to each other make a reader do the alignment —
/// which is the expensive part, and the part the aligner has already done. One
/// tree with a ring per node says *where* the runs diverged in the shape a
/// scenario actually has: a trunk that forks.
///
/// A branch that exists on one side only is **one labelled row**, however many
/// steps hang off it. A new `split` branch is one decision in the source;
/// drawing its four steps as four nodes describes that decision four times and
/// buries whatever else the run found.
class MergedTree extends StatelessWidget {
  const MergedTree({
    super.key,
    required this.scenario,
    required this.selected,
    required this.onSelect,
  });

  final ScenarioComparison scenario;

  /// The step id the address names, or null.
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    var graph = _MergedGraph.of(scenario);
    if (graph.nodes.isEmpty) return const SizedBox.shrink();

    // **The scenarios panel's own flow, with a comparison on it.** That panel
    // draws a run as a horizontal graph of device-framed shots, and a reader
    // who has learned to read one flow should not have to learn a second shape
    // to read two — so this is the same `DirectGraph`, the same orientation and
    // the same pan-and-zoom, with the nodes carrying a verdict.
    return DirectGraph(
      key: mergedTreeKey,
      list: graph.nodes,
      cellSize: const Size(_nodeWidth + 40, _thumbHeight + 70),
      cellPadding: 40,
      contactEdgesDistance: 0,
      tipLength: 14,
      orientation: MatrixOrientation.horizontal,
      interactiveBuilder: (context, child) => InteractiveViewer(
        maxScale: 1.5,
        minScale: 0.2,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(2000),
        child: child,
      ),
      builder: (context, node) {
        var cell = graph.cells[node.id]!;
        return switch (cell) {
          _StepCell(:var item) => _StepNode(
            item: item,
            frames: scenario.frames[item.id],
            selected: item.id == selected,
            onTap: () => onSelect(item.id),
          ),
          _BranchCell(:var branch) => _OneSidedBranch(branch),
        };
      },
    );
  }
}

/// What a node in the merged graph stands for.
sealed class _Cell {
  const _Cell();
}

class _StepCell extends _Cell {
  const _StepCell(this.item);
  final ComparedItem item;
}

class _BranchCell extends _Cell {
  const _BranchCell(this.branch);
  final BranchDelta branch;
}

/// The flat item list, back into the tree it came from.
///
/// **Read out of the ids rather than carried alongside them**: an item's id
/// *is* its path through the flow — `guest › small cup › Cart` — because that
/// is what a report has to address it by anyway. One representation, so the
/// tree and the artifact cannot disagree about where a step is.
class _MergedGraph {
  const _MergedGraph({required this.nodes, required this.cells});

  final List<NodeInput> nodes;
  final Map<String, _Cell> cells;

  static _MergedGraph of(ScenarioComparison scenario) {
    // Steps grouped by the branch path they sit on, in the order they arrived.
    var laneOrder = <String>[];
    var lanes = <String, List<ComparedItem>>{};
    for (var item in scenario.items) {
      var parts = item.id.split(' › ');
      var lane = parts.take(parts.length - 1).join(' › ');
      lanes
          .putIfAbsent(lane, () {
            laneOrder.add(lane);
            return [];
          })
          .add(item);
    }

    var cells = <String, _Cell>{};
    var next = <String, List<String>>{};

    for (var lane in laneOrder) {
      var steps = lanes[lane]!;
      for (var (index, item) in steps.indexed) {
        cells[item.id] = _StepCell(item);
        if (index + 1 < steps.length) {
          next[item.id] = [steps[index + 1].id];
        }
      }
      // A lane hangs off the last step of the lane above it — which is where
      // its `split` was written.
      var parent = _lastOfParentLane(lane, lanes);
      if (parent != null) {
        (next[parent] ??= []).add(steps.first.id);
      }
    }

    // A branch only one run has: one node, wherever it forked from.
    for (var (index, branch) in scenario.branches.indexed) {
      var id = 'branch:$index:${branch.label}';
      cells[id] = _BranchCell(branch);
      var parent = _lastOfLane(branch.path.join(' › '), lanes);
      if (parent != null) (next[parent] ??= []).add(id);
    }

    return _MergedGraph(
      nodes: [
        for (var id in cells.keys)
          NodeInput(id: id, next: next[id] ?? const []),
      ],
      cells: cells,
    );
  }

  static String? _lastOfParentLane(
    String lane,
    Map<String, List<ComparedItem>> lanes,
  ) {
    if (lane.isEmpty) return null;
    var parts = lane.split(' › ');
    return _lastOfLane(parts.take(parts.length - 1).join(' › '), lanes);
  }

  static String? _lastOfLane(
    String lane,
    Map<String, List<ComparedItem>> lanes,
  ) => lanes[lane]?.lastOrNull?.id;
}

/// A branch only one run has.
class _OneSidedBranch extends StatelessWidget {
  const _OneSidedBranch(this.branch);

  final BranchDelta branch;

  @override
  Widget build(BuildContext context) {
    var state = branch.added ? ComparedState.added : ComparedState.removed;
    var color = state.colorIn(context);
    return Container(
      width: _nodeWidth,
      padding: const EdgeInsets.all(FwSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        color: color.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StateChip(state),
          const Gap(FwSpacing.xs),
          Text(
            '${branch.steps} step${branch.steps == 1 ? '' : 's'}',
            style: context.type.caption.copyWith(color: context.colors.mut),
          ),
        ],
      ),
    );
  }
}

const _nodeWidth = 132.0;
const _thumbHeight = 190.0;

/// One step: its head frame, ringed by what the comparison said about it.
class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.item,
    required this.frames,
    required this.selected,
    required this.onTap,
  });

  final ComparedItem item;
  final ({FrameRef? base, FrameRef? head})? frames;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var color = item.state.colorIn(context);
    var ring = item.state.isFinding ? color : colors.line;

    return Padding(
      padding: const EdgeInsets.only(bottom: FwSpacing.md),
      child: Tappable.builder(
        key: stepNodeKey(item.id),
        onTap: onTap,
        builder: (context, hovered) => SizedBox(
          width: _nodeWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: _thumbHeight,
                decoration: BoxDecoration(
                  // **A ring, not a tint.** The frame is the subject; colouring
                  // it changes the very thing a reader is trying to judge.
                  border: Border.all(
                    color: selected ? colors.accent : ring,
                    width: selected || item.state.isFinding ? 2 : 1,
                  ),
                  color: hovered ? colors.hoverOverlay : colors.panel,
                ),
                child: _Thumbnail(
                  // The head frame, falling back to base for a step only the
                  // base run had — there is nothing else to show for it.
                  frames?.head ?? frames?.base,
                ),
              ),
              const Gap(FwSpacing.xs),
              Text(
                item.label ?? item.id.split(' › ').last,
                style: context.type.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.state.isFinding) ...[
                const Gap(2),
                StateChip(item.state),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One frame, decoded on demand.
class _Thumbnail extends StatefulWidget {
  const _Thumbnail(this.frame);

  final FrameRef? frame;

  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  Shot? _shot;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_Thumbnail old) {
    super.didUpdateWidget(old);
    if (old.frame?.path != widget.frame?.path) unawaited(_load());
  }

  Future<void> _load() async {
    var shot = await ShotPair.fromFile(widget.frame);
    if (!mounted) {
      shot?.image.dispose();
      return;
    }
    setState(() {
      _shot?.image.dispose();
      _shot = shot;
    });
  }

  @override
  Widget build(BuildContext context) {
    var shot = _shot;
    if (shot == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.all(2), child: ShotView(shot));
  }

  @override
  void dispose() {
    _shot?.image.dispose();
    super.dispose();
  }
}

import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import 'channels.dart';
import 'pixel_diff.dart';
import 'scenario_alignment.dart';
import 'tree_diff.dart';

/// One step of one run, with everything a comparison reads off it.
///
/// The artifact triple plus the transition: the picture, the tree, the texts,
/// and what the app did on the way here.
class ScenarioStepShot {
  const ScenarioStepShot({
    required this.step,
    this.rgba,
    this.width = 0,
    this.height = 0,
    this.tree,
    this.texts = const [],
    this.events = const [],
    this.failure,
  });

  final AlignableStep step;

  final Uint8List? rgba;
  final int width;
  final int height;
  final InspectNode? tree;
  final List<String> texts;
  final List<Map<String, Object?>> events;

  /// What the scenario broke on at this step, when it did.
  final String? failure;
}

/// One scenario's two runs, compared.
class ScenarioComparison {
  const ScenarioComparison({
    required this.scenario,
    required this.items,
    required this.branches,
    required this.state,
  });

  /// `<file>#<name>`.
  final String scenario;

  /// One per step: matched pairs with their channels, plus the steps that
  /// exist on one side only.
  final List<ComparedItem> items;

  /// Branches that exist on one side only — one row each, however many steps
  /// they hold.
  final List<BranchDelta> branches;

  /// The scenario's own verdict, worst of what its steps said.
  final ComparedState state;

  Map<String, Object?> toJson() => {
    'scenario': scenario,
    'state': state.name,
    if (branches.isNotEmpty)
      'branches': [
        for (var branch in branches)
          {
            'label': branch.label,
            'state': branch.added ? 'added' : 'removed',
            'steps': branch.steps,
            if (branch.path.isNotEmpty) 'path': branch.path,
          },
      ],
    'steps': [for (var item in items) item.toJson()],
  };

  /// Compares two runs of one scenario.
  ///
  /// **Pass and fail outrank every pixel.** A scenario that stopped completing
  /// is the most valuable thing this tool can say, and a percentage next to it
  /// would be answering a smaller question — so a failure that appeared is the
  /// verdict, whatever the steps before it look like.
  static ScenarioComparison of({
    required String scenario,
    required List<ScenarioStepShot> base,
    required List<ScenarioStepShot> head,
  }) {
    var alignment = ScenarioAlignment.of(
      base: [for (var shot in base) shot.step],
      head: [for (var shot in head) shot.step],
    );
    var baseByIndex = {for (var shot in base) shot.step.index: shot};
    var headByIndex = {for (var shot in head) shot.step.index: shot};

    var items = <ComparedItem>[];
    for (var pair in alignment.pairs) {
      items.add(switch (pair.delta) {
        StepDelta.added => ComparedItem(
          id: pair.path,
          state: ComparedState.added,
          label: pair.head!.label,
        ),
        StepDelta.removed => ComparedItem(
          id: pair.path,
          state: ComparedState.removed,
          label: pair.base!.label,
        ),
        StepDelta.matched || StepDelta.retargeted => _compare(
          pair,
          baseByIndex[pair.base!.index]!,
          headByIndex[pair.head!.index]!,
        ),
      });
    }

    return ScenarioComparison(
      scenario: scenario,
      items: items,
      branches: alignment.branches,
      state: _verdict(items, alignment),
    );
  }

  static ComparedItem _compare(
    AlignedPair pair,
    ScenarioStepShot base,
    ScenarioStepShot head,
  ) {
    // A step that broke is not a step that looks different: the picture is
    // whatever was on screen when it threw, and comparing it against a working
    // one measures the wrong thing.
    if (base.failure != null || head.failure != null) {
      return ComparedItem.of(
        id: pair.path,
        label: pair.head!.label,
        baseRendered: base.failure == null,
        headRendered: head.failure == null,
        note: head.failure ?? base.failure,
      );
    }
    var item = ComparedItem.of(
      id: pair.path,
      label: pair.head!.label,
      pixels: base.rgba == null || head.rgba == null
          ? null
          : PixelDiff.of(
              base: base.rgba!,
              baseWidth: base.width,
              baseHeight: base.height,
              head: head.rgba!,
              headWidth: head.width,
              headHeight: head.height,
            ),
      tree: TreeDiff.of(base.tree, head.tree),
      baseTexts: base.texts,
      headTexts: head.texts,
      baseEvents: base.events,
      headEvents: head.events,
    );
    // A retarget is a change whatever the channels found: the same step now
    // names something else, and two identical pictures are the *reason* it is
    // worth saying rather than a reason to stay quiet.
    if (pair.delta == StepDelta.retargeted &&
        item.state == ComparedState.same) {
      return ComparedItem(
        id: item.id,
        state: ComparedState.changed,
        label: item.label,
        pixels: item.pixels,
        tree: item.tree,
        note: 'retargeted: ${pair.base!.target} → ${pair.head!.target}',
      );
    }
    return item;
  }

  static ComparedState _verdict(
    List<ComparedItem> items,
    ScenarioAlignment alignment,
  ) {
    var worst = ComparedState.skipped;
    for (var item in items) {
      if (item.state.index < worst.index) worst = item.state;
    }
    if (alignment.branches.isNotEmpty &&
        worst.index > ComparedState.changed.index) {
      // A branch appearing or disappearing is a change to the flow even when
      // every step it shares with the other side is identical.
      return ComparedState.changed;
    }
    return worst;
  }
}

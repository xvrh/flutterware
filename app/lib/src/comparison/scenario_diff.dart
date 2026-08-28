/// What *produces* a `ScenarioComparison`, as opposed to what one is.
///
/// The result travels — it is written into `index.json` and read back by
/// `package:flutterware/comparison_report.dart` — and these two do not. A
/// [ScenarioStepShot] holds live pixels and a live tree straight out of a
/// replay, and the alignment is how two runs' steps are matched up; neither
/// reaches the file, so neither is anybody's API. That is the whole reason
/// this is a separate file from the model it builds: they were one file doing
/// two jobs, and publishing the model is what made the seam visible.
library;

import 'dart:typed_data';

import 'package:flutterware/comparison_report.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import 'scenario_alignment.dart';

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
    this.frame,
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

  /// Where the harness left this step's frame.
  ///
  /// A [FrameRef] rather than a `ShotCache` key, because a scenario's frames
  /// are written by the replay rather than filed by a renderer — one run
  /// produces a whole tree of them, which is the granularity the design gives
  /// scenarios and the reason their key covers the scenario rather than the
  /// step.
  final FrameRef? frame;
}

/// Compares two runs of one scenario.
///
/// Pass and fail outrank every pixel. A scenario that stopped completing
/// is the most valuable thing this tool can say, and a percentage next to it
/// would be answering a smaller question — so a failure that appeared is the
/// verdict, whatever the steps before it look like.
ScenarioComparison compareScenarioSteps({
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
  var frames = <String, ({FrameRef? base, FrameRef? head})>{};
  for (var pair in alignment.pairs) {
    frames[pair.path] = (
      base: pair.base == null ? null : baseByIndex[pair.base!.index]?.frame,
      head: pair.head == null ? null : headByIndex[pair.head!.index]?.frame,
    );
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
    frames: frames,
  );
}

ComparedItem _compare(
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
  if (pair.delta == StepDelta.retargeted && item.state == ComparedState.same) {
    return ComparedItem(
      id: item.id,
      state: ComparedState.changed,
      label: item.label,
      pixels: item.pixels,
      tree: item.tree,
      // Named *and* explained: "retargeted" is this model's word, not a
      // word a reader arrives with, and the whole point of the note is that
      // two identical pictures still deserve a sentence.
      note:
          'retargeted — same step, but it aimed at something else: '
          '${pair.base!.target} → ${pair.head!.target}',
    );
  }
  return item;
}

ComparedState _verdict(List<ComparedItem> items, ScenarioAlignment alignment) {
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
  // A step that appeared is a scenario that *changed*. Carrying the step's
  // own word up would say this flow is new when only a line inside it is —
  // and `added` outranks `changed`, so a gained step sorted a scenario above
  // one that genuinely broke nothing but looks different.
  return switch (worst) {
    ComparedState.added || ComparedState.removed => ComparedState.changed,
    _ => worst,
  };
}

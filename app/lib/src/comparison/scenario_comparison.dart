import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import 'channels.dart';
import 'frame_ref.dart';
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

/// One scenario's two runs, compared.
class ScenarioComparison {
  const ScenarioComparison({
    required this.scenario,
    required this.items,
    required this.branches,
    required this.state,
    this.frames = const {},
  });

  /// A scenario that was never replayed — one that exists on a single side,
  /// or one the skip rule answered without running anything.
  ///
  /// Present in the report rather than omitted, so the list of scenarios is
  /// the list of scenarios: a row that is missing tells a reader nothing, and
  /// "skipped" tells them the tool looked and found no reason to.
  const ScenarioComparison.notRun({required this.scenario, required this.state})
    : items = const [],
      branches = const [],
      frames = const {};

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

  /// Each step's two frames, by the id its [ComparedItem] carries.
  ///
  /// Beside the items rather than on them: a preview's `shots` are cache keys
  /// and these are paths, and one field meaning two different kinds of thing is
  /// how a reader ends up opening the wrong one.
  final Map<String, ({FrameRef? base, FrameRef? head})> frames;

  Map<String, Object?> toJson() => {
    // `id` rather than `scenario`, and `steps` alongside a preview's
    // `channels`: a reader walking the whole artifact should not need to know
    // which half a row came from to find out what it is called.
    'id': scenario,
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
    'steps': [
      for (var item in items)
        {
          ...item.toJson(),
          'frames': ?(frames[item.id] == null
              ? null
              : {
                  'base': ?frames[item.id]!.base?.toJson(),
                  'head': ?frames[item.id]!.head?.toJson(),
                }),
        },
    ],
  };

  /// A scenario read back off `index.json` — the exported page's side of
  /// [toJson].
  static ScenarioComparison fromJson(Map<String, Object?> json) {
    var items = <ComparedItem>[];
    var frames = <String, ({FrameRef? base, FrameRef? head})>{};
    for (var step in json['steps'] as List? ?? const []) {
      var map = (step as Map).cast<String, Object?>();
      var item = ComparedItem.fromJson(map);
      items.add(item);
      var pair = map['frames'] as Map<String, Object?>?;
      if (pair != null) {
        frames[item.id] = (
          base: FrameRef.fromJson(
            (pair['base'] as Map?)?.cast<String, Object?>(),
          ),
          head: FrameRef.fromJson(
            (pair['head'] as Map?)?.cast<String, Object?>(),
          ),
        );
      }
    }
    return ScenarioComparison(
      scenario: json['id'] as String? ?? '',
      state:
          ComparedState.values.asNameMap()[json['state']] ??
          ComparedState.skipped,
      items: items,
      frames: frames,
      branches: [
        for (var branch in json['branches'] as List? ?? const [])
          BranchDelta(
            label: (branch as Map)['label'] as String? ?? '',
            added: branch['state'] == 'added',
            steps: branch['steps'] as int? ?? 0,
            path: (branch['path'] as List? ?? const []).cast<String>(),
          ),
      ],
    );
  }

  /// Compares two runs of one scenario.
  ///
  /// Pass and fail outrank every pixel. A scenario that stopped completing
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
    // A step that appeared is a scenario that *changed*. Carrying the step's
    // own word up would say this flow is new when only a line inside it is —
    // and `added` outranks `changed`, so a gained step sorted a scenario above
    // one that genuinely broke nothing but looks different.
    return switch (worst) {
      ComparedState.added || ComparedState.removed => ComparedState.changed,
      _ => worst,
    };
  }
}

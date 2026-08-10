import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware_app/src/motion/lane_model.dart';
import 'package:flutterware_app/src/motion/values_file.dart';
import 'package:flutterware_app/src/plugins/native/motion_sequencer.dart';
import 'package:flutterware_app/src/ui/design/tokens.dart';

import 'shell.dart';

/// The sequencer and its inspector, off mocked guest data.
///
/// The panel proper needs a compiled guest, a running engine and a values file
/// on disk before it draws a single lane, which is why every bug in it so far
/// was found by a person looking at it rather than by a test. This is the same
/// widgets over a literal — every state reachable in one click, and the drag,
/// the selection and the `+` all live.
///
/// The edit closure is applied to the local model here, so a retime sticks the
/// way it would against a file. What is *not* exercised is the write: whether
/// `MotionValuesFile` can put the result back is the values-file tests' job.

const _dur = 620;

MotionSegmentView _seg(
  int start,
  int end,
  Object from,
  Object to, {
  String? curve = 'easeOutCubic',
}) => MotionSegmentView(
  startMs: start,
  endMs: end,
  from: _value(from),
  to: _value(to),
  curve: curve,
);

MotionValueView _value(Object raw) => switch (raw) {
  int argb when argb > 0xFFFF => MotionColorView(argb),
  num value => MotionNumberView(value.toDouble()),
  _ => const MotionNumberView(0),
};

/// Seven targets, mixed states — the shape of the receipt demo, which is the
/// biggest real motion in the repo and the one whose lane list stopped being
/// readable first.
List<MotionTargetView> _targets() => [
  MotionTargetView(
    name: 'glow',
    named: true,
    properties: [
      MotionPropertyView(
        name: 'opacity',
        state: MotionLaneState.wired,
        value: const MotionNumberView(0.42),
        segments: [_seg(60, 520, 0, 0.9)],
      ),
      MotionPropertyView(
        name: 'scale',
        state: MotionLaneState.wired,
        value: const MotionNumberView(0.78),
        segments: [_seg(0, 620, 0.55, 1)],
      ),
    ],
  ),
  MotionTargetView(
    name: 'sheet',
    named: true,
    // A MotionBox sweeps its frozen set, so six more are addable from the `+`.
    offered: const [
      'opacity',
      'translateX',
      'translateY',
      'scale',
      'rotate',
      'blur',
      'borderRadius',
      'color',
    ],
    properties: [
      MotionPropertyView(
        name: 'borderRadius',
        state: MotionLaneState.wired,
        value: const MotionNumberView(24.8),
        segments: [_seg(0, 560, 20, 32, curve: 'easeOutQuint')],
      ),
      MotionPropertyView(
        name: 'color',
        state: MotionLaneState.wired,
        value: const MotionColorView(0xFF1E242D),
        segments: [
          _seg(0, 560, 0xFF1A1F26, 0xFF232A34, curve: 'easeInOutCubic'),
        ],
      ),
    ],
  ),
  MotionTargetView(
    name: 'art',
    named: true,
    properties: [
      MotionPropertyView(
        name: 'width',
        state: MotionLaneState.wired,
        value: const MotionNumberView(148),
        segments: [_seg(0, 560, 64, 208, curve: 'easeOutQuint')],
      ),
      // Two spans on one lane: the case that made the grab decide once on the
      // way down rather than per sample.
      MotionPropertyView(
        name: 'elevation',
        state: MotionLaneState.wired,
        value: const MotionNumberView(11.5),
        segments: [_seg(80, 300, 2, 20), _seg(340, 600, 20, 8)],
      ),
      MotionPropertyView(
        name: 'rotate',
        state: MotionLaneState.wired,
        value: const MotionNumberView(-0.02),
        segments: [_seg(0, 620, -0.055, 0)],
      ),
    ],
  ),
  MotionTargetView(
    name: 'reveal',
    named: true,
    properties: [
      MotionPropertyView(
        name: 'progress',
        state: MotionLaneState.wired,
        value: const MotionNumberView(0.61),
        segments: [_seg(180, 620, 0, 1)],
      ),
      // Read by the build, tuned by nothing: the creation path, and the only
      // lane that draws as an outline.
      const MotionPropertyView(
        name: 'translateY',
        state: MotionLaneState.untuned,
        value: MotionNumberView(0),
      ),
    ],
  ),
  MotionTargetView(
    name: 'play',
    named: true,
    properties: [
      MotionPropertyView(
        name: 'scale',
        state: MotionLaneState.wired,
        value: const MotionNumberView(0.94),
        segments: [_seg(360, 620, 0.82, 1, curve: 'easeOutBack')],
      ),
      // A step keyframe — a zero-length span, which draws as a mark rather than
      // as nothing.
      MotionPropertyView(
        name: 'opacity',
        state: MotionLaneState.wired,
        value: const MotionNumberView(1),
        segments: [_seg(300, 300, 0, 1, curve: null)],
      ),
    ],
  ),
  // Tuned, and no build asked for it. The amber badge and the broken link.
  MotionTargetView(
    name: 'badge',
    named: false,
    properties: [
      MotionPropertyView(
        name: 'rotate',
        state: MotionLaneState.dead,
        value: const MotionNumberView(-0.2),
        segments: [_seg(150, 450, -0.2, 0)],
      ),
    ],
  ),
  // A curve the writer would refuse — the inspector says so rather than
  // plotting something it made up.
  MotionTargetView(
    name: 'artist',
    named: true,
    properties: [
      MotionPropertyView(
        name: 'fontSize',
        state: MotionLaneState.wired,
        value: const MotionNumberView(13.1),
        segments: [_seg(0, 560, 12, 14, curve: 'someProjectCurve')],
      ),
    ],
  ),
];

@Preview(name: 'Sequencer', group: 'Motion', wrapper: wrapInApp)
Widget motionSequencer() => const _Harness();

@Preview(name: 'Sequencer · states', group: 'Motion', wrapper: wrapInApp)
Widget motionSequencerStates() => Material(
  child: ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _Case(
        'Nothing mounted',
        MotionSequencer(
          scope: null,
          problems: const [],
          t: 0,
          selection: null,
          onSelect: (_) {},
          onSeek: (_) {},
          onSeekEnd: () {},
          onEdit: (_, _, _, _) async {},
          onCreate: (_, _) async {},
        ),
      ),
      _Case(
        'A write the editor refused',
        MotionSequencer(
          scope: MotionScopeView(
            id: 'x',
            durationMs: _dur,
            positionMs: 0,
            progress: 0,
            playing: false,
            targets: _targets().take(2).toList(),
          ),
          problems: [MotionFileProblem('sheet.color is not a literal Color')],
          t: 0.3,
          selection: null,
          onSelect: (_) {},
          onSeek: (_) {},
          onSeekEnd: () {},
          onEdit: (_, _, _, _) async {},
          onCreate: (_, _) async {},
        ),
      ),
      _Case(
        'Read, and nothing tuned yet',
        MotionSequencer(
          scope: const MotionScopeView(
            id: 'x',
            durationMs: _dur,
            positionMs: 0,
            progress: 0,
            playing: false,
            targets: [
              MotionTargetView(
                name: 'header',
                named: true,
                offered: ['opacity', 'translateY', 'scale'],
                properties: [
                  MotionPropertyView(
                    name: 'opacity',
                    state: MotionLaneState.untuned,
                  ),
                ],
              ),
            ],
          ),
          problems: const [],
          t: 0.5,
          selection: null,
          onSelect: (_) {},
          onSeek: (_) {},
          onSeekEnd: () {},
          onEdit: (_, _, _, _) async {},
          onCreate: (_, _) async {},
        ),
      ),
    ],
  ),
);

class _Case extends StatelessWidget {
  const _Case(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.type.caption),
        const SizedBox(height: 4),
        Container(
          height: 150,
          decoration: BoxDecoration(
            border: Border.all(color: context.colors.line),
          ),
          child: child,
        ),
      ],
    ),
  );
}

/// The interactive one: drag a span, tap to select, scrub the ruler, add a
/// property. State lives here so the edits stick.
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  var _targetList = _targets();
  MotionSelection? _selection = const MotionSelection('glow', 'opacity', 0);
  double _t = 0.35;

  MotionScopeView get _scope => MotionScopeView(
    id: 'demo',
    durationMs: _dur,
    positionMs: (_t * _dur).round(),
    progress: _t,
    playing: false,
    targets: _targetList,
  );

  /// Applies the panel's own edit closure to the mock, by translating a segment
  /// to the span the writer would see and back again.
  Future<void> _edit(
    String target,
    String property,
    int index,
    MotionSpan Function(MotionSpan) change,
  ) async {
    setState(() {
      _targetList = [
        for (var candidate in _targetList)
          if (candidate.name != target)
            candidate
          else
            MotionTargetView(
              name: candidate.name,
              named: candidate.named,
              offered: candidate.offered,
              properties: [
                for (var existing in candidate.properties)
                  if (existing.name != property)
                    existing
                  else
                    MotionPropertyView(
                      name: existing.name,
                      state: existing.state,
                      value: existing.value,
                      segments: [
                        for (var (at, segment) in existing.segments.indexed)
                          at == index ? _apply(segment, change) : segment,
                      ],
                    ),
              ],
            ),
      ];
    });
  }

  static MotionSegmentView _apply(
    MotionSegmentView segment,
    MotionSpan Function(MotionSpan) change,
  ) {
    var span = change(
      MotionSpan(
        startMs: segment.startMs,
        endMs: segment.endMs,
        from: _literal(segment.from),
        to: _literal(segment.to),
        curve: segment.curve,
      ),
    );
    return MotionSegmentView(
      startMs: span.startMs,
      endMs: span.endMs,
      from: _view(span.from),
      to: _view(span.to),
      curve: span.curve,
    );
  }

  static MotionLiteral _literal(MotionValueView? value) => switch (value) {
    MotionColorView(:var argb) => MotionColor(argb),
    MotionNumberView(:var value) => MotionNumber(value),
    null => const MotionNumber(0),
  };

  static MotionValueView _view(MotionLiteral literal) => switch (literal) {
    MotionColor(:var argb) => MotionColorView(argb),
    MotionNumber(:var value) => MotionNumberView(value),
  };

  /// Gives an untuned property a span, the way `newSpanFor` would.
  Future<void> _create(String target, String property) async {
    setState(() {
      _targetList = [
        for (var candidate in _targetList)
          if (candidate.name != target)
            candidate
          else
            MotionTargetView(
              name: candidate.name,
              named: candidate.named,
              offered: candidate.offered,
              properties: [
                for (var existing in candidate.properties)
                  if (existing.name != property)
                    existing
                  else
                    MotionPropertyView(
                      name: existing.name,
                      state: MotionLaneState.wired,
                      value: existing.value,
                      segments: [_seg(0, _dur ~/ 2, 0, 1)],
                    ),
                if (candidate.properties.every((p) => p.name != property))
                  MotionPropertyView(
                    name: property,
                    state: MotionLaneState.wired,
                    value: const MotionNumberView(0),
                    segments: [_seg(0, _dur ~/ 2, 0, 1)],
                  ),
              ],
            ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    // A `Material`, not a `ColoredBox`: the panel gets one from the shell, and
    // without it here every label renders in the yellow-underlined style
    // `MaterialApp` installs for exactly this mistake.
    return Material(
      color: context.colors.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MotionSequencer(
              scope: _scope,
              problems: const [],
              t: _t,
              selection: _selection,
              onSelect: (selection) => setState(() => _selection = selection),
              onSeek: (t) => setState(() => _t = t),
              onSeekEnd: () {},
              onEdit: _edit,
              onCreate: _create,
            ),
          ),
          VerticalDivider(width: 1, color: context.colors.line),
          SizedBox(
            width: 264,
            child: MotionInspector(scope: _scope, selection: _selection),
          ),
        ],
      ),
    );
  }
}

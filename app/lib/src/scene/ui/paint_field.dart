// What one pass paints with: the kind as a picker, then whatever that kind
// is made of — a colour, or a gradient's stops and its shape.
import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/picker.dart';
import '../gradient_edit.dart';
import 'gradient_field.dart';
import 'number_field.dart';
import 'number_shape.dart';
import 'swatches.dart';

/// A change to the paint, with the words for its undo entry.
typedef PaintChanged = void Function(
  ScenePaint? next, {
  required String label,
  String? mergeKey,
});

class ScenePaintField extends StatelessWidget {
  const ScenePaintField({
    super.key,
    required this.paint,
    required this.own,
    required this.onChanged,
  });

  /// Null is "the text's own colour".
  final ScenePaint? paint;

  /// The text's colour — what no paint draws, and what a gradient made out
  /// of no paint starts from.
  final SceneColor own;

  final PaintChanged onChanged;

  static const _degrees = SceneNumberShape(
    perPixel: 1,
    decimals: 0,
    unit: '°',
    angular: true,
  );
  static const _percent = SceneNumberShape(
    perPixel: 0.5,
    decimals: 0,
    unit: '%',
    softMin: 0,
    softMax: 100,
  );
  static const _radius = SceneNumberShape(
    perPixel: 0.005,
    decimals: 2,
    min: 0.01,
    softMin: 0,
    softMax: 2,
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FwPicker<ScenePaintKind>(
        key: const ValueKey('paint:kind'),
        choices: [
          for (var k in ScenePaintKind.values)
            FwChoice(value: k, label: k.label),
        ],
        selected: ScenePaintKind.of(paint),
        onChanged: (k) =>
            onChanged(convertPaint(paint, k, own: own), label: 'Layer paint'),
      ),
      ...switch (paint) {
        null => const <Widget>[],
        SolidPaint(:var color) => [
          const Gap(FwSpacing.sm),
          SceneColorField(
            current: color,
            allowNone: false,
            onPick: (c) => onChanged(SolidPaint(c!), label: 'Layer colour'),
          ),
        ],
        SceneGradient g => [
          const Gap(FwSpacing.sm),
          SceneGradientField(
            gradient: _editable(g),
            onChanged: (next, {required label, mergeKey}) =>
                onChanged(next, label: label, mergeKey: mergeKey),
          ),
          const Gap(FwSpacing.sm),
          ..._shape(g),
        ],
      },
    ],
  );

  /// A gradient the bar can hold: two colours at least. Only a hand-edited
  /// wire payload can arrive with fewer — the file refuses them — and this
  /// pads with the text's colour rather than drawing a bar with one stop.
  SceneGradient _editable(SceneGradient g) => g.colors.length >= 2
      ? g
      : g.withStops([
          ...g.colors,
          for (var i = g.colors.length; i < 2; i++) own,
        ], null);

  List<Widget> _shape(SceneGradient g) => switch (g) {
    LinearPaint p => [
      _number(
        'Angle',
        linearAngle(p),
        _degrees,
        (v) => onChanged(
          withLinearAngle(p, v),
          label: 'Gradient angle',
          mergeKey: 'angle',
        ),
      ),
    ],
    RadialPaint p => [
      _centre(
        p.center,
        (c) => onChanged(
          p.copyWith(center: c),
          label: 'Gradient centre',
          mergeKey: 'centre',
        ),
      ),
      const Gap(FwSpacing.sm),
      _number(
        'Radius',
        p.radius,
        _radius,
        (v) => onChanged(
          p.copyWith(radius: v),
          label: 'Gradient radius',
          mergeKey: 'radius',
        ),
      ),
    ],
    SweepPaint p => [
      _centre(
        p.center,
        (c) => onChanged(
          p.copyWith(center: c),
          label: 'Gradient centre',
          mergeKey: 'centre',
        ),
      ),
      const Gap(FwSpacing.sm),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _number(
              'From',
              p.startAngle,
              _degrees,
              (v) => onChanged(
                p.copyWith(startAngle: v),
                label: 'Gradient start',
                mergeKey: 'from',
              ),
            ),
          ),
          const Gap(FwSpacing.md),
          Expanded(
            child: _number(
              'To',
              p.endAngle,
              _degrees,
              (v) => onChanged(
                p.copyWith(endAngle: v),
                label: 'Gradient end',
                mergeKey: 'to',
              ),
            ),
          ),
        ],
      ),
    ],
  };

  /// A point in the box as two percentages from its top-left — what a
  /// designer reads, where the model's -1..1 is what Flutter's `Alignment`
  /// reads.
  Widget _centre(SceneAlignment c, ValueChanged<SceneAlignment> apply) => Row(
    children: [
      Expanded(
        child: _number(
          'Centre X',
          (c.x + 1) * 50,
          _percent,
          (v) => apply(SceneAlignment(v / 50 - 1, c.y)),
        ),
      ),
      const Gap(FwSpacing.md),
      Expanded(
        child: _number(
          'Centre Y',
          (c.y + 1) * 50,
          _percent,
          (v) => apply(SceneAlignment(c.x, v / 50 - 1)),
        ),
      ),
    ],
  );

  Widget _number(
    String label,
    double value,
    SceneNumberShape shape,
    ValueChanged<double> apply,
  ) => SceneNumberField(
    label: label,
    value: value,
    shape: shape,
    onChanged: apply,
    onCommit: apply,
  );
}

// How a number is edited, decided from the property's metadata rather than by
// a switch on its name.
//
// Salvaged from the motion plugin's property editor, which is the one part of
// that panel that was always right: `ScenePropSpec` carries `unit`, `softMin`,
// `softMax` and `angular` precisely so the editor needs no table of special
// cases, and this is where that metadata decides something.
//
// A shape rather than free functions taking a spec, because not every number
// in a scene panel is a tuned property: a key's time is milliseconds, wants
// the same drag, and has no entry in the vocabulary. One type describes both.
import 'package:flutterware/scene_authoring.dart';

/// The control a number gets under it.
enum SceneEditorShape {
  /// Drag the number itself. The default, and right for anything whose useful
  /// range is open-ended — a `translateY` of 400 is unusual, not wrong.
  scrub,

  /// A slider as well, for values where the soft range *is* the meaning: an
  /// opacity of 0.5 is half, and where it sits between 0 and 1 is the whole of
  /// what you want to see.
  slider,

  /// A dial, for angles. A number of degrees answers "how far"; only a dial
  /// answers "which way", which is the question you actually have.
  dial,
}

/// A slider earns its place only when the range is small enough that a
/// position along it means something. `translateX` is soft-bounded to ±200,
/// where a nudge is more useful than a slider.
const _sliderRange = 2.0;

class SceneNumberShape {
  const SceneNumberShape({
    required this.perPixel,
    required this.decimals,
    this.unit = '',
    this.angular = false,
    this.softMin,
    this.softMax,
    this.min,
  });

  /// A duration in milliseconds: whole numbers, one per pixel, never negative.
  static const milliseconds = SceneNumberShape(
    perPixel: 1,
    decimals: 0,
    unit: 'ms',
    min: 0,
  );

  /// A plain geometry number — an x, a width, a corner radius.
  static const pixels = SceneNumberShape(perPixel: 1, decimals: 1, unit: 'px');

  /// The shape a scene property gets.
  ///
  /// The drag rate is scaled so a few hundred pixels cover the soft range,
  /// which makes the *same gesture* mean a sensible amount whether the
  /// property runs 0..1 or 0..64. Unbounded properties fall back to a unit a
  /// pixel, which is what a pixel-valued property should have meant anyway.
  factory SceneNumberShape.of(ScenePropSpec? spec) {
    if (spec == null) return const SceneNumberShape(perPixel: 1, decimals: 2);
    var (softMin, softMax) = (spec.softMin, spec.softMax);
    return SceneNumberShape(
      // Degrees per pixel: our angles are stored in degrees (the wire and the
      // file both spell them that way), so a pixel is half a degree.
      perPixel: spec.angular
          ? 0.5
          : (softMin == null || softMax == null
                ? 1
                : (softMax - softMin) / 300),
      // A tenth of a degree is a visible amount of rotation; a hundredth is
      // not a number anybody typed.
      decimals: spec.angular ? 1 : 2,
      unit: spec.unit ?? '',
      angular: spec.angular,
      softMin: softMin,
      softMax: softMax,
    );
  }

  /// How much one pixel of drag is worth, in the units the field displays.
  final double perPixel;

  final int decimals;

  /// Shown beside the number, never parsed.
  final String unit;

  /// Whether the number is an angle — which is what earns it a dial.
  final bool angular;

  final double? softMin;
  final double? softMax;

  /// A hard floor, where one exists. A duration below zero is not a duration —
  /// unlike a soft bound, which is a hint about where to start.
  final double? min;

  SceneEditorShape get editor {
    if (angular) return SceneEditorShape.dial;
    var (low, high) = (softMin, softMax);
    if (low == null || high == null) return SceneEditorShape.scrub;
    return high - low <= _sliderRange
        ? SceneEditorShape.slider
        : SceneEditorShape.scrub;
  }

  /// The number as the field prints it, without its unit.
  String format(double value) => value.toStringAsFixed(decimals);

  /// Where a slider or dial should stop.
  (double, double) get range => (softMin ?? 0, softMax ?? 1);

  /// [value], held to whatever floor this shape has.
  double clamped(double value) =>
      min == null ? value : (value < min! ? min! : value);
}

/// The shape for one property of one node.
SceneNumberShape shapeFor(SceneNode node, String prop) =>
    SceneNumberShape.of(propSpecFor(node, prop));

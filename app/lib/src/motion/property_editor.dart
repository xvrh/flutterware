/// How a number is edited, decided from the vocabulary rather than by a
/// `switch` on its name.
///
/// `MotionProp` has carried `unit`, `softMin`, `softMax` and `angular` since the
/// vocabulary was written — "what the panel needs to know about a property
/// without a switch on its name" is its own doc comment. This is where that
/// metadata decides something.
///
/// It is a *shape* rather than a bag of free functions taking `MotionProp?`
/// because not every number in the panel is a tuned property: a span's start
/// and duration are milliseconds, want the same drag, and have no entry in a
/// vocabulary of animatable properties. One type describes both.
library;

import 'dart:math' as math;

import 'package:flutterware/motion_vocabulary.dart';

/// The control a number gets under it.
enum MotionEditorShape {
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

/// A slider earns its place only when the range is small enough that a position
/// along it means something. `translateX` is soft-bounded to ±200, where a
/// nudge is more useful than a slider.
const _sliderRange = 2.0;

class MotionNumberShape {
  const MotionNumberShape({
    required this.perPixel,
    required this.decimals,
    this.unit = '',
    this.angular = false,
    this.softMin,
    this.softMax,
    this.min,
  });

  /// A duration in milliseconds: whole numbers, one per pixel, never negative.
  static const milliseconds = MotionNumberShape(
    perPixel: 1,
    decimals: 0,
    unit: 'ms',
    min: 0,
  );

  /// The shape a tuned property gets.
  ///
  /// The drag rate is scaled so a few hundred pixels cover the soft range,
  /// which makes the *same gesture* mean a sensible amount whether the property
  /// runs 0..1 or 0..64. Unbounded properties fall back to a unit a pixel,
  /// which is what a pixel-valued property should have meant all along.
  factory MotionNumberShape.of(MotionProp? prop) {
    if (prop == null) {
      return const MotionNumberShape(perPixel: 1, decimals: 2);
    }
    var (softMin, softMax) = (prop.softMin, prop.softMax);
    return MotionNumberShape(
      // Degrees per pixel, not radians: a pixel worth of radians would be a
      // third of a turn.
      perPixel: prop.angular
          ? 0.5
          : (softMin == null || softMax == null
                ? 1
                : (softMax - softMin) / 300),
      // A tenth of a degree is a visible amount of rotation; a hundredth is not
      // a number anybody typed.
      decimals: prop.angular ? 1 : 2,
      unit: prop.unit ?? '',
      angular: prop.angular,
      softMin: softMin,
      softMax: softMax,
    );
  }

  /// How much one pixel of drag is worth, in the units the field displays.
  final double perPixel;

  final int decimals;

  /// Shown beside the number, never parsed.
  final String unit;

  /// Stored in radians, shown in degrees. `Transform.rotate` is where these are
  /// read, so storing anything else would make every hand-written value wrong.
  final bool angular;

  final double? softMin;
  final double? softMax;

  /// A hard floor, where one exists. A duration below zero is not a duration —
  /// unlike a soft bound, which is a hint about where to start.
  final double? min;

  MotionEditorShape get editor {
    if (angular) return MotionEditorShape.dial;
    var (low, high) = (softMin, softMax);
    if (low == null || high == null) return MotionEditorShape.scrub;
    return high - low <= _sliderRange
        ? MotionEditorShape.slider
        : MotionEditorShape.scrub;
  }

  double toDisplay(double stored) => angular ? stored * 180 / math.pi : stored;

  double fromDisplay(double shown) => angular ? shown * math.pi / 180 : shown;

  /// The number as the field prints it, without its unit.
  String format(double stored) => toDisplay(stored).toStringAsFixed(decimals);

  /// Where a slider or dial should stop, in display units.
  (double, double) get displayRange =>
      (toDisplay(softMin ?? 0), toDisplay(softMax ?? 1));

  /// [stored], held to whatever floor this shape has.
  double clampStored(double stored) =>
      min == null ? stored : math.max(min!, stored);
}

MotionProp? propFor(String property) => motionVocabularyByName[property];

MotionNumberShape shapeFor(String property) =>
    MotionNumberShape.of(propFor(property));

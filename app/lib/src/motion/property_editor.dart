/// How a property is edited, decided from the vocabulary rather than by a
/// `switch` on its name.
///
/// `MotionProp` has carried `unit`, `softMin`, `softMax` and `angular` since the
/// vocabulary was written — "what the panel needs to know about a property
/// without a switch on its name" is its own doc comment — and the panel then
/// spent its first two rounds putting every one of them in the same plain text
/// field. This is where that metadata finally decides something.
library;

import 'dart:math' as math;

import 'package:flutterware/motion_vocabulary.dart';

/// The control a property gets under its number.
enum MotionEditorShape {
  /// Drag the number itself. The default, and right for anything whose useful
  /// range is open-ended — a `translateY` of 400 is unusual, not wrong.
  scrub,

  /// A slider as well, for properties where the soft range *is* the meaning:
  /// an opacity of 0.5 is half, and where it sits between 0 and 1 is the whole
  /// of what you want to see.
  slider,

  /// A dial, for angles. A number of degrees answers "how far"; only a dial
  /// answers "which way", which is the question you actually have.
  dial,
}

/// A slider earns its place only when the range is small enough that a position
/// along it means something. `translateX` is soft-bounded to ±200 and a slider
/// there would say nothing a nudge does not say better.
const _sliderRange = 2.0;

MotionEditorShape editorShapeFor(MotionProp? prop) {
  if (prop == null) return MotionEditorShape.scrub;
  if (prop.angular) return MotionEditorShape.dial;
  var (min, max) = (prop.softMin, prop.softMax);
  if (min == null || max == null) return MotionEditorShape.scrub;
  return max - min <= _sliderRange
      ? MotionEditorShape.slider
      : MotionEditorShape.scrub;
}

/// How much one pixel of drag is worth, in the units the field displays.
///
/// Scaled so a drag across a few hundred pixels covers the soft range, which
/// makes the *same gesture* mean a sensible amount whether the property runs
/// 0..1 or 0..64. Unbounded properties fall back to a unit a pixel, which is
/// what a pixel-valued property should have meant all along.
double scrubPerPixel(MotionProp? prop) {
  if (prop == null) return 1;
  if (prop.angular) return 0.5;
  var (min, max) = (prop.softMin, prop.softMax);
  if (min == null || max == null) return 1;
  return (max - min) / 300;
}

/// The number the field shows, from the number the file stores.
///
/// Angles are stored in radians — `Transform.rotate` is where they are read, so
/// anything else would make every hand-written value wrong — and shown in
/// degrees, because nobody says "0.35 radians".
double toDisplay(MotionProp? prop, double stored) =>
    prop?.angular == true ? stored * 180 / math.pi : stored;

double fromDisplay(MotionProp? prop, double shown) =>
    prop?.angular == true ? shown * math.pi / 180 : shown;

/// Where a slider or dial should stop, in display units.
(double, double) displayRange(MotionProp? prop) {
  var min = prop?.softMin ?? 0;
  var max = prop?.softMax ?? 1;
  return (toDisplay(prop, min), toDisplay(prop, max));
}

/// The number as the field prints it, without its unit.
///
/// Degrees to one place and everything else to two: a tenth of a degree is a
/// visible amount of rotation, and a hundredth is not a number anybody typed.
String formatDisplay(MotionProp? prop, double stored) {
  var shown = toDisplay(prop, stored);
  return shown.toStringAsFixed(prop?.angular == true ? 1 : 2);
}

/// What goes after the number, or empty.
String unitOf(MotionProp? prop) => prop?.unit ?? '';

MotionProp? propFor(String property) => motionVocabularyByName[property];

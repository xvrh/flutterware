/// A tuned value is a number or a colour. Nothing else.
///
/// This is the decision that keeps the vocabulary cheap: the panel needs
/// exactly two value editors, so adding a property costs a getter, a default
/// and a line of documentation, and costs the editor nothing at all.
enum MotionValueKind { number, color }

/// What the panel needs to know about a property without a `switch` on its
/// name — its editor, its resting value, what to call its unit, and where a
/// slider should start and stop.
class MotionProp {
  final String name;
  final MotionValueKind kind;

  /// The value a read returns when nothing is tuned, or null when the property
  /// has no resting value and its getter is therefore nullable.
  final double? identity;

  /// Shown beside the number, never parsed.
  final String? unit;

  /// Where a slider should sit. A hint, not a clamp — a scale of 40 is
  /// legitimate, it just is not what the drag should make easy.
  final double? softMin;
  final double? softMax;

  /// Stored in radians, shown in degrees. Storing turns would match
  /// `RotationTransition` and make every hand-written value wrong by 2π
  /// against `Transform.rotate`, which is where these are actually read.
  final bool angular;

  const MotionProp(
    this.name,
    this.kind, {
    this.identity,
    this.unit,
    this.softMin,
    this.softMax,
    this.angular = false,
  });

  /// Whether the getter for this property returns null when nothing is tuned.
  bool get isNullable => identity == null;
}

/// The closed set, v1.
///
/// Closed because the panel has to know each one's editor, and because the
/// generated file is only legible if its property names mean one thing. The
/// escape hatch for everything not here is [MotionProp] `progress` — a tuned
/// number with no semantics that you apply yourself — which is what makes a
/// closed vocabulary survivable rather than a cage.
const motionVocabulary = <MotionProp>[
  // Identity-having: non-null getters.
  MotionProp(
    'opacity',
    MotionValueKind.number,
    identity: 1,
    softMin: 0,
    softMax: 1,
  ),
  MotionProp(
    'translateX',
    MotionValueKind.number,
    identity: 0,
    unit: 'px',
    softMin: -200,
    softMax: 200,
  ),
  MotionProp(
    'translateY',
    MotionValueKind.number,
    identity: 0,
    unit: 'px',
    softMin: -200,
    softMax: 200,
  ),
  MotionProp(
    'scale',
    MotionValueKind.number,
    identity: 1,
    unit: '×',
    softMin: 0,
    softMax: 2,
  ),
  MotionProp(
    'scaleX',
    MotionValueKind.number,
    identity: 1,
    unit: '×',
    softMin: 0,
    softMax: 2,
  ),
  MotionProp(
    'scaleY',
    MotionValueKind.number,
    identity: 1,
    unit: '×',
    softMin: 0,
    softMax: 2,
  ),
  MotionProp(
    'rotate',
    MotionValueKind.number,
    identity: 0,
    unit: '°',
    softMin: -6.2832,
    softMax: 6.2832,
    angular: true,
  ),
  MotionProp(
    'blur',
    MotionValueKind.number,
    identity: 0,
    unit: 'σ',
    softMin: 0,
    softMax: 40,
  ),
  MotionProp(
    'elevation',
    MotionValueKind.number,
    identity: 0,
    unit: 'dp',
    softMin: 0,
    softMax: 24,
  ),
  MotionProp(
    'padding',
    MotionValueKind.number,
    identity: 0,
    unit: 'px',
    softMin: 0,
    softMax: 64,
  ),
  MotionProp(
    'progress',
    MotionValueKind.number,
    identity: 0,
    softMin: 0,
    softMax: 1,
  ),

  // No resting value: nullable getters, and the `??` at the read site is where
  // the un-animated value is stated.
  MotionProp('color', MotionValueKind.color),
  MotionProp(
    'width',
    MotionValueKind.number,
    unit: 'px',
    softMin: 0,
    softMax: 600,
  ),
  MotionProp(
    'height',
    MotionValueKind.number,
    unit: 'px',
    softMin: 0,
    softMax: 600,
  ),
  MotionProp(
    'borderRadius',
    MotionValueKind.number,
    unit: 'px',
    softMin: 0,
    softMax: 64,
  ),
  MotionProp(
    'fontSize',
    MotionValueKind.number,
    unit: 'px',
    softMin: 8,
    softMax: 96,
  ),
];

/// The vocabulary by name, for the panel and for validating a file.
final motionVocabularyByName = {
  for (var property in motionVocabulary) property.name: property,
};

/// What `MotionBox` applies, and **this list is frozen**.
///
/// Growing [motionVocabulary] later must not silently change what code already
/// written does. Anything outside this set stays a read at the call site, which
/// is the clearest signal that it is doing something structural.
const motionBoxProps = <String>[
  'opacity',
  'translateX',
  'translateY',
  'scale',
  'scaleX',
  'scaleY',
  'rotate',
  'blur',
];

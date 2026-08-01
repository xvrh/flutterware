import 'package:flutterware/motion_vocabulary.dart';

import 'values_file.dart';

/// What `+` puts on an empty lane.
///
/// **An editor decision, not a runtime one**, which is why it lives here and not
/// in the published vocabulary. `MotionProp` says what a property *is* — its
/// kind, its resting value, where a slider should sit. What a newly created span
/// should open at is a matter of taste about authoring, and a runtime that
/// carried it would be shipping an opinion to every app that only the panel has
/// any use for.
///
/// The shape is **from an offset, to the resting value**: `opacity` 0→1,
/// `translateY` 24→0, `scale` 0.92→1. An entrance is the common case, and
/// landing on the identity means the screen looks *correct* at `t = 1` the
/// moment you create one — a default that left the end wrong would have you
/// fixing two numbers before you could judge the first.
///
/// Properties whose identity is the resting *absence* of the effect —
/// `elevation`, `padding` — invert it and arrive instead, because a span from 8
/// to 0 on a shadow is a thing that disappears.
const _debuts = <String, (double, double)>{
  'opacity': (0, 1),
  'translateX': (24, 0),
  'translateY': (24, 0),
  'scale': (0.92, 1),
  'scaleX': (0.92, 1),
  'scaleY': (0.92, 1),
  'rotate': (-0.35, 0),
  'blur': (8, 0),
  'progress': (0, 1),

  // Nothing to return to: these arrive rather than settle.
  'elevation': (0, 8),
  'padding': (0, 16),

  // No resting value at all, so every one of these is the editor inventing a
  // number. Chosen to be *visibly wrong rather than invisibly wrong* — you can
  // see what you are dragging, which is more useful than a span that does
  // nothing and looks broken.
  'width': (0, 200),
  'height': (0, 200),
  'borderRadius': (24, 8),
  'fontSize': (16, 24),
};

/// The colour a new colour span opens at, both ends.
///
/// A flat span, and the honest reason is that we cannot do better: a colour has
/// no identity, so nothing here knows what the widget is currently painted —
/// the guest can only report a value for a property something already tunes.
/// Opening flat says "you set both ends" rather than guessing a ramp.
const _newColor = MotionColor(0xFFBFC6C4);

/// How long a new span runs when the motion has no duration yet.
const _debutMs = 400;

/// The span `+` creates for [property], or null when it names nothing.
MotionSpan? newSpanFor(String property, {int? durationMs}) {
  var prop = motionVocabularyByName[property];
  if (prop == null) return null;
  var end = durationMs == null || durationMs <= 0 ? _debutMs : durationMs;

  if (prop.kind == MotionValueKind.color) {
    return MotionSpan(
      startMs: 0,
      endMs: end,
      from: _newColor,
      to: _newColor,
      curve: 'easeOutCubic',
    );
  }

  var (from, to) =
      _debuts[property] ?? (prop.identity ?? 0, prop.identity ?? 1);
  return MotionSpan(
    startMs: 0,
    endMs: end,
    from: MotionNumber(from),
    to: MotionNumber(to),
    // Named rather than left to the default: `Curves.linear` is what a motion
    // looks like when nobody has chosen, and the point of `+` is to give you
    // something worth judging.
    curve: 'easeOutCubic',
  );
}

/// [targets] with [property] added under [target], creating the target if it is
/// not there yet.
///
/// Appends rather than sorts: the file's order is the order somebody arranged,
/// and a `+` that reshuffled the whole file to insert one line would make every
/// edit unreviewable.
List<MotionTargetValues> withNewProperty(
  List<MotionTargetValues> targets,
  String target,
  String property,
  MotionSpan span,
) {
  var found = false;
  var next = [
    for (var existing in targets)
      if (existing.name != target)
        existing
      else
        () {
          found = true;
          return MotionTargetValues(
            name: existing.name,
            comments: existing.comments,
            blankBefore: existing.blankBefore,
            properties: [
              ...existing.properties.where((p) => p.name != property),
              MotionPropertyValues(name: property, spans: [span]),
            ],
          );
        }(),
  ];
  if (found) return next;
  return [
    ...next,
    MotionTargetValues(
      name: target,
      blankBefore: next.isNotEmpty,
      properties: [
        MotionPropertyValues(name: property, spans: [span]),
      ],
    ),
  ];
}

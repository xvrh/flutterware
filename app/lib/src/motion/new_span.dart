import 'dart:math' as math;

import 'package:flutterware/motion_vocabulary.dart';

import 'values_file.dart';

/// What `+` puts on an empty lane.
///
/// An editor decision, not a runtime one, which is why it lives here and not
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
/// A flat span, because nothing better is available: a colour has no identity,
/// so nothing here knows what the widget is currently painted —
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

/// The span inserted when a lane that is already tuned gets another one.
///
/// It starts at the playhead and its `from` is what the property is worth
/// there, which is the whole reason to insert at the playhead rather than at
/// the end: nothing on screen jumps when the span appears, so what you judge
/// afterwards is the change you asked for rather than a discontinuity you did
/// not. It runs to whatever comes next — the following span's start, or the end
/// of the motion — because a span you have to trim before you can judge it is
/// one drag of nothing.
///
/// Null when there is no room: the playhead is at or past the end, it is inside
/// a span already, or the gap it landed in has closed.
///
/// The inside-a-span case is refused *here* as well as by the panel, which
/// wants to say which span. Overlapping spans are something `evaluateSegments`
/// explicitly does not resolve, so being unable to produce one is worth
/// checking twice rather than leaving to whoever calls next.
MotionSpan? spanAt({
  required String property,
  required int atMs,
  required int durationMs,
  required List<(int, int)> existing,
  MotionLiteral? current,
}) {
  if (atMs >= durationMs) return null;
  if (existing.any((span) => atMs >= span.$1 && atMs < span.$2)) return null;
  var next = existing
      .map((span) => span.$1)
      .where((start) => start > atMs)
      .fold<int?>(
        null,
        (best, start) => best == null ? start : math.min(best, start),
      );
  var end = math.min(next ?? durationMs, durationMs);
  if (end <= atMs) return null;

  var debut = newSpanFor(property, durationMs: durationMs);
  if (debut == null) return null;

  return MotionSpan(
    startMs: atMs,
    endMs: end,
    from: current ?? debut.from,
    to: current == null ? debut.to : _awayFrom(current, debut),
    curve: 'easeOutCubic',
  );
}

/// Where `+` actually puts a span on a lane that already has one.
///
/// Prefers the playhead, because that is where you are looking and the span
/// can open at the value the property already has there. Falls back to the
/// widest stretch of free time when the playhead will not do — and that is not
/// an edge case: a motion that has just finished playing leaves the playhead at
/// the very end, where by definition nothing fits, so a `+` that only ever
/// tried the playhead refused most of the times anybody pressed it.
///
/// The fallback does not claim continuity. Away from the playhead nothing here
/// knows what the property is worth, so the span opens at the debut's own value
/// rather than at a number borrowed from a different instant.
MotionSpan? spanFor({
  required String property,
  required int atMs,
  required int durationMs,
  required List<(int, int)> existing,
  MotionLiteral? current,
}) {
  var atPlayhead = spanAt(
    property: property,
    atMs: atMs,
    durationMs: durationMs,
    existing: existing,
    current: current,
  );
  if (atPlayhead != null) return atPlayhead;

  var gap = widestGap(existing, durationMs);
  if (gap == null) return null;
  return spanAt(
    property: property,
    atMs: gap,
    durationMs: durationMs,
    existing: existing,
  );
}

/// The start of the widest stretch of time no span covers, or null when the
/// lane is covered end to end.
///
/// Sorted and swept rather than trusting the order: the spans come from a file
/// that may have been hand-edited, and an unsorted list would report a gap that
/// is really an overlap.
int? widestGap(List<(int, int)> existing, int durationMs) {
  var sorted = [...existing]..sort((a, b) => a.$1.compareTo(b.$1));
  int? best;
  var widest = 0;
  var cursor = 0;
  for (var (start, end) in sorted) {
    if (start - cursor > widest) {
      widest = start - cursor;
      best = cursor;
    }
    if (end > cursor) cursor = end;
  }
  if (durationMs - cursor > widest) {
    widest = durationMs - cursor;
    best = cursor;
  }
  return widest > 0 ? best : null;
}

/// Whichever end of the debut is further from where the property already is.
///
/// A second span that opens at the current value and closes at the resting one
/// is a span that does nothing whenever the property is already at rest — which
/// is most of the time, since the first span usually lands there. Picking the
/// far end means an inserted span is always visible, and visible is the only
/// thing that makes it worth judging.
MotionLiteral _awayFrom(MotionLiteral current, MotionSpan debut) {
  if (current is! MotionNumber) return debut.to;
  var from = debut.from;
  var to = debut.to;
  if (from is! MotionNumber || to is! MotionNumber) return debut.to;
  return (from.value - current.value).abs() >= (to.value - current.value).abs()
      ? from
      : to;
}

/// [targets] with [span] inserted into [property], in start order.
///
/// The order is not cosmetic. `evaluateSegments` reads `first` and `last`
/// for its before-the-start and after-the-end rules, so a span appended out of
/// order would make the property hold the wrong value at both ends of the
/// motion — a bug visible only outside the spans, which is exactly where nobody
/// looks.
List<MotionTargetValues> withSpanAdded(
  List<MotionTargetValues> targets,
  String target,
  String property,
  MotionSpan span,
) => [
  for (var existing in targets)
    if (existing.name != target)
      existing
    else
      MotionTargetValues(
        name: existing.name,
        comments: existing.comments,
        blankBefore: existing.blankBefore,
        properties: [
          for (var candidate in existing.properties)
            if (candidate.name != property)
              candidate
            else
              MotionPropertyValues(
                name: candidate.name,
                comments: candidate.comments,
                blankBefore: candidate.blankBefore,
                spans: [...candidate.spans, span]
                  ..sort((a, b) => a.startMs.compareTo(b.startMs)),
              ),
        ],
      ),
];

/// [targets] with one span removed — and the property with it when that was its
/// last, and the target too when that was its last property.
///
/// A property with no spans is not a thing the file can spell, and a lane that
/// lingered empty would read as tuned-and-broken rather than as untuned. The
/// state it should fall back to is the one the code already puts it in.
List<MotionTargetValues> withSpanRemoved(
  List<MotionTargetValues> targets,
  String target,
  String property,
  int index,
) => [
  for (var existing in targets)
    if (existing.name != target)
      existing
    else
      () {
        var properties = [
          for (var candidate in existing.properties)
            if (candidate.name != property)
              candidate
            else
              MotionPropertyValues(
                name: candidate.name,
                comments: candidate.comments,
                blankBefore: candidate.blankBefore,
                spans: [
                  for (var (at, span) in candidate.spans.indexed)
                    if (at != index) span,
                ],
              ),
        ]..removeWhere((candidate) => candidate.spans.isEmpty);
        return MotionTargetValues(
          name: existing.name,
          comments: existing.comments,
          blankBefore: existing.blankBefore,
          properties: properties,
        );
      }(),
]..removeWhere((existing) => existing.properties.isEmpty);

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

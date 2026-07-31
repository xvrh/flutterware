import 'package:flutter/animation.dart';

/// One tweened span of one property.
///
/// [from] and [to] are a `double` or a `Color` and nothing else. Everything
/// richer — an `Offset`, a `Matrix4`, a `TextStyle` — is assembled at read time
/// from several of these, which is what keeps the editor down to two value
/// editors however large the vocabulary grows.
class Seg<T> {
  final Duration start;
  final Duration end;
  final T from;
  final T to;
  final Curve curve;

  const Seg({
    required this.start,
    required this.end,
    required this.from,
    required this.to,
    this.curve = Curves.linear,
  });

  Duration get length => end - start;
}

/// Everything the editor tuned, and nothing else.
///
/// Structure — which targets exist, which properties they have — comes from the
/// code that reads them. This carries only the numbers, which is why it can be
/// a whole-file rewrite by a tool without ever touching what somebody wrote.
///
/// Keyed target → property → segments. A list per property because several
/// spans of one property *is* the keyframe case.
class MotionValues {
  /// Null means "as long as the last segment ends", which is almost always
  /// what you want and cannot be written by a `const` constructor — hence
  /// [resolveDuration] rather than a computed field.
  final Duration? duration;

  final Map<String, Map<String, List<Seg<Object?>>>> targets;

  const MotionValues({this.duration, required this.targets});

  static const empty = MotionValues(targets: {});

  /// The declared duration, or the end of the last segment.
  Duration resolveDuration() {
    var declared = duration;
    if (declared != null) return declared;
    var end = Duration.zero;
    for (var properties in targets.values) {
      for (var segments in properties.values) {
        for (var segment in segments) {
          if (segment.end > end) end = segment.end;
        }
      }
    }
    return end;
  }

  List<Seg<Object?>>? segmentsFor(String target, String property) =>
      targets[target]?[property];
}

/// What [segments] is worth at [at].
///
/// Two rules, stated here because they are the whole semantics and are
/// otherwise the sort of thing every reader re-derives differently:
///
/// - **Hold.** Before the first segment a property is that segment's `from`;
///   after the last it is that segment's `to`. So `t = 0` is well defined even
///   for a property whose first span starts at 100ms.
/// - **Gaps.** Between two segments a property holds the earlier one's `to`.
///
/// Overlapping spans on one property are not resolved here — they are an error
/// the editor cannot produce and [findOverlap] reports.
Object? evaluateSegments(List<Seg<Object?>> segments, Duration at) {
  if (segments.isEmpty) return null;

  var first = segments.first;
  var last = segments.last;
  // After before before, deliberately. The two rules only ever both apply to a
  // zero-length span — a step keyframe — and there the useful answer is that
  // the new value takes effect at its own instant, not one microsecond later.
  if (at >= last.end) return last.to;
  if (at <= first.start) return first.from;

  Seg<Object?>? previous;
  for (var segment in segments) {
    if (at >= segment.start && at <= segment.end) {
      var span = segment.end.inMicroseconds - segment.start.inMicroseconds;
      if (span <= 0) return segment.to;
      var u = (at.inMicroseconds - segment.start.inMicroseconds) / span;
      return lerpMotionValue(
        segment.from,
        segment.to,
        segment.curve.transform(u),
      );
    }
    if (segment.end < at) previous = segment;
  }
  return previous?.to ?? first.from;
}

/// The only two types a segment may carry.
///
/// Deliberately not extensible: a third case here would be a third editor in
/// the panel, and the composed-read rule exists so that never has to happen.
Object? lerpMotionValue(Object? a, Object? b, double u) {
  if (a is double && b is double) return a + (b - a) * u;
  if (a is Color && b is Color) return Color.lerp(a, b, u);
  throw ArgumentError(
    'A motion segment carries a double or a Color, not ${a.runtimeType}. '
    'Richer values are composed at the read site from several segments.',
  );
}

/// The first pair of segments on one property whose spans intersect, or null.
///
/// Returned rather than thrown so a bad file shows one loud diagnostic in the
/// panel instead of taking the whole guest down.
(Seg<Object?>, Seg<Object?>)? findOverlap(List<Seg<Object?>> segments) {
  var sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].start < sorted[i - 1].end) return (sorted[i - 1], sorted[i]);
  }
  return null;
}

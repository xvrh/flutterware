/// Where a clip's frames sit on the playhead.
///
/// Here rather than beside the encoder because it is a fact about the
/// **motion** rather than about the file: it answers "how many moments is this
/// at `fps`", and the harness that renders them and the app that encodes them
/// have to agree. Two copies of this arithmetic are two clips of different
/// lengths from one motion.
library;

/// The playhead positions a motion of [durationMs] should be rendered at to
/// play back at [fps].
///
/// Both ends included, like a filmstrip's stops and for the same reason: the
/// first frame is what the motion starts from and the last is where it lands,
/// and a video missing either does not show the motion. That makes the clip
/// one frame longer than `duration × fps` — 31 frames for a second at 30fps —
/// which is the correct length for a motion that is played once rather than
/// looped.
List<double> videoStops({required int durationMs, required int fps}) {
  var count = (durationMs * fps / 1000).round() + 1;
  if (count < 2) return const [0, 1];
  return [for (var i = 0; i < count; i++) i / (count - 1)];
}

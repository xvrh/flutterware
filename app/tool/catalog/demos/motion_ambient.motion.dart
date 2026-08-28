import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// A loop, which the law says is outside the scope and the runtime plays
/// anyway — `MotionController.repeat()`.
///
/// Every lane here is written twice, out and back, because a `Seg` carries
/// `from` and `to` and a round trip is two of them. And **nothing checks that
/// the last value equals the first**: the seam is a convention held by hand in
/// six places. Change `1.0` to `1.02` in any `to:` below and the loop ticks
/// once a cycle forever, silently.
const ambientMotion = MotionValues(
  duration: Duration(milliseconds: 1800),
  targets: {
    // The breath. Out for 900ms, back for 900ms, and the two must agree.
    'dot': {
      'scale': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 900),
          from: 1,
          to: 1.18,
          curve: Curves.easeInOut,
        ),
        Seg<double>(
          start: Duration(milliseconds: 900),
          end: Duration(milliseconds: 1800),
          from: 1.18,
          to: 1,
          curve: Curves.easeInOut,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 900),
          from: 1,
          to: 0.72,
          curve: Curves.easeInOut,
        ),
        Seg<double>(
          start: Duration(milliseconds: 900),
          end: Duration(milliseconds: 1800),
          from: 0.72,
          to: 1,
          curve: Curves.easeInOut,
        ),
      ],
    },

    // The ping. This one does NOT return — it restarts, which is a different
    // kind of seam and the only one that happens to be forgiving.
    'ring': {
      'scale': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 1800),
          from: 0.9,
          to: 2.6,
          curve: Curves.easeOutCubic,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 1400),
          from: 0.45,
          to: 0,
          curve: Curves.easeOut,
        ),
      ],
    },

    'label': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 900),
          from: 0.55,
          to: 0.9,
          curve: Curves.easeInOut,
        ),
        Seg<double>(
          start: Duration(milliseconds: 900),
          end: Duration(milliseconds: 1800),
          from: 0.9,
          to: 0.55,
          curve: Curves.easeInOut,
        ),
      ],
    },
  },
);

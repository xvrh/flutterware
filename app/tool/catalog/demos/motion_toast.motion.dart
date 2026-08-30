import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// Enter, hold, exit — on one playhead, which works, and shows what it costs.
///
/// The middle 1580ms is a hold: nothing moves, no lane says anything, and the
/// only reason the toast stays up that long is that the two moving segments are
/// far apart. **The dwell is not a value anywhere.** To keep it up for three
/// seconds instead of two you retime the exit, the duration, and every lane
/// that touches the exit — six numbers to change one intention.
const toastMotion = MotionValues(
  duration: Duration(milliseconds: 2400),
  targets: {
    'toast': {
      'translateY': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 340),
          from: 72,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
        Seg<double>(
          start: Duration(milliseconds: 1920),
          end: Duration(milliseconds: 2400),
          from: 0,
          to: 72,
          curve: Curves.easeInCubic,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 240),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
        Seg<double>(
          start: Duration(milliseconds: 1920),
          end: Duration(milliseconds: 2280),
          from: 1,
          to: 0,
          curve: Curves.easeIn,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 420),
          from: 0.94,
          to: 1,
          curve: Curves.easeOutBack,
        ),
        Seg<double>(
          start: Duration(milliseconds: 1920),
          end: Duration(milliseconds: 2400),
          from: 1,
          to: 0.97,
          curve: Curves.easeIn,
        ),
      ],
    },

    'tick': {
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 160),
          end: Duration(milliseconds: 520),
          from: 0,
          to: 1,
          curve: Curves.easeOutBack,
        ),
      ],
    },

    // The dwell, made visible: a bar that drains while nothing else moves.
    // The only lane in the file that says anything about how long it stays.
    'meter': {
      'progress': [
        Seg<double>(
          start: Duration(milliseconds: 420),
          end: Duration(milliseconds: 1920),
          from: 1,
          to: 0,
          curve: Curves.linear,
        ),
      ],
    },
  },
);

import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// Tuned by the Motion editor. A source of truth, not a derivative — do not
/// regenerate, do not delete.
const checkoutMotion = MotionValues(
  duration: Duration(milliseconds: 600),
  targets: {
    'first': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 320),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 420),
          from: 16,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
  },
);

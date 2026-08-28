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

    'cta': {
      'borderRadius': [
        Seg<double>(
          start: Duration(milliseconds: 261),
          end: Duration(milliseconds: 495),
          from: 24,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    'card': {
      'borderRadius': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 600),
          from: 0,
          to: 19.53283132530111,
          curve: Curves.easeOutCubic,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 600),
          from: 0,
          to: 30,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
  },
);

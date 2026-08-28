import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// The fuse's own timeline, in its own file.
///
/// This is the nesting claim made literal: a fuse is a component with two
/// string props and a timeline of its own, edited and reused without knowing
/// which page it lands on. The page maps a slice of its own progress onto this.
///
/// `easeOutExpo` on the halves is the "infinite slowdown" — asymptotic inside a
/// fixed duration. The perpetual version is an idle state, which the model does
/// not have yet.
const fuseMotion = MotionValues(
  duration: Duration(milliseconds: 900),
  targets: {
    'left': {
      'translateX': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 900),
          from: -120,
          to: 0,
          curve: Curves.easeOutExpo,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 420),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
    },

    'right': {
      'translateX': [
        Seg<double>(
          start: Duration(milliseconds: 60),
          end: Duration(milliseconds: 900),
          from: 120,
          to: 0,
          curve: Curves.easeOutExpo,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 60),
          end: Duration(milliseconds: 480),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
    },

    // The shadow layers are elements, not a text property. That is what makes
    // them animatable at all — each is a copy of the string with its own
    // offset, blur and opacity.
    'glowA': {
      'translateY': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 900),
          from: 0,
          to: 7,
          curve: Curves.easeOutCubic,
        ),
      ],
      'blur': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 900),
          from: 26,
          to: 11,
          curve: Curves.easeOutCubic,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 120),
          end: Duration(milliseconds: 760),
          from: 0,
          to: 0.85,
          curve: Curves.easeOut,
        ),
      ],
    },

    'glowB': {
      'translateX': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 900),
          from: 0,
          to: -5,
          curve: Curves.easeOutCubic,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 900),
          from: 0,
          to: -4,
          curve: Curves.easeOutCubic,
        ),
      ],
      'blur': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 900),
          from: 34,
          to: 16,
          curve: Curves.easeOutCubic,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 160),
          end: Duration(milliseconds: 820),
          from: 0,
          to: 0.55,
          curve: Curves.easeOut,
        ),
      ],
    },
  },
);

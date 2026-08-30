import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// One page's presentation timeline.
///
/// FAKE (parametric parameters): the wave needs three numbers — phase,
/// amplitude, frequency — and the vocabulary gives each target exactly one
/// unnamed number, `progress`. So one shape is spelled here as two targets
/// whose names mean nothing to the model, and the third parameter is a
/// constant in code because there is no third target worth inventing.
const onboardingPageMotion = MotionValues(
  duration: Duration(milliseconds: 1100),
  targets: {
    // Phase, in radians. Animating this alone makes the split line travel.
    'wave': {
      'progress': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 1100),
          from: 0,
          to: 6.2832,
          curve: Curves.easeInOutSine,
        ),
      ],
    },

    // Amplitude, as a fraction of the image height. A number the editor would
    // show as `0.09` with no unit, when the author means "9% of the height".
    'waveDepth': {
      'progress': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 1100),
          from: 0.035,
          to: 0.085,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    'image': {
      'scale': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 1100),
          from: 1.12,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 380),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
    },

    'subtitle': {
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 260),
          end: Duration(milliseconds: 900),
          from: 20,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 260),
          end: Duration(milliseconds: 760),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
    },

    'action': {
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 380),
          end: Duration(milliseconds: 1040),
          from: 28,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 380),
          end: Duration(milliseconds: 1040),
          from: 0.94,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 380),
          end: Duration(milliseconds: 820),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
    },
  },
);

import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// The fuse's own timeline, in its own file.
///
/// **A pass, not an entrance.** The two lines travel in opposite directions on
/// different rows, cross, decelerate into a settled reading moment in the
/// middle of the timeline, hold, and then continue the way they were already
/// going and re-accelerate off the page. `t = 0.5` is the picture; the two ends
/// are off-screen.
///
/// That shape is why the timeline is symmetric rather than a 0→1 entrance, and
/// why the host hands it a **signed** position — where a page is relative to
/// the viewport — instead of how far through an entrance it is.
///
/// `easeOutExpo` in and `easeInExpo` out is the "infinite slowdown": asymptotic
/// into the settle inside a fixed duration. The perpetual version is an idle
/// state, which the model does not have yet.
///
/// FAKE (units): 460 is "far enough off a phone" in raw pixels. On a tablet it
/// is not off-screen at all, which is why the fades at both ends are load
/// bearing rather than decorative. A travel of `120%w` would need no fade.
const fuseMotion = MotionValues(
  duration: Duration(milliseconds: 1000),
  targets: {
    'left': {
      'translateX': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 440),
          from: -460,
          to: 0,
          curve: Curves.easeOutExpo,
        ),
        Seg<double>(
          start: Duration(milliseconds: 560),
          end: Duration(milliseconds: 1000),
          from: 0,
          to: 460,
          curve: Curves.easeInExpo,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 190),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
        Seg<double>(
          start: Duration(milliseconds: 810),
          end: Duration(milliseconds: 1000),
          from: 1,
          to: 0,
          curve: Curves.easeIn,
        ),
      ],
    },

    // The same journey, mirrored. They are on different rows, so the paths
    // cross rather than collide.
    'right': {
      'translateX': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 440),
          from: 460,
          to: 0,
          curve: Curves.easeOutExpo,
        ),
        Seg<double>(
          start: Duration(milliseconds: 560),
          end: Duration(milliseconds: 1000),
          from: 0,
          to: -460,
          curve: Curves.easeInExpo,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 40),
          end: Duration(milliseconds: 230),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
        Seg<double>(
          start: Duration(milliseconds: 810),
          end: Duration(milliseconds: 1000),
          from: 1,
          to: 0,
          curve: Curves.easeIn,
        ),
      ],
    },

    // The shadow layers are elements, not a text property. That is what makes
    // them animatable at all — each is a copy of the string with its own
    // offset, blur and opacity, and they tighten as the line settles.
    'glowA': {
      'translateY': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 440),
          from: 0,
          to: 7,
          curve: Curves.easeOutCubic,
        ),
        Seg<double>(
          start: Duration(milliseconds: 560),
          end: Duration(milliseconds: 1000),
          from: 7,
          to: 0,
          curve: Curves.easeInCubic,
        ),
      ],
      'blur': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 440),
          from: 30,
          to: 11,
          curve: Curves.easeOutCubic,
        ),
        Seg<double>(
          start: Duration(milliseconds: 560),
          end: Duration(milliseconds: 1000),
          from: 11,
          to: 30,
          curve: Curves.easeInCubic,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 380),
          from: 0,
          to: 0.9,
          curve: Curves.easeOut,
        ),
        Seg<double>(
          start: Duration(milliseconds: 620),
          end: Duration(milliseconds: 1000),
          from: 0.9,
          to: 0,
          curve: Curves.easeIn,
        ),
      ],
    },

    'glowB': {
      'translateX': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 440),
          from: 0,
          to: -5,
          curve: Curves.easeOutCubic,
        ),
        Seg<double>(
          start: Duration(milliseconds: 560),
          end: Duration(milliseconds: 1000),
          from: -5,
          to: 0,
          curve: Curves.easeInCubic,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 440),
          from: 0,
          to: -4,
          curve: Curves.easeOutCubic,
        ),
        Seg<double>(
          start: Duration(milliseconds: 560),
          end: Duration(milliseconds: 1000),
          from: -4,
          to: 0,
          curve: Curves.easeInCubic,
        ),
      ],
      'blur': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 440),
          from: 38,
          to: 16,
          curve: Curves.easeOutCubic,
        ),
        Seg<double>(
          start: Duration(milliseconds: 560),
          end: Duration(milliseconds: 1000),
          from: 16,
          to: 38,
          curve: Curves.easeInCubic,
        ),
      ],
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 420),
          from: 0,
          to: 0.6,
          curve: Curves.easeOut,
        ),
        Seg<double>(
          start: Duration(milliseconds: 580),
          end: Duration(milliseconds: 1000),
          from: 0.6,
          to: 0,
          curve: Curves.easeIn,
        ),
      ],
    },
  },
);

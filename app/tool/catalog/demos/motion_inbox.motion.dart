import 'dart:ui' show Color;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// Hand-written today, written by the Motion panel tomorrow — and the point of
/// the demo is that this is the **only** file the editor will ever touch.
///
/// Nothing here says what a target is or which widget it reaches. That comes
/// from `motion_inbox.dart` reading it, which is why an edit in the panel can
/// never break a build.
const inboxMotion = MotionValues(
  duration: Duration(milliseconds: 780),
  targets: {
    'header': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 200),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 300),
          from: -12,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      // The title settles into its size rather than arriving at it. Six pixels
      // over 420ms is not a thing anyone types on the first try — it is a thing
      // you find by dragging, which is the whole argument for the editor.
      'fontSize': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 420),
          from: 21,
          to: 27,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
    'search': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 90),
          end: Duration(milliseconds: 300),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 90),
          end: Duration(milliseconds: 400),
          from: 16,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      // The only blur on this screen, and deliberately: `ImageFiltered` is the
      // one layer here expensive enough to show up in a frame trace.
      'blur': [
        Seg<double>(
          start: Duration(milliseconds: 90),
          end: Duration(milliseconds: 360),
          from: 7,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'borderRadius': [
        Seg<double>(
          start: Duration(milliseconds: 90),
          end: Duration(milliseconds: 460),
          from: 26,
          to: 13,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    // Four rows, 60ms apart. Written out one at a time because that is what the
    // panel will write — a stagger is four sets of numbers, not a loop.
    'msg1': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 160),
          end: Duration(milliseconds: 400),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 160),
          end: Duration(milliseconds: 500),
          from: 26,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 160),
          end: Duration(milliseconds: 520),
          from: 0.97,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
    'msg2': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 220),
          end: Duration(milliseconds: 460),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 220),
          end: Duration(milliseconds: 560),
          from: 26,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 220),
          end: Duration(milliseconds: 580),
          from: 0.97,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
    'msg3': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 280),
          end: Duration(milliseconds: 520),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 280),
          end: Duration(milliseconds: 620),
          from: 26,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 280),
          end: Duration(milliseconds: 640),
          from: 0.97,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
    'msg4': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 340),
          end: Duration(milliseconds: 580),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 340),
          end: Duration(milliseconds: 680),
          from: 26,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 340),
          end: Duration(milliseconds: 700),
          from: 0.97,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    // Last in, and the only thing on screen allowed to overshoot.
    'fab': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 500),
          end: Duration(milliseconds: 600),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 500),
          end: Duration(milliseconds: 760),
          from: 0.5,
          to: 1,
          curve: Curves.easeOutBack,
        ),
      ],
      'rotate': [
        Seg<double>(
          start: Duration(milliseconds: 500),
          end: Duration(milliseconds: 760),
          from: -0.7,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'elevation': [
        Seg<double>(
          start: Duration(milliseconds: 500),
          end: Duration(milliseconds: 780),
          from: 0,
          to: 14,
          curve: Curves.easeOutCubic,
        ),
      ],
      // Grey until it has arrived. The colour is the last thing to land, which
      // is what makes the button read as *becoming* the action.
      'color': [
        Seg<Color>(
          start: Duration(milliseconds: 520),
          end: Duration(milliseconds: 780),
          from: Color(0xFFB9BEBC),
          to: Color(0xFFB23A48),
          curve: Curves.easeInOutCubic,
        ),
      ],
    },
  },
);

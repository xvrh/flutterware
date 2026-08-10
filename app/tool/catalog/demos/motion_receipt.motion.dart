import 'dart:ui' show Color;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// Hand-written today, written by the Motion panel tomorrow — and the point of
/// the demo is that this is the **only** file the editor will ever touch.
///
/// Seven targets, each doing something different. There is no repeated block
/// here and there should not be one: a stagger of four identical rows is four
/// copies of the same numbers, which is a thing to generate rather than a thing
/// to demonstrate.
const receiptMotion = MotionValues(
  duration: Duration(milliseconds: 900),
  targets: {
    // Everything arrives out of focus. One `ImageFiltered` for the whole
    // screen, which is the only affordable way to use blur.
    'scrim': {
      'blur': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 420),
          from: 10,
          to: 0,
          curve: Curves.easeOutCubic,
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
      ],
    },

    // The one thing allowed to overshoot, and the only rotation on screen.
    'badge': {
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 60),
          end: Duration(milliseconds: 420),
          from: 0.4,
          to: 1,
          curve: Curves.easeOutBack,
        ),
      ],
      'rotate': [
        Seg<double>(
          start: Duration(milliseconds: 60),
          end: Duration(milliseconds: 460),
          from: -0.5,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      // Grey until it has landed: the colour is what makes it read as
      // *becoming* confirmed rather than starting that way.
      'color': [
        Seg<Color>(
          start: Duration(milliseconds: 120),
          end: Duration(milliseconds: 480),
          from: Color(0xFFBFC6C4),
          to: Color(0xFF12695A),
          curve: Curves.easeInOutCubic,
        ),
      ],
    },

    // `progress` is the escape hatch — a tuned number with no meaning until the
    // read site gives it one. In `motion_player` it is an `Align.heightFactor`;
    // here it is the sweep of an arc. That is the whole of its generality.
    'ring': {
      'progress': [
        Seg<double>(
          start: Duration(milliseconds: 80),
          end: Duration(milliseconds: 640),
          from: 0,
          to: 1,
          curve: Curves.easeInOutCubic,
        ),
      ],
    },

    'title': {
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
          end: Duration(milliseconds: 560),
          from: 14,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'fontSize': [
        Seg<double>(
          start: Duration(milliseconds: 280),
          end: Duration(milliseconds: 600),
          from: 18,
          to: 24,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    // A card settling: it rises, its corners tighten, and its shadow arrives
    // last. Three properties on one element, none of them a transform.
    'card': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 360),
          end: Duration(milliseconds: 600),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 360),
          end: Duration(milliseconds: 720),
          from: 40,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'borderRadius': [
        Seg<double>(
          start: Duration(milliseconds: 360),
          end: Duration(milliseconds: 760),
          from: 28,
          to: 14,
          curve: Curves.easeOutCubic,
        ),
      ],
      'elevation': [
        Seg<double>(
          start: Duration(milliseconds: 400),
          end: Duration(milliseconds: 800),
          from: 0,
          to: 18,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    // The number lands after the card it sits in, which is the whole trick.
    'total': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 560),
          end: Duration(milliseconds: 760),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'fontSize': [
        Seg<double>(
          start: Duration(milliseconds: 560),
          end: Duration(milliseconds: 860),
          from: 20,
          to: 30,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    'cta': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 700),
          end: Duration(milliseconds: 840),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 700),
          end: Duration(milliseconds: 880),
          from: 16,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'elevation': [
        Seg<double>(
          start: Duration(milliseconds: 720),
          end: Duration(milliseconds: 900),
          from: 0,
          to: 12,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
  },
);

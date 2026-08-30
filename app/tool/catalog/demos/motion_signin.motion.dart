import 'dart:ui' show Color;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// Real widgets, animated — a working `TextFormField` you can type into while
/// the motion runs.
///
/// The point of the file is the split it forces. `opacity`, `translateY` and
/// `scale` are **imposed**: a wrapper applies them and the field never learns
/// it was animated. `color` is **intrinsic**: no parent can recolour a
/// `TextFormField`'s fill, so `email.color` only does anything because the
/// build method reaches in and hands it to an `InputDecoration`. Delete that
/// one read and the lane below keeps animating, keeps showing in the panel,
/// and changes nothing on screen.
const signInMotion = MotionValues(
  duration: Duration(milliseconds: 900),
  targets: {
    'title': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 260),
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
      'blur': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 900),
          from: 8,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    'email': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 120),
          end: Duration(milliseconds: 400),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 120),
          end: Duration(milliseconds: 460),
          from: 16,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      // Intrinsic. Works only because the build method reads it.
      'color': [
        Seg<Color>(
          start: Duration(milliseconds: 200),
          end: Duration(milliseconds: 760),
          from: Color(0xFFEDEFF2),
          to: Color(0xFFFFFFFF),
          curve: Curves.easeInOut,
        ),
      ],
    },

    'password': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 200),
          end: Duration(milliseconds: 480),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 200),
          end: Duration(milliseconds: 540),
          from: 16,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      // Intrinsic, and deliberately NOT read at the call site. It animates,
      // the panel lists it, and the screen never shows it. This is the whole
      // argument for judging a lane by running rather than by reading.
      'color': [
        Seg<Color>(
          start: Duration(milliseconds: 280),
          end: Duration(milliseconds: 840),
          from: Color(0xFFEDEFF2),
          to: Color(0xFFFFF0F0),
          curve: Curves.easeInOut,
        ),
      ],
    },

    'cta': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 340),
          end: Duration(milliseconds: 600),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 340),
          end: Duration(milliseconds: 900),
          from: 0.95,
          to: 1,
          curve: Curves.easeOutBack,
        ),
      ],
      'elevation': [
        Seg<double>(
          start: Duration(milliseconds: 500),
          end: Duration(milliseconds: 900),
          from: 0,
          to: 6,
          curve: Curves.easeOut,
        ),
      ],
    },
  },
);

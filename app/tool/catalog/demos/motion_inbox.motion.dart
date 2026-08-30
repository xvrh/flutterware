import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// The stagger `motion_receipt.dart` refused to write, written out so the cost
/// is a number rather than an opinion.
///
/// Five rows, one entrance, offset 70ms each. Every row's three lanes are the
/// same three lanes with one number changed, and there is no way to say that —
/// so it is said five times. Count the `Seg`s: seventeen, of which fifteen are
/// one animation copy-pasted.
const inboxMotion = MotionValues(
  duration: Duration(milliseconds: 800),
  targets: {
    'header': {
      'opacity': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 220),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 260),
          from: -10,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    'row0': {
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
          end: Duration(milliseconds: 480),
          from: 18,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 160),
          end: Duration(milliseconds: 480),
          from: 0.96,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    'row1': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 230),
          end: Duration(milliseconds: 470),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 230),
          end: Duration(milliseconds: 550),
          from: 18,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 230),
          end: Duration(milliseconds: 550),
          from: 0.96,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    'row2': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 300),
          end: Duration(milliseconds: 540),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 300),
          end: Duration(milliseconds: 620),
          from: 18,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 300),
          end: Duration(milliseconds: 620),
          from: 0.96,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    'row3': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 370),
          end: Duration(milliseconds: 610),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 370),
          end: Duration(milliseconds: 690),
          from: 18,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 370),
          end: Duration(milliseconds: 690),
          from: 0.96,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    'row4': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 440),
          end: Duration(milliseconds: 680),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 440),
          end: Duration(milliseconds: 760),
          from: 18,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 440),
          end: Duration(milliseconds: 760),
          from: 0.96,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
  },
);

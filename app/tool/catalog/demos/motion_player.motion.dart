import 'dart:ui' show Color;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// A two-state morph: a compact card at `t = 0`, a full player at `t = 1`.
///
/// The interesting thing about this file is what is *not* in it. There is no
/// collapsed state and no expanded state — there is one function of `t`, and
/// the two states are the values it happens to take at the ends. That is what
/// makes `reverse()` free, and it is why a scrubber can sit anywhere between
/// them and still show something coherent.
const playerMotion = MotionValues(
  duration: Duration(milliseconds: 620),
  anchors: {
    // The light behind the card, which is doing more work than it looks like.
    'glow': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 60),
          end: Duration(milliseconds: 520),
          from: 0,
          to: 0.9,
          curve: Curves.easeOutCubic,
        ),
      ],
      'scale': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 620),
          from: 0.55,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
    'sheet': {
      'borderRadius': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 560),
          from: 20,
          to: 32,
          curve: Curves.easeOutQuint,
        ),
      ],
      'padding': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 560),
          from: 14,
          to: 22,
          curve: Curves.easeOutQuint,
        ),
      ],
      'elevation': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 560),
          from: 6,
          to: 28,
          curve: Curves.easeOutCubic,
        ),
      ],
      'color': [
        Seg<Color>(
          start: Duration.zero,
          end: Duration(milliseconds: 560),
          from: Color(0xFF1A1F26),
          to: Color(0xFF232A34),
          curve: Curves.easeInOutCubic,
        ),
      ],
    },
    'art': {
      // easeOutQuint on the size and easeOutCubic on the shadow: the cover
      // arrives before its shadow settles, which is what stops the growth from
      // reading as a single flat scale.
      'width': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 560),
          from: 64,
          to: 208,
          curve: Curves.easeOutQuint,
        ),
      ],
      'height': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 560),
          from: 64,
          to: 208,
          curve: Curves.easeOutQuint,
        ),
      ],
      'borderRadius': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 560),
          from: 14,
          to: 26,
          curve: Curves.easeOutQuint,
        ),
      ],
      // Three degrees of tilt, unwound over the whole run. Secondary motion:
      // you do not see it, you notice its absence.
      'rotate': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 620),
          from: -0.055,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'elevation': [
        Seg<double>(
          start: Duration(milliseconds: 80),
          end: Duration(milliseconds: 600),
          from: 2,
          to: 20,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
    'title': {
      'fontSize': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 560),
          from: 15,
          to: 25,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
    'artist': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 200),
          end: Duration(milliseconds: 520),
          from: 0.55,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'fontSize': [
        Seg<double>(
          start: Duration.zero,
          end: Duration(milliseconds: 560),
          from: 12,
          to: 14,
          curve: Curves.easeOutCubic,
        ),
      ],
    },

    // `progress` is the escape hatch — a tuned number with no meaning until the
    // read site gives it one. Here it is an `Align.heightFactor`, which is how
    // the lower half of the card is revealed without anybody measuring it.
    'reveal': {
      'progress': [
        Seg<double>(
          start: Duration(milliseconds: 180),
          end: Duration(milliseconds: 620),
          from: 0,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
      // 60ms behind the space that holds it, and no more. Further behind and a
      // scrub through the middle of the run shows an empty box opening — which
      // is a thing you only find out by parking the playhead there.
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 240),
          end: Duration(milliseconds: 560),
          from: 0,
          to: 1,
          curve: Curves.easeOut,
        ),
      ],
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 240),
          end: Duration(milliseconds: 620),
          from: 14,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
    'play': {
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 360),
          end: Duration(milliseconds: 620),
          from: 0.82,
          to: 1,
          curve: Curves.easeOutBack,
        ),
      ],
      'color': [
        Seg<Color>(
          start: Duration(milliseconds: 280),
          end: Duration(milliseconds: 600),
          from: Color(0xFF3A424E),
          to: Color(0xFFE0A33E),
          curve: Curves.easeInOutCubic,
        ),
      ],
    },
  },
);

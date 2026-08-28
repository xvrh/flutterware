import 'package:flutter/animation.dart' show Curves;
import 'package:flutterware/motion.dart';

/// The **flow's** timeline: how the journey through the pages is paced.
///
/// One number, `flow`, running 0 → 1 across the whole onboarding. The demo
/// multiplies it by the last page's index, so it *is* the `PageView`'s offset:
/// 0 is the first page, 1 the last, 0.5 the middle one.
///
/// It exists because a swipe is not a timeline. The pages animate from the
/// gesture beautifully and cannot be exported, because a gesture has no
/// playhead to seek — and everything the tool offers, from the scrubber to
/// `motion video`, is a seek. So the composition gets a playhead of its own,
/// and the gesture becomes one of two things that can move it.
///
/// The pacing is holds and slides rather than a linear ramp, because a video
/// of an onboarding is not a scrub through it: a viewer needs to read each
/// page before the next one arrives. 700ms to read, 700ms to travel.
///
/// FAKE (page count): `0.5` is the middle page because there are three. A
/// four-page flow needs waypoints at a third and two thirds, so this file
/// silently encodes how many pages the demo has. A motion that took the count
/// as a parameter — the same need as the wave's three numbers, and the same
/// missing feature — would not.
const onboardingMotion = MotionValues(
  duration: Duration(milliseconds: 3500),
  targets: {
    'flow': {
      'progress': [
        Seg<double>(
          start: Duration(milliseconds: 700),
          end: Duration(milliseconds: 1400),
          from: 0,
          to: 0.5,
          curve: Curves.easeInOutCubic,
        ),
        // The gap from 1400 to 2100 is the hold on the middle page: a property
        // between two segments keeps the earlier one's `to`, so a pause needs
        // no segment of its own.
        Seg<double>(
          start: Duration(milliseconds: 2100),
          end: Duration(milliseconds: 2800),
          from: 0.5,
          to: 1,
          curve: Curves.easeInOutCubic,
        ),
      ],
    },
  },
);

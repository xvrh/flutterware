import 'package:flutter/material.dart' show Color;
import 'package:flutterware/motion.dart';

/// **Prototype.** What the editor would have written for `signInMotion` if the
/// motion had been started from a "New motion" button instead of by hand.
///
/// Owned by the tool: one `StageElement` per target, positioned by rect. The
/// four targets are the same four `motion_signin.dart` reads — the same motion
/// drives both, and neither host knows about the other.
const signInStage = MotionStage(
  width: 340,
  height: 380,
  elements: [
    StageElement(
      target: 'title',
      kind: StageKind.text,
      label: 'Welcome back',
      x: 28,
      y: 44,
      width: 220,
      height: 26,
    ),
    StageElement(target: 'email', x: 28, y: 108, width: 284, height: 48),
    StageElement(target: 'password', x: 28, y: 168, width: 284, height: 48),
    StageElement(
      target: 'cta',
      x: 28,
      y: 240,
      width: 284,
      height: 46,
      tint: Color(0xFF2563EB),
    ),
  ],
);

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Draws the film's cursor over a frame the app has already painted.
///
/// **Over, never in.** Nothing here is a widget: the app's tree does not
/// contain a cursor, so it cannot lay out around one, rebuild for one, or
/// carry one into a screenshot. What this paints goes onto the rasterised
/// frame on its way to the encoder.
///
/// Everything is in the app's own logical points, the space [ScenarioAim] is
/// in — the caller scales the canvas once. So a fingertip is 20 points here
/// and stays a fingertip whether the film renders at 1× or 3×.
///
/// Two looks, chosen by the stage rather than by a flag, because the choice is
/// not a preference: a phone is touched and a window is pointed at, and a film
/// showing an arrow on a phone is showing something that never happens.
class ScenarioFilmCursor {
  const ScenarioFilmCursor({required this.touch});

  /// Whether the stage is a touch device.
  final bool touch;

  /// Ink and paper, and every mark is drawn in both.
  ///
  /// A cursor lands wherever the flow takes it: over a white card, over a
  /// brown button, over a photograph. One colour cannot survive all three, so
  /// every shape here is a dark mark with a light one under or around it —
  /// the same defence `ScenarioAimPainter` makes for its rings, and the reason
  /// a film of a dark app needs no setting.
  static const _ink = Color(0xCC000000);
  static const _paper = Color(0xF2FFFFFF);

  /// A fingertip. The tap target every mobile guideline asks for, so the mark
  /// stays a mark whatever the film is watched at.
  static const _touchRadius = 20.0;

  /// How long a press ripple takes to travel out and fade.
  ///
  /// It outlives the press on purpose: a tap is a few frames and the ripple is
  /// what makes it *read* as a tap rather than as a cursor that flickered.
  static const rippleSeconds = 0.45;

  /// Paints the cursor at [at].
  ///
  /// [down] is whether the pointer is pressed on this frame; [sincePress] is
  /// how long ago the last press began, in seconds, or null where there has
  /// not been one. The two are separate because they end at different times.
  void paint(
    ui.Canvas canvas,
    Offset at, {
    required bool down,
    double? sincePress,
  }) {
    if (sincePress case var since? when since < rippleSeconds) {
      _ripple(canvas, at, since / rippleSeconds);
    }
    if (touch) {
      _finger(canvas, at, down: down);
    } else {
      _arrow(canvas, at, down: down, sincePress: sincePress);
    }
  }

  /// The contact ring, travelling out and fading.
  void _ripple(ui.Canvas canvas, Offset at, double t) {
    var eased = Curves.easeOutCubic.transform(t);
    var radius = ui.lerpDouble(
      touch ? _touchRadius : 6,
      touch ? 46 : 28,
      eased,
    )!;
    var fade = 1 - t;
    canvas
      ..drawCircle(
        at,
        radius + 1,
        Paint()
          ..color = _ink.withValues(alpha: 0.35 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      )
      ..drawCircle(
        at,
        radius,
        Paint()
          ..color = _paper.withValues(alpha: 0.9 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
  }

  /// The touch mark: a disc that shrinks under the press, the way a fingertip
  /// flattens against the glass.
  ///
  /// **Quiet at rest and definite under the press.** A fingertip spends most of
  /// a film not touching anything, and at the weight the press needs it sits
  /// on the screen like a smudge — it competes with the app, which is the one
  /// thing the app's own film must not do. So the fill, the ring and the
  /// shadow all lighten when the finger is up, and the difference between the
  /// two states does the work the ripple used to do alone.
  void _finger(ui.Canvas canvas, Offset at, {required bool down}) {
    var radius = down ? _touchRadius * 0.78 : _touchRadius;
    canvas
      ..drawCircle(
        at,
        radius,
        Paint()
          ..color = _ink.withValues(alpha: down ? 0.10 : 0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      )
      ..drawCircle(
        at,
        radius,
        Paint()..color = _ink.withValues(alpha: down ? 0.42 : 0.16),
      )
      ..drawCircle(
        at,
        radius,
        Paint()
          ..color = down ? _paper : _paper.withValues(alpha: 0.72)
          ..style = PaintingStyle.stroke
          ..strokeWidth = down ? 2.5 : 1.6,
      );
  }

  /// The pointer: the arrow every desktop has, tip on the contact point.
  ///
  /// Drawn rather than borrowed. The platform's own cursor is a texture the
  /// app never sees — a film is rendered, not recorded, so there is nothing to
  /// capture and the shape has to be a path like everything else here.
  void _arrow(
    ui.Canvas canvas,
    Offset at, {
    required bool down,
    double? sincePress,
  }) {
    // A press dips the arrow briefly, which is what makes a click read as a
    // click on a screen with no button feedback of its own.
    var dip = switch (sincePress) {
      var since? when since < 0.12 => 0.88,
      _ => down ? 0.88 : 1.0,
    };
    var path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(0, 17.4)
      ..lineTo(4.3, 13.4)
      ..lineTo(7.0, 19.6)
      ..lineTo(9.8, 18.3)
      ..lineTo(7.2, 12.2)
      ..lineTo(12.3, 11.8)
      ..close();
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..scale(dip)
      // Under the arrow rather than around it: an outline alone disappears
      // into a busy background, and a shadow is what a real cursor has.
      ..drawPath(
        path.shift(const Offset(0.6, 1.2)),
        Paint()
          ..color = _ink.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      )
      ..drawPath(path, Paint()..color = _paper)
      ..drawPath(
        path,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..strokeJoin = StrokeJoin.round,
      )
      ..restore();
  }

  /// How far a fingertip reaches past the point it is on — what a caller adds
  /// to a bound when it needs to know the mark's own extent.
  static double get reach => math.max(_touchRadius, 28);
}

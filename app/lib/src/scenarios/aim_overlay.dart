import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../plugins/native/scenarios_results.dart';
import '../ui/theme.dart';

/// Where the next verb's finger goes, drawn over the frame it went down on.
///
/// A scenario has no cursor, so a screenshot of a tap and a screenshot of a
/// screen sitting still are the same picture. Hovering a next link answers
/// the question the link's own label cannot — the label says `tap
/// "Cappuccino"`, this says *which* Cappuccino.
///
/// Painted **inside a surface that is the app's own logical size**, like
/// [NodeHighlightPainter] and for the same reason: [ScenarioAim] is in the
/// view's logical pixels, so in that box there is no transform to apply and
/// whatever `FittedBox` or device frame sits above it is inherited.
class ScenarioAimOverlay extends StatelessWidget {
  const ScenarioAimOverlay({super.key, required this.aim, required this.verb});

  final ScenarioAim aim;

  /// What the finger did — `tap`, `longPress`, `drag`. A held press is drawn
  /// as a held press, because the picture is the only place a reader would
  /// learn the difference without reading the code.
  final String? verb;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: ScenarioAimPainter(
      aim: aim,
      verb: verb,
      color: context.colors.accent,
    ),
  );
}

class ScenarioAimPainter extends CustomPainter {
  ScenarioAimPainter({
    required this.aim,
    required this.verb,
    required this.color,
  });

  final ScenarioAim aim;
  final String? verb;
  final Color color;

  /// A fingertip, near enough: the tap target every mobile guideline asks for,
  /// so the mark stays a mark at whatever scale the phone is drawn at rather
  /// than becoming a dot on a big window and a blob on a small one.
  static const _touch = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    var (px, py) = aim.point;
    var point = Offset(px, py);
    var box = Rect.fromLTWH(aim.x, aim.y, aim.width, aim.height);

    // The resolved box, faintly. It is the *finder's* box — `tap('Cappuccino')`
    // resolves the word, not the card around it — so it is drawn as context
    // for the point rather than as the thing that was hit.
    canvas.drawRect(
      box,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        // Two logical pixels because the phone is drawn at about a quarter
        // size on the step page, where a hairline is a rumour.
        ..strokeWidth = 2,
    );

    if ((aim.dx, aim.dy) case (var dx?, var dy?)) {
      _arrow(canvas, point, point + Offset(dx, dy));
    }

    // A held press wears a second ring: the two verbs are the same picture
    // otherwise, and which one it was changes what the app did.
    if (verb == 'longPress') {
      canvas.drawCircle(
        point,
        _touch + 6,
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    canvas
      // White under the ring, so the mark survives an accent-coloured button.
      ..drawCircle(
        point,
        _touch,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      )
      ..drawCircle(
        point,
        _touch,
        Paint()..color = color.withValues(alpha: 0.22),
      )
      ..drawCircle(
        point,
        _touch,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
  }

  /// The travel of a drag: a line out of the contact ring's edge to where the
  /// finger let go, with a head on it. From the edge rather than the centre,
  /// so the ring stays a ring.
  void _arrow(Canvas canvas, Offset from, Offset to) {
    var line = to - from;
    if (line.distance <= _touch) return;
    var direction = math.atan2(line.dy, line.dx);
    var start = from + Offset.fromDirection(direction, _touch);
    var stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    var halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;
    const head = 11.0;
    var wings = [
      to - Offset.fromDirection(direction - 0.4, head),
      to - Offset.fromDirection(direction + 0.4, head),
    ];
    for (var paint in [halo, stroke]) {
      canvas.drawLine(start, to, paint);
      for (var wing in wings) {
        canvas.drawLine(to, wing, paint);
      }
    }
  }

  @override
  bool shouldRepaint(ScenarioAimPainter old) =>
      old.aim != aim || old.verb != verb || old.color != color;
}

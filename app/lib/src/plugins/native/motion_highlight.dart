/// A ring around the target a lane drives, drawn over the guest.
///
/// **Painted into a surface that is the guest's logical size**, which costs
/// nothing to arrange here: the panel is the thing that calls `engine.resize`,
/// so the `Texture`'s box and the guest's coordinate space are the same
/// rectangle and the rect arrives ready to use. It is the same contract the
/// inspect layer's node rects are drawn under.
library;

import 'package:flutter/material.dart';

import '../../ui/design/tokens.dart';

class MotionStageHighlight extends StatelessWidget {
  const MotionStageHighlight({super.key, required this.extent, this.label});

  /// Where the target is, in guest coordinates, or null to draw nothing.
  final Rect? extent;

  /// The target's name, printed on the ring.
  final String? label;

  @override
  Widget build(BuildContext context) {
    var extent = this.extent;
    if (extent == null) return const SizedBox.expand();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _RingPainter(
          extent: extent,
          label: label,
          tone: context.colors.accent,
          onTone: context.colors.bg,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.extent,
    required this.tone,
    required this.onTone,
    this.label,
  });

  final Rect extent;
  final String? label;
  final Color tone;
  final Color onTone;

  @override
  void paint(Canvas canvas, Size size) {
    // Outset, so the ring sits *around* the thing rather than over its edge —
    // a target whose whole animation is a 2px border move would otherwise be
    // hidden by the very thing pointing at it.
    var rect = extent.inflate(2);
    var rounded = RRect.fromRectAndRadius(rect, const Radius.circular(3));

    canvas
      ..drawRRect(rounded, Paint()..color = tone.withValues(alpha: 0.12))
      ..drawRRect(
        rounded,
        Paint()
          ..color = tone
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

    if (label == null) return;
    var text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: onTone, fontSize: 10, height: 1.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Above when there is room, inside when there is not: a label clipped off
    // the top of the stage names nothing.
    var padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2);
    var chip = Rect.fromLTWH(
      rect.left,
      rect.top - text.height - padding.vertical >= 0
          ? rect.top - text.height - padding.vertical
          : rect.top,
      text.width + padding.horizontal,
      text.height + padding.vertical,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(chip, const Radius.circular(2)),
        Paint()..color = tone,
      )
      ..save();
    text.paint(canvas, chip.topLeft + Offset(padding.left, padding.top));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.extent != extent ||
      old.label != label ||
      old.tone != tone ||
      old.onTone != onTone;
}

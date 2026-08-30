import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A parametric shape: the wave that splits the image from the content.
///
/// **This is the first element in the design that is not a widget.** It is a
/// clip whose path is generated from three named numbers, and animating it
/// means animating those numbers — which is the whole reason a scene tool
/// wants parametric shapes rather than drawn paths. Amplitude and phase are
/// two drags; the same motion expressed as bezier control points is a keyframe
/// per node.
///
/// FAKE (units): [amplitude] is a fraction of the box height rather than a
/// number of pixels, resolved here at the read site. That works, but it is
/// invisible to the editor — a lane driving it would show `progress 0.06` with
/// no unit and no hint that the author meant "6% of the height".
class WaveClip extends CustomClipper<Path> {
  const WaveClip({
    required this.amplitude,
    required this.phase,
    this.frequency = 1.15,
  });

  /// Fraction of the box height, peak to baseline.
  final double amplitude;

  /// Radians. Animating this alone makes the wave travel.
  final double phase;

  /// How many crests across the width.
  final double frequency;

  @override
  Path getClip(Size size) {
    var peak = size.height * amplitude;
    var baseline = size.height - peak;
    var path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, baseline);

    // Sampled rather than beziered: a sampled sine is exact at any frequency,
    // and the cost is one lineTo per 4px of width.
    for (var x = size.width; x >= 0; x -= 4) {
      var t = x / size.width;
      path.lineTo(
        x,
        baseline + peak * math.sin(t * frequency * 2 * math.pi + phase),
      );
    }

    return path
      ..lineTo(0, 0)
      ..close();
  }

  @override
  bool shouldReclip(WaveClip old) =>
      old.amplitude != amplitude ||
      old.phase != phase ||
      old.frequency != frequency;
}

/// Stands in for the photograph a developer would pass.
///
/// The component takes a `Widget` for its image, so what this is does not
/// matter to the model — it is here because the repository ships no
/// photographs, and a scene tool's demo cannot be judged on grey boxes.
class AuroraImage extends StatelessWidget {
  const AuroraImage({super.key, required this.seed, required this.accent});

  final int seed;
  final Color accent;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _AuroraPainter(seed: seed, accent: accent),
  );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.seed, required this.accent});

  final int seed;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    var rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF120E1C),
            Color.lerp(const Color(0xFF1B1430), accent, 0.22)!,
          ],
        ).createShader(rect),
    );

    var random = math.Random(seed);
    for (var i = 0; i < 5; i++) {
      var centre = Offset(
        size.width * (0.15 + random.nextDouble() * 0.7),
        size.height * (0.15 + random.nextDouble() * 0.7),
      );
      var radius = size.shortestSide * (0.28 + random.nextDouble() * 0.34);
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Color.lerp(
                accent,
                Colors.white,
                random.nextDouble() * 0.5,
              )!.withValues(alpha: 0.42),
              accent.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    // The scrim. Text over an image needs one, and it is part of the
    // presentation the tool owns rather than of the image the developer hands
    // in — which is why it lives here and not in the slot.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x00000000),
            const Color(0x22000000),
            const Color(0x66000000),
          ],
          stops: const [0.35, 0.7, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.seed != seed || old.accent != accent;
}

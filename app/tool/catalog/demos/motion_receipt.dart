import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutterware/motion.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/previews.dart';

import 'motion_receipt.motion.dart';
import 'shell.dart';

/// An order confirmation, and the demo that looks like real work.
///
/// Seven targets, each doing something different — no repeated block, because a
/// stagger of four identical rows is four copies of the same numbers and is a
/// thing to *generate*, not a thing to hand-write. Between them they use ten of
/// the sixteen vocabulary properties, and every one of them earns its place:
/// the badge is the only thing that overshoots, the blur is the only image
/// filter, the card's shadow arrives after the card, and the total lands after
/// the card it sits in.
///
/// Mixed on purpose. `motion_player.dart` reads every property at its call
/// site and wears no `MotionBox`; this one does both, because that is what real
/// code looks like — a box where an element just moves, a read where the value
/// is structural (`card.borderRadius` on a `BoxDecoration`, `ring.progress` on
/// an arc, `total.fontSize` on a `TextStyle`).
///
/// One habit worth copying: the reads happen **in the builder** and the values
/// are passed down, rather than handing a target to a helper widget and reading
/// it in there. Both work at run time; only the first is visible to the
/// syntactic scan, so the panel can show you the lanes before anything has been
/// compiled.
///
/// Drag `t` to scrub, tap to replay.
@Preview(name: 'Order confirmed', group: 'Motion', wrapper: wrapInApp)
Widget motionReceipt() => const _Receipt();

const _ground = Color(0xFFECEEF1);
const _card = Color(0xFFFFFFFF);
const _ink = Color(0xFF14171A);
const _muted = Color(0xFF6B7280);
const _hairline = Color(0xFFDFE3E6);
const _pine = Color(0xFF12695A);

class _Receipt extends StatefulWidget {
  const _Receipt();

  @override
  State<_Receipt> createState() => _ReceiptState();
}

class _ReceiptState extends State<_Receipt> {
  final _controller = MotionController(autoplay: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller.progress = context.knobs.double('t', 1, min: 0, max: 1);

    return MotionScope(
      motion: receiptMotion,
      controller: _controller,
      builder: (m) {
        var scrim = m.target('scrim');
        var badge = m.target('badge');
        var ring = m.target('ring');
        var title = m.target('title');
        var card = m.target('card');
        var total = m.target('total');
        var cta = m.target('cta');

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _controller.play(restart: true),
          child: Scaffold(
            backgroundColor: _ground,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: _blurred(
                    sigma: scrim.blur,
                    opacity: scrim.opacity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: _Badge(
                              badge: badge,
                              sweep: ring.progress,
                              tint: badge.color ?? _pine,
                            ),
                          ),
                          const SizedBox(height: 22),
                          MotionBox(
                            title,
                            child: Text(
                              'Order confirmed',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: title.fontSize ?? 24,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                                color: _ink,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Arriving Thursday, 12–4pm',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, color: _muted),
                          ),
                          const SizedBox(height: 26),
                          MotionBox(
                            card,
                            child: _ReceiptCard(
                              radius: card.borderRadius ?? 14,
                              elevation: card.elevation,
                              totalSize: total.fontSize ?? 30,
                              totalOpacity: total.opacity,
                            ),
                          ),
                          const SizedBox(height: 20),
                          MotionBox(cta, child: _Cta(elevation: cta.elevation)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// One filter for the whole screen, skipped entirely at rest.
  Widget _blurred({
    required double sigma,
    required double opacity,
    required Widget child,
  }) {
    var result = opacity == 1 ? child : Opacity(opacity: opacity, child: child);
    if (sigma <= 0) return result;
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: result,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.badge, required this.sweep, required this.tint});

  final MotionTarget badge;
  final double sweep;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The ring draws itself around the badge, from the same number that
          // means nothing until here.
          CustomPaint(
            size: const Size.square(92),
            painter: _RingPainter(sweep: sweep, color: tint),
          ),
          MotionBox(
            badge,
            child: Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: const Icon(
                Icons.check_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.sweep, required this.color});

  final double sweep;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (sweep <= 0) return;
    canvas.drawArc(
      Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
      -math.pi / 2,
      sweep * math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.sweep != sweep || old.color != color;
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.radius,
    required this.elevation,
    required this.totalSize,
    required this.totalOpacity,
  });

  final double radius;
  final double elevation;
  final double totalSize;
  final double totalOpacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _hairline),
        boxShadow: shadowFor(elevation, _ink),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Line('Ash & Elm side table', '£248.00'),
          const SizedBox(height: 8),
          const _Line('Delivery', 'Included'),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _hairline),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontSize: 13, color: _muted),
              ),
              const Spacer(),
              Opacity(
                opacity: totalOpacity,
                child: Text(
                  '£248.00',
                  style: TextStyle(
                    fontSize: totalSize,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.6,
                    color: _ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            color: _ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Cta extends StatelessWidget {
  const _Cta({required this.elevation});

  final double elevation;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _pine,
        borderRadius: BorderRadius.circular(12),
        boxShadow: shadowFor(elevation, _pine),
      ),
      child: const Text(
        'Track your order',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// One `elevation` number, two shadows — the near one for contact, the far one
/// for lift. Shared with `motion_player.dart` so both read it the same way.
List<BoxShadow> shadowFor(double elevation, Color tint) {
  if (elevation <= 0) return const [];
  return [
    BoxShadow(
      color: tint.withValues(alpha: 0.16),
      blurRadius: elevation * 1.8,
      offset: Offset(0, elevation * 0.6),
    ),
    BoxShadow(
      color: tint.withValues(alpha: 0.10),
      blurRadius: elevation * 0.6,
      offset: Offset(0, elevation * 0.15),
    ),
  ];
}

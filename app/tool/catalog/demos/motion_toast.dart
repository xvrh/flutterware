import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/previews.dart';

import 'motion_toast.motion.dart';
import 'shell.dart';

/// A toast that arrives, waits and leaves — enter and exit on **one** playhead.
///
/// It works, and that answers the question it was written for: a single
/// `t ∈ [0,1]` is enough for a round trip, and no second controller or reversed
/// direction is needed. Every lane simply has two segments with a gap.
///
/// What it also shows is what the gap costs. The 1580ms the toast spends on
/// screen is not written down — it is the distance between two segments, and
/// it is spelled six times across three lanes plus `duration`. Changing the
/// dwell is a seven-number edit, and getting one of them wrong is a toast that
/// fades while it is still sliding.
///
/// Drag `t` to scrub, tap to replay.
@Preview(name: 'Toast (enter/exit)', group: 'Motion', wrapper: wrapInApp)
Widget motionToast() => const _Toast();

const _ground = Color(0xFFF4F5F7);
const _panel = Color(0xFF1C1F23);
const _ink = Color(0xFFF2F3F5);
const _muted = Color(0xFF9AA3AD);
const _good = Color(0xFF30A46C);

class _Toast extends StatefulWidget {
  const _Toast();

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  final _controller = MotionController(autoplay: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller.progress = context.knobs.double('t', 0.5, min: 0, max: 1);

    return MotionScope(
      motion: toastMotion,
      controller: _controller,
      builder: (m) {
        var toast = m.target('toast');
        var tick = m.target('tick');
        var meter = m.target('meter');

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _controller.play(restart: true),
          child: Scaffold(
            backgroundColor: _ground,
            body: SafeArea(
              child: Stack(
                children: [
                  const Center(
                    child: Text(
                      'tap to replay',
                      style: TextStyle(fontSize: 12, color: Color(0xFFAAB2BB)),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Opacity(
                        opacity: toast.opacity,
                        child: Transform.translate(
                          offset: Offset(0, toast.translateY),
                          child: Transform.scale(
                            scale: toast.scale,
                            child: _Card(
                              tickScale: tick.scale,
                              remaining: meter.progress,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.tickScale, required this.remaining});

  final double tickScale;
  final double remaining;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Transform.scale(
                  scale: tickScale,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: _good,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Changes saved',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '3 files written to main',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // The dwell, drawn. Nothing else on screen moves while this drains.
          SizedBox(
            height: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: remaining.clamp(0.0, 1.0),
                child: Container(
                  decoration: const BoxDecoration(
                    color: _good,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

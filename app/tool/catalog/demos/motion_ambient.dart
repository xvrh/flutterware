import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/previews.dart';

import 'motion_ambient.motion.dart';
import 'shell.dart';

/// A recording indicator that never stops — the case `lib/motion.dart` puts
/// outside its own scope: *"designed choreography of a fixed duration."*
///
/// It plays fine. `MotionController.repeat()` drives the same `evaluate(t)`,
/// and a loop is just a playhead that wraps. What the format cannot do is
/// **say** it loops: the seam at `t = 1 → 0` is held by hand in six `to:`
/// values, nothing checks it, and a mismatch is a once-a-cycle tick that no
/// filmstrip will ever show you — the two frames it falls between are the two
/// frames a contact sheet omits.
///
/// Drag `t` to scrub, tap to start and stop the loop.
@Preview(name: 'Recording (loop)', group: 'Motion', wrapper: wrapInApp)
Widget motionAmbient() => const _Ambient();

const _ground = Color(0xFF101215);
const _live = Color(0xFFE5484D);
const _ink = Color(0xFFEDEEF0);

class _Ambient extends StatefulWidget {
  const _Ambient();

  @override
  State<_Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<_Ambient> {
  final _controller = MotionController(autoplay: false);
  var _running = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _running = !_running);
    if (_running) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_running) {
      _controller.progress = context.knobs.double('t', 0.5, min: 0, max: 1);
    }

    return MotionScope(
      motion: ambientMotion,
      controller: _controller,
      builder: (m) {
        var dot = m.target('dot');
        var ring = m.target('ring');
        var label = m.target('label');

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Scaffold(
            backgroundColor: _ground,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.scale(
                          scale: ring.scale,
                          child: Opacity(
                            opacity: ring.opacity,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: _live, width: 2),
                              ),
                            ),
                          ),
                        ),
                        Transform.scale(
                          scale: dot.scale,
                          child: Opacity(
                            opacity: dot.opacity,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                color: _live,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: label.opacity,
                    child: const Text(
                      'Recording',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 14,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w500,
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

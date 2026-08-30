import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/previews.dart';

import 'motion_signin.motion.dart';
import 'motion_signin.stage.dart';
import 'shell.dart';

/// A motion over widgets that actually work — the fields take focus and text
/// while the animation is mid-flight.
///
/// Written to test the claim that a slot can be bound to a real element rather
/// than a placeholder. It can, and the demo splits cleanly in two:
///
/// - **Imposed** (`opacity`, `translateY`, `scale`, `elevation`) — a wrapper
///   applies them and `TextFormField` never learns it was animated. Any widget
///   would do; the motion does not know what it is moving.
/// - **Intrinsic** (`color`) — nothing outside a `TextFormField` can recolour
///   its fill, so the value only lands because this build method reads it and
///   hands it to an `InputDecoration`.
///
/// `password.color` is animated and **not** read, on purpose. It is a live lane
/// that changes nothing, invisible to any amount of staring at the file.
///
/// The scope carries a `stage:` beside its `builder:`, so the studio's
/// Draft/Real switch drives this file with nothing in it to say so. Both
/// bodies sit **inside one `MotionScope`** — the flip is a choice of body
/// rather than a teardown, one playhead drives both, and the two halves cannot
/// drift because there is only one motion.
///
/// Flip to Draft at `t = 0.75` and watch the password field: grey here, pink
/// there. That is `password.color` imposed on a box the tool owns and merely
/// offered to a widget that never reads it.
///
/// Drag `t` to scrub, tap the background to replay.
@Preview(name: 'Sign in (real fields)', group: 'Motion', wrapper: wrapInApp)
Widget motionSignIn() => const _SignIn();

const _ground = Color(0xFFF7F8FA);
const _ink = Color(0xFF14171A);
const _muted = Color(0xFF6B7280);
const _brand = Color(0xFF2563EB);

class _SignIn extends StatefulWidget {
  const _SignIn();

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
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
      motion: signInMotion,
      stage: signInStage,
      controller: _controller,
      builder: (m) {
        var title = m.target('title');
        var email = m.target('email');
        var password = m.target('password');
        var cta = m.target('cta');

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _controller.play(restart: true),
          child: Scaffold(
            backgroundColor: _ground,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Opacity(
                          opacity: title.opacity,
                          child: Transform.translate(
                            offset: Offset(0, title.translateY),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome back',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.3,
                                    color: _ink,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Sign in to continue',
                                  style: TextStyle(fontSize: 13, color: _muted),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Imposed properties wrap it; the intrinsic one is
                        // handed in. A real field either way.
                        _Field(
                          target: email,
                          label: 'Email',
                          fill: email.color ?? const Color(0xFFEDEFF2),
                        ),
                        const SizedBox(height: 12),

                        // Same wrapper, and `password.color` is never asked
                        // for — so its lane runs and lands nowhere.
                        _Field(
                          target: password,
                          label: 'Password',
                          obscure: true,
                          fill: const Color(0xFFEDEFF2),
                        ),
                        const SizedBox(height: 20),

                        Opacity(
                          opacity: cta.opacity,
                          child: Transform.scale(
                            scale: cta.scale,
                            child: FilledButton(
                              onPressed: () {},
                              style: FilledButton.styleFrom(
                                backgroundColor: _brand,
                                elevation: cta.elevation,
                                minimumSize: const Size.fromHeight(46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Continue'),
                            ),
                          ),
                        ),
                      ],
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
}

class _Field extends StatelessWidget {
  const _Field({
    required this.target,
    required this.label,
    required this.fill,
    this.obscure = false,
  });

  final MotionTarget target;
  final String label;
  final Color fill;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: target.opacity,
      child: Transform.translate(
        offset: Offset(0, target.translateY),
        child: TextFormField(
          obscureText: obscure,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }
}

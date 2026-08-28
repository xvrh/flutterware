import 'package:flutter/material.dart';
import 'package:flutterware/motion.dart';

import 'fuse_label.dart';
import 'onboarding_page.motion.dart';
import 'onboarding_wave.dart';

/// One onboarding page's **presentation**, with its content as props.
///
/// This is the shape the editor would author: layout, timing and styling live
/// here, and every piece of content — the image, the words, the control at the
/// bottom — is handed in at the use site. A developer writes this three times
/// with their own strings and their own widgets; a video renderer writes it
/// once with injected parameters and evaluates it frame by frame.
///
/// The rules it was written under, and did not break:
///
/// - Flex layout only. No `Positioned`, no hard-coded x/y. `Align` with a
///   fractional alignment is the strongest positioning used.
/// - Animation only through `onboarding_page.motion.dart`. No
///   `AnimationController`, no `Tween`, no `Interval` computed by hand.
/// - Every varying value is either a target property or a prop.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.image,
    required this.titleLeft,
    required this.titleRight,
    required this.subtitle,
    required this.action,
    required this.progress,
    required this.accent,
  });

  /// The photograph, as a slot. The tool never owns this.
  final Widget image;

  /// The two halves of the headline. Two strings, not one split — so a
  /// translator sees both and word order is theirs to decide.
  final String titleLeft;
  final String titleRight;

  final String subtitle;

  /// The control at the bottom: a button on the first pages, a real
  /// `TextFormField` and a submit on the last. A slot, so it stays live.
  final Widget action;

  /// 0..1 through this page's entrance.
  final double progress;

  final Color accent;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = MotionController(autoplay: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller.progress = widget.progress.clamp(0.0, 1.0);

    return MotionScope(
      motion: onboardingPageMotion,
      controller: _controller,
      builder: (m) {
        var depth = m.target('waveDepth').progress;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                // FAKE (units): resolving "9% of the height" needs the box, so
                // anything unit-aware has to sit under one of these. A tool
                // emitting unit-tagged values would have to insert them.
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipPath(
                      clipper: WaveClip(
                        amplitude: depth,
                        phase: m.target('wave').progress,
                      ),
                      child: MotionBox(m.target('image'), child: widget.image),
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          0,
                          24,
                          constraints.maxHeight * depth + 16,
                        ),
                        child: FuseLabel(
                          left: widget.titleLeft,
                          right: widget.titleRight,
                          // The nested timeline's window, in Dart rather than
                          // in a values file: this page's first 80% drives the
                          // whole of the fuse.
                          progress: (widget.progress / 0.8).clamp(0.0, 1.0),
                          glow: widget.accent,
                          style: const TextStyle(
                            fontSize: 38,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MotionBox(
                    m.target('subtitle'),
                    child: Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  MotionBox(m.target('action'), child: widget.action),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/previews.dart';

import 'fuse_label.motion.dart';

/// The fuse on its own, which is how a reusable animation wants to be worked
/// on: its own entry, its own playhead, nothing else on screen to explain a
/// mistake away.
///
/// It is also what makes it capturable at all — `motion filmstrip` finds a
/// motion through an entry in the same file, so a component whose file has no
/// entry cannot be photographed.
@Preview(name: 'Fuse label', group: 'Motion', wrapper: onInk)
Widget fuseLabelPreview() => Builder(
  builder: (context) => Center(
    child: FuseLabel(
      left: context.knobs.string('left', 'Find your'),
      right: context.knobs.string('right', 'morning'),
      progress: context.knobs.double('t', 1, min: 0, max: 1),
      glow: const Color(0xFFFF8A4C),
      style: const TextStyle(
        fontSize: 38,
        height: 1.05,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
        color: Colors.white,
      ),
    ),
  ),
);

Widget onInk(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(backgroundColor: const Color(0xFF0C0913), body: child),
);

/// Two strings that arrive from opposite sides and fuse into one line.
///
/// A **nested, parameterised animation**: it takes its content as props, owns
/// its own timeline, and is driven by whatever progress its host hands it. The
/// page below neither knows nor sets its timing.
///
/// Taking two strings rather than splitting one is what makes it translatable.
/// A split derived from the laid-out string would be authored in English and
/// wrong in German; two strings are two entries a translator can see.
///
/// FAKE (nesting): the host maps time by writing [progress] into a controller
/// this widget owns. A real nested motion would declare the time window in the
/// parent's values file, where an editor could drag it. Here the window is
/// `OnboardingPage`'s Dart, so it cannot be tuned without editing code.
class FuseLabel extends StatefulWidget {
  const FuseLabel({
    super.key,
    required this.left,
    required this.right,
    required this.progress,
    required this.style,
    required this.glow,
  });

  final String left;
  final String right;

  /// 0..1 through this component's own timeline.
  final double progress;

  final TextStyle style;

  /// The colour both shadow layers are drawn in.
  final Color glow;

  @override
  State<FuseLabel> createState() => _FuseLabelState();
}

class _FuseLabelState extends State<FuseLabel> {
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
      motion: fuseMotion,
      controller: _controller,
      // FOUND, then fixed: two halves that fuse must sit side by side, and a
      // `Row` cannot wrap — so a German headline overflowed by 35px with
      // Flutter's yellow stripe rather than degrading. Two strings solved
      // translation for *content* and broke it for *layout*.
      //
      // Auto-fit is the fix, and it is a presentation policy the tool owns
      // rather than something a caller should have to think about. It is also
      // only safe because animation never touches layout: the halves are moved
      // by `Transform`, which does not change the row's width, so the fit is
      // computed once and the text does not breathe through the entrance.
      builder: (m) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            MotionBox(
              m.target('left'),
              child: _Layered(
                text: widget.left,
                style: widget.style,
                glow: widget.glow,
                motion: m,
              ),
            ),
            // The halves are laid out independently, so the join is an authored
            // gap rather than a real space. At this size it reads as a space; on
            // a fuse that has to close completely it would have to be a value.
            SizedBox(width: widget.style.fontSize! * 0.28),
            MotionBox(
              m.target('right'),
              child: _Layered(
                text: widget.right,
                style: widget.style,
                glow: widget.glow,
                motion: m,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One word, painted three times.
///
/// The two copies behind it are elements with their own offsets, blurs and
/// opacities — which is the whole reason this is a stack of widgets rather than
/// `TextStyle.shadows`. A shadow inside a text style is one frozen list; these
/// are two things the timeline can move independently.
class _Layered extends StatelessWidget {
  const _Layered({
    required this.text,
    required this.style,
    required this.glow,
    required this.motion,
  });

  final String text;
  final TextStyle style;
  final Color glow;
  final Motion motion;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        for (var layer in const ['glowB', 'glowA'])
          MotionBox(
            motion.target(layer),
            child: Text(text, style: style.copyWith(color: glow)),
          ),
        Text(text, style: style),
      ],
    );
  }
}

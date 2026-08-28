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
      position: context.knobs.double('position', 0, min: -1, max: 1),
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

/// Two lines that cross, settle, and carry on the way they were going.
///
/// A **nested, parameterised animation**: it takes its content as props, owns
/// its own timeline, and is driven by whatever position its host hands it. The
/// page neither knows nor sets its timing.
///
/// The two lines sit on **different rows**, travel in opposite directions, and
/// pass each other rather than meeting end to end. That is what makes the whole
/// thing work under translation: each line is laid out on its own, so a long
/// German line wraps or shrinks without the other one caring. The earlier
/// side-by-side version needed a `Row`, a `Row` cannot wrap, and German
/// overflowed by 35px.
///
/// Taking two strings rather than splitting one is what makes it translatable
/// at all. A split derived from the laid-out string would be authored in
/// English and wrong in German; two strings are two entries a translator sees.
///
/// FAKE (nesting): the host maps position by writing [position] into a
/// controller this widget owns. A real nested motion would declare the mapping
/// in the parent's values file, where an editor could drag it. Here it is
/// `OnboardingPage`'s Dart, so it cannot be tuned without editing code.
class FuseLabel extends StatefulWidget {
  const FuseLabel({
    super.key,
    required this.left,
    required this.right,
    required this.position,
    required this.style,
    required this.glow,
    this.indent = 0.22,
  });

  /// The line that enters from the left and leaves to the right.
  final String left;

  /// The line that enters from the right and leaves to the left.
  final String right;

  /// **Signed**, -1 to 1. Zero is the settled reading moment; the ends are off
  /// the page. A host hands in where its page sits relative to the viewport,
  /// which is a position rather than a progress — the sign is what tells the
  /// two lines which way they are already travelling.
  final double position;

  /// How far the second line is inset, as a fraction of the first line's width.
  /// Static layout, not animated: it is what makes the settled frame read as a
  /// designed two-line headline rather than two centred strings.
  final double indent;

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
    _controller.progress = ((widget.position + 1) / 2).clamp(0.0, 1.0);

    return MotionScope(
      motion: fuseMotion,
      controller: _controller,
      // Two rows, not one. Each line lays out on its own, so a long German
      // line wraps or shrinks without touching the other — the side-by-side
      // version needed a `Row`, a `Row` cannot wrap, and German overflowed by
      // 35px with Flutter's yellow stripe.
      //
      // Each line still auto-fits, which is a presentation policy the tool
      // owns rather than something a caller thinks about. `AutoSizeText` is
      // the production answer; `FittedBox` avoids adding a package to the
      // workspace for a validation demo. Either is only safe because animation
      // never touches layout — the lines are moved by `Transform`, so the fit
      // is computed once and the text does not breathe as it travels.
      builder: (m) => LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MotionBox(
              m.target('left'),
              child: _Line(
                text: widget.left,
                style: widget.style,
                glow: widget.glow,
                motion: m,
                maxWidth: constraints.maxWidth,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: constraints.maxWidth * widget.indent,
              ),
              child: MotionBox(
                m.target('right'),
                child: _Line(
                  text: widget.right,
                  style: widget.style,
                  glow: widget.glow,
                  motion: m,
                  maxWidth: constraints.maxWidth * (1 - widget.indent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line, painted three times.
///
/// The two copies behind it are elements with their own offsets, blurs and
/// opacities — which is the whole reason this is a stack of widgets rather than
/// `TextStyle.shadows`. A shadow inside a text style is one frozen list; these
/// are two things the timeline can move independently.
class _Line extends StatelessWidget {
  const _Line({
    required this.text,
    required this.style,
    required this.glow,
    required this.motion,
    required this.maxWidth,
  });

  final String text;
  final TextStyle style;
  final Color glow;
  final Motion motion;

  /// What this line has to fit into. The shrink happens per line, so a long
  /// German first line does not shrink a short second one.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Computed target names, which the scan cannot see: `motion list`
            // reports this component's targets as `left` and `right` only, and
            // the two glow layers are invisible to it. The same hole as
            // `m.target('row$i')`, met again in ordinary code.
            for (var layer in const ['glowB', 'glowA'])
              MotionBox(
                motion.target(layer),
                child: Text(
                  text,
                  maxLines: 1,
                  style: style.copyWith(color: glow),
                ),
              ),
            Text(text, maxLines: 1, style: style),
          ],
        ),
      ),
    );
  }
}

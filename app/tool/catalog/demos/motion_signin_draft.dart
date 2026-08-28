import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/previews.dart';

import 'motion_signin.motion.dart';
import 'motion_signin.stage.dart';
import 'motion_stage.dart';
import 'shell.dart';

/// **Prototype.** `signInMotion` on a draft stage — the same values file that
/// drives `motion_signin.dart`'s real `TextFormField`s, with placeholders in
/// their place.
///
/// Put the two side by side. Nothing in `motion_signin.motion.dart` changed,
/// and nothing in it knows which host it landed in, which is the property the
/// whole draft-then-bind idea rests on.
///
/// Two differences are worth looking for rather than reading about:
///
/// - `password.color` animates **here** and does nothing in the real screen.
///   The tool owns this box, so it can impose a fill; a `TextFormField` has to
///   be handed one. A lane tuned on the draft can go silent on the bind, and
///   no amount of staring at either file says so.
/// - `cta.elevation` draws a shadow here because the placeholder chooses to
///   read it. On the real screen the `FilledButton` takes it as a parameter.
///   Same lane, two mechanisms, and only one of them is automatic.
///
/// Drag `t` to scrub, tap to replay.
@Preview(name: 'Sign in (draft stage)', group: 'Motion', wrapper: wrapInApp)
Widget motionSignInDraft() => const _Draft();

class _Draft extends StatefulWidget {
  const _Draft();

  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  final _controller = MotionController(autoplay: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller.progress = context.knobs.double('t', 1, min: 0, max: 1);
    var names = context.knobs.bool('names', true);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _controller.play(restart: true),
      child: Scaffold(
        backgroundColor: const Color(0xFFE9ECF0),
        body: MotionStageView(
          stage: signInStage,
          motion: signInMotion,
          controller: _controller,
          showNames: names,
        ),
      ),
    );
  }
}

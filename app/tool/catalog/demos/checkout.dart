import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/previews.dart';

import 'checkout.motion.dart';
import 'checkout.stage.dart';

/// Written by `fw run motion new`. Yours from here.
///
/// It has only the draft stage, because there is nothing real to bind to yet.
/// Give the scope a `builder` when there is, and the studio's Draft/Real switch
/// appears on its own — the same motion drives both, so it is a rehearsal of
/// the screen rather than a second drawing of it.
@Preview(name: 'checkout', group: 'Motion')
Widget checkout() => const _Checkout();

class _Checkout extends StatefulWidget {
  const _Checkout();

  @override
  State<_Checkout> createState() => _CheckoutState();
}

class _CheckoutState extends State<_Checkout> {
  final _controller = MotionController(autoplay: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller.progress = context.knobs.double('t', 1, min: 0, max: 1);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _controller.play(restart: true),
      child: Scaffold(
        backgroundColor: const Color(0xFFE9ECF0),
        body: MotionScope(
          motion: checkoutMotion,
          stage: checkoutStage,
          controller: _controller,
          // Your screen goes here. Read the same targets the stage stands in
          // for — `m.target('first')` — and nothing else has to change.
          //
          // builder: (m) => MotionBox(m.target('first'), child: ...),
        ),
      ),
    );
  }
}

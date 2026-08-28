import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/previews.dart';

import 'checkout.motion.dart';
import 'checkout.stage.dart';

/// Written by `fw run motion new`. Yours from here.
///
/// It opens on the draft stage, because there is nothing real to bind to yet.
/// When there is, put the real screen in `_real` and the `host` knob switches
/// between them — the same motion drives both.
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

    var host = context.knobs.picker('host', {
      'Draft': 'draft',
      'Real': 'real',
    }, 'draft');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _controller.play(restart: true),
      child: Scaffold(
        backgroundColor: const Color(0xFFE9ECF0),
        // One scope, two bodies. The switch keeps the playhead, because `t`
        // lives on the scope rather than on either host.
        body: MotionScope(
          motion: checkoutMotion,
          controller: _controller,
          builder: (m) => switch (host) {
            'real' => _real(m),
            _ => MotionStageView(
              stage: checkoutStage,
              motion: m,
              showNames: context.knobs.bool('names', true),
            ),
          },
        ),
      ),
    );
  }

  /// Your screen goes here. Read the same targets the stage stands in for —
  /// `m.target('first')` — and the draft becomes a rehearsal of the real thing
  /// rather than a separate drawing of it.
  Widget _real(Motion m) => const Center(
    child: Text('Nothing bound yet. Flip `host` back to Draft.'),
  );
}

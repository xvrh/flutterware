import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/previews.dart';

import 'motion_inbox.motion.dart';
import 'shell.dart';

/// A staggered list — the shape `motion_receipt.dart` names and refuses:
/// *"a stagger of four identical rows is four copies of the same numbers, and
/// is a thing to generate, not a thing to hand-write."*
///
/// Written anyway, because the refusal was right and the cost of being right
/// is worth measuring. One entrance, five rows, 70ms apart. The build method
/// says it once in a loop; the values file says it five times because it has
/// no loop to say it with, and that asymmetry is the whole demo.
///
/// Drag `t` to scrub, tap to replay.
@Preview(name: 'Inbox stagger', group: 'Motion', wrapper: wrapInApp)
Widget motionInbox() => const _Inbox();

const _ground = Color(0xFFF7F8FA);
const _card = Color(0xFFFFFFFF);
const _ink = Color(0xFF14171A);
const _muted = Color(0xFF6B7280);
const _hairline = Color(0xFFE6E9ED);

const _rows = [
  ('Priya Raman', 'Re: shipping estimate for Q3', Color(0xFF2563EB)),
  ('Deploy bot', 'staging is green — 214 passed', Color(0xFF059669)),
  ('Tomas Lind', 'invoice #4471 attached', Color(0xFFD97706)),
  ('Design review', 'three notes on the settings pass', Color(0xFF7C3AED)),
  ('Ana Beltrán', 'lunch thursday?', Color(0xFFDC2626)),
];

class _Inbox extends StatefulWidget {
  const _Inbox();

  @override
  State<_Inbox> createState() => _InboxState();
}

class _InboxState extends State<_Inbox> {
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
      motion: inboxMotion,
      controller: _controller,
      builder: (m) {
        var header = m.target('header');

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _controller.play(restart: true),
          child: Scaffold(
            backgroundColor: _ground,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Opacity(
                          opacity: header.opacity,
                          child: Transform.translate(
                            offset: Offset(0, header.translateY),
                            child: const Text(
                              'Inbox',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.4,
                                color: _ink,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // The build method says the stagger once. The values
                        // file next door says it five times.
                        for (var i = 0; i < _rows.length; i++) ...[
                          _Row(target: m.target('row$i'), data: _rows[i]),
                          if (i < _rows.length - 1) const SizedBox(height: 10),
                        ],
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

class _Row extends StatelessWidget {
  const _Row({required this.target, required this.data});

  final MotionTarget target;
  final (String, String, Color) data;

  @override
  Widget build(BuildContext context) {
    var (name, line, tint) = data;

    return Opacity(
      opacity: target.opacity,
      child: Transform.translate(
        offset: Offset(0, target.translateY),
        child: Transform.scale(
          scale: target.scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _hairline),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    name.characters.first,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: _muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

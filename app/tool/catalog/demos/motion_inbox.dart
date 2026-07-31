import 'package:flutter/material.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/ui_catalog.dart';

import 'motion_inbox.motion.dart';
import 'shell.dart';

/// A staggered entrance, written the way a screen actually gets written.
///
/// This is the `MotionBox` half of the demonstration: every element wears one,
/// nothing here computes a transform, and the six anchors below are the entire
/// wiring. Its counterpart, `motion_player.dart`, uses no `MotionBox` at all
/// and reads every property at the call site — between them they cover the
/// whole of the API.
///
/// The numbers live in `motion_inbox.motion.dart` and nowhere else. Delete
/// that file and this screen still builds, still lays out, and simply does not
/// move: every property falls back to its resting value.
///
/// **Drag `t` to scrub, tap to play.** The knob stands in for the Motion
/// panel's playhead until the panel exists — which is also the honest statement
/// of what the runtime already guarantees, since a motion is a pure function of
/// `t` and the knob is the only proof of that anybody needs.
@Demo(name: 'Inbox entrance', group: 'Motion', wrapper: wrapInApp)
Widget motionInbox() => const _Inbox();

// A palette, not a theme: the demo states its own colours so that what you see
// is what the timing was tuned against.
const _porcelain = Color(0xFFF2F4F3);
const _card = Color(0xFFFFFFFF);
const _ink = Color(0xFF15181B);
const _muted = Color(0xFF697079);
const _hairline = Color(0xFFE1E5E4);
const _garnet = Color(0xFFB23A48);

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
    // Writing the playhead from a knob is the whole integration. Tapping does
    // not rebuild this widget, so a tap-to-play is not immediately clobbered by
    // the knob on the next frame.
    _controller.progress = context.uiCatalog.parameters.double(
      't',
      1,
      min: 0,
      max: 1,
    );

    return MotionScope(
      motion: inboxMotion,
      controller: _controller,
      builder: (m) {
        var header = m.anchor('header');
        var search = m.anchor('search');
        var fab = m.anchor('fab');

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _controller.play(restart: true),
          child: Scaffold(
            backgroundColor: _porcelain,
            body: SafeArea(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 96),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 10,
                          children: [
                            MotionBox(
                              header,
                              origin: Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TUESDAY',
                                    style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 1.4,
                                      fontWeight: FontWeight.w600,
                                      color: _muted,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Inbox',
                                    style: TextStyle(
                                      // A call-site read: `fontSize` is not one
                                      // of the eight a MotionBox applies, and
                                      // that is the signal it is doing
                                      // something structural.
                                      fontSize: header.fontSize ?? 27,
                                      height: 1.1,
                                      fontWeight: FontWeight.w700,
                                      color: _ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            MotionBox(
                              search,
                              child: _SearchField(radius: search.borderRadius),
                            ),
                            const SizedBox(height: 2),
                            for (var (index, message) in _messages.indexed)
                              MotionBox(
                                m.anchor('msg${index + 1}'),
                                child: _MessageRow(message),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 26,
                    child: MotionBox(fab, child: _Compose(fab)),
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

class _SearchField extends StatelessWidget {
  const _SearchField({required this.radius});

  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(radius ?? 13),
        border: Border.all(color: _hairline),
      ),
      child: const Row(
        spacing: 10,
        children: [
          Icon(Icons.search_rounded, size: 18, color: _muted),
          Text('Search', style: TextStyle(fontSize: 14, color: _muted)),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow(this.message);

  final _Message message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: message.tint,
              shape: BoxShape.circle,
            ),
            child: Text(
              message.initials,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _card,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.from,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            message.at,
            style: const TextStyle(
              fontSize: 11,
              color: _muted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Compose extends StatelessWidget {
  const _Compose(this.anchor);

  final MotionAnchor anchor;

  @override
  Widget build(BuildContext context) {
    // `color` and `elevation` are read here rather than applied by the box: one
    // is a paint, the other is a shadow this widget composes itself.
    var elevation = anchor.elevation;
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: anchor.color ?? _garnet,
        shape: BoxShape.circle,
        boxShadow: shadowFor(elevation, _garnet),
      ),
      child: const Icon(Icons.edit_outlined, size: 22, color: _card),
    );
  }
}

/// One `elevation` number, two shadows — the near one for contact, the far one
/// for lift. Kept out of the widgets so both demos read it the same way.
List<BoxShadow> shadowFor(double elevation, Color tint) {
  if (elevation <= 0) return const [];
  return [
    BoxShadow(
      color: tint.withValues(alpha: 0.16),
      blurRadius: elevation * 1.8,
      offset: Offset(0, elevation * 0.6),
    ),
    BoxShadow(
      color: tint.withValues(alpha: 0.10),
      blurRadius: elevation * 0.6,
      offset: Offset(0, elevation * 0.15),
    ),
  ];
}

class _Message {
  const _Message(this.initials, this.from, this.preview, this.at, this.tint);

  final String initials;
  final String from;
  final String preview;
  final String at;
  final Color tint;
}

const _messages = [
  _Message(
    'RK',
    'Rosa Kelleher',
    'The pressing plant moved the date — we have until Friday.',
    '9:41',
    Color(0xFFB23A48),
  ),
  _Message(
    'TN',
    'Tomás Nyari',
    'Sleeve proofs attached. The spine text is 1pt off.',
    '9:12',
    Color(0xFF3F5E52),
  ),
  _Message(
    'JD',
    'June Dahl',
    'Rehearsal room is booked Thursday, 6 til late.',
    '8:30',
    Color(0xFF7A5C3E),
  ),
  _Message(
    'MO',
    'Mikkel Ø.',
    'Sent the stems. Track 4 still clips on the master bus.',
    'Mon',
    Color(0xFF44506B),
  ),
];

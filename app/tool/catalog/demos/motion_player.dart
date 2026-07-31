import 'package:flutter/material.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/ui_catalog.dart';

import 'motion_inbox.dart' show shadowFor;
import 'motion_player.motion.dart';
import 'shell.dart';

/// A card that blooms into a player, and the counterpart to
/// `motion_inbox.dart`.
///
/// **There is not one `MotionBox` in this file.** Every property is read at the
/// site that uses it — `art.width` on a `SizedBox`, `sheet.color` on a
/// `BoxDecoration`, `reveal.progress` on an `Align.heightFactor` — which is the
/// half of the API that has to hold up before the convenience wrapper is worth
/// anything. Seven anchors, twenty tuned properties, and no transform maths
/// anywhere: the properties the box would have applied are exactly the ones it
/// turned out not to need here.
///
/// **Drag `t` to scrub, tap to expand or collapse.** Expanding and collapsing
/// are the same numbers read forwards and backwards, so there is no second
/// state to keep in sync — which is the practical consequence of a motion being
/// a pure function of `t`.
@Demo(name: 'Player bloom', group: 'Motion', wrapper: wrapInApp)
Widget motionPlayer() => const _Player();

const _ground = Color(0xFF12141A);
const _paper = Color(0xFFF0EDE8);
const _muted = Color(0xFF8B929B);
const _rail = Color(0xFF3A424E);
const _amber = Color(0xFFE0A33E);
const _rust = Color(0xFFC2483D);

class _Player extends StatefulWidget {
  const _Player();

  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  final _controller = MotionController(autoplay: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_controller.progress >= 1) {
      _controller.reverse();
    } else {
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    _controller.progress = context.uiCatalog.parameters.double(
      't',
      1,
      min: 0,
      max: 1,
    );

    return MotionScope(
      motion: playerMotion,
      controller: _controller,
      builder: (m) {
        var glow = m.anchor('glow');
        var sheet = m.anchor('sheet');

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          // A `Scaffold`, not a `ColoredBox`: without a `Material` above it
          // every `Text` here inherits the style `MaterialApp` installs for
          // exactly that mistake, and the first render of this demo came back
          // yellow-underlined rather than wrong in any way the code showed.
          child: Scaffold(
            backgroundColor: _ground,
            body: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: glow.scale,
                    child: Opacity(
                      opacity: glow.opacity,
                      child: Container(
                        width: 460,
                        height: 460,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [Color(0x59C2483D), Color(0x00C2483D)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: EdgeInsets.all(sheet.padding),
                      decoration: BoxDecoration(
                        color: sheet.color ?? const Color(0xFF1A1F26),
                        borderRadius: BorderRadius.circular(
                          sheet.borderRadius ?? 20,
                        ),
                        boxShadow: shadowFor(sheet.elevation, Colors.black),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Cover(m.anchor('art')),
                          const SizedBox(height: 14),
                          _Titles(
                            title: m.anchor('title'),
                            artist: m.anchor('artist'),
                          ),
                          _Reveal(
                            anchor: m.anchor('reveal'),
                            child: _Controls(m.anchor('play')),
                          ),
                        ],
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

class _Cover extends StatelessWidget {
  const _Cover(this.anchor);

  final MotionAnchor anchor;

  @override
  Widget build(BuildContext context) {
    var size = anchor.width ?? 64;
    var radius = BorderRadius.circular(anchor.borderRadius ?? 14);
    return Transform.rotate(
      angle: anchor.rotate,
      child: Container(
        width: size,
        height: anchor.height ?? size,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: shadowFor(anchor.elevation, Colors.black),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_rust, _amber],
              ),
            ),
            // A cover, not a coloured square: the disc is what makes the growth
            // legible, because a plain gradient scaling up looks like nothing
            // moved at all.
            child: FractionallySizedBox(
              alignment: const Alignment(0.45, -0.4),
              widthFactor: 0.5,
              heightFactor: 0.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _paper.withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Titles extends StatelessWidget {
  const _Titles({required this.title, required this.artist});

  final MotionAnchor title;
  final MotionAnchor artist;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Nightjar',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: title.fontSize ?? 15,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: _paper,
          ),
        ),
        const SizedBox(height: 4),
        Opacity(
          opacity: artist.opacity,
          child: Text(
            'Hollow Coves',
            style: TextStyle(fontSize: artist.fontSize ?? 12, color: _muted),
          ),
        ),
      ],
    );
  }
}

/// The lower half, revealed by a number that means nothing until here.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.anchor, required this.child});

  final MotionAnchor anchor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: anchor.progress,
        child: Opacity(
          opacity: anchor.opacity,
          child: Transform.translate(
            offset: Offset(0, anchor.translateY),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls(this.play);

  final MotionAnchor play;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Scrubber(),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 22,
            children: [
              const Icon(Icons.skip_previous_rounded, size: 26, color: _muted),
              Transform.scale(
                scale: play.scale,
                child: Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: play.color ?? _rail,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 30,
                    color: Color(0xFF12141A),
                  ),
                ),
              ),
              const Icon(Icons.skip_next_rounded, size: 26, color: _muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: const LinearProgressIndicator(
            value: 0.38,
            minHeight: 3,
            backgroundColor: _rail,
            valueColor: AlwaysStoppedAnimation(_paper),
          ),
        ),
        const SizedBox(height: 7),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '1:24',
              style: TextStyle(
                fontSize: 11,
                color: _muted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              '-2:17',
              style: TextStyle(
                fontSize: 11,
                color: _muted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

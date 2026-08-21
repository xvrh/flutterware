/// What the preview sits *on*, and what marks where it ends.
///
/// The problem this solves: staged as a phone, the guest reads as a separate
/// app, because the silhouette turns it into an object sitting on a
/// ground. Staged as `Fit` — or as a phone with the body switched off — it read
/// as another page of the studio: same white, same design system, edges flush
/// with the pane's own chrome, and a demo's `Reload` button two pixels from a
/// real one.
///
/// So the device body is not the trick, it is one instance of the trick. The
/// rule underneath it is that **the guest is never the pane's background**:
/// there is always a ground, and the picture always has an edge.
///
/// Four other looks were built and photographed against this one — a dot grid,
/// a checkerboard, print crop marks, and the flush original. Nothing here
/// switches between them any more: the grid and the checkerboard have nowhere
/// to live in `Fit`, where the ground is a 12px margin, and the crop marks go
/// invisible in dark against a ground that is *lighter* than the pane.
library;

import 'package:flutter/material.dart';

import '../ui/design/design.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';

/// How far the guest is held off the pane's edges.
///
/// A constant rather than a literal at each site because two of them have to
/// agree: the stage pads by it, and in `Fit` the guest is told to render the
/// size that padding leaves.
const stageInset = FwSpacing.lg;

/// The recessed surface a preview sits on.
///
/// Derived rather than a token: the palette has no "ground" step, and its two
/// candidates do not survive both themes — light `panel2` (#fbfbfa) is
/// *lighter* than `panel`, so a ground made of it disappears against the white
/// it is supposed to sit behind. Blending ink into the panel moves the right
/// way in both.
///
/// How deep. 5.5% was the first guess and it measured `#EBECEE` — a real
/// step, and invisible in use: against a 393pt white phone the eye reads the
/// whole stage as white and the margin as a rendering artefact. A ground has to
/// be as far below the specimen as the specimen is above it, which is where
/// every canvas that works sits — roughly a tenth of ink between the two.
Color stageGroundColor(FwPalette colors) =>
    Color.alphaBlend(colors.ink.withValues(alpha: 0.10), colors.panel);

/// Paints the ground behind the whole stage.
///
/// Outside the zoom transform, so the specimen moves over the ground rather
/// than dragging it along — magnifying is leaning towards the phone, and a
/// table that leaned with it would say the opposite.
class StageGround extends StatelessWidget {
  const StageGround({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GroundPainter(stageGroundColor(context.colors)),
    child: child,
  );
}

/// The edge around the guest's own pixels, and the only thing on screen that
/// says where the keyboard is going.
///
/// Drawn only where nothing else already draws one: a device body *is* this,
/// and a border inside a silhouette would be a second frame a millimetre in.
///
/// `foregroundDecoration` for the border, not a clip. The child is a
/// `Texture` — an external layer — and painting the line over its edge asks
/// nothing of the compositor, where clipping it to a rounded rect asks
/// something that has to be verified per platform.
class StageSpecimen extends StatelessWidget {
  const StageSpecimen({super.key, required this.focus, required this.child});

  /// The node the guest's input region focuses on a click. The edge turns
  /// accent while it holds focus, which is the same line doing a second job:
  /// otherwise the only way to find out where your keystrokes are going is to
  /// type and see.
  final FocusNode focus;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    // **The release, which the guest cannot do for itself.** Its input region
    // requests focus on pointer-down and nothing in the studio ever takes it
    // back — no panel control is focusable — so a node focused once stayed
    // focused until the panel was torn down, and the ring was permanently lit:
    // true, and useless for being true of everything.
    //
    // A `TapRegion` rather than a listener at the panel's root: the question is
    // whether the press landed on the picture, which is exactly what a region
    // knows, and which a root listener would have to work out from a rect that
    // moves with every zoom, pan and device change.
    return TapRegion(
      onTapOutside: (_) {
        if (focus.hasFocus) focus.unfocus();
      },
      child: ListenableBuilder(
        listenable: focus,
        // The picture passed through rather than rebuilt: what a focus change
        // moves is one colour, and rebuilding the texture underneath it for
        // that would drop the guest's frame on every click.
        child: child,
        builder: (context, child) => Container(
          decoration: BoxDecoration(boxShadow: context.elevation.sm),
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: focus.hasFocus ? colors.accent : colors.line,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The one control the keyboard has: a key that takes it away.
///
/// Drawn by the host, over the guest's own pixels, and that split is the
/// design rather than an accident of where it was easy to put. The slab is
/// inside the guest so that every capture already contains a keyboard; this is
/// a tool affordance, and a tool affordance inside the guest would be in every
/// screenshot, every thumbnail and every web export of a demo that has nothing
/// to do with the studio.
///
/// It sits in the picture's own coordinates rather than the panel's, so it
/// scales with the specimen: magnify the stage and the key grows with the
/// keyboard it is on, which is what it would do if it were painted there.
///
/// Pressing it is not a mode change. [onDismiss] tells the guest its text
/// input connection went away — what a platform sends when the user closes the
/// IME without touching the app — so the field unfocuses and the keyboard
/// comes down *because the view dismissed it*. Making the artwork vanish
/// instead would be a keyboard the app never noticed leaving.
class StageKeyboardDismiss extends StatelessWidget {
  const StageKeyboardDismiss({
    super.key,
    required this.band,
    required this.onDismiss,
    required this.child,
  });

  /// How tall the keyboard is on screen, in the picture's logical pixels. Zero
  /// draws nothing at all — not a disabled key, nothing.
  final double band;

  final VoidCallback onDismiss;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (band <= 0) return child;
    // Proportional to the band, because the band is a measurement: the same
    // key on an iPhone SE's 260 points and an iPad Pro's 501 has to be the
    // same fraction of a keyboard, not the same number of pixels.
    var size = (band * 0.13).clamp(18.0, 34.0);
    var inset = size * 0.4;
    return Stack(
      children: [
        child,
        Positioned(
          right: inset,
          bottom: inset,
          child: Tooltip(
            message: 'Dismiss the keyboard',
            child: Tappable(
              onTap: onDismiss,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  // Its own ink and its own ground rather than the theme's:
                  // this is drawn over a keyboard whose colours come from the
                  // *staged* platform, which has no idea what the studio's
                  // palette is doing.
                  color: const Color(0xCC1F2023),
                  borderRadius: BorderRadius.circular(size * 0.25),
                ),
                child: Icon(
                  Icons.keyboard_hide,
                  size: size * 0.62,
                  color: const Color(0xFFFFFFFF),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GroundPainter extends CustomPainter {
  _GroundPainter(this.fill);

  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_GroundPainter old) => old.fill != fill;
}

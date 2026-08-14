import 'dart:math';

import 'package:flutter/widgets.dart';

/// The smallest window the shell lays out for.
///
/// **Derived, not chosen.** The densest thing in the app is the dependencies
/// table, whose seven columns declare 800px of minimum width between them
/// (160 + 110 + 120 + 120 + 110 + 90 + 90). Add the sidebar and the panel
/// gutter either side of it — 232 + 24 + 800 + 24 — and 1080 is the width at
/// which the widest panel still fits without scrolling inside itself. The
/// height is what leaves the plugin rail room for its entries and their
/// sub-entries without scrolling.
///
/// Narrow the table's columns and this can narrow with it. It is one number,
/// and it is deliberately the only one.
const shellMinimumSize = Size(1080, 700);

/// Lays its [child] out at [minimumSize] and scales it down to fit whenever the
/// window is smaller, so a shrunken window keeps working rather than
/// overflowing.
///
/// **This is the whole responsive policy.** At or above [minimumSize] the app is
/// ordinary flex; below it everything scales uniformly. There is no third
/// regime — no breakpoints, no columns that disappear, no panes that become
/// drawers — which is what makes "does this panel work?" a question with one
/// answer, checkable at one width.
///
/// The scale is a transform applied when the scene is rasterised, so glyphs are
/// re-rendered at the smaller size rather than resampled from a bitmap: the UI
/// gets smaller, not blurrier.
///
/// The wrappers are always there, at scale 1.0 when there is nothing to scale.
/// Eliding them above the minimum would be cheaper by one render object and
/// wrong: the tree's *shape* would change as a resize crossed the minimum, so
/// every element below would be discarded and rebuilt from nothing — scroll
/// offsets, text fields, controllers, whichever panel was open. A window
/// dragged across 1080px is exactly when that must not happen.
///
/// It overrides the ambient [MediaQuery] with the size the child is *actually*
/// laid out at. Without that, layout would use the pretend size while
/// `MediaQuery.sizeOf` kept reporting the real window, and anything that
/// positions itself against the viewport — a centred overlay, a width clamped
/// to the screen — would be measured against a box it is not in.
class FittedApp extends StatelessWidget {
  const FittedApp({
    super.key,
    required this.child,
    this.minimumSize = shellMinimumSize,
  });

  final Widget child;

  final Size minimumSize;

  @override
  Widget build(BuildContext context) {
    var media = MediaQuery.of(context);
    var size = media.size;

    // A window with no area has no ratio to take; 1.0 keeps the arithmetic off
    // zero and the tree the same shape as every other frame.
    var scale = size.isEmpty
        ? 1.0
        : min(
            1.0,
            min(
              size.width / minimumSize.width,
              size.height / minimumSize.height,
            ),
          );

    // Keeps the window's aspect ratio, so `BoxFit.contain` resolves to exactly
    // [scale] and the child fills the window with nothing letterboxed — and at
    // scale 1.0 it is the window, so the transform is the identity.
    var laidOut = size / scale;
    return MediaQuery(
      data: media.copyWith(size: laidOut),
      child: FittedBox(
        child: SizedBox.fromSize(size: laidOut, child: child),
      ),
    );
  }
}

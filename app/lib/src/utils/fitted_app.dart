import 'dart:math';

import 'package:flutter/widgets.dart';

/// The narrowest pane the shell lays out for, and the floor every window
/// minimum is built up from.
///
/// Derived, not chosen. The densest thing in the app is the dependencies
/// table, whose seven columns declare 800px of minimum width between them
/// (160 + 110 + 120 + 120 + 110 + 90 + 90). Add the panel's own gutter either
/// side of it — 24 + 800 + 24 — and 848 is the width at which the widest panel
/// still fits without scrolling inside itself. The height is what leaves the
/// plugin rail room for its entries and their sub-entries without scrolling.
///
/// A window minimum is this plus whatever chrome the user keeps beside it —
/// the rail's 232 while the sidebar preference is on, nothing once ⌘B turns it
/// off. Only the shell knows which, so the sum is made there: `shellMinimumSize`
/// in `shell_view.dart`. Counting the rail while it is hidden is what used to
/// make ⌘B scale the window at a width it had the room for — but the sum
/// follows the *preference*, not the frame's layout: the worktrees space drops
/// the rail and keeps the minimum, or crossing into it would zoom the window.
///
/// Narrow the table's columns and this can narrow with it. It is one number,
/// and it is deliberately the only one.
const shellPaneMinimumSize = Size(848, 700);

/// Lays its [child] out at [minimumSize] and scales it down to fit whenever the
/// window is smaller, so a shrunken window keeps working rather than
/// overflowing.
///
/// This is the whole responsive policy. At or above [minimumSize] the app is
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
///
/// [minimumSize] may change while the app is running — the shell drops the
/// rail's share of it when ⌘B hides the rail — so a change is animated over
/// [duration]. Hiding the rail at a 900px window takes the scale
/// from 0.83 to 1.0, and 20% arriving in one frame reads as a glitch where a
/// short zoom reads as the room you just asked for. Above the minimum both ends
/// scale at 1.0, so the tween is invisible in the ordinary case rather than
/// something every window pays for.
class FittedApp extends StatelessWidget {
  const FittedApp({
    super.key,
    required this.child,
    this.minimumSize = shellPaneMinimumSize,
    this.duration = const Duration(milliseconds: 150),
  });

  final Widget child;

  final Size minimumSize;

  /// How long a change of [minimumSize] takes to land.
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Size?>(
      tween: SizeTween(end: minimumSize),
      duration: duration,
      curve: Curves.easeOut,
      // The app rides through as `child`: an animating minimum re-lays it out,
      // which is the point, and must not rebuild it, which would be a fresh
      // widget tree every frame of the zoom.
      child: child,
      builder: (context, minimum, child) =>
          _fit(context, minimum ?? minimumSize, child!),
    );
  }

  /// Lays [child] out at [minimum] and scales it to fit the window, where
  /// [minimum] is wherever the tween has got to rather than the target.
  Widget _fit(BuildContext context, Size minimum, Widget child) {
    var media = MediaQuery.of(context);
    var size = media.size;

    // A window with no area has no ratio to take; 1.0 keeps the arithmetic off
    // zero and the tree the same shape as every other frame.
    var scale = size.isEmpty
        ? 1.0
        : min(
            1.0,
            min(size.width / minimum.width, size.height / minimum.height),
          );

    // Keeps the window's aspect ratio, so `BoxFit.contain` resolves to exactly
    // [scale] and the child fills the window with nothing letterboxed — and at
    // scale 1.0 it is the window, so the transform is the identity.
    var laidOut = size / scale;
    return MediaQuery(
      data: media.copyWith(size: laidOut),
      child: AppScale(
        scale: scale,
        child: FittedBox(
          child: SizedBox.fromSize(size: laidOut, child: child),
        ),
      ),
    );
  }
}

/// What [FittedApp] is currently scaling the app by, for the few things that
/// must *not* scale with it.
///
/// The platform's own chrome is drawn on the real window at a real size: the
/// macOS traffic lights are the same 78 logical pixels wide whether the app
/// beneath them is at 1.0 or at 0.7. Anything reserving room for them has to
/// state the measurement in real pixels and divide it by [of], or the band
/// reserving 78 of its own shrunken pixels ends up drawing its tabs underneath
/// buttons it thought it had cleared.
///
/// 1.0 wherever there is no [FittedApp] above — a preview, a test, a panel
/// mounted on its own — so a caller never has to ask whether it is in the app.
class AppScale extends InheritedWidget {
  const AppScale({super.key, required this.scale, required super.child});

  final double scale;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScale>()?.scale ?? 1.0;

  @override
  bool updateShouldNotify(AppScale oldWidget) => oldWidget.scale != scale;
}

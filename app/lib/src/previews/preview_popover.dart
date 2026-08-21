import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/design/design.dart';
import '../ui/loading_state.dart';
import 'catalog_entry.dart';
import 'thumbnails.dart';

///
/// Beside it, rather than on the canvas. The canvas is where a *click*
/// lands, so a hover that changed it read as a commitment nobody made — and it
/// is 500 pixels from the pointer, with nothing between the two to connect
/// them. This is at the hand, it points at the row it belongs to, and it leaves
/// what you actually chose alone.
///
/// It can only exist because the picture is a photograph. There is one embedded
/// guest and one texture, so a *live* preview of another entry is the canvas,
/// necessarily — see [PreviewThumbnails].
class PreviewPopover extends StatelessWidget {
  const PreviewPopover({
    super.key,
    required this.entry,
    required this.anchor,
    required this.thumbnail,
  });

  final CatalogEntry entry;

  /// The row, in global coordinates — which are the root overlay's too.
  final Rect anchor;

  /// What the store has to say about [entry] right now. Null is the frame
  /// between the pointer stopping and the store having been asked.
  ///
  /// Handed in rather than looked up, so this is a pure function of a state —
  /// which is what makes each of its faces an entry in the catalog rather than
  /// something only a running harness can show you.
  final Thumbnail? thumbnail;

  /// Wide enough for a 900-pixel panel to be read at a third of its size, and
  /// narrow enough to leave the canvas behind it recognisable.
  static const width = 340.0;

  /// The gap the arrow lives in.
  static const _gap = 10.0;

  /// Taller than this and a phone would fill the window; the picture gives up
  /// width to stay inside it.
  static const _maxPicture = 420.0;

  /// How long the swap from waiting to picture takes.
  ///
  /// Short — this is a card that appeared under the pointer a moment ago, and
  /// anything longer would still be settling when the hand has moved on.
  static const _swap = Duration(milliseconds: 160);

  /// How long a *warm* render has to take before the popover admits to
  /// waiting.
  ///
  /// Measured at 20–170ms, so almost every one of them lands inside this and
  /// the picture is simply what the card opens with — no spinner shown, none
  /// to fade out, nothing to flash. A cold catalog does not get this grace and
  /// should not: tens of seconds of silence is a card that looks broken.
  static const _admitWaiting = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var left = math.min(
      anchor.right + _gap,
      MediaQuery.of(context).size.width - width - FwSpacing.md,
    );
    return Stack(
      children: [
        CustomSingleChildLayout(
          // Only the height is unknown — the width is fixed and the left
          // edge with it — so this exists to clamp the top against a window
          // the popover might otherwise hang off the bottom of.
          delegate: _PopoverLayout(left: left, centre: anchor.center.dy),
          child: _body(context, colors),
        ),
        // The arrow is placed against the *row*, not against the body, so it
        // goes on pointing at what it belongs to however far the body was
        // clamped. The body is at least 200 tall and the clamp keeps it
        // overlapping its own row, so the two always touch.
        Positioned(
          left: left - 7,
          top: anchor.center.dy - 8,
          child: IgnorePointer(
            child: CustomPaint(
              size: const Size(8, 16),
              painter: _ArrowPainter(fill: colors.panel, edge: colors.line),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, FwPalette colors) {
    return IgnorePointer(
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: colors.panel,
          border: Border.all(color: colors.line),
          borderRadius: BorderRadius.circular(context.radii.radius),
          boxShadow: context.elevation.md,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The height changes when the picture lands — a 200-tall wait
            // becoming a 252-tall panel shot — and changing it in one frame is
            // the card snapping open under the pointer. Both halves animate:
            // the box grows, and the contents cross-fade inside it.
            AnimatedSize(
              duration: _swap,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: _swap,
                // Keyed on the entry as well as the state, so moving between
                // two rows that both have a picture cross-fades rather than
                // cutting.
                child: KeyedSubtree(
                  key: ValueKey('${entry.id}/${_face(thumbnail)}'),
                  child: _picture(context, colors),
                ),
              ),
            ),
            Divider(height: 1, color: colors.line),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FwSpacing.md,
                vertical: FwSpacing.sm,
              ),
              child: Text(
                '${entry.path} · ${entry.symbol}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.micro.copyWith(color: colors.mut),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _picture(BuildContext context, FwPalette colors) {
    switch (thumbnail) {
      case ThumbnailReady(:var image):
        return ColoredBox(
          color: colors.bg,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxPicture),
              child: AspectRatio(
                aspectRatio: image.width / image.height,
                child: RawImage(image: image, fit: BoxFit.contain),
              ),
            ),
          ),
        );
      case ThumbnailFailed(:var reason):
        return _waiting(
          context,
          colors,
          child: Padding(
            padding: const EdgeInsets.all(FwSpacing.lg),
            child: Text(
              reason,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: context.type.micro.copyWith(
                color: colors.red,
                fontFamily: 'monospace',
              ),
            ),
          ),
        );
      // A cold catalog is a compile of every entry and says so at once —
      // silence for that long reads as a card that failed to open.
      case ThumbnailPending(compiling: true):
        return _waiting(
          context,
          colors,
          child: const LoadingState(title: 'Compiling the catalog…'),
        );
      // Null is the frame between the pointer stopping and the store having
      // been asked. Same face as a warm pending, deliberately: a box that
      // showed something else for one frame is the flash this is avoiding.
      case ThumbnailPending() || null:
        return _waiting(
          context,
          colors,
          child: const _DelayedFade(
            after: _admitWaiting,
            child: LoadingState(title: 'Rendering…'),
          ),
        );
    }
  }

  /// A box the size the picture will be, so the popover does not resize under
  /// the pointer when one arrives.
  Widget _waiting(
    BuildContext context,
    FwPalette colors, {
    required Widget child,
  }) => Container(
    height: 200,
    alignment: Alignment.center,
    color: colors.bg,
    child: child,
  );
}

/// Which face [thumbnail] is, for a switcher that has to tell them apart
/// without telling two pictures apart.
String _face(Thumbnail? thumbnail) => switch (thumbnail) {
  ThumbnailReady() => 'ready',
  ThumbnailFailed() => 'failed',
  // Both waits are one face: a warm render that overshoots its grace grows a
  // spinner where it stands rather than swapping the box under it.
  ThumbnailPending() || null => 'waiting',
};

/// [child], faded in once [after] has passed and not before.
///
/// A spinner for work that takes 40ms is a flash, not a state. This is how the
/// popover shows one only for the renders slow enough to be worth admitting
/// to.
class _DelayedFade extends StatelessWidget {
  const _DelayedFade({required this.after, required this.child});

  final Duration after;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      // The delay *is* the curve: nothing for the grace, then a short fade.
      // One animation rather than a timer and a rebuild, which is one less
      // thing to cancel when the picture arrives first.
      duration: after + PreviewPopover._swap,
      curve: Interval(
        after.inMilliseconds /
            (after.inMilliseconds + PreviewPopover._swap.inMilliseconds),
        1,
      ),
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}

/// Puts the popover at a fixed [left], centred on [centre] where the window
/// allows and pushed inside it where it does not.
class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout({required this.left, required this.centre});

  final double left;

  /// Where the row it belongs to is, vertically.
  final double centre;

  static const _margin = FwSpacing.md;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: PreviewPopover.width,
        maxHeight: constraints.maxHeight - _margin * 2,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    left,
    (centre - childSize.height / 2).clamp(
      _margin,
      math.max(_margin, size.height - childSize.height - _margin),
    ),
  );

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      old.left != left || old.centre != centre;
}

/// The little triangle, tip to the left, sitting on the popover's edge.
class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.fill, required this.edge});

  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    // Only the two sloped edges: the third is where the body is, and a line
    // drawn there would show through as a seam.
    canvas.drawPath(
      Path()
        ..moveTo(size.width, 0)
        ..lineTo(0, size.height / 2)
        ..lineTo(size.width, size.height),
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.fill != fill || old.edge != edge;
}

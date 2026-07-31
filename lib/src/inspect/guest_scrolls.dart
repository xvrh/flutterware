import 'package:flutter/widgets.dart';

/// Counts what the demo scrolls, so [GuestWatch] can see the one kind of
/// staleness its other tiers are blind to by construction.
///
/// **Why the shape hash cannot see a scroll.** Scrolling changes offsets and
/// nothing else: the same widgets at the same depths, and the demo's own box
/// the size it always was. So the structure tier hashes the same number, the
/// resize tier reads the same size, and the tree the host is holding goes on
/// reporting the rects the widgets had before the scroll — which the panel then
/// draws the picker's rectangle from, over whatever used to be there. A list of
/// identical rows is the worst case rather than the best: recycling its items
/// leaves even the element shape identical.
///
/// **Why a counter and not a flag.** The watch decides everything by comparing
/// this frame against the last one. A boolean would need somebody to clear it,
/// and whoever cleared it would race the frame that set it; a number that only
/// goes up is the same comparison the other tiers already make.
///
/// **Why every notification and not only the ends.** A fling reports on every
/// frame of itself, and that is the point: the host waits for the scroll to
/// *stop* before paying for a tree read, so it needs to be told the thing is
/// still moving. Counting only the start and the end would have the host read
/// once in the middle of a fling — a walk it would then have to do again.
///
/// Costs nothing while nothing scrolls: notifications arrive from scrolling and
/// from no other event, so a demo standing still delivers none.
class GuestScrolls {
  GuestScrolls._();

  static final instance = GuestScrolls._();

  /// How many scroll notifications the demo has sent since the guest started.
  /// Only the difference between two frames means anything.
  int get ticks => _ticks;
  var _ticks = 0;

  /// Puts [child] under a listener that counts what it scrolls.
  ///
  /// Belongs **above** the marker the tree is read from, so that counting the
  /// demo's scrolling does not put a widget in the tree the panel shows.
  Widget watching({required Widget child}) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _ticks++;
        // False: this is a bystander. Consuming the notification would stop it
        // reaching whatever the catalog puts above the demo.
        return false;
      },
      child: child,
    );
  }
}

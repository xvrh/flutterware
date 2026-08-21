import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'embedded_engine.dart';
import 'protocol.dart';

/// Everything a guest needs to be driven: keys, hover, pointers, scrolling and
/// trackpad gestures.
///
/// Coordinates and deltas are scaled because the wire speaks physical pixels:
/// the guest divides by its own ratio, so a wheel tick scrolls the same logical
/// distance whether the guest fills the panel or is staged as a phone.
///
/// **The ratio is read from the engine at event time, not passed in at build.**
/// It is the engine that was told what to render at, so it is the only value
/// that cannot disagree with what the guest is actually doing — and it moves
/// without this widget rebuilding, because magnifying the stage changes the
/// ratio and nothing else. Passed in, it goes stale the moment a zoom settles,
/// and a stale ratio does not fail loudly: every click simply lands somewhere
/// other than where it was aimed.
class EmbedderInputRegion extends StatelessWidget {
  const EmbedderInputRegion({
    super.key,
    required this.engine,
    required this.focusNode,
    this.shouldIgnoreKey,
    this.shouldIgnorePointer,
    required this.child,
  });

  final EmbeddedEngine engine;
  final FocusNode focusNode;

  /// Keys the host keeps for itself — chords a surrounding
  /// `CallbackShortcuts` should claim. Returning true answers `ignored`, not
  /// `handled`, so the event carries on up to whichever binding wants it.
  final bool Function(KeyEvent event)? shouldIgnoreKey;

  /// Pointer events the host keeps for itself — a scroll or a pinch that means
  /// the stage, or a drag that is moving it.
  ///
  /// Only the *forwarding* stops. A `Listener` above this one is in the same
  /// hit-test path and receives the event whatever this answers — and, being a
  /// listener rather than a recognizer, it never loses a gesture arena either.
  /// So the host does not need a way to claim anything; it needs a way to stop
  /// the demo acting on a gesture aimed over its head. Everything not claimed
  /// still arrives, which is what keeps a magnified preview a preview you can
  /// still click, type into and scroll.
  final bool Function(PointerEvent event)? shouldIgnorePointer;

  final Widget child;

  bool _ignores(PointerEvent event) =>
      shouldIgnorePointer?.call(event) ?? false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (shouldIgnoreKey?.call(event) ?? false) {
          return KeyEventResult.ignored;
        }
        engine.sendKey(
          kind: event is KeyDownEvent
              ? KeyEventKind.down
              : event is KeyRepeatEvent
              ? KeyEventKind.repeat
              : KeyEventKind.up,
          physicalKey: event.physicalKey.usbHidUsage,
          logicalKey: event.logicalKey.keyId,
          // The host's layout resolved this keystroke to text; the guest's
          // text input builds editing state from it and can get it nowhere
          // else. Null on ups and non-printing keys.
          character: event.character,
        );
        return KeyEventResult.handled;
      },
      // Hover is not a [Listener]'s business: with no button held the engine
      // sends `PointerHoverEvent`, which `onPointerMove` never sees. Without
      // this the demo is blind to the mouse unless you are dragging — no ink
      // highlight, no `MouseRegion`, no hover tooltip, every demo frozen in
      // its resting state.
      child: MouseRegion(
        onEnter: (e) => engine.sendPointer(
          phaseKind: PointerPhase.add,
          x: e.localPosition.dx * engine.pixelRatio,
          y: e.localPosition.dy * engine.pixelRatio,
        ),
        onHover: (e) => engine.sendPointer(
          phaseKind: PointerPhase.hover,
          x: e.localPosition.dx * engine.pixelRatio,
          y: e.localPosition.dy * engine.pixelRatio,
        ),
        // Paired with the add: the guest is tracking a device that has left
        // the window, and a hover state left behind never lifts.
        onExit: (e) => engine.sendPointer(
          phaseKind: PointerPhase.remove,
          x: e.localPosition.dx * engine.pixelRatio,
          y: e.localPosition.dy * engine.pixelRatio,
        ),
        child: Listener(
          onPointerDown: (e) {
            if (_ignores(e)) return;
            focusNode.requestFocus();
            engine.sendPointer(
              phaseKind: PointerPhase.down,
              x: e.localPosition.dx * engine.pixelRatio,
              y: e.localPosition.dy * engine.pixelRatio,
              buttons: 1,
            );
          },
          onPointerMove: (e) => _ignores(e)
              ? null
              : engine.sendPointer(
                  phaseKind: PointerPhase.move,
                  x: e.localPosition.dx * engine.pixelRatio,
                  y: e.localPosition.dy * engine.pixelRatio,
                  buttons: 1,
                ),
          // Withheld like the moves, and for a reason that is easy to miss:
          // the demo has already had a `cancel` by the time the host is
          // claiming this gesture, and an `up` arriving after it is an up with
          // no down behind it.
          onPointerUp: (e) => _ignores(e)
              ? null
              : engine.sendPointer(
                  phaseKind: PointerPhase.up,
                  x: e.localPosition.dx * engine.pixelRatio,
                  y: e.localPosition.dy * engine.pixelRatio,
                ),
          // A discrete wheel only — a trackpad's two-finger scroll has not
          // arrived here since Flutter 3.3; it is the pan-zoom sequence below.
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent || _ignores(e)) return;
            engine.sendPointer(
              phaseKind: PointerPhase.hover,
              x: e.localPosition.dx * engine.pixelRatio,
              y: e.localPosition.dy * engine.pixelRatio,
              scrollDeltaX: e.scrollDelta.dx * engine.pixelRatio,
              scrollDeltaY: e.scrollDelta.dy * engine.pixelRatio,
            );
          },
          onPointerPanZoomStart: (e) => engine.sendPointer(
            phaseKind: PointerPhase.panZoomStart,
            x: e.localPosition.dx * engine.pixelRatio,
            y: e.localPosition.dy * engine.pixelRatio,
          ),
          // Cumulative since the start event, not per-update deltas — the
          // embedder API's convention, and the framework's own events already
          // carry it that way.
          onPointerPanZoomUpdate: (e) => _ignores(e)
              ? null
              : engine.sendPointer(
                  phaseKind: PointerPhase.panZoomUpdate,
                  x: e.localPosition.dx * engine.pixelRatio,
                  y: e.localPosition.dy * engine.pixelRatio,
                  panX: e.pan.dx * engine.pixelRatio,
                  panY: e.pan.dy * engine.pixelRatio,
                  scale: e.scale,
                  rotation: e.rotation,
                ),
          onPointerPanZoomEnd: (e) => engine.sendPointer(
            phaseKind: PointerPhase.panZoomEnd,
            x: e.localPosition.dx * engine.pixelRatio,
            y: e.localPosition.dy * engine.pixelRatio,
          ),
          child: child,
        ),
      ),
    );
  }
}

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'embedded_engine.dart';
import 'protocol.dart';

/// Everything a guest needs to be driven: keys, hover, pointers, scrolling and
/// trackpad gestures, forwarded in [dpr] — the panel's when the guest fills
/// the panel, the device's when it is staged as one.
///
/// Coordinates and deltas are scaled by [dpr] because the wire speaks physical
/// pixels: the guest divides by its own ratio, so a wheel tick scrolls the
/// same logical distance whether the guest is the panel or a phone.
class EmbedderInputRegion extends StatelessWidget {
  const EmbedderInputRegion({
    super.key,
    required this.engine,
    required this.dpr,
    required this.focusNode,
    this.shouldIgnoreKey,
    required this.child,
  });

  final EmbeddedEngine engine;
  final double dpr;
  final FocusNode focusNode;

  /// Keys the host keeps for itself — chords a surrounding
  /// `CallbackShortcuts` should claim. Returning true answers `ignored`, not
  /// `handled`, so the event carries on up to whichever binding wants it.
  final bool Function(KeyEvent event)? shouldIgnoreKey;

  final Widget child;

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
          x: e.localPosition.dx * dpr,
          y: e.localPosition.dy * dpr,
        ),
        onHover: (e) => engine.sendPointer(
          phaseKind: PointerPhase.hover,
          x: e.localPosition.dx * dpr,
          y: e.localPosition.dy * dpr,
        ),
        // Paired with the add: the guest is tracking a device that has left
        // the window, and a hover state left behind never lifts.
        onExit: (e) => engine.sendPointer(
          phaseKind: PointerPhase.remove,
          x: e.localPosition.dx * dpr,
          y: e.localPosition.dy * dpr,
        ),
        child: Listener(
          onPointerDown: (e) {
            focusNode.requestFocus();
            engine.sendPointer(
              phaseKind: PointerPhase.down,
              x: e.localPosition.dx * dpr,
              y: e.localPosition.dy * dpr,
              buttons: 1,
            );
          },
          onPointerMove: (e) => engine.sendPointer(
            phaseKind: PointerPhase.move,
            x: e.localPosition.dx * dpr,
            y: e.localPosition.dy * dpr,
            buttons: 1,
          ),
          onPointerUp: (e) => engine.sendPointer(
            phaseKind: PointerPhase.up,
            x: e.localPosition.dx * dpr,
            y: e.localPosition.dy * dpr,
          ),
          // A discrete wheel only — a trackpad's two-finger scroll has not
          // arrived here since Flutter 3.3; it is the pan-zoom sequence below.
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            engine.sendPointer(
              phaseKind: PointerPhase.hover,
              x: e.localPosition.dx * dpr,
              y: e.localPosition.dy * dpr,
              scrollDeltaX: e.scrollDelta.dx * dpr,
              scrollDeltaY: e.scrollDelta.dy * dpr,
            );
          },
          onPointerPanZoomStart: (e) => engine.sendPointer(
            phaseKind: PointerPhase.panZoomStart,
            x: e.localPosition.dx * dpr,
            y: e.localPosition.dy * dpr,
          ),
          // Cumulative since the start event, not per-update deltas — the
          // embedder API's convention, and the framework's own events already
          // carry it that way.
          onPointerPanZoomUpdate: (e) => engine.sendPointer(
            phaseKind: PointerPhase.panZoomUpdate,
            x: e.localPosition.dx * dpr,
            y: e.localPosition.dy * dpr,
            panX: e.pan.dx * dpr,
            panY: e.pan.dy * dpr,
            scale: e.scale,
            rotation: e.rotation,
          ),
          onPointerPanZoomEnd: (e) => engine.sendPointer(
            phaseKind: PointerPhase.panZoomEnd,
            x: e.localPosition.dx * dpr,
            y: e.localPosition.dy * dpr,
          ),
          child: child,
        ),
      ),
    );
  }
}

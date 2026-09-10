import 'dart:typed_data';

import 'package:flutter/widgets.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import 'embedded_engine.dart' show EmbeddedEnginePhase;

/// The guest's picture, as the catalog stage draws it: something with a
/// size, a pixel ratio and pixels, that takes the stage's input.
///
/// Two implementations. [EmbeddedEngine] paints an embedder process into a
/// texture and forwards the stage's pointer and keys to it over a pipe. The
/// inline surface *is* the widget, laid out at the size the stage asks for
/// — the studio's web demo, and a widget test of the panel over a real
/// entry. The stage draws either the same way; `catalog_view.dart` never
/// knows which.
abstract interface class GuestSurface implements Listenable {
  EmbeddedEnginePhase get phase;

  /// Whether the guest has drawn its current generation — the frame after
  /// the last resize or reload.
  bool get hasPainted;

  /// The ratio the guest is rendering at: a device's when staged as one, the
  /// panel's otherwise.
  double get pixelRatio;

  /// The pixels the guest should render — physical, with the safe areas it
  /// should lay out against, in the same units.
  void resize(
    int width,
    int height,
    double pixelRatio, {
    EdgeInsets insets = EdgeInsets.zero,
  });

  /// Ends whatever gesture the guest thinks is in progress — the stage took
  /// the pointer for a pan.
  void cancelPointer();

  /// The picture, sized by its parent: the texture, or the widget.
  Widget picture();

  /// [child] — the picture with the stage's overlays — receiving the input a
  /// guest gets: keys when [focusNode] has focus, the pointer as touch or as a
  /// mouse. [shouldIgnorePointer] and [shouldIgnoreKey] are the stage's
  /// veto, per event.
  Widget input({
    required Widget child,
    required FocusNode focusNode,
    required bool touch,
    bool Function(KeyEvent event)? shouldIgnoreKey,
    bool Function(PointerEvent event)? shouldIgnorePointer,
  });

  /// A PNG of what is on screen, [crop]ped to a node's box when given.
  Future<Uint8List> capturePng({
    InspectLayout? crop,
    List<InspectNode> annotate = const [],
    double pixelRatio = 1,
  });

  void dispose();
}

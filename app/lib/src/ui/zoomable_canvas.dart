import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The pan-and-zoom surface the graph canvases sit on: `InteractiveViewer`,
/// with a zoom direction somebody chose.
///
/// Flutter's own is not one. On macOS the embedder negates a wheel's delta and
/// hands a trackpad's pan through unnegated — correctly, because the framework
/// reads a pan as a finger drag — and then `InteractiveViewer` runs both
/// through the same `exp(-dy / factor)`. Measured, not deduced: the same `+20`
/// scrolls a list to 1020 down the wheel path and to 980 down the trackpad
/// path, and scales by 0.905 on both. So one gesture zooms in on a laptop and
/// out on a mouse.
///
/// One direction for both devices, and it is the browsers': **the gesture that
/// scrolls a page down zooms out**. That is Figma, Miro and every canvas in a
/// tab; macOS's own accessibility zoom is the other way, but nothing else a
/// designer touches all day is. The wheel already lands there, so what this
/// widget adds is the trackpad's ⌘ zoom, inverted from Flutter's. Pinch is
/// untouched — a spread is always larger, whatever the scroll does.
class ZoomableCanvas extends StatefulWidget {
  const ZoomableCanvas({
    super.key,
    this.transformationController,
    required this.minScale,
    required this.maxScale,
    required this.boundaryMargin,
    required this.child,
  });

  /// Owned by the caller when the canvas has to survive the page, as the
  /// scenario flow's does; otherwise this widget keeps one of its own.
  final TransformationController? transformationController;

  final double minScale;
  final double maxScale;
  final EdgeInsets boundaryMargin;
  final Widget child;

  @override
  State<ZoomableCanvas> createState() => _ZoomableCanvasState();
}

class _ZoomableCanvasState extends State<ZoomableCanvas> {
  /// `InteractiveViewer`'s own `kDefaultMouseScrollToScaleFactor`, so the
  /// trackpad keeps the sensitivity it had and only changes direction.
  static const _scaleFactor = 200.0;

  TransformationController? _own;
  late var _zooming = _zoomKeyDown;

  TransformationController get _transform =>
      widget.transformationController ?? (_own ??= TransformationController());

  @override
  void initState() {
    super.initState();
    // The modifier decides what a trackpad scroll means, and only key events
    // say when it changed.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _own?.dispose();
    super.dispose();
  }

  bool get _zoomKeyDown =>
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  bool _onKey(KeyEvent event) {
    if (_zoomKeyDown != _zooming) setState(() => _zooming = _zoomKeyDown);
    return false;
  }

  void _onPanZoom(PointerPanZoomUpdateEvent event) {
    if (!_zooming) return;
    var dy = event.localPanDelta.dy;
    if (dy == 0) return;
    _zoomBy(math.exp(dy / _scaleFactor), event.localPosition);
  }

  /// Scales about [focal] — the point under the pointer stays under it — the
  /// way `InteractiveViewer` does it for a wheel.
  void _zoomBy(double change, Offset focal) {
    var value = _transform.value;
    var scale = value.getMaxScaleOnAxis();
    var target = (scale * change).clamp(widget.minScale, widget.maxScale);
    if (target == scale) return;
    var factor = target / scale;
    var before = _toScene(focal, value);
    var scaled = value.scaledByDouble(factor, factor, factor, 1);
    var after = _toScene(focal, scaled);
    _transform.value = scaled
      ..translateByDouble(after.dx - before.dx, after.dy - before.dy, 0, 1);
  }

  Offset _toScene(Offset viewport, Matrix4 matrix) =>
      MatrixUtils.transformPoint(Matrix4.inverted(matrix), viewport);

  @override
  Widget build(BuildContext context) {
    // The listener sits directly on the viewer so a pan-zoom's local position
    // is already the coordinates `_zoomBy` scales about, and `panEnabled`
    // keeps the viewer from sliding the canvas under the same gesture.
    return Listener(
      onPointerPanZoomUpdate: _onPanZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: widget.minScale,
        maxScale: widget.maxScale,
        panEnabled: !_zooming,
        constrained: false,
        boundaryMargin: widget.boundaryMargin,
        child: widget.child,
      ),
    );
  }
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'model.dart';
import 'text_extract.dart';

/// Replays [root]'s paint pass into a [VgRecording] instead of the engine.
///
/// Nothing composites: every layer the tree would push is inlined into one
/// command stream, and the context keeps a stack of the render objects being
/// painted so canvas calls can be joined back to the semantics that produced
/// them (text content from [RenderParagraph], gradients from
/// [RenderDecoratedBox]).
VgRecording captureVector(RenderObject root) {
  var recording = VgRecording();
  var context = ExportPaintingContext(recording);
  context.paintChild(root, Offset.zero);
  return recording;
}

class ExportPaintingContext extends ClipContext implements PaintingContext {
  ExportPaintingContext(this.recording) {
    canvas = _RecordingCanvas(recording, this);
  }

  final VgRecording recording;

  @override
  late final ui.Canvas canvas;

  final renderObjectStack = <RenderObject>[];

  @override
  void paintChild(RenderObject child, Offset offset) {
    renderObjectStack.add(child);
    // A repaint boundary may carry its effect on the composited layer
    // instead of the paint stream — RenderOpacity holds its alpha there and
    // paints the child at full opacity.
    double? layerOpacity;
    if (child.isRepaintBoundary) {
      var layer = child.updateCompositedLayer(oldLayer: null);
      if (layer is OpacityLayer) layerOpacity = (layer.alpha ?? 255) / 255;
      layer.dispose();
    }
    if (layerOpacity != null && layerOpacity < 1) {
      recording.ops.add(VgSaveLayer(layerOpacity));
      child.paint(this, offset);
      recording.ops.add(VgRestore());
    } else {
      child.paint(this, offset);
    }
    renderObjectStack.removeLast();
  }

  @override
  ClipRectLayer? pushClipRect(
    bool needsCompositing,
    Offset offset,
    Rect clipRect,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.hardEdge,
    ClipRectLayer? oldLayer,
  }) {
    clipRectAndPaint(
      clipRect.shift(offset),
      clipBehavior,
      clipRect.shift(offset),
      () => painter(this, offset),
    );
    return null;
  }

  @override
  ClipRRectLayer? pushClipRRect(
    bool needsCompositing,
    Offset offset,
    Rect bounds,
    RRect clipRRect,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.antiAlias,
    ClipRRectLayer? oldLayer,
  }) {
    clipRRectAndPaint(
      clipRRect.shift(offset),
      clipBehavior,
      bounds.shift(offset),
      () => painter(this, offset),
    );
    return null;
  }

  @override
  ClipPathLayer? pushClipPath(
    bool needsCompositing,
    Offset offset,
    Rect bounds,
    Path clipPath,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.antiAlias,
    ClipPathLayer? oldLayer,
  }) {
    clipPathAndPaint(
      clipPath.shift(offset),
      clipBehavior,
      bounds.shift(offset),
      () => painter(this, offset),
    );
    return null;
  }

  @override
  TransformLayer? pushTransform(
    bool needsCompositing,
    Offset offset,
    Matrix4 transform,
    PaintingContextCallback painter, {
    TransformLayer? oldLayer,
  }) {
    // The transform applies around the paint offset, same as the real
    // PaintingContext.pushTransform.
    var effective = Matrix4.translationValues(offset.dx, offset.dy, 0)
      ..multiply(transform)
      ..translateByDouble(-offset.dx, -offset.dy, 0, 1);
    canvas.save();
    canvas.transform(effective.storage);
    painter(this, offset);
    canvas.restore();
    return null;
  }

  @override
  OpacityLayer pushOpacity(
    Offset offset,
    int alpha,
    PaintingContextCallback painter, {
    OpacityLayer? oldLayer,
  }) {
    recording.ops.add(VgSaveLayer(alpha / 255));
    painter(this, offset);
    recording.ops.add(VgRestore());
    return OpacityLayer();
  }

  @override
  void pushLayer(
    Layer childLayer,
    PaintingContextCallback painter,
    Offset offset, {
    Rect? childPaintBounds,
  }) {
    painter(this, offset);
  }

  @override
  VoidCallback addCompositionCallback(CompositionCallback callback) => () {};

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  /// The semantic joins: canvas calls ask the render object being painted.
  VgLinearGradient? resolveGradient(ui.Paint paint, Rect bounds) {
    if (paint.shader == null) return null;
    for (var ro in renderObjectStack.reversed) {
      if (ro is RenderDecoratedBox) {
        var decoration = ro.decoration;
        if (decoration is BoxDecoration &&
            decoration.gradient is LinearGradient) {
          var gradient = decoration.gradient! as LinearGradient;
          var begin = gradient.begin.resolve(TextDirection.ltr);
          var end = gradient.end.resolve(TextDirection.ltr);
          return VgLinearGradient(
            begin.withinRect(bounds),
            end.withinRect(bounds),
            gradient.colors,
            gradient.stops,
          );
        }
      }
    }
    return null;
  }

  VgOp resolveParagraph(ui.Paragraph paragraph, Offset offset) {
    for (var ro in renderObjectStack.reversed) {
      if (ro is RenderParagraph) {
        return VgDrawText(extractTextRuns(paragraph, ro.text, offset));
      }
    }
    // A paragraph laid out without a max width reports width = Infinity;
    // the ink is bounded by its longest line.
    var width = paragraph.width.isFinite
        ? paragraph.width
        : paragraph.longestLine;
    return VgDrawUnknownParagraph(
      Rect.fromLTWH(offset.dx, offset.dy, width, paragraph.height),
      paragraph,
    );
  }
}

class _RecordingCanvas implements ui.Canvas {
  _RecordingCanvas(this.recording, this.context);

  final VgRecording recording;
  final ExportPaintingContext context;
  var _saveCount = 1;

  List<VgOp> get _ops => recording.ops;

  VgPaint _paint(ui.Paint paint, Rect bounds) {
    return VgPaint.from(
      paint,
      gradient: context.resolveGradient(paint, bounds),
    );
  }

  @override
  void save() {
    _saveCount++;
    _ops.add(VgSave());
  }

  @override
  void saveLayer(Rect? bounds, ui.Paint paint) {
    _saveCount++;
    _ops.add(VgSaveLayer(paint.color.a));
  }

  @override
  void restore() {
    _saveCount--;
    _ops.add(VgRestore());
  }

  @override
  int getSaveCount() => _saveCount;

  @override
  void restoreToCount(int count) {
    while (_saveCount > count) {
      restore();
    }
  }

  @override
  void translate(double dx, double dy) {
    _ops.add(VgTransform(Matrix4.translationValues(dx, dy, 0).storage));
  }

  @override
  void scale(double sx, [double? sy]) {
    _ops.add(VgTransform(Matrix4.diagonal3Values(sx, sy ?? sx, 1).storage));
  }

  @override
  void rotate(double radians) {
    _ops.add(VgTransform(Matrix4.rotationZ(radians).storage));
  }

  @override
  void skew(double sx, double sy) {
    var m = Matrix4.identity();
    m.setEntry(0, 1, sx);
    m.setEntry(1, 0, sy);
    _ops.add(VgTransform(m.storage));
  }

  @override
  void transform(Float64List matrix4) {
    _ops.add(VgTransform(Float64List.fromList(matrix4)));
  }

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    _ops.add(VgClipRect(rect));
  }

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) {
    _ops.add(VgClipRRect(rrect));
  }

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {
    _ops.add(VgClipPath(VgPathData.fromPath(path)));
  }

  @override
  void drawRect(Rect rect, ui.Paint paint) {
    _ops.add(VgDrawRect(rect, _paint(paint, rect)));
  }

  @override
  void drawRRect(RRect rrect, ui.Paint paint) {
    _ops.add(VgDrawRRect(rrect, _paint(paint, rrect.outerRect)));
  }

  @override
  void drawDRRect(RRect outer, RRect inner, ui.Paint paint) {
    _ops.add(VgDrawDRRect(outer, inner, _paint(paint, outer.outerRect)));
  }

  @override
  void drawCircle(Offset c, double radius, ui.Paint paint) {
    _ops.add(
      VgDrawCircle(
        c,
        radius,
        _paint(paint, Rect.fromCircle(center: c, radius: radius)),
      ),
    );
  }

  @override
  void drawOval(Rect rect, ui.Paint paint) {
    _ops.add(VgDrawOval(rect, _paint(paint, rect)));
  }

  @override
  void drawLine(Offset p1, Offset p2, ui.Paint paint) {
    _ops.add(VgDrawLine(p1, p2, _paint(paint, Rect.fromPoints(p1, p2))));
  }

  @override
  void drawPath(ui.Path path, ui.Paint paint) {
    _ops.add(
      VgDrawPath(
        VgPathData.fromPath(path),
        _paint(paint, path.getBounds()),
        source: ui.Path.from(path),
      ),
    );
  }

  @override
  void drawShadow(
    ui.Path path,
    Color color,
    double elevation,
    bool transparentOccluder,
  ) {
    _ops.add(
      VgDrawShadow(
        VgPathData.fromPath(path),
        color,
        elevation,
        ui.Path.from(path),
      ),
    );
  }

  @override
  void drawPaint(ui.Paint paint) {
    _ops.add(VgDrawRect(Rect.largest, _paint(paint, Rect.largest)));
  }

  @override
  void drawColor(Color color, ui.BlendMode blendMode) {
    _ops.add(
      VgDrawRect(
        Rect.largest,
        VgPaint(
          color: color,
          style: PaintingStyle.fill,
          strokeWidth: 0,
          strokeCap: StrokeCap.butt,
          strokeJoin: StrokeJoin.miter,
        ),
      ),
    );
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    _ops.add(context.resolveParagraph(paragraph, offset));
  }

  @override
  void drawImage(ui.Image image, Offset offset, ui.Paint paint) {
    drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(
        offset.dx,
        offset.dy,
        image.width.toDouble(),
        image.height.toDouble(),
      ),
      paint,
    );
  }

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, ui.Paint paint) {
    var id = identityHashCode(image);
    recording.images[id] = image;
    _ops.add(VgDrawImageRect(id, src, dst));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    var name = invocation.memberName.toString();
    recording.unhandled.add(name);
    return null;
  }
}

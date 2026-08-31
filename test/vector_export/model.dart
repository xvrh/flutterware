import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// What to do with a text run.
enum VgTextMode {
  /// Draw each glyph as a path read from the font file.
  vectorize,

  /// Emit real text and embed the font bytes.
  embedFont,

  /// Emit real text naming the family and let the viewer resolve it.
  systemFont,
}

/// What to do with an op the writer cannot express (shadows, unresolvable
/// shaders, paragraphs whose text could not be recovered).
enum VgUnsupportedMode {
  /// Replay the op onto a real canvas at capture time and place the raster.
  rasterize,

  /// Cheapest visible stand-in: a solid color, a plain box.
  flatten,

  /// Leave it out.
  skip,
}

class VgExportOptions {
  VgExportOptions({
    VgTextMode Function(VgTextRun run)? textMode,
    this.unsupported = VgUnsupportedMode.rasterize,
  }) : textMode = textMode ?? ((_) => VgTextMode.embedFont);

  /// Called per run, so icons and body text can take different roads.
  final VgTextMode Function(VgTextRun run) textMode;
  final VgUnsupportedMode unsupported;
}

/// The captured draw-command stream: what crossed the [ui.Canvas] boundary,
/// lifted back into inspectable values.
class VgRecording {
  final ops = <VgOp>[];
  final images = <int, ui.Image>{};
  final unhandled = <String>{};

  /// PNG bytes per image id, filled by [encodeImages] after the sync capture.
  final imagePngs = <int, Uint8List>{};
  final imageRgba = <int, Uint8List>{};

  /// Where a rasterized op's patch lands on the page, keyed by image id.
  final rasterRects = <int, Rect>{};
  var _nextRasterId = -1;

  /// Replays every op no vector writer can express onto a real canvas and
  /// keeps the result as an image patch. Possible because the ops kept their
  /// original dart:ui objects (paint with its live shader, path, paragraph)
  /// alongside the lifted values.
  Future<void> rasterizeUnsupported({double pixelRatio = 3}) async {
    for (var op in ops) {
      var plan = switch (op) {
        VgDrawShadow s => (
          s.source.getBounds().inflate(4 + s.elevation * 2),
          (ui.Canvas c) => c.drawShadow(s.source, s.color, s.elevation, false),
          (int id) => s.rasterId = id,
        ),
        VgDrawUnknownParagraph u => (
          u.bounds.inflate(1),
          (ui.Canvas c) => c.drawParagraph(u.paragraph, u.bounds.topLeft),
          (int id) => u.rasterId = id,
        ),
        VgDrawRect r when r.paint.needsRaster => (
          r.rect.inflate(r.paint.strokeWidth + 1),
          (ui.Canvas c) => c.drawRect(r.rect, r.paint.source!),
          (int id) => r.rasterId = id,
        ),
        VgDrawRRect r when r.paint.needsRaster => (
          r.rrect.outerRect.inflate(r.paint.strokeWidth + 1),
          (ui.Canvas c) => c.drawRRect(r.rrect, r.paint.source!),
          (int id) => r.rasterId = id,
        ),
        VgDrawOval o when o.paint.needsRaster => (
          o.rect.inflate(o.paint.strokeWidth + 1),
          (ui.Canvas c) => c.drawOval(o.rect, o.paint.source!),
          (int id) => o.rasterId = id,
        ),
        VgDrawCircle o when o.paint.needsRaster => (
          Rect.fromCircle(
            center: o.center,
            radius: o.radius + o.paint.strokeWidth + 1,
          ),
          (ui.Canvas c) => c.drawCircle(o.center, o.radius, o.paint.source!),
          (int id) => o.rasterId = id,
        ),
        VgDrawPath p when p.paint.needsRaster && p.source != null => (
          p.source!.getBounds().inflate(p.paint.strokeWidth + 1),
          (ui.Canvas c) => c.drawPath(p.source!, p.paint.source!),
          (int id) => p.rasterId = id,
        ),
        _ => null,
      };
      if (plan == null) continue;
      var (bounds, draw, assign) = plan;
      if (bounds.isEmpty || !bounds.isFinite) continue;
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.scale(pixelRatio);
      canvas.translate(-bounds.left, -bounds.top);
      draw(canvas);
      var image = await recorder.endRecording().toImage(
        (bounds.width * pixelRatio).ceil(),
        (bounds.height * pixelRatio).ceil(),
      );
      var id = _nextRasterId--;
      images[id] = image;
      rasterRects[id] = bounds;
      assign(id);
    }
  }

  Future<void> encodeImages() async {
    for (var entry in images.entries) {
      var png = await entry.value.toByteData(format: ui.ImageByteFormat.png);
      imagePngs[entry.key] = png!.buffer.asUint8List();
      var raw = await entry.value.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      imageRgba[entry.key] = raw!.buffer.asUint8List();
    }
  }
}

sealed class VgOp {}

class VgSave extends VgOp {}

class VgSaveLayer extends VgOp {
  VgSaveLayer(this.opacity);
  final double opacity;
}

class VgRestore extends VgOp {}

class VgTransform extends VgOp {
  VgTransform(this.matrix);
  final Float64List matrix;
}

class VgClipRect extends VgOp {
  VgClipRect(this.rect);
  final Rect rect;
}

class VgClipRRect extends VgOp {
  VgClipRRect(this.rrect);
  final RRect rrect;
}

class VgClipPath extends VgOp {
  VgClipPath(this.path);
  final VgPathData path;
}

class VgDrawRect extends VgOp {
  VgDrawRect(this.rect, this.paint);
  final Rect rect;
  final VgPaint paint;
  int? rasterId;
}

class VgDrawRRect extends VgOp {
  VgDrawRRect(this.rrect, this.paint);
  final RRect rrect;
  final VgPaint paint;
  int? rasterId;
}

class VgDrawDRRect extends VgOp {
  VgDrawDRRect(this.outer, this.inner, this.paint);
  final RRect outer;
  final RRect inner;
  final VgPaint paint;
}

class VgDrawCircle extends VgOp {
  VgDrawCircle(this.center, this.radius, this.paint);
  final Offset center;
  final double radius;
  final VgPaint paint;
  int? rasterId;
}

class VgDrawOval extends VgOp {
  VgDrawOval(this.rect, this.paint);
  final Rect rect;
  final VgPaint paint;
  int? rasterId;
}

class VgDrawLine extends VgOp {
  VgDrawLine(this.a, this.b, this.paint);
  final Offset a;
  final Offset b;
  final VgPaint paint;
}

class VgDrawPath extends VgOp {
  VgDrawPath(this.path, this.paint, {this.source});
  final VgPathData path;
  final VgPaint paint;
  final ui.Path? source;
  int? rasterId;
}

class VgDrawShadow extends VgOp {
  VgDrawShadow(this.path, this.color, this.elevation, this.source);
  final VgPathData path;
  final Color color;
  final double elevation;
  final ui.Path source;
  int? rasterId;
}

class VgDrawImageRect extends VgOp {
  VgDrawImageRect(this.imageId, this.src, this.dst);
  final int imageId;
  final Rect src;
  final Rect dst;
}

/// A paragraph whose content could be recovered from the render tree:
/// positioned styled runs, one per (line × style run) cell.
class VgDrawText extends VgOp {
  VgDrawText(this.runs);
  final List<VgTextRun> runs;
}

/// A paragraph whose owner we could not read text out of; the live
/// [ui.Paragraph] is kept so the raster lane can still draw it.
class VgDrawUnknownParagraph extends VgOp {
  VgDrawUnknownParagraph(this.bounds, this.paragraph);
  final Rect bounds;
  final ui.Paragraph paragraph;
  int? rasterId;
}

class VgTextRun {
  VgTextRun({
    required this.text,
    required this.x,
    required this.baseline,
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.fontStyle,
    required this.color,
    this.letterSpacing,
    this.clusters,
  });

  final String text;
  final double x;
  final double baseline;
  final String? fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final Color color;
  final double? letterSpacing;

  /// Per-character positions from the laid-out paragraph, for writers that
  /// place each glyph themselves instead of emitting the run as a string.
  final List<VgCluster>? clusters;
}

class VgCluster {
  VgCluster(this.text, this.x);
  final String text;
  final double x;
}

class VgPaint {
  VgPaint({
    required this.color,
    required this.style,
    required this.strokeWidth,
    required this.strokeCap,
    required this.strokeJoin,
    this.gradient,
    this.hadUnresolvedShader = false,
    this.source,
  });

  factory VgPaint.from(ui.Paint paint, {VgLinearGradient? gradient}) {
    var unresolved = paint.shader != null && gradient == null;
    return VgPaint(
      color: paint.color,
      style: paint.style,
      strokeWidth: paint.strokeWidth,
      strokeCap: paint.strokeCap,
      strokeJoin: paint.strokeJoin,
      gradient: gradient,
      hadUnresolvedShader: unresolved,
      // Snapshot the live paint (shader included) so the raster lane can
      // replay this op faithfully.
      source: unresolved ? ui.Paint.from(paint) : null,
    );
  }

  final Color color;
  final PaintingStyle style;
  final double strokeWidth;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;
  final VgLinearGradient? gradient;

  /// The paint carried a [ui.Shader] the capture could not see through; what
  /// happens then is [VgExportOptions.unsupported]'s call.
  final bool hadUnresolvedShader;
  final ui.Paint? source;

  bool get needsRaster => hadUnresolvedShader && source != null;
}

class VgLinearGradient {
  VgLinearGradient(this.from, this.to, this.colors, this.stops);
  final Offset from;
  final Offset to;
  final List<Color> colors;
  final List<double>? stops;
}

/// A [ui.Path] flattened to polyline contours.
///
/// dart:ui exposes no way to iterate a path's verbs, so the capture samples
/// each contour through [ui.PathMetrics]. Curves become dense polylines: the
/// output stays vector but loses the analytic curve.
class VgPathData {
  VgPathData(this.contours, this.evenOdd);

  factory VgPathData.fromPath(ui.Path path) {
    var contours = <VgContour>[];
    for (var metric in path.computeMetrics()) {
      var length = metric.length;
      if (length == 0) continue;
      var steps = (length / 1.5).ceil().clamp(8, 512);
      var points = <Offset>[];
      for (var i = 0; i <= steps; i++) {
        var tangent = metric.getTangentForOffset(length * i / steps);
        if (tangent != null) points.add(tangent.position);
      }
      contours.add(VgContour(points, metric.isClosed));
    }
    return VgPathData(contours, path.fillType == PathFillType.evenOdd);
  }

  final List<VgContour> contours;
  final bool evenOdd;
}

class VgContour {
  VgContour(this.points, this.closed);
  final List<Offset> points;
  final bool closed;
}

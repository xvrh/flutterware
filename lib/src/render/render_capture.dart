import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'capture.dart';
import 'model.dart';
import 'pdf_writer.dart';
import 'svg_writer.dart';

/// Captures [render]'s painted content as a self-contained SVG.
///
/// [render] must be laid out — typically a [RenderRepaintBoundary] found
/// through a [GlobalKey], in a test or a running app. [size] defaults to the
/// box's own size. The result's warnings say what the vector output does not
/// carry exactly (raster patches, dropped effects, unrecovered text).
Future<SvgResult> captureSvg(
  RenderObject render, {
  Size? size,
  List<RenderFont> fonts = const [],
  CaptureOptions? options,
}) async {
  var opts = options ?? CaptureOptions();
  var recording = await _capture(render, opts);
  var svg = writeSvg(recording, size ?? _sizeOf(render), fonts, options: opts);
  return SvgResult(svg, recording.collectWarnings(opts));
}

/// Captures [render]'s painted content as a single-page PDF.
Future<PdfResult> capturePdf(
  RenderObject render, {
  Size? size,
  List<RenderFont> fonts = const [],
  CaptureOptions? options,
}) async {
  var opts = options ?? CaptureOptions();
  var recording = await _capture(render, opts);
  var warnings = recording.collectWarnings(opts);
  var bytes = await writePdf(
    recording,
    size ?? _sizeOf(render),
    fonts,
    options: opts,
    warnings: warnings,
  );
  return PdfResult(bytes, warnings);
}

Future<VgRecording> _capture(RenderObject render, CaptureOptions opts) async {
  var recording = captureVector(render);
  if (opts.unsupported == UnsupportedPolicy.rasterize) {
    await recording.rasterizeUnsupported(pixelRatio: opts.rasterScale);
  }
  await recording.encodeImages();
  return recording;
}

Size _sizeOf(RenderObject render) {
  if (render is RenderBox && render.hasSize) return render.size;
  throw ArgumentError(
    'size is required when the render object is not a laid-out RenderBox',
  );
}

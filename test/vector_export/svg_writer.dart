import 'dart:convert';
import 'dart:ui';

import 'glyph_outlines.dart';
import 'model.dart';

export 'glyph_outlines.dart' show VgFontFace;

/// [VgExportOptions.textMode] decides per run whether its glyphs become
/// paths read from the font file, real `<text>` with the font embedded, or
/// real `<text>` resolved by the viewer. [VgExportOptions.unsupported]
/// decides what an inexpressible op (shadow, unresolvable shader,
/// unrecoverable paragraph) turns into.
String writeSvg(
  VgRecording rec,
  Size size,
  List<VgFontFace> fonts, {
  VgExportOptions? options,
}) {
  var opts = options ?? VgExportOptions();
  var defs = StringBuffer();
  var body = StringBuffer();
  var defId = 0;

  var glyphSources = <VgFontFace, GlyphSource?>{};
  GlyphSource? sourceFor(VgTextRun run) =>
      glyphSourceForRun(fonts, run, glyphSources);

  var embeddedFaces = <VgFontFace>{};
  void embedFace(String? family) {
    for (var font in fonts) {
      if (family != null && font.family != family) continue;
      if (!embeddedFaces.add(font)) continue;
      defs.write(
        '<style>@font-face{font-family:"${font.family}";'
        'src:url(data:font/ttf;base64,${base64Encode(font.bytes)});'
        'font-weight:${font.bold ? 700 : 400};'
        'font-style:${font.italic ? 'italic' : 'normal'};}</style>',
      );
    }
  }

  bool emitRaster(int? rasterId) {
    var png = rasterId == null ? null : rec.imagePngs[rasterId];
    var bounds = rasterId == null ? null : rec.rasterRects[rasterId];
    if (png == null || bounds == null) return false;
    body.write(
      '<image x="${_n(bounds.left)}" y="${_n(bounds.top)}" '
      'width="${_n(bounds.width)}" height="${_n(bounds.height)}" '
      'preserveAspectRatio="none" '
      'href="data:image/png;base64,${base64Encode(png)}"/>',
    );
    return true;
  }

  /// Applies the unsupported-op policy to a shader the capture could not
  /// see through. True when the op is fully dealt with (raster placed, or
  /// skipped); false to draw the flat-color stand-in.
  bool tookUnsupported(VgPaint paint, int? rasterId) {
    if (!paint.hadUnresolvedShader) return false;
    return switch (opts.unsupported) {
      // No raster available (the capture skipped rasterizeUnsupported):
      // degrade to the flat stand-in rather than losing the op.
      VgUnsupportedMode.rasterize => emitRaster(rasterId),
      VgUnsupportedMode.flatten => false,
      VgUnsupportedMode.skip => true,
    };
  }

  // save()/restore() have no SVG equivalent, so every transform, clip or
  // opacity opens a <g> counted against the save frame it belongs to; the
  // matching restore closes them.
  var frames = <int>[0];
  void openGroup(String attrs) {
    body.write('<g $attrs>');
    frames[frames.length - 1]++;
  }

  String css(Color c) =>
      'rgba(${(c.r * 255).round()},${(c.g * 255).round()},'
      '${(c.b * 255).round()},${c.a.toStringAsFixed(3)})';

  String fillAttrs(VgPaint p) {
    String fill;
    if (p.gradient != null) {
      var g = p.gradient!;
      var id = 'grad${defId++}';
      defs.write(
        '<linearGradient id="$id" gradientUnits="userSpaceOnUse" '
        'x1="${g.from.dx}" y1="${g.from.dy}" '
        'x2="${g.to.dx}" y2="${g.to.dy}">',
      );
      for (var i = 0; i < g.colors.length; i++) {
        var offset = g.stops?[i] ?? i / (g.colors.length - 1);
        defs.write('<stop offset="$offset" stop-color="${css(g.colors[i])}"/>');
      }
      defs.write('</linearGradient>');
      fill = 'url(#$id)';
    } else {
      fill = css(p.color);
    }
    if (p.style == PaintingStyle.fill) {
      return 'fill="$fill"';
    }
    var cap = switch (p.strokeCap) {
      StrokeCap.butt => 'butt',
      StrokeCap.round => 'round',
      StrokeCap.square => 'square',
    };
    return 'fill="none" stroke="$fill" stroke-width="${p.strokeWidth}" '
        'stroke-linecap="$cap"';
  }

  String pathD(VgPathData path) {
    var d = StringBuffer();
    for (var contour in path.contours) {
      if (contour.points.isEmpty) continue;
      d.write('M${_n(contour.points.first.dx)} ${_n(contour.points.first.dy)}');
      for (var point in contour.points.skip(1)) {
        d.write('L${_n(point.dx)} ${_n(point.dy)}');
      }
      if (contour.closed) d.write('Z');
    }
    return d.toString();
  }

  for (var op in rec.ops) {
    switch (op) {
      case VgSave():
        frames.add(0);
      case VgSaveLayer(:var opacity):
        frames.add(0);
        openGroup('opacity="${opacity.toStringAsFixed(3)}"');
      case VgRestore():
        var opened = frames.removeLast();
        body.write('</g>' * opened);
      case VgTransform(:var matrix):
        var m = matrix;
        openGroup(
          'transform="matrix(${_n(m[0])} ${_n(m[1])} ${_n(m[4])} '
          '${_n(m[5])} ${_n(m[12])} ${_n(m[13])})"',
        );
      case VgClipRect(:var rect):
        var id = 'clip${defId++}';
        defs.write(
          '<clipPath id="$id"><rect x="${_n(rect.left)}" y="${_n(rect.top)}" '
          'width="${_n(rect.width)}" height="${_n(rect.height)}"/></clipPath>',
        );
        openGroup('clip-path="url(#$id)"');
      case VgClipRRect(:var rrect):
        var id = 'clip${defId++}';
        defs.write(
          '<clipPath id="$id"><path d="${_rrectD(rrect)}"/></clipPath>',
        );
        openGroup('clip-path="url(#$id)"');
      case VgClipPath(:var path):
        var id = 'clip${defId++}';
        defs.write('<clipPath id="$id"><path d="${pathD(path)}"/></clipPath>');
        openGroup('clip-path="url(#$id)"');
      case VgDrawRect(:var rect, :var paint, :var rasterId):
        if (tookUnsupported(paint, rasterId)) break;
        body.write(
          '<rect x="${_n(rect.left)}" y="${_n(rect.top)}" '
          'width="${_n(rect.width)}" height="${_n(rect.height)}" '
          '${fillAttrs(paint)}/>',
        );
      case VgDrawRRect(:var rrect, :var paint, :var rasterId):
        if (tookUnsupported(paint, rasterId)) break;
        body.write('<path d="${_rrectD(rrect)}" ${fillAttrs(paint)}/>');
      case VgDrawDRRect(:var outer, :var inner, :var paint):
        body.write(
          '<path d="${_rrectD(outer)}${_rrectD(inner)}" fill-rule="evenodd" '
          '${fillAttrs(paint)}/>',
        );
      case VgDrawCircle(:var center, :var radius, :var paint, :var rasterId):
        if (tookUnsupported(paint, rasterId)) break;
        body.write(
          '<circle cx="${_n(center.dx)}" cy="${_n(center.dy)}" '
          'r="${_n(radius)}" ${fillAttrs(paint)}/>',
        );
      case VgDrawOval(:var rect, :var paint, :var rasterId):
        if (tookUnsupported(paint, rasterId)) break;
        body.write(
          '<ellipse cx="${_n(rect.center.dx)}" cy="${_n(rect.center.dy)}" '
          'rx="${_n(rect.width / 2)}" ry="${_n(rect.height / 2)}" '
          '${fillAttrs(paint)}/>',
        );
      case VgDrawLine(:var a, :var b, :var paint):
        body.write(
          '<line x1="${_n(a.dx)}" y1="${_n(a.dy)}" x2="${_n(b.dx)}" '
          'y2="${_n(b.dy)}" ${fillAttrs(paint)}/>',
        );
      case VgDrawPath(:var path, :var paint, :var rasterId):
        if (tookUnsupported(paint, rasterId)) break;
        var rule = path.evenOdd ? ' fill-rule="evenodd"' : '';
        body.write('<path d="${pathD(path)}"$rule ${fillAttrs(paint)}/>');
      case VgDrawShadow(:var rasterId):
        if (opts.unsupported == VgUnsupportedMode.rasterize) {
          emitRaster(rasterId);
        }
      case VgDrawImageRect(:var imageId, :var dst):
        var png = rec.imagePngs[imageId]!;
        body.write(
          '<image x="${_n(dst.left)}" y="${_n(dst.top)}" '
          'width="${_n(dst.width)}" height="${_n(dst.height)}" '
          'preserveAspectRatio="none" '
          'href="data:image/png;base64,${base64Encode(png)}"/>',
        );
      case VgDrawText(:var runs):
        for (var run in runs) {
          var mode = opts.textMode(run);
          if (mode == VgTextMode.vectorize) {
            var source = run.clusters == null ? null : sourceFor(run);
            if (source != null) {
              var scale = run.fontSize / source.unitsPerEm;
              var d = StringBuffer();
              var missingGlyph = false;
              for (var cluster in run.clusters!) {
                var outline = source.outlineForChar(cluster.text.runes.first);
                if (outline == null) {
                  missingGlyph = true;
                  break;
                }
                for (var contour in outline) {
                  String px(double v) => _n(cluster.x + v * scale);
                  String py(double v) => _n(run.baseline - v * scale);
                  d.write('M${px(contour.start.dx)} ${py(contour.start.dy)}');
                  for (var segment in contour.segments) {
                    switch (segment) {
                      case GlyphLine(:var to):
                        d.write('L${px(to.dx)} ${py(to.dy)}');
                      case GlyphQuad(:var control, :var to):
                        d.write(
                          'Q${px(control.dx)} ${py(control.dy)} '
                          '${px(to.dx)} ${py(to.dy)}',
                        );
                      case GlyphCubic(:var control1, :var control2, :var to):
                        d.write(
                          'C${px(control1.dx)} ${py(control1.dy)} '
                          '${px(control2.dx)} ${py(control2.dy)} '
                          '${px(to.dx)} ${py(to.dy)}',
                        );
                    }
                  }
                  d.write('Z');
                }
              }
              if (!missingGlyph) {
                body.write('<path d="$d" fill="${css(run.color)}"/>');
                continue;
              }
            }
            // No outline source for this face: fall through to embedded
            // real text rather than losing the run.
          }
          if (mode != VgTextMode.systemFont) embedFace(run.fontFamily);
          var family = run.fontFamily ?? 'sans-serif';
          if (mode == VgTextMode.systemFont) family = '$family, sans-serif';
          var spacing = run.letterSpacing != null
              ? ' letter-spacing="${run.letterSpacing}"'
              : '';
          var style = run.fontStyle == FontStyle.italic
              ? ' font-style="italic"'
              : '';
          body.write(
            '<text x="${_n(run.x)}" y="${_n(run.baseline)}" '
            'font-family="$family" '
            'font-size="${run.fontSize}" '
            'font-weight="${run.fontWeight.value}"$style$spacing '
            'fill="${css(run.color)}" '
            'xml:space="preserve">${_escape(run.text)}</text>',
          );
        }
      case VgDrawUnknownParagraph(:var bounds, :var rasterId):
        if (opts.unsupported == VgUnsupportedMode.rasterize &&
            emitRaster(rasterId)) {
          break;
        }
        if (opts.unsupported == VgUnsupportedMode.skip) break;
        body.write(
          '<rect x="${_n(bounds.left)}" y="${_n(bounds.top)}" '
          'width="${_n(bounds.width)}" height="${_n(bounds.height)}" '
          'fill="rgba(255,0,255,0.3)"/>',
        );
    }
  }

  return '<svg xmlns="http://www.w3.org/2000/svg" '
      'width="${size.width}" height="${size.height}" '
      'viewBox="0 0 ${size.width} ${size.height}">'
      '<defs>$defs</defs>$body</svg>';
}

String _n(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(2);
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _rrectD(RRect r) {
  var d = StringBuffer();
  d.write('M${_n(r.left + r.tlRadiusX)} ${_n(r.top)}');
  d.write('L${_n(r.right - r.trRadiusX)} ${_n(r.top)}');
  d.write(
    'A${_n(r.trRadiusX)} ${_n(r.trRadiusY)} 0 0 1 '
    '${_n(r.right)} ${_n(r.top + r.trRadiusY)}',
  );
  d.write('L${_n(r.right)} ${_n(r.bottom - r.brRadiusY)}');
  d.write(
    'A${_n(r.brRadiusX)} ${_n(r.brRadiusY)} 0 0 1 '
    '${_n(r.right - r.brRadiusX)} ${_n(r.bottom)}',
  );
  d.write('L${_n(r.left + r.blRadiusX)} ${_n(r.bottom)}');
  d.write(
    'A${_n(r.blRadiusX)} ${_n(r.blRadiusY)} 0 0 1 '
    '${_n(r.left)} ${_n(r.bottom - r.blRadiusY)}',
  );
  d.write('L${_n(r.left)} ${_n(r.top + r.tlRadiusY)}');
  d.write(
    'A${_n(r.tlRadiusX)} ${_n(r.tlRadiusY)} 0 0 1 '
    '${_n(r.left + r.tlRadiusX)} ${_n(r.top)}',
  );
  d.write('Z');
  return d.toString();
}

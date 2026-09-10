// Text painted more than once.
//
// A single `Text` fills the glyph outlines once, in one colour, and that is
// the ceiling every text effect lives above. A paint stack is an ordered list
// of PASSES over the same paragraph — a drop shadow is a blurred offset fill,
// an outline is a stroke beneath the fill, sticker type is stroke-stroke-fill,
// extruded type is a dozen offset fills under a gradient one — and none of
// those is a code path here (master plan §4.5).
//
// THE LAW: a pass may change paint, never layout. A stroke widens the mark
// visually without touching the metrics, which is the only reason several
// passes stay registered on each other; let a pass carry its own tracking and
// there are two layouts, drifting by a subpixel that grows along the line.
//
// So the layout is Flutter's, once: an ordinary `Text.rich`, drawn in a
// transparent colour, sizes the box and keeps the wrapping, the ellipsis, the
// alignment and the semantics that a hand-rolled render object would have to
// re-earn. Every pass then re-lays-out INSIDE that box with the identical
// metric inputs, which is the same layout by construction, and paints. The
// painters are cached on those inputs, so a colour that changes costs a
// repaint and a size that changes costs a relayout.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'core/values.dart';
import 'flutter_bridge.dart';
import 'gradient_shader.dart';

/// A text node's paragraph, painted once per layer.
///
/// With no layers this is exactly the `Text.rich` it always was — the stack
/// is opt-in, and the ordinary case pays nothing for it.
class LayeredText extends StatelessWidget {
  const LayeredText({
    super.key,
    required this.span,
    required this.style,
    required this.layers,
    required this.textAlign,
    required this.maxLines,
  });

  final InlineSpan span;

  /// The metric style — what every pass shares, and what the cache is keyed
  /// on. Its colour is the fallback a layer with no paint of its own takes.
  final TextStyle style;
  final List<TextLayer> layers;
  final TextAlign textAlign;
  final int? maxLines;

  TextOverflow get _overflow =>
      maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis;

  @override
  Widget build(BuildContext context) {
    // What a `Text` would actually draw with, resolved HERE and handed to
    // both halves.
    //
    // This is the law's fine print. A `Text` merges its style over the
    // ambient `DefaultTextStyle`; a `TextPainter` merges over nothing. Give
    // the painter the unmerged style and the two disagree about any property
    // the scene left unset — the family, most of all — so they SHAPE
    // differently, wrap at different widths, and the box no longer describes
    // what is painted in it. That is one input feeding two layouts, which is
    // exactly what "a pass may change paint, never layout" forbids, and it
    // does not announce itself: it looks like a layout bug in whatever holds
    // the text.
    var ambient = DefaultTextStyle.of(context);
    var resolved = ambient.style.merge(style);
    var text = Text.rich(
      span,
      // A stack replaces the single draw rather than adding to it, so the
      // widget that does the LAYOUT draws nothing: transparent, not
      // `Opacity(0)`, which would cost a save layer for the same nothing.
      style: layers.isEmpty
          ? resolved
          : resolved.copyWith(color: const Color(0x00000000)),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: _overflow,
    );
    if (layers.isEmpty) return text;
    return CustomPaint(
      // Foreground rather than background: the passes are the text, and the
      // child is only there to have been measured.
      foregroundPainter: SceneTextStackPainter(
        span: span,
        style: resolved,
        layers: layers,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: _overflow,
        textDirection: Directionality.of(context),
        scaler: MediaQuery.textScalerOf(context),
        // The rest of what a `Text` reads off the ambient style, for the same
        // reason: every metric input, or two layouts.
        widthBasis: ambient.textWidthBasis,
        heightBehavior: ambient.textHeightBehavior,
      ),
      child: text,
    );
  }
}

/// Public so a test can hold the invariant the whole thing rests on: the
/// [style] here IS the style the base text was laid out with. One resolved
/// style, two consumers.
class SceneTextStackPainter extends CustomPainter {
  SceneTextStackPainter({
    required this.span,
    required this.style,
    required this.layers,
    required this.textAlign,
    required this.maxLines,
    required this.overflow,
    required this.textDirection,
    required this.scaler,
    required this.widthBasis,
    required this.heightBehavior,
  });

  final InlineSpan span;
  final TextStyle style;
  final List<TextLayer> layers;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  final TextDirection textDirection;
  final TextScaler scaler;
  final TextWidthBasis widthBasis;
  final TextHeightBehavior? heightBehavior;

  @override
  void paint(Canvas canvas, Size size) {
    for (var layer in layers) {
      var painter = _painterFor(layer, size);
      if (layer.dx == 0 && layer.dy == 0) {
        painter.paint(canvas, Offset.zero);
        continue;
      }
      canvas.save();
      canvas.translate(layer.dx, layer.dy);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  TextPainter _painterFor(TextLayer layer, Size size) {
    var key = _PainterKey(
      span.toPlainText(),
      style,
      layer,
      size,
      textAlign,
      maxLines,
      textDirection,
      scaler,
      widthBasis,
      heightBehavior,
    );
    return _cache.putIfAbsent(key, () {
      var painter = TextPainter(
        text: TextSpan(
          children: [span],
          style: style.copyWith(
            // `foreground` and `color` are mutually exclusive in a TextStyle,
            // and this is the one that carries a stroke or a gradient.
            foreground: _paintFor(layer, size, style.color),
          ),
        ),
        textAlign: textAlign,
        maxLines: maxLines,
        ellipsis: overflow == TextOverflow.ellipsis ? '…' : null,
        textDirection: textDirection,
        textScaler: scaler,
        textWidthBasis: widthBasis,
        textHeightBehavior: heightBehavior,
      );
      // The same width the child was laid out in, so the lines break where
      // they broke: identical metric inputs, identical layout.
      painter.layout(maxWidth: size.width);
      return painter;
    });
  }

  ui.Paint _paintFor(TextLayer layer, Size size, Color? own) {
    var paint = ui.Paint();
    if (layer case StrokeLayer(:var width, :var join)) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = join.flutter
        // A miter join on a tight counter spikes; round is what a designer
        // means by an outline, and is the default the model spells.
        ..strokeCap = StrokeCap.round;
    }
    switch (layer.paint) {
      case SolidPaint(:var color):
        paint.color = _faded(color.flutter, layer.opacity);
      case SceneGradient(:var colors) when colors.length < 2:
        // One colour is that colour, and none is the text's: the engine
        // refuses both as gradients.
        paint.color = _faded(
          colors.firstOrNull?.flutter ?? own ?? const Color(0xFF000000),
          layer.opacity,
        );
      case SceneGradient g:
        paint.shader = sceneGradientShader(
          g,
          Offset.zero & size,
          opacity: layer.opacity,
        );
      case null:
        // No paint of its own: the text's colour, which is what lets one
        // stack serve several colours.
        paint.color = _faded(own ?? const Color(0xFF000000), layer.opacity);
    }
    if (layer.blur > 0) {
      // On the pass's own paint, so the glyph OUTLINE is blurred. Compositing
      // the pass and blurring the result would be a save layer each, which is
      // a different performance story and a different look.
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, layer.blur);
    }
    return paint;
  }

  @override
  bool shouldRepaint(SceneTextStackPainter old) =>
      old.span.toPlainText() != span.toPlainText() ||
      old.style != style ||
      !_sameLayers(old.layers, layers) ||
      old.textAlign != textAlign ||
      old.maxLines != maxLines ||
      old.textDirection != textDirection ||
      old.scaler != scaler ||
      old.widthBasis != widthBasis ||
      old.heightBehavior != heightBehavior;
}

Color _faded(Color c, double opacity) =>
    opacity == 1 ? c : c.withValues(alpha: c.a * opacity);

bool _sameLayers(List<TextLayer> a, List<TextLayer> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What makes two passes the same pass: the metric inputs, the layer, and the
/// box. A colour that changes is a different layer and so a different key; a
/// size that changes is a different key because a gradient is measured
/// against the box.
class _PainterKey {
  const _PainterKey(
    this.text,
    this.style,
    this.layer,
    this.size,
    this.align,
    this.maxLines,
    this.direction,
    this.scaler,
    this.widthBasis,
    this.heightBehavior,
  );

  final String text;
  final TextStyle style;
  final TextLayer layer;
  final Size size;
  final TextAlign align;
  final int? maxLines;
  final TextDirection direction;
  final TextScaler scaler;
  final TextWidthBasis widthBasis;
  final TextHeightBehavior? heightBehavior;

  @override
  bool operator ==(Object other) =>
      other is _PainterKey &&
      other.text == text &&
      other.style == style &&
      other.layer == layer &&
      other.size == size &&
      other.align == align &&
      other.maxLines == maxLines &&
      other.direction == direction &&
      other.scaler == scaler &&
      other.widthBasis == widthBasis &&
      other.heightBehavior == heightBehavior;

  @override
  int get hashCode => Object.hash(
    text,
    style,
    layer,
    size,
    align,
    maxLines,
    direction,
    scaler,
    widthBasis,
    heightBehavior,
  );
}

/// Bounded and least-recently-used, because a motion plays: every frame of an
/// animated size is a different key, and an unbounded map would hold every
/// frame of every title the session ever drew.
const _cacheLimit = 128;
final _cache = _PainterCache();

class _PainterCache {
  // A plain map, because Dart's preserves insertion order — which is the
  // whole of what a least-recently-used eviction needs.
  final _entries = <_PainterKey, TextPainter>{};

  TextPainter putIfAbsent(_PainterKey key, TextPainter Function() build) {
    var found = _entries.remove(key);
    if (found != null) return _entries[key] = found;
    while (_entries.length >= _cacheLimit) {
      _entries.remove(_entries.keys.first)?.dispose();
    }
    return _entries[key] = build();
  }
}

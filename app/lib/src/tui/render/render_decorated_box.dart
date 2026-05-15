part of 'render.dart';

/// A box border described by its glyphs and color. Reuses the stage 2
/// [BorderChars].
class BoxBorder {
  final BorderChars chars;
  final Color fg;

  const BoxBorder({
    this.chars = const BorderChars.single(),
    this.fg = Color.defaultFg,
  });
}

/// A background fill and/or a border. Painted by [RenderDecoratedBox].
class BoxDecoration {
  /// The cell painted across the whole box; null leaves the background as-is.
  final Cell? fill;

  /// The perimeter border; null draws no border.
  final BoxBorder? border;

  const BoxDecoration({this.fill, this.border});
}

/// A single-child render object that paints a [BoxDecoration] around its
/// child. The decoration does not affect layout — a bordered panel is a
/// [RenderDecoratedBox] wrapping a [RenderPadding] so content clears the
/// 1-cell border.
class RenderDecoratedBox extends RenderBox with RenderBoxWithChild {
  RenderDecoratedBox({required BoxDecoration decoration, RenderBox? child})
      : _decoration = decoration {
    this.child = child;
  }

  BoxDecoration _decoration;
  BoxDecoration get decoration => _decoration;
  set decoration(BoxDecoration value) {
    // BoxDecoration has no structural equality; reuse a reference to skip the repaint.
    if (identical(value, _decoration)) return;
    _decoration = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    var c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints, parentUsesSize: true);
    (c.parentData! as BoxParentData).offset = CellOffset.zero;
    size = c.size;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(Painter painter) {
    var rect = CellRect.fromOffsetSize(CellOffset.zero, size);
    var fill = _decoration.fill;
    if (fill != null) {
      painter.fillRect(rect, fill);
    }
    child?.paint(painter);
    var border = _decoration.border;
    if (border != null) {
      painter.drawBorder(rect, chars: border.chars, fg: border.fg);
    }
  }
}

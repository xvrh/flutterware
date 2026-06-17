part of 'render.dart';

/// A single-child render object that insets its child by [padding].
class RenderPadding extends RenderBox with RenderBoxWithChild {
  RenderPadding({required this._padding, RenderBox? child}) {
    this.child = child;
  }

  EdgeInsets _padding;
  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    var h = _padding.horizontal;
    var v = _padding.vertical;
    var c = child;
    if (c == null) {
      size = constraints.constrain(CellSize(v, h));
      return;
    }
    c.layout(constraints.deflate(_padding), parentUsesSize: true);
    (c.parentData! as BoxParentData).offset = CellOffset(
      _padding.top,
      _padding.left,
    );
    size = constraints.constrain(CellSize(c.size.rows + v, c.size.cols + h));
  }

  int _innerWidth(int width) {
    if (width >= BoxConstraints.unbounded) return width;
    var inner = width - _padding.horizontal;
    return inner < 0 ? 0 : inner;
  }

  int _innerHeight(int height) {
    if (height >= BoxConstraints.unbounded) return height;
    var inner = height - _padding.vertical;
    return inner < 0 ? 0 : inner;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      (child?.getMinIntrinsicWidth(_innerHeight(height)) ?? 0) +
      _padding.horizontal;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      (child?.getMaxIntrinsicWidth(_innerHeight(height)) ?? 0) +
      _padding.horizontal;

  @override
  int computeMinIntrinsicHeight(int width) =>
      (child?.getMinIntrinsicHeight(_innerWidth(width)) ?? 0) +
      _padding.vertical;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      (child?.getMaxIntrinsicHeight(_innerWidth(width)) ?? 0) +
      _padding.vertical;

  @override
  void paint(Painter painter) {
    var c = child;
    if (c == null) return;
    var offset = (c.parentData! as BoxParentData).offset;
    c.paint(painter.translate(offset));
  }
}

part of 'render.dart';

/// A single-child render object that imposes [additionalConstraints] on top
/// of the constraints it receives. Underpins `SizedBox`/`ConstrainedBox` and
/// fixed-extent regions in stage 4.
class RenderConstrainedBox extends RenderBox with RenderBoxWithChild {
  RenderConstrainedBox({
    required this._additionalConstraints,
    RenderBox? child,
  }) {
    this.child = child;
  }

  BoxConstraints _additionalConstraints;
  BoxConstraints get additionalConstraints => _additionalConstraints;
  set additionalConstraints(BoxConstraints value) {
    if (value == _additionalConstraints) return;
    _additionalConstraints = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    var inner = _additionalConstraints.enforce(constraints);
    var c = child;
    if (c == null) {
      size = inner.constrain(CellSize.zero);
      return;
    }
    c.layout(inner, parentUsesSize: true);
    (c.parentData! as BoxParentData).offset = CellOffset.zero;
    size = c.size;
  }

  int _constrainW(int width) {
    var a = _additionalConstraints;
    var value = a.minWidth == a.maxWidth ? a.minWidth : width;
    return a.constrainWidth(value);
  }

  int _constrainH(int height) {
    var a = _additionalConstraints;
    var value = a.minHeight == a.maxHeight ? a.minHeight : height;
    return a.constrainHeight(value);
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      _constrainW(child?.getMinIntrinsicWidth(height) ?? 0);

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _constrainW(child?.getMaxIntrinsicWidth(height) ?? 0);

  @override
  int computeMinIntrinsicHeight(int width) =>
      _constrainH(child?.getMinIntrinsicHeight(width) ?? 0);

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _constrainH(child?.getMaxIntrinsicHeight(width) ?? 0);

  @override
  void paint(Painter painter) {
    child?.paint(painter);
  }
}

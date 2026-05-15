part of 'render.dart';

/// A render object that uses the cell-box layout protocol: it receives
/// [BoxConstraints] from its parent and produces a [CellSize].
abstract class RenderBox extends RenderObject {
  BoxConstraints? _constraints;

  /// The constraints from the most recent [layout] call.
  BoxConstraints get constraints => _constraints!;

  CellSize? _size;

  /// The size produced by the most recent [performLayout].
  CellSize get size => _size!;
  set size(CellSize value) {
    _size = value;
  }

  /// When true, the size depends only on the constraints, so [performResize]
  /// can set it before children are laid out. No Stage 3 box sets this; it
  /// exists for protocol completeness.
  bool get sizedByParent => false;

  /// Sets [size] from the constraints alone. Only called when [sizedByParent].
  void performResize() {}

  /// The layout entry point. Not meant to be overridden — subclasses override
  /// [performLayout] (and [performResize]/[sizedByParent] if relevant).
  ///
  /// Pass [parentUsesSize] true when the caller will read [size]; this affects
  /// whether the child becomes its own relayout boundary.
  void layout(BoxConstraints constraints, {bool parentUsesSize = false}) {
    var p = parent;
    var isBoundary = !parentUsesSize ||
        sizedByParent ||
        constraints.isTight ||
        p is! RenderBox;
    RenderObject? boundary;
    if (p is RenderBox && !isBoundary) {
      assert(p._relayoutBoundary != null,
          'A child must be laid out after its parent.');
      boundary = p._relayoutBoundary;
    } else {
      boundary = this;
    }

    if (!_needsLayout && constraints == _constraints) {
      if (boundary != _relayoutBoundary) {
        _relayoutBoundary = boundary;
        visitChildren(
            // Every child of a RenderBox is itself a RenderBox.
            (child) => (child as RenderBox)._propagateRelayoutBoundary());
      }
      return;
    }

    _constraints = constraints;
    _relayoutBoundary = boundary;
    if (sizedByParent) {
      performResize();
    }
    performLayout();
    _needsLayout = false;
    markNeedsPaint();
  }

  void _propagateRelayoutBoundary() {
    if (_relayoutBoundary == this) {
      return;
    }
    var parentBoundary = (parent! as RenderBox)._relayoutBoundary;
    if (parentBoundary != _relayoutBoundary) {
      _relayoutBoundary = parentBoundary;
      visitChildren(
          // Every child of a RenderBox is itself a RenderBox.
          (child) => (child as RenderBox)._propagateRelayoutBoundary());
    }
  }

  /// Intrinsic dimensions. The public getters delegate to the `compute*`
  /// methods, which subclasses override.
  int getMinIntrinsicWidth(int height) => computeMinIntrinsicWidth(height);
  int getMaxIntrinsicWidth(int height) => computeMaxIntrinsicWidth(height);
  int getMinIntrinsicHeight(int width) => computeMinIntrinsicHeight(width);
  int getMaxIntrinsicHeight(int width) => computeMaxIntrinsicHeight(width);

  int computeMinIntrinsicWidth(int height) => 0;
  int computeMaxIntrinsicWidth(int height) => 0;
  int computeMinIntrinsicHeight(int width) => 0;
  int computeMaxIntrinsicHeight(int width) => 0;

  /// Paints this box. [painter] is already translated so this box's top-left
  /// is local `(0, 0)`. Subclasses override.
  void paint(Painter painter) {}
}

/// Mixin for render boxes that hold exactly one box child.
mixin RenderBoxWithChild on RenderBox {
  RenderBox? _child;
  RenderBox? get child => _child;
  set child(RenderBox? value) {
    if (_child != null) {
      dropChild(_child!);
    }
    _child = value;
    if (value != null) {
      adoptChild(value);
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  @override
  void redepthChildren() {
    if (_child != null) {
      redepthChild(_child!);
    }
  }

  @override
  void visitChildren(void Function(RenderObject child) visitor) {
    if (_child != null) {
      visitor(_child!);
    }
  }
}

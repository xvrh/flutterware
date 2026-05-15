part of 'render.dart';

/// The root of the render tree. Holds one [RenderBox] child, lays it out tight
/// to the terminal [configuration], and bridges the tree to a [Painter].
///
/// It is a [RenderObject] but not a [RenderBox]: it has no parent and is not
/// laid out by a constraint protocol.
class RenderTuiView extends RenderObject {
  RenderTuiView(CellSize configuration) : _configuration = configuration;

  CellSize _configuration;

  /// The terminal size, in cells. Setting it requests a re-layout.
  CellSize get configuration => _configuration;
  set configuration(CellSize value) {
    if (value == _configuration) return;
    _configuration = value;
    markNeedsLayout();
  }

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

  /// The view's own size — always the [configuration].
  CellSize get size => _configuration;

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

  /// Registers the view for its first layout. Must be called once, after
  /// [attach] and after [child] is set.
  void prepareInitialFrame() {
    assert(
        attached, 'RenderTuiView must be attached to a PipelineOwner first.');
    _relayoutBoundary = this;
    _needsLayout = true;
    owner!._nodesNeedingLayout.add(this);
  }

  @override
  void performLayout() {
    _child?.layout(BoxConstraints.tight(_configuration), parentUsesSize: false);
  }

  /// Flushes any pending layout and paints the whole tree into [painter].
  void compositeFrame(Painter painter) {
    assert(
        attached, 'RenderTuiView must be attached to a PipelineOwner first.');
    owner!.flushLayout();
    _child?.paint(painter);
    owner!.clearNeedsPaint();
  }
}

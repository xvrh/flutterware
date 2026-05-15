part of 'render.dart';

/// Per-child data a parent attaches to each of its children. The concrete
/// subclass depends on the parent ([BoxParentData], [FlexParentData]).
class ParentData {}

/// [ParentData] for box-model children: the child's top-left offset within
/// the parent, in cells.
class BoxParentData extends ParentData {
  CellOffset offset = CellOffset.zero;
}

/// Owns the dirty render objects and flushes layout each frame.
///
/// Stage 3 has no layer tree, so there are no repaint boundaries: a repaint
/// request sets [needsPaint] and the whole tree is repainted. Re-layout *is*
/// localized — see [RenderObject.markNeedsLayout].
class PipelineOwner {
  final List<RenderObject> _nodesNeedingLayout = [];
  bool _needsPaint = false;

  /// Whether any render object has requested a repaint since the last clear.
  bool get needsPaint => _needsPaint;

  /// Re-runs layout for every dirty relayout boundary, shallowest depth first.
  /// A boundary's re-layout may clean nested boundaries enqueued in the same
  /// pass; those are skipped.
  void flushLayout() {
    // while loop, not for: laying out a boundary can enqueue new dirty nodes
    // (e.g. via layout callbacks), which must be flushed in the same pass.
    while (_nodesNeedingLayout.isNotEmpty) {
      var dirty = _nodesNeedingLayout.toList()
        ..sort((a, b) => a.depth - b.depth);
      _nodesNeedingLayout.clear();
      for (var node in dirty) {
        if (node._needsLayout && node._owner == this) {
          node._layoutWithoutResize();
        }
      }
    }
  }

  /// Clears the repaint flag. Call once a frame has been painted.
  void clearNeedsPaint() {
    _needsPaint = false;
  }
}

/// Base of the render tree: parentage, depth, attachment, and dirty-tracking.
/// [RenderBox] adds the box layout protocol; [RenderTuiView] is the root.
abstract class RenderObject {
  RenderObject? _parent;
  RenderObject? get parent => _parent;

  /// Data this object's parent attaches to it.
  ParentData? parentData;

  int _depth = 0;

  /// Distance from the root. Used only to order [PipelineOwner.flushLayout].
  int get depth => _depth;

  PipelineOwner? _owner;
  PipelineOwner? get owner => _owner;
  bool get attached => _owner != null;

  bool _needsLayout = true;
  RenderObject? _relayoutBoundary;

  /// Installs [parentData] of the right type on [child]. Parents that need a
  /// richer parent-data type override this.
  void setupParentData(RenderObject child) {
    child.parentData ??= ParentData();
  }

  /// Called by a subclass when it installs [child].
  void adoptChild(RenderObject child) {
    setupParentData(child);
    child._parent = this;
    if (attached) {
      child.attach(_owner!);
    }
    redepthChild(child);
    markNeedsLayout();
  }

  /// Called by a subclass when it removes [child].
  void dropChild(RenderObject child) {
    child._cleanRelayoutBoundary();
    child.parentData = null;
    child._parent = null;
    if (attached) {
      child.detach();
    }
    markNeedsLayout();
  }

  /// Ensures [child] (and its descendants) have a depth greater than this.
  void redepthChild(RenderObject child) {
    if (child._depth <= _depth) {
      child._depth = _depth + 1;
      child.redepthChildren();
    }
  }

  /// Calls [redepthChild] on every child. Parents with children override this.
  void redepthChildren() {}

  /// Visits every child. Parents with children override this.
  void visitChildren(void Function(RenderObject child) visitor) {}

  /// Attaches this subtree to [owner].
  void attach(PipelineOwner owner) {
    _owner = owner;
    visitChildren((child) => child.attach(owner));
  }

  /// Detaches this subtree from its owner.
  void detach() {
    _owner = null;
    visitChildren((child) => child.detach());
  }

  /// Marks this object dirty, walking up to the nearest relayout boundary and
  /// enqueuing *that* node on the owner. Intermediate nodes are flagged but
  /// not enqueued — the boundary's re-layout will revisit them.
  void markNeedsLayout() {
    if (_needsLayout) {
      return;
    }
    if (_relayoutBoundary == null) {
      // Never laid out yet: bubble up so a future layout reaches this subtree.
      _needsLayout = true;
      _parent?.markNeedsLayout();
      return;
    }
    if (_relayoutBoundary != this) {
      _needsLayout = true;
      assert(_parent != null,
          'A non-root render object must have a parent to bubble layout to.');
      _parent!.markNeedsLayout();
    } else {
      _needsLayout = true;
      _owner?._nodesNeedingLayout.add(this);
    }
  }

  void _cleanRelayoutBoundary() {
    if (_relayoutBoundary != this) {
      _relayoutBoundary = null;
      _needsLayout = true;
      visitChildren((child) => child._cleanRelayoutBoundary());
    }
  }

  /// Requests a repaint. With no layer tree this flags a whole-tree repaint.
  void markNeedsPaint() {
    _owner?._needsPaint = true;
  }

  /// Re-runs layout in place (constraints unchanged). Called by
  /// [PipelineOwner.flushLayout] on a dirty relayout boundary.
  void _layoutWithoutResize() {
    performLayout();
    _needsLayout = false;
    markNeedsPaint();
  }

  /// Computes this object's layout. Subclasses override.
  void performLayout();
}

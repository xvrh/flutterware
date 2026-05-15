part of 'widgets.dart';

/// Owns the dirty elements and drives depth-ordered rebuilds.
///
/// Elements mark themselves dirty (via [Element.markNeedsBuild]) and land in
/// [_dirtyElements]; [buildScope] rebuilds them shallowest-first, re-sorting
/// to absorb elements dirtied during the pass. [finalizeTree] unmounts
/// everything deactivated and not reclaimed this frame.
class BuildOwner {
  final List<Element> _dirtyElements = [];
  bool _dirtyElementsNeedsResorting = false;
  bool _buildScopeActive = false;

  final _InactiveElements _inactiveElements = _InactiveElements();

  /// Called the first time an element is scheduled for build in an otherwise
  /// idle owner. The binding uses this to schedule a frame.
  void Function()? onBuildScheduled;

  /// Enqueues [element] for rebuilding.
  void scheduleBuildFor(Element element) {
    assert(element.owner == this);
    if (element._inDirtyList) {
      _dirtyElementsNeedsResorting = true;
      return;
    }
    if (!_buildScopeActive && _dirtyElements.isEmpty) {
      onBuildScheduled?.call();
    }
    _dirtyElements.add(element);
    element._inDirtyList = true;
  }

  /// Rebuilds every dirty element, shallowest depth first.
  ///
  /// If [callback] is given it runs first (used to mount the root). Elements
  /// dirtied during the pass are caught by re-sorting the list.
  void buildScope(Element context, [void Function()? callback]) {
    if (callback == null && _dirtyElements.isEmpty) {
      return;
    }
    _buildScopeActive = true;
    try {
      if (callback != null) {
        callback();
      }
      _dirtyElements.sort(Element._sort);
      _dirtyElementsNeedsResorting = false;
      var index = 0;
      while (index < _dirtyElements.length) {
        var element = _dirtyElements[index];
        if (element._lifecycleState == _ElementLifecycle.active &&
            element._inDirtyList) {
          element.rebuild();
        }
        index += 1;
        if (_dirtyElementsNeedsResorting) {
          _dirtyElements.sort(Element._sort);
          _dirtyElementsNeedsResorting = false;
          // An element dirtied during the pass may have sorted before
          // `index`; rewind over any still-dirty prefix so it is built.
          while (index > 0 && _dirtyElements[index - 1].dirty) {
            index -= 1;
          }
        }
      }
    } finally {
      for (var element in _dirtyElements) {
        element._inDirtyList = false;
      }
      _dirtyElements.clear();
      _buildScopeActive = false;
    }
  }

  /// Unmounts every element deactivated this frame and not reactivated.
  void finalizeTree() {
    _inactiveElements._unmountAll();
  }
}

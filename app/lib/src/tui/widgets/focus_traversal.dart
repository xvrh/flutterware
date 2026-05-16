part of 'widgets.dart';

/// A direction for directional focus traversal (arrow keys).
enum TraversalDirection { up, down, left, right }

/// Determines the order in which focus moves between focusable nodes.
///
/// A policy operates over the [FocusNode.traversalDescendants] of the current
/// node's [FocusNode.nearestScope]. Transcribed in spirit from Flutter's
/// `FocusTraversalPolicy`, simplified for the TUI: order is derived from the
/// post-layout cell rectangles of the nodes.
abstract class FocusTraversalPolicy {
  /// Orders [descendants] for traversal.
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants);

  /// Moves focus to the node after [currentNode]; returns whether it moved.
  bool next(FocusNode currentNode) => _move(currentNode, forward: true);

  /// Moves focus to the node before [currentNode]; returns whether it moved.
  bool previous(FocusNode currentNode) => _move(currentNode, forward: false);

  /// Moves focus in [direction]; returns whether it moved.
  bool inDirection(FocusNode currentNode, TraversalDirection direction);

  List<FocusNode> _candidates(FocusNode node) =>
      sortDescendants(node.nearestScope.traversalDescendants).toList();

  bool _move(FocusNode currentNode, {required bool forward}) {
    var ordered = _candidates(currentNode);
    if (ordered.length < 2) return false;
    var index = ordered.indexOf(currentNode);
    int nextIndex;
    if (index < 0) {
      nextIndex = forward ? 0 : ordered.length - 1;
    } else {
      nextIndex = forward
          ? (index + 1) % ordered.length
          : (index - 1 + ordered.length) % ordered.length;
    }
    ordered[nextIndex].requestFocus();
    return true;
  }
}

/// The default policy: nodes are visited top row first, then left column.
class ReadingOrderTraversalPolicy extends FocusTraversalPolicy {
  @override
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants) {
    var withRect = descendants.where((n) => n.rect != null).toList();
    withRect.sort((a, b) {
      var ra = a.rect!;
      var rb = b.rect!;
      if (ra.top != rb.top) return ra.top - rb.top;
      return ra.left - rb.left;
    });
    return withRect;
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    // Reading-order policy has no directional behaviour of its own; a
    // DirectionalFocusTraversalPolicy (a later task) handles arrow keys.
    return false;
  }
}

/// Arrow-key traversal: moves focus to the geometrically nearest focusable in
/// the requested [TraversalDirection].
class DirectionalFocusTraversalPolicy extends FocusTraversalPolicy {
  @override
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants) =>
      descendants.where((n) => n.rect != null);

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    var from = currentNode.rect;
    if (from == null) return false;
    var fromCenter = _center(from);

    FocusNode? best;
    var bestScore = double.infinity;
    for (var node in _candidates(currentNode)) {
      if (identical(node, currentNode)) continue;
      var rect = node.rect!;
      var toCenter = _center(rect);
      var dRow = toCenter.$1 - fromCenter.$1;
      var dCol = toCenter.$2 - fromCenter.$2;
      var inDirection = switch (direction) {
        TraversalDirection.up => dRow < 0,
        TraversalDirection.down => dRow > 0,
        TraversalDirection.left => dCol < 0,
        TraversalDirection.right => dCol > 0,
      };
      if (!inDirection) continue;
      // Distance, biased so motion along the travel axis dominates.
      var primary = switch (direction) {
        TraversalDirection.up || TraversalDirection.down => dRow.abs(),
        TraversalDirection.left || TraversalDirection.right => dCol.abs(),
      };
      var secondary = switch (direction) {
        TraversalDirection.up || TraversalDirection.down => dCol.abs(),
        TraversalDirection.left || TraversalDirection.right => dRow.abs(),
      };
      var score = primary + secondary * 2.0;
      if (score < bestScore) {
        bestScore = score;
        best = node;
      }
    }
    if (best == null) return false;
    best.requestFocus();
    return true;
  }

  (double, double) _center(CellRect r) =>
      (r.top + r.height / 2.0, r.left + r.width / 2.0);
}

/// Inherited marker carrying the active [FocusTraversalPolicy] down the tree.
class _FocusTraversalMarker extends InheritedWidget {
  const _FocusTraversalMarker({required this.policy, required super.child});

  final FocusTraversalPolicy policy;

  @override
  bool updateShouldNotify(_FocusTraversalMarker oldWidget) =>
      !identical(policy, oldWidget.policy);
}

/// Scopes a [FocusTraversalPolicy] to a subtree. The built-in Tab/arrow
/// fallback in [FocusManager] uses the policy nearest the focused node.
class FocusTraversalGroup extends StatelessWidget {
  const FocusTraversalGroup({
    super.key,
    required this.policy,
    required this.child,
  });

  final FocusTraversalPolicy policy;
  final Widget child;

  /// The nearest enclosing policy, or null when there is no group.
  static FocusTraversalPolicy? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_FocusTraversalMarker>()
      ?.policy;

  @override
  Widget build(BuildContext context) =>
      _FocusTraversalMarker(policy: policy, child: child);
}

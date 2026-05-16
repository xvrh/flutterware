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

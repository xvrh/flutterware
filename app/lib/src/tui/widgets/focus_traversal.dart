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

/// Intent: move focus to the next node in traversal order.
class NextFocusIntent extends Intent {
  const NextFocusIntent();
}

/// Intent: move focus to the previous node in traversal order.
class PreviousFocusIntent extends Intent {
  const PreviousFocusIntent();
}

/// Intent: move focus in a direction (arrow keys).
class DirectionalFocusIntent extends Intent {
  const DirectionalFocusIntent(this.direction);
  final TraversalDirection direction;
}

/// The traversal policy nearest [node], defaulting to reading order.
///
/// Reads the [FocusTraversalGroup] policy from [node]'s context when it has
/// one; otherwise a fresh [ReadingOrderTraversalPolicy]. (Relocated from the
/// Stage 4.5a `FocusManager._policyFor`.)
FocusTraversalPolicy _policyFor(FocusNode node) {
  var context = node.context;
  if (context != null) {
    var policy = FocusTraversalGroup.maybeOf(context);
    if (policy != null) return policy;
  }
  return ReadingOrderTraversalPolicy();
}

/// Moves focus to the next traversable node.
class NextFocusAction extends Action<NextFocusIntent> {
  NextFocusAction(this.focusManager);
  final FocusManager focusManager;

  @override
  Object? invoke(NextFocusIntent intent) {
    var node = focusManager.primaryFocus;
    _policyFor(node).next(node);
    return null;
  }
}

/// Moves focus to the previous traversable node.
class PreviousFocusAction extends Action<PreviousFocusIntent> {
  PreviousFocusAction(this.focusManager);
  final FocusManager focusManager;

  @override
  Object? invoke(PreviousFocusIntent intent) {
    var node = focusManager.primaryFocus;
    _policyFor(node).previous(node);
    return null;
  }
}

/// Moves focus in [DirectionalFocusIntent.direction].
///
/// Directional traversal always uses a [DirectionalFocusTraversalPolicy], even
/// when the ambient policy is reading-order. (Relocated from the Stage 4.5a
/// `FocusManager._directional`.)
class DirectionalFocusAction extends Action<DirectionalFocusIntent> {
  DirectionalFocusAction(this.focusManager);
  final FocusManager focusManager;

  @override
  Object? invoke(DirectionalFocusIntent intent) {
    var node = focusManager.primaryFocus;
    var policy = _policyFor(node);
    var directional = policy is DirectionalFocusTraversalPolicy
        ? policy
        : DirectionalFocusTraversalPolicy();
    directional.inDirection(node, intent.direction);
    return null;
  }
}

/// The default traversal action map for a root [ShortcutManager]'s
/// `fallbackActions`.
Map<Type, Action<Intent>> defaultTraversalActions(FocusManager focusManager) =>
    {
      NextFocusIntent: NextFocusAction(focusManager),
      PreviousFocusIntent: PreviousFocusAction(focusManager),
      DirectionalFocusIntent: DirectionalFocusAction(focusManager),
    };

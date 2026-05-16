part of 'widgets.dart';

/// The outcome of an [FocusOnKeyEventCallback]. Transcribed from Flutter.
enum KeyEventResult {
  /// The handler consumed the event; stop dispatching.
  handled,

  /// The handler did not consume the event; continue to the next ancestor.
  ignored,

  /// Stop dispatching, but treat the event as unconsumed.
  skipRemainingHandlers,
}

/// Signature for [FocusNode.onKeyEvent]: given the node and a key event,
/// return whether the event was handled.
typedef FocusOnKeyEventCallback = KeyEventResult Function(
    FocusNode node, KeyEvent event);

/// A node in the focus tree.
///
/// Focus nodes form a tree parallel to the element tree. A [Focus] widget owns
/// one and attaches it under the focus node of the nearest enclosing
/// [Focus]/[FocusScope]. The [FocusManager] tracks which node currently holds
/// the primary focus and routes key events to it.
///
/// A [FocusNode] is a minimal listenable — it has [addListener]/[removeListener]
/// but is deliberately not `package:flutter/foundation`'s `ChangeNotifier`, so
/// the TUI keeps its zero-pub-dependency rule.
class FocusNode {
  FocusNode({this.skipTraversal = false, bool canRequestFocus = true})
      : _canRequestFocus = canRequestFocus;

  FocusNode? _parent;
  final List<FocusNode> _children = [];
  FocusManager? _manager;

  /// The focus node this node is attached under, or null if detached.
  FocusNode? get parent => _parent;

  /// The build context of the owning [Focus] widget. Set by [Focus]'s state;
  /// used by traversal to compute this node's on-screen rectangle.
  BuildContext? context;

  /// This node's on-screen rectangle, derived from the owning widget's render
  /// object. Null when the node has no context or has not been laid out.
  /// Valid only after layout — used by focus traversal.
  CellRect? get rect {
    var renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox) return null;
    CellSize size;
    try {
      size = renderObject.size;
    } catch (_) {
      return null; // not laid out yet
    }
    return CellRect.fromOffsetSize(renderObject.globalOffset, size);
  }

  /// When true, focus traversal skips this node.
  bool skipTraversal;

  bool _canRequestFocus;

  /// When false, this node cannot receive focus and traversal skips it.
  bool get canRequestFocus => _canRequestFocus;
  set canRequestFocus(bool value) {
    if (_canRequestFocus == value) return;
    _canRequestFocus = value;
    if (!value && hasPrimaryFocus) unfocus();
  }

  /// Invoked when a key event is dispatched to this node. May be null.
  FocusOnKeyEventCallback? onKeyEvent;

  /// Whether this node, or one of its descendants, holds the primary focus.
  bool get hasFocus {
    var node = _manager?.primaryFocus;
    while (node != null) {
      if (identical(node, this)) return true;
      node = node._parent;
    }
    return false;
  }

  /// Whether this node itself holds the primary focus.
  bool get hasPrimaryFocus => identical(_manager?.primaryFocus, this);

  /// The nearest ancestor [FocusScopeNode], or null if there is none.
  FocusScopeNode? get enclosingScope {
    for (var node in ancestors) {
      if (node is FocusScopeNode) return node;
    }
    return null;
  }

  /// The nearest enclosing scope — itself for a [FocusScopeNode].
  ///
  /// Must only be read on a node attached to the focus tree (every attached
  /// node has the manager's root scope as an ancestor).
  FocusScopeNode get nearestScope {
    var scope = enclosingScope;
    assert(scope != null,
        'nearestScope read on a FocusNode with no enclosing scope.');
    return scope!;
  }

  /// This node's ancestors, nearest first.
  Iterable<FocusNode> get ancestors sync* {
    var node = _parent;
    while (node != null) {
      yield node;
      node = node._parent;
    }
  }

  /// Every node beneath this one, in post-order.
  Iterable<FocusNode> get descendants sync* {
    for (var child in _children) {
      yield* child.descendants;
      yield child;
    }
  }

  /// Descendants eligible for focus traversal.
  Iterable<FocusNode> get traversalDescendants =>
      descendants.where((n) => n.canRequestFocus && !n.skipTraversal);

  final List<void Function()> _listeners = [];

  /// Registers [listener], called whenever this node's focus state changes.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Unregisters [listener].
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (var listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Test-only hook to fire listeners directly.
  void debugNotify() => _notify();

  /// Test-only hook to attach [child] without a [Focus] widget.
  void debugAttachChild(FocusNode child) => _reparent(child);

  void _reparent(FocusNode child) {
    if (identical(child._parent, this)) return;
    child._parent?._children.remove(child);
    _children.add(child);
    child._parent = this;
    child._setManager(_manager);
  }

  void _removeFromParent() {
    _parent?._children.remove(this);
    _parent = null;
    _setManager(null);
  }

  void _setManager(FocusManager? manager) {
    if (identical(_manager, manager)) return;
    _manager = manager;
    for (var child in _children) {
      child._setManager(manager);
    }
  }

  /// Requests that this node (or [node], if given) become the primary focus.
  ///
  /// The change is applied at the start of the next frame by the
  /// [FocusManager]. A no-op if the node is not attached to a manager.
  void requestFocus([FocusNode? node]) {
    if (node != null) {
      node.requestFocus();
      return;
    }
    if (!canRequestFocus) return;
    _manager?._markNextFocus(this);
  }

  /// Hands focus back to the enclosing scope.
  void unfocus() {
    var scope = enclosingScope;
    if (scope == null) return;
    _manager?._markNextFocus(scope);
  }

  /// Detaches this node from the focus tree and drops its listeners.
  void dispose() {
    if (_manager != null && identical(_manager!.primaryFocus, this)) {
      _manager!._markNextFocus(enclosingScope ?? _manager!.rootScope);
    }
    for (var child in List.of(_children)) {
      child._removeFromParent();
    }
    _removeFromParent();
    _listeners.clear();
  }
}

/// A [FocusNode] that groups a subtree of focusable nodes.
///
/// A scope remembers its most-recently-focused descendant ([focusedChild]) and
/// is itself the [nearestScope] for everything beneath it.
class FocusScopeNode extends FocusNode {
  FocusScopeNode({super.skipTraversal, super.canRequestFocus});

  FocusNode? _focusedChild;

  /// The most-recently-focused descendant of this scope, or null.
  FocusNode? get focusedChild => _focusedChild;

  @override
  FocusScopeNode get nearestScope => this;
}

/// Owns the focus tree root and the primary focus, applies pending focus
/// changes at frame boundaries, and routes key events.
///
/// One [FocusManager] is owned by each [TuiBinding]. Focus changes requested
/// via [FocusNode.requestFocus]/[FocusNode.unfocus] are recorded as pending
/// and applied by [applyFocusChangesIfNeeded], which the binding calls at the
/// top of every frame — before `buildScope`, so focus-driven `setState`s land
/// in the same frame.
class FocusManager {
  FocusManager() {
    rootScope._setManager(this);
    _primaryFocus = rootScope;
  }

  /// The root of the focus tree. Every [Focus]/[FocusScope] node attaches
  /// beneath it (directly or transitively).
  final FocusScopeNode rootScope = FocusScopeNode();

  late FocusNode _primaryFocus;

  /// The node that currently holds the primary focus.
  FocusNode get primaryFocus => _primaryFocus;

  FocusNode? _nextFocus;
  bool _haveScheduledUpdate = false;

  /// Invoked the first time a focus change is requested while none is pending.
  /// The [TuiBinding] wires this to its frame scheduler.
  void Function()? onFocusChange;

  /// The traversal policy used by the built-in Tab/arrow fallback when no
  /// [FocusTraversalGroup] overrides it.
  final FocusTraversalPolicy defaultTraversalPolicy =
      ReadingOrderTraversalPolicy();

  void _markNextFocus(FocusNode node) {
    _nextFocus = node;
    if (!_haveScheduledUpdate) {
      _haveScheduledUpdate = true;
      onFocusChange?.call();
    }
  }

  /// Applies a pending focus change, if any. Called at the top of each frame.
  void applyFocusChangesIfNeeded() {
    if (!_haveScheduledUpdate) return;
    _haveScheduledUpdate = false;
    var next = _nextFocus ?? _primaryFocus;
    _nextFocus = null;
    if (identical(next, _primaryFocus)) return;

    var oldChain = _chainOf(_primaryFocus);
    var newChain = _chainOf(next);
    _primaryFocus = next;

    // Record the focused descendant on each enclosing scope.
    var scope = next.enclosingScope;
    if (scope != null) scope._focusedChild = next;

    // Notify every node whose hasFocus flipped (the symmetric difference of
    // the old and new focus chains).
    for (var node in {...oldChain, ...newChain}) {
      if (oldChain.contains(node) != newChain.contains(node)) {
        node._notify();
      }
    }
  }

  /// Routes [event] through the focus chain.
  ///
  /// Calls [FocusNode.onKeyEvent] on the primary focus, then each ancestor up
  /// to [rootScope], stopping on [KeyEventResult.handled] or
  /// [KeyEventResult.skipRemainingHandlers]. If the whole chain returns
  /// [KeyEventResult.ignored], the built-in traversal fallback runs (see
  /// [_handleTraversalKey]).
  KeyEventResult handleKeyEvent(KeyEvent event) {
    var chain = <FocusNode>[_primaryFocus, ..._primaryFocus.ancestors];
    for (var node in chain) {
      var callback = node.onKeyEvent;
      if (callback == null) continue;
      var result = callback(node, event);
      if (result == KeyEventResult.handled ||
          result == KeyEventResult.skipRemainingHandlers) {
        return result;
      }
    }
    return _handleTraversalKey(event);
  }

  // Replaced with real traversal in a later task.
  KeyEventResult _handleTraversalKey(KeyEvent event) => KeyEventResult.ignored;

  Set<FocusNode> _chainOf(FocusNode node) {
    var chain = <FocusNode>{node};
    chain.addAll(node.ancestors);
    return chain;
  }
}

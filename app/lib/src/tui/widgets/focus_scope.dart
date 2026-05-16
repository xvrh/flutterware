part of 'widgets.dart';

/// Inherited marker carrying the nearest [FocusNode] down the tree.
///
/// Every [Focus] inserts one wrapping its child, so a descendant [Focus] finds
/// its parent node and a descendant reading [Focus.of] rebuilds when
/// `hasFocus` flips. [TuiBinding.attachRootWidget] inserts the root marker for
/// [FocusManager.rootScope].
class _FocusMarker extends InheritedWidget {
  const _FocusMarker({
    required this.node,
    required this.hasFocus,
    required super.child,
  });

  final FocusNode node;
  final bool hasFocus;

  @override
  bool updateShouldNotify(_FocusMarker oldWidget) =>
      !identical(node, oldWidget.node) || hasFocus != oldWidget.hasFocus;
}

/// A widget that manages a [FocusNode], making its subtree focusable.
///
/// Owns a [FocusNode] (or adopts one passed as [focusNode]), attaches it under
/// the nearest enclosing focus node, and re-exposes it to descendants so
/// `Focus.of(context).hasFocus` works and rebuilds on focus change.
class Focus extends StatefulWidget {
  const Focus({
    super.key,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    this.onKeyEvent,
    this.canRequestFocus = true,
    this.skipTraversal = false,
  });

  final Widget child;

  /// An externally-owned node to adopt. When null, [Focus] creates and owns
  /// its own node (and disposes it).
  final FocusNode? focusNode;

  /// When true, this node requests focus on mount if its scope has none.
  final bool autofocus;

  /// Invoked when a key event reaches this node.
  final FocusOnKeyEventCallback? onKeyEvent;

  final bool canRequestFocus;
  final bool skipTraversal;

  /// The nearest enclosing [FocusNode]. Registers a dependency, so the caller
  /// rebuilds when that node's `hasFocus` changes.
  static FocusNode of(BuildContext context) => maybeOf(context)!;

  /// Like [of] but returns null when there is no enclosing [Focus].
  static FocusNode? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FocusMarker>()?.node;

  @override
  State<Focus> createState() => _FocusState();
}

class _FocusState extends State<Focus> {
  late FocusNode _node;
  bool _createdNode = false;

  @override
  void initState() {
    _node = widget.focusNode ?? FocusNode();
    _createdNode = widget.focusNode == null;
    _applyWidgetToNode();
    _node.addListener(_onNodeChange);
  }

  void _applyWidgetToNode() {
    _node.context = context;
    _node.onKeyEvent = widget.onKeyEvent;
    _node.canRequestFocus = widget.canRequestFocus;
    _node.skipTraversal = widget.skipTraversal;
  }

  void _onNodeChange() => setState(() {});

  @override
  void didChangeDependencies() {
    var parentNode = Focus.maybeOf(context);
    if (parentNode != null && !identical(_node.parent, parentNode)) {
      parentNode._reparent(_node);
    }
    if (widget.autofocus &&
        _node.canRequestFocus &&
        (_node.enclosingScope?.focusedChild == null)) {
      _node.requestFocus();
    }
  }

  @override
  void didUpdateWidget(Focus oldWidget) {
    _applyWidgetToNode();
  }

  @override
  void dispose() {
    _node.removeListener(_onNodeChange);
    if (_createdNode) {
      _node.dispose();
    } else {
      _node.context = null;
      _node._removeFromParent();
    }
  }

  @override
  Widget build(BuildContext context) {
    _node.context = context;
    return _FocusMarker(
      node: _node,
      hasFocus: _node.hasFocus,
      child: widget.child,
    );
  }
}

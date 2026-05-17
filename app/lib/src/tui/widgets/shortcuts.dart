part of 'widgets.dart';

/// A key-event-to-intent map.
///
/// [KeyEvent] has value equality and a `Set<Modifier>`, so it is a usable map
/// key directly — the TUI needs no `LogicalKeySet`/`ShortcutActivator`
/// machinery.
typedef ShortcutMap = Map<KeyEvent, Intent>;

/// Resolves a [KeyEvent] to an [Intent] and invokes the matching [Action].
///
/// One [ShortcutManager] backs each [Shortcuts] widget, and one — carrying the
/// default bindings — is wired onto [FocusManager.rootScope]'s `onKeyEvent` by
/// `attachRootWidget`. The only difference between an app manager and the root
/// manager is that the root one carries [fallbackActions].
class ShortcutManager {
  ShortcutManager({
    this.shortcuts = const {},
    this.fallbackActions = const {},
  });

  /// The key bindings this manager owns.
  ShortcutMap shortcuts;

  /// Actions consulted when no enclosing [Actions] widget supplies one for a
  /// resolved intent. Empty for app [Shortcuts]; the root manager carries the
  /// default traversal actions here.
  Map<Type, Action<Intent>> fallbackActions;

  /// A [FocusOnKeyEventCallback]: used as `rootScope.onKeyEvent` and as the
  /// [Shortcuts] widget's `Focus.onKeyEvent`.
  ///
  /// Looks [event] up in [shortcuts]; if it maps to an intent, resolves the
  /// [Action] from the *focused* widget's context (so an [Actions] widget on
  /// the focused path is honoured), then from [fallbackActions]. Returns
  /// [KeyEventResult.handled] only when an enabled action ran.
  KeyEventResult handleFocusKeyEvent(FocusNode node, KeyEvent event) {
    var intent = shortcuts[event];
    if (intent == null) return KeyEventResult.ignored;

    var context = node.manager?.primaryFocus.context;
    Action<Intent>? action;
    if (context != null) {
      action = Actions.maybeFind(context, intent);
    }
    action ??= fallbackActions[intent.runtimeType];

    if (action == null || !action.isEnabled(intent)) {
      return KeyEventResult.ignored;
    }
    action.invoke(intent);
    return KeyEventResult.handled;
  }
}

/// Maps [KeyEvent]s to [Intent]s for a subtree.
///
/// Wraps [child] in a non-focusable, traversal-skipping [Focus] whose
/// `onKeyEvent` is the [ShortcutManager]. Because that [Focus] joins the focus
/// chain, a [Shortcuts] enclosing the focused subtree intercepts keys before
/// the root defaults — giving scoped overrides.
class Shortcuts extends StatefulWidget {
  const Shortcuts({
    super.key,
    required this.shortcuts,
    required this.child,
    this.manager,
  });

  /// The key bindings for this subtree.
  final ShortcutMap shortcuts;

  /// An externally-owned manager to adopt. When null, one is created.
  final ShortcutManager? manager;

  final Widget child;

  @override
  State<Shortcuts> createState() => _ShortcutsState();
}

class _ShortcutsState extends State<Shortcuts> {
  late ShortcutManager _manager;

  @override
  void initState() {
    _manager = widget.manager ?? ShortcutManager();
    _manager.shortcuts = widget.shortcuts;
  }

  @override
  void didUpdateWidget(Shortcuts oldWidget) {
    if (!identical(widget.manager, oldWidget.manager)) {
      _manager = widget.manager ?? ShortcutManager();
    }
    _manager.shortcuts = widget.shortcuts;
  }

  @override
  Widget build(BuildContext context) => Focus(
        skipTraversal: true,
        canRequestFocus: false,
        onKeyEvent: _manager.handleFocusKeyEvent,
        child: widget.child,
      );
}

/// The framework default key bindings, auto-installed on
/// [FocusManager.rootScope] by `attachRootWidget`.
///
/// Tab/Shift-Tab and the arrow keys drive focus traversal; Enter and Escape
/// map to [ActivateIntent]/[DismissIntent] (an app supplies the actions).
ShortcutMap defaultShortcuts() => {
      const SpecialKey(code: SpecialKeyCode.tab, modifiers: {}):
          const NextFocusIntent(),
      const SpecialKey(code: SpecialKeyCode.tab, modifiers: {Modifier.shift}):
          const PreviousFocusIntent(),
      const SpecialKey(code: SpecialKeyCode.up, modifiers: {}):
          const DirectionalFocusIntent(TraversalDirection.up),
      const SpecialKey(code: SpecialKeyCode.down, modifiers: {}):
          const DirectionalFocusIntent(TraversalDirection.down),
      const SpecialKey(code: SpecialKeyCode.left, modifiers: {}):
          const DirectionalFocusIntent(TraversalDirection.left),
      const SpecialKey(code: SpecialKeyCode.right, modifiers: {}):
          const DirectionalFocusIntent(TraversalDirection.right),
      const SpecialKey(code: SpecialKeyCode.enter, modifiers: {}):
          const ActivateIntent(),
      const SpecialKey(code: SpecialKeyCode.escape, modifiers: {}):
          const DismissIntent(),
    };

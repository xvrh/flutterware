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

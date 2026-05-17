part of 'widgets.dart';

/// A marker describing a desired action.
///
/// An [Intent] is an immutable value object. A [Shortcuts] widget maps a
/// [KeyEvent] to an [Intent]; an [Actions] widget maps an [Intent]'s runtime
/// type to an [Action] that performs it. Transcribed from Flutter.
abstract class Intent {
  const Intent();
}

/// Performs the work for an [Intent] of type [T].
///
/// Registered in an [Actions] widget keyed by intent type. [Action] is
/// generic and Dart class generics are covariant, so an `Action<MyIntent>`
/// stores into a `Map<Type, Action<Intent>>`; lookups are by
/// `intent.runtimeType`, so the value passed to [invoke]/[isEnabled] always
/// matches the action's real [T].
abstract class Action<T extends Intent> {
  /// Whether this action can run for [intent] right now. Defaults to true.
  bool isEnabled(T intent) => true;

  /// Performs the action. The return value is forwarded to the invoker.
  Object? invoke(T intent);
}

/// "Activate the focused thing" — e.g. press a button.
///
/// Bound to Enter by [defaultShortcuts]; an app supplies the matching [Action]
/// via an [Actions] widget. No default action ships with the framework.
class ActivateIntent extends Intent {
  const ActivateIntent();
}

/// "Dismiss / cancel" — e.g. close a dialog.
///
/// Bound to Escape by [defaultShortcuts]; an app supplies the matching
/// [Action]. No default action ships with the framework.
class DismissIntent extends Intent {
  const DismissIntent();
}

/// Inherited marker carrying an [Action] map down the tree.
///
/// The element layer keeps only the nearest inherited element per type, so a
/// chained lookup cannot see every [_ActionsMarker] at once. Each marker
/// therefore holds a [parent] pointer to the enclosing marker, and [find]
/// recurses outward.
class _ActionsMarker extends InheritedWidget {
  const _ActionsMarker({
    required this.actions,
    required this.parent,
    required super.child,
  });

  final Map<Type, Action<Intent>> actions;
  final _ActionsMarker? parent;

  /// The nearest [Action] registered for [intentType], walking outward.
  Action<Intent>? find(Type intentType) =>
      actions[intentType] ?? parent?.find(intentType);

  @override
  bool updateShouldNotify(_ActionsMarker oldWidget) =>
      actions != oldWidget.actions || !identical(parent, oldWidget.parent);
}

/// Maps [Intent] runtime types to the [Action]s that perform them.
///
/// Lookups walk outward through enclosing [Actions]: an inner [Actions]
/// shadows an outer one for the same intent type, and an unmatched type falls
/// through to the enclosing [Actions].
class Actions extends StatelessWidget {
  const Actions({super.key, required this.actions, required this.child});

  /// Intent runtime type → [Action]. Build a map literal such as
  /// `{ActivateIntent: MyActivateAction()}`.
  final Map<Type, Action<Intent>> actions;

  final Widget child;

  /// The nearest [Action] registered for [intent]'s runtime type, or null.
  ///
  /// Does not register an inherited dependency — safe to call from a key
  /// handler rather than a build method.
  static Action<Intent>? maybeFind(BuildContext context, Intent intent) {
    var marker = context.getInheritedWidgetOfExactType<_ActionsMarker>();
    return marker?.find(intent.runtimeType);
  }

  @override
  Widget build(BuildContext context) {
    // Depend on the enclosing marker: if an Actions is inserted above, this
    // one must rebuild to refresh its parent pointer.
    var parent = context.dependOnInheritedWidgetOfExactType<_ActionsMarker>();
    return _ActionsMarker(actions: actions, parent: parent, child: child);
  }
}

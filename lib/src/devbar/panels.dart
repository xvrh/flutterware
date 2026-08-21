/// Serving a panel from code, for a scope that is not a subtree.
library;

import 'bridge.dart';
import 'panel_source.dart';

/// Serves a panel for as long as the handle is held.
///
/// The imperative half of `AddDevbarPanel`, the same way
/// `UiService.addButton` is the imperative half of `AddDevbarButton`. The
/// widget is the wrapper: it calls this in `initState` and removes in
/// `dispose`.
///
/// ```dart
/// _panel = DevbarPanels.add(DatabasePanelSource(adapter));  // at login
/// _panel.remove();                                          // at logout
/// ```
///
/// Which half to use is a question about the scope, not about taste. A
/// panel belonging to a subtree — a signed-in shell, a checkout flow — should
/// be declared where that subtree is, and the widget makes forgetting to
/// remove it impossible. A panel belonging to a *service* — a session opened
/// at login and closed at logout, an environment being switched — has no
/// subtree to hang from, and reaching for the widget there means inventing a
/// widget boundary for a lifetime that is not one. Inserting a widget above an
/// existing subtree remounts it.
///
/// Needs no `Devbar` above it, and no `BuildContext`: a panel is served to
/// flutterware, not drawn in the overlay. Outside flutterware [add] hands back
/// an inert handle rather than null, so the call site never grows a `?`.
class DevbarPanels {
  DevbarPanels._();

  /// Starts serving [source]. Put the handle where the thing it describes is
  /// closed — [DevbarPanelHandle.remove] belongs on the line next to the
  /// `close()` it belongs to.
  static DevbarPanelHandle add(DevbarPanelSource source) =>
      DevbarPanelHandle._(DevbarBridge.add(source));
}

/// One panel being served, and the only way to stop.
///
/// A handle that is never removed leaves a panel outliving what it describes —
/// still listed, still answering, its handlers closed over a database that was
/// closed at logout. Nothing reports it: the visible symptom is the *next* one
/// arriving as `db:main#2`, because the id it wanted is still taken. That is
/// the cost of the imperative half, and why the widget exists.
class DevbarPanelHandle {
  DevbarPanelHandle._(this.id);

  /// The id the panel actually got, which is not always the one
  /// [DevbarPanelSource.panelId] asked for — a panel already using that name
  /// keeps it and this one is suffixed. Null when nothing is watching.
  final String? id;

  var _removed = false;

  /// Stops serving it. Removing twice is a no-op, so this can sit in a
  /// `dispose` that a `close` has already run through.
  void remove() {
    if (_removed) return;
    _removed = true;
    DevbarBridge.remove(id);
  }
}

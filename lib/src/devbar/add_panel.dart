/// A panel that belongs to a subtree — mounted with it, gone with it.
library;

import 'package:flutter/widgets.dart';

import 'bridge.dart';
import 'panel_source.dart';

/// Serves [source] as a panel for as long as this widget is mounted.
///
/// **The unit is the panel, not the plugin.** A devbar's plugins are declared
/// once and live as long as it does, which is right for the things an app has
/// all the time — its flags, its logs, its network. It is wrong for anything
/// scoped to something the app opens and closes. A database opened at login
/// and closed at logout has nothing to hand a devbar built at `runApp`, and
/// the panel it would serve has no business existing while nobody is signed
/// in. So it is declared where that scope is: in the widget tree.
///
/// ```dart
/// AddDevbarPanel(
///   source: _session.databasePanel,
///   child: signedInApp,
/// )
/// ```
///
/// Everything downstream already expected this. The list of panels is
/// announced on every change and every host re-reads it, so a panel appearing
/// mid-run reaches the cockpit's App tab, `fw` and MCP without any of them
/// being told about sessions.
///
/// **[source] is not owned here.** [DevbarPanelSource] declares no `dispose`,
/// so this cannot be the thing that disposes one — build the source where its
/// data lives (a `State`, a session object) and let it die with that. Building
/// one inside `build` is the same mistake as building an `AnimationController`
/// there, with the same symptom: a new instance every frame, and here that
/// means the panel is torn down and re-declared every frame.
///
/// **Consider not doing this at all.** A panel that comes and goes cannot
/// explain its own absence: an agent asking for `db:main` is told *"this app
/// declares no panel db:main"* whether the app has no database or the user
/// simply is not signed in, and only one of those is worth acting on. A panel
/// that is always there and answers *"no session is open"* keeps them apart —
/// see `DatabaseUnavailable`, which is that answer for a database. Reach for
/// this widget when the panel genuinely does not exist outside the scope,
/// not merely when its data does not.
class AddDevbarPanel extends StatefulWidget {
  const AddDevbarPanel({super.key, required this.source, this.child});

  final DevbarPanelSource source;

  /// The subtree this panel is scoped to. Rendered unchanged — this widget
  /// adds no box, no layout and no paint, so it can be dropped in anywhere
  /// without moving anything.
  final Widget? child;

  @override
  State<AddDevbarPanel> createState() => _AddDevbarPanelState();
}

class _AddDevbarPanelState extends State<AddDevbarPanel> {
  /// The id the bridge gave out, which is not always the one the source asked
  /// for. Null outside flutterware, where all of this is a no-op.
  String? _panelId;

  @override
  void initState() {
    super.initState();
    _panelId = DevbarBridge.add(widget.source);
  }

  /// A new source is a new panel — the environment switched, the session was
  /// replaced. By identity, so a rebuild that hands back the same source
  /// costs nothing: re-describing means tearing down the old panel's channels
  /// and announcing a changed list, which is not something to do per frame.
  @override
  void didUpdateWidget(covariant AddDevbarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.source, widget.source)) return;
    DevbarBridge.remove(_panelId);
    _panelId = DevbarBridge.add(widget.source);
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();

  @override
  void dispose() {
    DevbarBridge.remove(_panelId);
    super.dispose();
  }
}

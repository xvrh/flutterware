import 'dart:async';

import 'package:flutter/widgets.dart';

import 'plugin_core.dart';
import 'plugin_host.dart';

/// The GUI-side runtime of a native plugin — one instance per open worktree.
///
/// **A panel over a [PluginCore], and nothing more.** The core holds the
/// behaviour: the report, the actions, what `reload` does. This class exists
/// because `buildPanel` returns a `Widget` and a `Widget` cannot be linked into
/// `fw`.
///
/// **There is deliberately no `report` and no `invoke` on this class.** Callers
/// read `plugin.core.report` and dispatch `session.invoke(plugin, action,
/// args)`. Dart cannot seal a member, so the only way to stop a panel
/// overriding the report — becoming a second, disagreeing answer to what the
/// sidebar shows — is not to give it one to override; and a panel that could
/// run an action directly would be a fourth door into behaviour the CLI and
/// MCP reach through `Session.invoke`, which is exactly the drift this split
/// exists to prevent. A panel widget with business logic in `onPressed` is a
/// bug.
abstract class NativePlugin<C extends PluginCore> extends ChangeNotifier {
  NativePlugin(this.core) {
    // `skip(1)` drops the replay. A ValueStream hands every new subscriber the
    // value that was already current, and "what it already was" is not a
    // change — without this, constructing a panel notifies the shell that
    // something moved before the panel has drawn anything at all.
    _changes = core.changes.stream.skip(1).listen((_) => notifyListeners());
  }

  /// The behaviour this panel draws. Owned by the [Session] that resolved it,
  /// not by this — closing the worktree disposes the session, which disposes
  /// the cores.
  final C core;

  late final StreamSubscription<int> _changes;

  PluginHost get host => core.host;

  String get id => core.id;

  /// The panel mounted when this plugin is selected. Real Flutter, no limits.
  ///
  /// [childId] is the selected sub-entry — a package path for a package-scoped
  /// plugin — or null when the plugin has no children. The shell owns that
  /// selection because the sidebar children *are* the picker; a panel that
  /// grew its own would be a second, disagreeing source of truth.
  Widget buildPanel(BuildContext context, String? childId);

  /// Schedules a change notification, coalescing bursts into one.
  ///
  /// Prefer this over [notifyListeners]. A plugin's work starts when a widget
  /// subscribes, and that happens in `initState` — inside the build phase,
  /// where marking the shell dirty synchronously throws
  /// "setState() called during build". Deferring by a microtask makes the
  /// common case safe instead of leaving every plugin to remember.
  ///
  /// Changes originating in the core already arrive this way, so this is for
  /// state the *panel* owns.
  @protected
  void notifyChanged() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  var _notifyScheduled = false;
  var _disposed = false;

  /// Called when the worktree is closed. Release whatever the *panel* holds —
  /// the core is released by the session.
  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes.cancel());
    super.dispose();
  }
}

/// Builds a plugin's panel over the core the session already resolved.
typedef NativePluginFactory = NativePlugin Function(PluginCore core);

/// Adapts a panel that wants a specific core to the registry's untyped factory.
///
/// The cast is checked rather than assumed. The two registries are separate
/// maps — one produces panels, one produces behaviour — so a panel registered
/// for an id whose core is missing or is somebody else's must degrade to a
/// visible [MissingPlugin] rather than throw halfway through opening a
/// worktree.
NativePluginFactory panelFor<C extends PluginCore>(
  NativePlugin Function(C core) build,
) =>
    (core) => core is C
    ? build(core)
    : MissingPlugin(
        core,
        reason:
            'The panel registered for "${core.id}" needs a $C, but this build '
            'resolved a ${core.runtimeType}.',
      );

/// Stands in for a plugin the project declared but this build has no panel for.
///
/// Deliberately visible rather than skipped: a declaration that silently
/// vanishes looks like a config bug that never surfaces, and after the
/// declarative tier lands, an unknown id is the normal symptom of a version
/// mismatch. It must be legible.
///
/// Its [report] is still the core's. When the core exists and only the panel is
/// missing, the sidebar shows the plugin's real status and only the panel says
/// anything is wrong — which is true, and more useful than hiding a working
/// plugin behind an error.
class MissingPlugin extends NativePlugin {
  MissingPlugin(super.core, {this.reason});

  /// Why there is no panel, when it is more specific than "none registered".
  final String? reason;

  @override
  Widget buildPanel(BuildContext context, String? childId) =>
      _MissingPanel(host: host, reason: reason);
}

class _MissingPanel extends StatelessWidget {
  const _MissingPanel({required this.host, this.reason});

  final PluginHost host;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          reason ??
              'No native plugin is registered for "${host.id}".\n'
                  'It is declared in tool/flutterware.dart but this build does '
                  'not implement it.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

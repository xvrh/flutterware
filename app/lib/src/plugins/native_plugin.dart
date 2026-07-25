import 'package:flutter/widgets.dart';
import 'package:flutterware/plugins.dart';

import 'plugin_host.dart';

/// The GUI-side runtime of a native plugin — one instance per open worktree.
///
/// The split that matters: [report] is **pure data** and is what the sidebar,
/// the worktree switcher, `fw` and an agent read; [buildPanel] is the one place
/// a native plugin is unrestricted Flutter. Anything a renderer other than the
/// GUI needs must be in [report], because nothing else can see the widget.
abstract class NativePlugin extends ChangeNotifier {
  NativePlugin(this.host);

  final PluginHost host;

  String get id => host.id;

  /// Everything this plugin currently says about itself. Recomputed on demand;
  /// call [notifyListeners] when the underlying state moves.
  PluginReport get report;

  /// The panel mounted when this plugin is selected. Real Flutter, no limits.
  Widget buildPanel(BuildContext context);

  /// Runs one of [report]'s actions. The default refuses unknown ids loudly
  /// rather than silently doing nothing.
  Future<void> invoke(String actionId) async {
    throw ArgumentError.value(actionId, 'actionId', 'unknown action on $id');
  }

  /// Called when the worktree is closed. Release watchers, subscriptions and
  /// processes here — this is what makes closing a worktree actually free
  /// resources rather than just hide a tab.
  @override
  void dispose() => super.dispose();
}

/// Builds a plugin's runtime for one worktree.
typedef NativePluginFactory = NativePlugin Function(PluginHost host);

/// Stands in for a plugin the project declared but this build has no
/// implementation for.
///
/// Deliberately visible rather than skipped: a declaration that silently
/// vanishes looks like a config bug that never surfaces, and after the
/// declarative tier lands, an unknown id is the normal symptom of a version
/// mismatch. It must be legible.
class MissingPlugin extends NativePlugin {
  MissingPlugin(super.host);

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: Status.error('no implementation'),
    badge: const Badge.dot(Tone.error),
    view: PluginView([
      ViewText(
        'This build of flutterware has no native plugin registered for '
        '"${host.id}".',
      ),
      ViewField('Declared in', 'tool/flutterware.dart'),
      if (host.config.isNotEmpty)
        ViewField('Config', host.config.keys.join(', ')),
    ]),
  );

  @override
  Widget buildPanel(BuildContext context) => _MissingPanel(host: host);
}

class _MissingPanel extends StatelessWidget {
  const _MissingPanel({required this.host});

  final PluginHost host;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No native plugin is registered for "${host.id}".\n'
          'It is declared in tool/flutterware.dart but this build does not '
          'implement it.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

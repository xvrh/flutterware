import 'package:flutter/widgets.dart';
// `Dependencies` here is the app's dependency model, not the plugin
// declaration of the same name in package:flutterware.
import 'package:flutterware/plugins.dart' hide Dependencies;

import '../../dependencies/list.dart';
import '../../dependencies/model/service.dart';
import '../../utils/async_value.dart';
import '../native_plugin.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const dependenciesPluginId = 'flutterware.dependencies';

/// How many rows the text projection carries before it starts counting.
/// A projection is read, not scrolled; the rest is reported as a count so it
/// never looks complete when it is not.
const _projectedRows = 12;

/// First native plugin: the project's pub dependencies.
///
/// Shows the shape every native plugin follows — a [report] built from the
/// worktree's services, and a [buildPanel] that mounts real Flutter.
class DependenciesPlugin extends NativePlugin {
  DependenciesPlugin(super.host) {
    // Listening starts the load, which is what gives the sidebar a real status
    // for every plugin in an open worktree rather than only the selected one.
    _dependencies.addListener(notifyListeners);
  }

  AsyncValue<Dependencies> get _dependencies =>
      host.project.dependencies.dependencies;

  @override
  PluginReport get report {
    var snapshot = _dependencies.value;
    return PluginReport(
      id: host.id,
      label: host.label,
      status: _status(snapshot),
      badge: snapshot.error != null ? const Badge.dot(Tone.error) : Badge.none,
      actions: const [PluginAction('reload', 'Reload')],
      view: _view(snapshot),
    );
  }

  Status _status(Snapshot<Dependencies> snapshot) {
    if (snapshot.error != null) return const Status.error('failed to load');
    var data = snapshot.data;
    if (data == null) return const Status.neutral('loading…');
    var direct = data.dependencies.where((d) => d.isDirect).length;
    return Status.neutral('$direct direct');
  }

  PluginView _view(Snapshot<Dependencies> snapshot) {
    if (snapshot.error != null) {
      return PluginView([
        ViewText('Could not read the dependencies.', tone: Tone.error),
        ViewField('Error', '${snapshot.error}'),
      ]);
    }
    var data = snapshot.data;
    if (data == null) return const PluginView([ViewText('Loading…')]);

    var all = data.dependencies.toList();
    var direct = all.where((d) => d.isDirect).toList();
    var shown = direct.take(_projectedRows).toList();

    return PluginView([
      ViewField('Direct', '${direct.length}'),
      ViewField('Transitive', '${all.length - direct.length}'),
      ViewSection('Direct dependencies', [
        ViewTable(
          const ['PACKAGE', 'VERSION'],
          [
            for (var dependency in shown)
              [dependency.name, dependency.pubspec.version?.toString() ?? ''],
          ],
          truncated: direct.length - shown.length,
        ),
      ]),
    ]);
  }

  @override
  Future<void> invoke(String actionId) async {
    if (actionId != 'reload') return super.invoke(actionId);
    await _dependencies.refresh();
  }

  @override
  Widget buildPanel(BuildContext context) => DependenciesScreen(host.project);

  @override
  void dispose() {
    _dependencies.removeListener(notifyListeners);
    super.dispose();
  }
}

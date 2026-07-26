import 'package:flutter/material.dart';
// `Dependencies` here is the app's dependency model, not the plugin
// declaration of the same name in package:flutterware.
import 'package:flutterware/plugins.dart' hide Dependencies;

import '../../dependencies/list.dart';
import '../../dependencies/model/service.dart';
import '../../ui/theme.dart';
import '../../utils/async_value.dart';
import '../native_plugin.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const dependenciesPluginId = 'flutterware.dependencies';

/// Rows the text projection carries before it starts counting. A projection is
/// read, not scrolled; the rest is reported as a count so it never looks
/// complete when it is not.
const _projectedRows = 12;

/// Pub dependencies for each declared package.
///
/// Shows the shape every native plugin follows, including the rule that matters
/// most: **nothing here starts work.** The constructor allocates nothing and
/// [report] only reads what some widget already caused to load. Loading begins
/// in [track], which the panel calls on mount and reverses on unmount.
class DependenciesPlugin extends NativePlugin {
  DependenciesPlugin(super.host);

  final _tracked = <String, VoidCallback>{};

  /// Declared packages, filtered to those the workspace knows about.
  late final List<String> packages = [
    for (var path in host.packagePaths)
      if (host.workspace.declaredAt(path) != null) path,
  ];

  /// Starts (and keeps) the load for [path]. Idempotent.
  void track(String path) {
    if (_tracked.containsKey(path)) return;
    void listener() => notifyChanged();
    _tracked[path] = listener;
    // AsyncValue loads on its first listener, so this *is* the trigger.
    _sourceFor(path).addListener(listener);
    notifyChanged();
  }

  /// Releases [path]. The data stays cached — demand says what work is
  /// justified, not what must be discarded.
  void untrack(String path) {
    var listener = _tracked.remove(path);
    if (listener == null) return;
    if (host.workspace.isRealised(path)) {
      _sourceFor(path).removeListener(listener);
    }
    notifyChanged();
  }

  AsyncValue<Dependencies> _sourceFor(String path) =>
      host.workspace.projectFor(path).dependencies.dependencies;

  /// Cached snapshot for [path], or null when nothing has looked at it yet.
  /// Deliberately does **not** realise the package's services.
  Snapshot<Dependencies>? _cached(String path) =>
      host.workspace.isRealised(path) ? _sourceFor(path).value : null;

  @override
  PluginReport get report {
    var known = <String, Snapshot<Dependencies>>{};
    for (var path in packages) {
      var snapshot = _cached(path);
      if (snapshot != null) known[path] = snapshot;
    }
    return PluginReport(
      id: host.id,
      label: host.label,
      status: _status(known),
      children: [
        for (var path in packages)
          PluginChild(
            id: path,
            label: path == '.' ? 'root' : path,
            status: _packageStatus(known[path]),
          ),
      ],
      badge: known.values.any((s) => s.error != null)
          ? const StatusBadge.dot(Tone.error)
          : StatusBadge.none,
      actions: const [PluginAction('reload', 'Reload')],
      view: _view(known),
    );
  }

  /// Summarising several packages by *summing* their dependency counts is
  /// meaningless — everything shared gets counted once per package. So the
  /// parent row counts packages and the per-package numbers live in the
  /// children.
  Status _status(Map<String, Snapshot<Dependencies>> known) {
    if (packages.isEmpty) return const Status.warn('no packages');
    if (known.values.any((s) => s.error != null)) {
      return const Status.error('failed to load');
    }
    var loaded = known.values.where((s) => s.data != null).length;
    if (loaded == 0) return Status.neutral('${packages.length} packages');
    return Status.neutral('$loaded/${packages.length} loaded');
  }

  Status _packageStatus(Snapshot<Dependencies>? snapshot) {
    if (snapshot == null) return const Status.neutral('—');
    if (snapshot.error != null) return const Status.error('failed');
    var data = snapshot.data;
    if (data == null) return const Status.neutral('loading…');
    return Status.neutral('${data.directs.length} direct');
  }

  PluginView _view(Map<String, Snapshot<Dependencies>> known) {
    if (packages.isEmpty) {
      return const PluginView([
        ViewText(
          'This plugin has no packages. Add them in tool/flutterware.dart.',
          tone: Tone.warn,
        ),
      ]);
    }

    return PluginView([
      for (var path in packages)
        ViewSection(path, [
          // Honest: nothing has looked at this package, so nothing was
          // computed. That is not the same as "zero dependencies".
          ...?(known[path] == null ? null : _packageNodes(known[path]!)),
          if (known[path] == null) const ViewText('not computed'),
        ]),
    ]);
  }

  List<ViewNode> _packageNodes(Snapshot<Dependencies> snapshot) {
    if (snapshot.error != null) {
      return [ViewField('Error', '${snapshot.error}', tone: Tone.error)];
    }
    var data = snapshot.data;
    if (data == null) return const [ViewText('loading…')];

    var direct = data.directs;
    var shown = direct.take(_projectedRows).toList();
    return [
      ViewField('Direct', '${direct.length}'),
      ViewField('Transitive', '${data.transitives.length}'),
      ViewTable(
        const ['PACKAGE', 'VERSION'],
        [
          for (var dependency in shown)
            [dependency.name, dependency.pubspec.version?.toString() ?? ''],
        ],
        truncated: direct.length - shown.length,
      ),
    ];
  }

  @override
  Future<void> invoke(String actionId) async {
    if (actionId != 'reload') return super.invoke(actionId);
    for (var path in _tracked.keys.toList()) {
      await _sourceFor(path).refresh();
    }
  }

  @override
  Widget buildPanel(BuildContext context, String? childId) =>
      _DependenciesPanel(this, childId);

  @override
  void dispose() {
    for (var path in _tracked.keys.toList()) {
      untrack(path);
    }
    super.dispose();
  }
}

/// Owns the subscription: mounting starts the load, unmounting releases it.
/// With several packages it shows a picker and tracks only the visible one.
class _DependenciesPanel extends StatefulWidget {
  const _DependenciesPanel(this.plugin, this.childId);

  final DependenciesPlugin plugin;

  /// The package the shell has selected, from the sidebar children.
  final String? childId;

  @override
  State<_DependenciesPanel> createState() => _DependenciesPanelState();
}

class _DependenciesPanelState extends State<_DependenciesPanel> {
  String? _tracked;

  String? get _path => widget.childId ?? widget.plugin.packages.firstOrNull;

  @override
  void initState() {
    super.initState();
    _retrack();
  }

  @override
  void didUpdateWidget(_DependenciesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _retrack();
  }

  /// Follows the shell's selection: only the visible package is subscribed, so
  /// switching packages stops the old load and starts the new one.
  void _retrack() {
    var wanted = _path;
    if (wanted == _tracked) return;
    if (_tracked != null) widget.plugin.untrack(_tracked!);
    _tracked = wanted;
    if (wanted != null) widget.plugin.track(wanted);
  }

  @override
  void dispose() {
    if (_tracked != null) widget.plugin.untrack(_tracked!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var path = _path;
    if (path == null) {
      return Center(
        child: Text(
          'No packages configured for this plugin.\n'
          'Add them in tool/flutterware.dart.',
          textAlign: TextAlign.center,
          style: context.type.bodyMuted,
        ),
      );
    }

    return DependenciesScreen(
      widget.plugin.host.workspace.projectFor(path),
      key: ValueKey(path),
    );
  }
}

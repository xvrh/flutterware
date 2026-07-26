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
      badge: known.values.any((s) => s.error != null)
          ? const StatusBadge.dot(Tone.error)
          : StatusBadge.none,
      actions: const [PluginAction('reload', 'Reload')],
      view: _view(known),
    );
  }

  Status _status(Map<String, Snapshot<Dependencies>> known) {
    if (packages.isEmpty) return const Status.warn('no packages');
    if (known.values.any((s) => s.error != null)) {
      return const Status.error('failed to load');
    }
    var loaded = [
      for (var snapshot in known.values)
        if (snapshot.data != null) snapshot.data!,
    ];
    if (loaded.isEmpty) return const Status.neutral('—');
    var direct = loaded.fold(0, (sum, d) => sum + d.directs.length);
    return Status.neutral('$direct direct');
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
  Widget buildPanel(BuildContext context) => _DependenciesPanel(this);

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
  const _DependenciesPanel(this.plugin);

  final DependenciesPlugin plugin;

  @override
  State<_DependenciesPanel> createState() => _DependenciesPanelState();
}

class _DependenciesPanelState extends State<_DependenciesPanel> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _path = widget.plugin.packages.firstOrNull;
    if (_path != null) widget.plugin.track(_path!);
  }

  @override
  void dispose() {
    if (_path != null) widget.plugin.untrack(_path!);
    super.dispose();
  }

  void _select(String path) {
    if (path == _path) return;
    if (_path != null) widget.plugin.untrack(_path!);
    setState(() => _path = path);
    widget.plugin.track(path);
  }

  @override
  Widget build(BuildContext context) {
    var packages = widget.plugin.packages;
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

    return Column(
      children: [
        if (packages.length > 1) _PackagePicker(packages, path, _select),
        Expanded(
          child: DependenciesScreen(
            widget.plugin.host.workspace.projectFor(path),
            key: ValueKey(path),
          ),
        ),
      ],
    );
  }
}

class _PackagePicker extends StatelessWidget {
  const _PackagePicker(this.packages, this.selected, this.onSelect);

  final List<String> packages;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.xxl,
        vertical: FwSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          for (var path in packages)
            GestureDetector(
              onTap: () => onSelect(path),
              child: Container(
                margin: const EdgeInsets.only(right: FwSpacing.xs),
                padding: const EdgeInsets.symmetric(
                  horizontal: FwSpacing.lg,
                  vertical: FwSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: path == selected
                      ? colors.accentSoft
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    context.radii.radiusSmall,
                  ),
                ),
                child: Text(
                  path,
                  style: path == selected
                      ? context.type.bodyStrong.copyWith(color: colors.accent)
                      : context.type.body,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

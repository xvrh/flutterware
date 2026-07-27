import 'dart:async';

// `Dependencies` here is the app's dependency model, not the plugin
// declaration of the same name in package:flutterware.
import 'package:flutterware/plugins.dart' hide Dependencies;

import '../../dependencies/model/service.dart';
import '../../utils/async_value.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const dependenciesPluginId = 'flutterware.dependencies';

/// Rows the text projection carries before it starts counting. A projection is
/// read, not scrolled; the rest is reported as a count so it never looks
/// complete when it is not.
const _projectedRows = 12;

/// Pub dependencies for each declared package — all of the behaviour, none of
/// the widgets.
///
/// Shows the shape every plugin core follows, including the rule that matters
/// most: **nothing here starts work.** The constructor allocates nothing and
/// [report] only reads what somebody already caused to load. Loading begins in
/// [track], which the panel calls on mount and `fw` calls for the duration of
/// a request.
class DependenciesCore extends PluginCore {
  DependenciesCore(super.host);

  final _tracked = <String, StreamSubscription<Snapshot<Dependencies>>>{};

  /// This plugin's own services, one per package, built on first use. Owned
  /// here rather than by the workspace: a service belongs to the plugin that
  /// knows what it is for.
  final _services = <String, DependenciesService>{};

  /// Declared packages, filtered to those the workspace knows about.
  late final List<String> packages = [
    for (var path in host.packagePaths)
      if (host.workspace.declaredAt(path) != null) path,
  ];

  DependenciesService serviceFor(String path) => _services.putIfAbsent(
    path,
    () => DependenciesService(host.workspace.packageFor(path)),
  );

  /// Whether [path]'s service has been built yet — the laziness rule, made
  /// observable. False until something subscribes.
  bool isRealised(String path) => _services.containsKey(path);

  /// Starts (and keeps) the load for [path]. Idempotent.
  void track(String path) {
    if (_tracked.containsKey(path)) return;
    // AsyncValue loads on its first subscriber, so this *is* the trigger.
    _tracked[path] = _sourceFor(path).listen((_) => notifyChanged());
    notifyChanged();
  }

  /// Releases [path]. The data stays cached — demand says what work is
  /// justified, not what must be discarded.
  void untrack(String path) {
    var subscription = _tracked.remove(path);
    if (subscription == null) return;
    unawaited(subscription.cancel());
    notifyChanged();
  }

  AsyncValue<Dependencies> _sourceFor(String path) =>
      serviceFor(path).dependencies;

  /// Cached snapshot for [path], or null when nothing has looked at it yet.
  /// Deliberately does **not** build the package's service.
  Snapshot<Dependencies>? _cached(String path) =>
      _services.containsKey(path) ? _services[path]!.dependencies.value : null;

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

  /// Silent once loaded. Counting dependencies across packages by *summing*
  /// them is meaningless — everything shared gets counted once per package —
  /// and the per-package number is already a click away in the panel. The row
  /// speaks only while it is working or when something went wrong.
  Status _status(Map<String, Snapshot<Dependencies>> known) {
    if (packages.isEmpty) return const Status.warn('no packages');
    if (known.values.any((s) => s.error != null)) {
      return const Status.error('failed to load');
    }
    var loading = known.values.where((s) => s.data == null).length;
    return loading == 0 ? Status.none : const Status.info('loading…');
  }

  Status _packageStatus(Snapshot<Dependencies>? snapshot) {
    if (snapshot == null) return Status.none;
    if (snapshot.error != null) return const Status.error('failed');
    if (snapshot.data == null) return const Status.info('loading…');
    return Status.none;
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
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    if (actionId != 'reload') {
      return super.invoke(actionId, arguments: arguments);
    }
    // Reload what is being watched; with nothing tracked there is nothing
    // loaded to make stale, and refreshing would be starting work from an
    // action that is meant to redo it.
    for (var path in _tracked.keys.toList()) {
      await _sourceFor(path).refresh();
    }
    return null;
  }

  /// Loads every declared package and waits — what `fw` does for the duration
  /// of one request, where there is no widget to subscribe on its behalf.
  @override
  Future<void> computeAll() async {
    for (var path in packages) {
      track(path);
    }
    await Future.wait([for (var path in packages) _sourceFor(path).refresh()]);
  }

  @override
  void dispose() {
    for (var path in _tracked.keys.toList()) {
      untrack(path);
    }
    for (var service in _services.values) {
      service.dispose();
    }
    _services.clear();
    super.dispose();
  }
}

PluginCore dependenciesCoreFactory(PluginHost host) => DependenciesCore(host);

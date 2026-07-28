import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../catalog/catalog_session.dart';
import '../../catalog/catalog_view.dart';
import '../native_plugin.dart';
import 'ui_catalog_core.dart';

export 'ui_catalog_core.dart' show UiCatalogCore, uiCatalogPluginId;

/// The GUI half of the UI catalog: the live compile loop, and a panel.
///
/// Everything else — the scan, the entry list, the report, `rescan` and
/// `screenshot` — lives in [UiCatalogCore], which is pure Dart, so `fw` and an
/// agent reach exactly the same behaviour. What stays here is
/// [CatalogSession]: it drives a guest engine into a texture, which is
/// Flutter-bound by nature.
///
/// The session is owned by the plugin rather than the panel so that leaving the
/// panel does not throw away a running daemon — and so the sidebar can say what
/// the compiler is doing while you are looking elsewhere. That progress reaches
/// the report through [UiCatalogCore.busyStatusFor].
class UiCatalogPlugin extends NativePlugin<UiCatalogCore> {
  UiCatalogPlugin(super.core) {
    core.busyStatusFor = _busyStatusFor;
  }

  final _sessions = <String, CatalogSession>{};

  List<String> get packages => core.packages;

  /// The live compile loop for [path], started on first ask — which is the
  /// panel mounting.
  CatalogSession sessionFor(String path) => _sessions.putIfAbsent(path, () {
    var session = CatalogSession(
      appPackageRoot: host.workspace.appContext.appToolDirectory.path,
      flutterSdkRoot: host.workspace.flutterSdk.root,
      projectRoot: p.join(host.worktree.path, path),
      roots: [_rootFor(path)],
    )..addListener(core.notifyChanged);
    unawaited(session.start());
    return session;
  });

  /// The package's demo directory: `entrypoint` when declared, else `demo/`.
  String _rootFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] != path) continue;
      var entrypoint = config['entrypoint'];
      if (entrypoint is String && entrypoint.isNotEmpty) return entrypoint;
    }
    return 'demo';
  }

  /// What the compiler is doing for [path], or null when it is idle.
  ///
  /// This is the status worth a sidebar row: a cold compile is the only thing
  /// here that takes seconds, and a word that stays put until it goes away is
  /// what lets you look elsewhere and notice when it lands. No elapsed count —
  /// a figure ticking in the corner of the eye is movement, not information.
  Status? _busyStatusFor(String path) {
    if (_sessions[path]?.busyWith case var busy?) return Status.info(busy);
    if (_sessions[path]?.phase == CatalogSessionPhase.error) {
      return const Status.error('failed to start');
    }
    return null;
  }

  @override
  Widget buildPanel(BuildContext context, String? childId) =>
      _CatalogPanel(plugin: this, packagePath: childId ?? packages.firstOrNull);

  /// Closing the worktree is what ends the compile loops — nothing shorter
  /// does, which is the whole point of the plugin owning them.
  @override
  void dispose() {
    for (var session in _sessions.values) {
      session
        ..removeListener(core.notifyChanged)
        ..dispose();
    }
    _sessions.clear();
    super.dispose();
  }
}

class _CatalogPanel extends StatefulWidget {
  const _CatalogPanel({required this.plugin, required this.packagePath});

  final UiCatalogPlugin plugin;
  final String? packagePath;

  @override
  State<_CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends State<_CatalogPanel> {
  @override
  void initState() {
    super.initState();
    _track();
  }

  @override
  void didUpdateWidget(_CatalogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packagePath != widget.packagePath) {
      if (oldWidget.packagePath case var previous?) {
        widget.plugin.core.untrack(previous);
      }
      _track();
    }
  }

  @override
  void dispose() {
    if (widget.packagePath case var path?) widget.plugin.core.untrack(path);
    super.dispose();
  }

  /// Mounting the panel is the demand: the scan, and the compile loop the scan
  /// deliberately leaves alone.
  void _track() {
    if (widget.packagePath case var path?) {
      widget.plugin.core.track(path);
      widget.plugin.sessionFor(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    var path = widget.packagePath;
    if (path == null) {
      return const Center(child: Text('No package declared for this plugin.'));
    }
    return AnimatedBuilder(
      animation: widget.plugin,
      builder: (context, _) {
        // The scan's own failure, which is the one that arrives first and
        // explains why the daemon would refuse to start.
        if (widget.plugin.core.failureFor(path) case var failure?) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                failure,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }

        // The live loop. The core's own scan stays — it is what `fw` and an
        // agent read without a daemon running — but what the panel shows is the
        // compiled catalog, because only the daemon knows which entries
        // actually build.
        return CatalogView(
          key: ValueKey(path),
          session: widget.plugin.sessionFor(path),
        );
      },
    );
  }
}

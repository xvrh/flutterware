import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart' hide Dependencies;

import '../../dependencies/list.dart';
import '../../ui/theme.dart';
import '../native_plugin.dart';
import '../plugin_host.dart';
import 'dependencies_core.dart';

export 'dependencies_core.dart' show DependenciesCore, dependenciesPluginId;

/// The GUI half of the dependencies plugin: a panel, and nothing else.
///
/// Every decision — what the report says, which packages are declared, what
/// `reload` does — lives in [DependenciesCore], which is pure Dart so that
/// `fw` and an agent reach exactly the same behaviour. This class exists only
/// because `buildPanel` returns a `Widget`.
class DependenciesPlugin extends NativePlugin {
  DependenciesPlugin(PluginHost host) : this._(DependenciesCore(host));

  DependenciesPlugin._(this.core) : super(core.host) {
    _changes = core.changes.listen((_) => notifyListeners());
  }

  final DependenciesCore core;
  late final StreamSubscription<int> _changes;

  List<String> get packages => core.packages;

  @override
  PluginReport get report => core.report;

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) => core.invoke(actionId, arguments: arguments);

  @override
  Widget buildPanel(BuildContext context, String? childId) =>
      _DependenciesPanel(this, childId);

  @override
  void dispose() {
    unawaited(_changes.cancel());
    core.dispose();
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

  DependenciesCore get _core => widget.plugin.core;

  String? get _path => widget.childId ?? _core.packages.firstOrNull;

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
    if (_tracked != null) _core.untrack(_tracked!);
    _tracked = wanted;
    if (wanted != null) _core.track(wanted);
  }

  @override
  void dispose() {
    if (_tracked != null) _core.untrack(_tracked!);
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

    return DependenciesScreen(_core.serviceFor(path), key: ValueKey(path));
  }
}

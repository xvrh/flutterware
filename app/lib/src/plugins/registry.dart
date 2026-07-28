import 'native_plugin.dart';
import 'plugin_core.dart';

/// Maps a declared plugin id to the **panel** compiled into this GUI binary.
///
/// Panels only. Which plugins a worktree has, and what they do, is decided by
/// `PluginCoreRegistry` when the [Session] resolves the manifest — this map is
/// asked afterwards, one core at a time, for something to draw. A plugin with
/// no entry here is fully functional from `fw` and MCP and simply has no
/// screen.
///
/// v1 is first-party only, so this is a plain map rather than any kind of
/// dynamic loading. When third-party native plugins arrive they are extra
/// pubspec entries compiled into the host-built GUI and registered here the
/// same way — the lookup does not change.
class PluginRegistry {
  PluginRegistry([Map<String, NativePluginFactory>? factories])
    : _factories = {...?factories};

  final Map<String, NativePluginFactory> _factories;

  Iterable<String> get ids => _factories.keys;

  void register(String id, NativePluginFactory factory) {
    if (_factories.containsKey(id)) {
      throw StateError('A plugin is already registered for "$id".');
    }
    _factories[id] = factory;
  }

  bool knows(String id) => _factories.containsKey(id);

  /// Builds the panel for [core], or a [MissingPlugin] when this build has
  /// none. Never returns null: a declared plugin must stay visible.
  NativePlugin create(PluginCore core) =>
      (_factories[core.id] ?? MissingPlugin.new)(core);

  /// Panels for a session's cores, in the same order — the project's order, so
  /// the sidebar reflects the config file rather than registration order.
  List<NativePlugin> resolve(List<PluginCore> cores) => [
    for (var core in cores) create(core),
  ];
}

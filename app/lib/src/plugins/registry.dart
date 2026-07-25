import 'package:flutterware/plugins.dart';

import '../shell/worktree.dart';
import 'native_plugin.dart';
import 'plugin_host.dart';

/// Maps a declared plugin id to the native implementation compiled into this
/// GUI binary.
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

  /// Instantiates the implementation for [host], or a [MissingPlugin] when this
  /// build has none. Never returns null: an undeclared id must stay visible.
  NativePlugin create(PluginHost host) =>
      (_factories[host.id] ?? MissingPlugin.new)(host);

  /// Resolves a whole manifest into live plugins for one worktree, in declared
  /// order — the order is the project's, so the sidebar reflects the config
  /// file rather than registration order.
  List<NativePlugin> resolve(PluginManifest manifest, Worktree worktree) => [
    for (var declaration in manifest.plugins)
      create(
        PluginHost(
          id: declaration.id,
          label: declaration.label,
          worktree: worktree,
          config: declaration.config,
        ),
      ),
  ];
}

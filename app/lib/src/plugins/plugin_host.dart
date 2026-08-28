// ignore: implementation_imports
import 'package:flutterware/src/scenarios/network_mode.dart';

import '../shell/workspace.dart';
import '../shell/worktree.dart';

/// The handle a native plugin is constructed with: who it is, how the project
/// configured it, and which worktree it is mounted in.
///
/// One host per (plugin, worktree) pair — the same plugin class runs once per
/// open worktree and never shares state across them.
class PluginHost {
  const PluginHost({
    required this.id,
    required this.label,
    required this.worktree,
    required this.workspace,
    this.config = const {},
    this.projectClock,
    this.projectNetwork,
  });

  /// The declared id — also the registry key its implementation was found by.
  final String id;

  /// The label the project declared, or the plugin's default.
  final String label;

  final Worktree worktree;

  /// The worktree's packages, and the services for each — built on demand.
  final Workspace workspace;

  /// What the project declared with `fw.clock(...)`, or null for
  /// flutterware's own pin.
  ///
  /// The one project-level fact a plugin is handed rather than a shell screen,
  /// because four plugins render a date and they have to render the same one.
  final DateTime? projectClock;

  /// What the project declared with `fw.network(...)`, or null for
  /// [ScenarioNetwork.off] — the lowest altitude of the four.
  final ScenarioNetwork? projectNetwork;

  /// Whatever `tool/flutterware.dart` passed for this instance. Already decoded
  /// from the manifest; plugins are responsible for validating their own keys.
  final Map<String, Object?> config;

  /// Reads a string setting, or [fallback] when absent or the wrong type.
  String? string(String key, [String? fallback]) {
    var value = config[key];
    return value is String ? value : fallback;
  }

  /// Reads a bool setting, or [fallback] when absent or the wrong type.
  bool boolean(String key, {bool fallback = false}) {
    var value = config[key];
    return value is bool ? value : fallback;
  }

  /// The `packages:` entries this plugin was declared with, as raw maps. Each
  /// plugin decodes its own per-package shape; the framework only guarantees a
  /// `path`.
  List<Map<String, Object?>> get packageConfigs => [
    for (var entry in (config['packages'] as List? ?? const []))
      if (entry is Map) entry.cast<String, Object?>(),
  ];

  /// Declared package paths, filtered to those the workspace knows about, so a
  /// typo cannot make a plugin operate on a directory that is not there.
  List<String> get packagePaths => [
    for (var entry in packageConfigs)
      if (entry['path'] is String) entry['path']! as String,
  ];
}

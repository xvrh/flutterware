import '../project.dart';
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
    required this.project,
    this.config = const {},
  });

  /// The declared id — also the registry key its implementation was found by.
  final String id;

  /// The label the project declared, or the plugin's default.
  final String label;

  final Worktree worktree;

  /// The services for this worktree's checkout — tests, dependencies, icons,
  /// the UI catalog. One [Project] per open worktree; it is disposed when the
  /// worktree closes.
  final Project project;

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
}

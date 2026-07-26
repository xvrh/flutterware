import 'package:flutter/foundation.dart';
import 'package:flutterware/plugins.dart';

import '../shell/workspace.dart';
import '../shell/worktree.dart';
import 'native_plugin.dart';
import 'registry.dart';

/// One *open* worktree: its resolved plugins and everything they hold.
///
/// The unit of the open/close lifecycle. Closing a worktree disposes this,
/// which disposes every plugin — that is what makes closing a tab release
/// watchers and subscriptions rather than merely hide them.
///
/// Worktrees that are known but not open have no session at all; anything the
/// switcher shows for them has to come from somewhere cheaper.
class WorktreeSession extends ChangeNotifier {
  WorktreeSession({required this.worktree, required List<NativePlugin> plugins})
    : plugins = List.unmodifiable(plugins) {
    for (var plugin in this.plugins) {
      plugin.addListener(notifyListeners);
    }
  }

  factory WorktreeSession.resolve({
    required Worktree worktree,
    required PluginManifest manifest,
    required PluginRegistry registry,
    required Workspace workspace,
  }) => WorktreeSession(
    worktree: worktree,
    plugins: registry.resolve(manifest, worktree, workspace),
  );

  final Worktree worktree;

  /// The resolved plugins, in the order `tool/flutterware.dart` declared them.
  final List<NativePlugin> plugins;

  bool get isDisposed => _disposed;
  var _disposed = false;

  NativePlugin? pluginById(String id) =>
      plugins.where((p) => p.id == id).firstOrNull;

  /// Every plugin's contract, in declared order — what the sidebar renders and
  /// what `fw` / an agent would read for this worktree.
  List<PluginReport> get reports => [for (var p in plugins) p.report];

  /// The worktree's own reduced state: the most severe plugin status wins, so
  /// the tab and the switcher row can show one glyph.
  Status get status {
    Status? worst;
    for (var report in reports) {
      if (report.status.isEmpty) continue;
      if (worst == null || report.status.tone.index > worst.tone.index) {
        worst = report.status;
      }
    }
    return worst ?? Status.none;
  }

  /// Teardown steps from every plugin, ordered by phase then declaration.
  List<TeardownStep> get teardownSteps {
    var steps = [for (var p in plugins) ...p.report.teardown];
    steps.sort((a, b) => a.phase.index.compareTo(b.phase.index));
    return steps;
  }

  /// Every plugin's objection to closing this worktree.
  List<Guard> get guards => [for (var p in plugins) ...p.report.guards];

  /// True when some plugin hard-blocks teardown.
  bool get isBlocked => guards.any((g) => g.level == GuardLevel.block);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (var plugin in plugins) {
      plugin.removeListener(notifyListeners);
      plugin.dispose();
    }
    super.dispose();
  }
}

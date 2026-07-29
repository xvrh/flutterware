import 'package:flutter/foundation.dart';
import 'package:flutterware/plugins.dart';

import '../session/job.dart';
import '../session/session.dart';
import '../shell/workspace.dart';
import '../shell/worktree.dart';
import 'manifest_diff.dart';
import 'native_plugin.dart';
import 'plugin_core.dart';
import 'registry.dart';

/// One *open* worktree in the GUI: a [Session], and a panel for each of its
/// plugins.
///
/// **It wraps a session rather than being one.** The two used to be parallel
/// implementations — same plugin list in the same order, same `reports`, same
/// lookup, one over panels and one over cores — and parallel implementations
/// of the same thing are how a GUI ends up able to do something no other
/// renderer can. Everything below the panels now comes from [session], so the
/// sidebar and `fw` cannot disagree, and [invoke] is the same single door the
/// CLI and MCP go through.
///
/// The unit of the open/close lifecycle. Closing a worktree disposes this,
/// which disposes every panel and then the session's cores — that is what makes
/// closing a tab release watchers and subscriptions rather than merely hide
/// them.
///
/// Worktrees that are known but not open have no session at all; anything the
/// switcher shows for them has to come from somewhere cheaper.
class WorktreeSession extends ChangeNotifier {
  // An initializing formal would have to be named `_plugins`, and a named
  // parameter cannot be private.
  WorktreeSession({
    required this.session,
    required List<NativePlugin> plugins,
    // ignore: prefer_initializing_formals
  }) : _plugins = plugins {
    for (var plugin in _plugins) {
      plugin.addListener(notifyListeners);
    }
  }

  /// Resolves a manifest into cores, then draws a panel over each.
  ///
  /// The order matters and is not an accident: cores first, because which
  /// plugins exist is not the GUI's decision to make.
  factory WorktreeSession.resolve({
    required Worktree worktree,
    required PluginManifest manifest,
    required PluginRegistry registry,
    required Workspace workspace,
    PluginCoreRegistry? coreRegistry,
  }) {
    var session = Session.resolved(
      worktree: worktree,
      workspace: workspace,
      manifest: manifest,
      registry: coreRegistry,
    );
    return WorktreeSession(
      session: session,
      plugins: registry.resolve(session.cores),
    );
  }

  /// The plugin behaviour, shared with every other renderer.
  final Session session;

  Worktree get worktree => session.worktree;

  /// The resolved panels, in the order `tool/flutterware.dart` declared them.
  ///
  /// Unmodifiable to callers; [reconcile] is the only writer.
  List<NativePlugin> get plugins => List.unmodifiable(_plugins);

  List<NativePlugin> _plugins;

  /// Re-runs the plugin graph against a new manifest, keeping everything the
  /// edit did not touch.
  ///
  /// **This is where a guest engine survives a reload.** `UiCatalogPlugin`
  /// holds a `CatalogSession` per package — the compile loop and the texture
  /// live in the *panel*, not the core — so keeping the core while rebuilding
  /// the panel over it would still cost the device. A retained core keeps its
  /// panel, by identity.
  ///
  /// Ordering is [session]'s to enforce: `onRelease` disposes a panel before
  /// the core beneath it goes, which is the same rule [dispose] follows, stated
  /// once instead of twice.
  List<String> reconcile(
    PluginManifest manifest,
    ManifestDiff diff, {
    required PluginRegistry registry,
    PluginCoreRegistry? coreRegistry,
  }) {
    if (diff.isEmpty) return const [];

    var panels = {for (var plugin in _plugins) plugin.core: plugin};

    var rebuilt = session.reconcile(
      manifest,
      diff,
      registry: coreRegistry,
      onRelease: (core) {
        panels.remove(core)
          ?..removeListener(notifyListeners)
          ..dispose();
      },
    );

    _plugins = [
      for (var core in session.cores)
        panels[core] ?? (registry.create(core)..addListener(notifyListeners)),
    ];

    notifyListeners();
    return rebuilt;
  }

  bool get isDisposed => _disposed;
  var _disposed = false;

  NativePlugin? pluginById(String id) =>
      plugins.where((p) => p.id == id).firstOrNull;

  /// Every plugin's contract, in declared order — what the sidebar renders and
  /// what `fw` / an agent read for this worktree. The same objects, from the
  /// same cores.
  List<PluginReport> get reports => session.reports;

  /// Runs one of the declared actions.
  ///
  /// Straight through to [Session.invoke], deliberately without a GUI-specific
  /// path: a button and `fw run` must be the same call, or the parity rule is
  /// enforced for two renderers out of three.
  Job invoke(
    String plugin,
    String action, {
    Map<String, Object?> arguments = const {},
  }) => session.invoke(plugin, action, arguments: arguments);

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
    var steps = [for (var report in reports) ...report.teardown];
    steps.sort((a, b) => a.phase.index.compareTo(b.phase.index));
    return steps;
  }

  /// Every plugin's objection to closing this worktree.
  List<Guard> get guards => [for (var report in reports) ...report.guards];

  /// True when some plugin hard-blocks teardown.
  bool get isBlocked => guards.any((g) => g.level == GuardLevel.block);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Panels first, then the behaviour under them: a panel disposing after its
    // core would be drawing something already torn down. [reconcile] honours
    // the same order through its `onRelease`, so the two paths cannot drift.
    for (var plugin in _plugins) {
      plugin.removeListener(notifyListeners);
      plugin.dispose();
    }
    session.dispose();
    super.dispose();
  }
}

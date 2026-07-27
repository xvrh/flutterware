import 'dart:io';

import 'package:flutterware/plugins.dart';

// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';

import '../context.dart';
import '../plugins/manifest_loader.dart';
import '../plugins/native/dependencies_core.dart';
import '../plugins/native/ui_catalog_core.dart';
import '../plugins/plugin_core.dart';
import '../shell/workspace.dart';
import '../shell/worktree.dart';
import '../shell/worktree_discovery.dart';
import '../utils/flutter_sdk.dart';

/// One open worktree, and the plugin cores for it — the thing `fw`, MCP and
/// (later) the GUI all drive.
///
/// Pure Dart on purpose. It is what makes "no renderer is privileged" true
/// rather than aspirational: the CLI does not reimplement the GUI's behaviour,
/// it instantiates the same [PluginCore]s.
///
/// **Laziness is subscription.** A widget subscribes for as long as it is
/// mounted; `fw` subscribes for the duration of a request and releases. Same
/// sources, same rule, no GUI required — so a cold `fw status` honestly reports
/// "not computed" for anything nobody has looked at, and computing is something
/// the caller asks for explicitly.
class Session {
  Session._(this.root, this.worktree, this.workspace, this.cores);

  /// The worktree root — where `tool/flutterware.dart` lives.
  final String root;

  final Worktree worktree;
  final Workspace workspace;

  /// One core per declared plugin, in the order the config declared them.
  final List<PluginCore> cores;

  /// Opens the session for whichever repo [start] sits in.
  ///
  /// Walks up to the repo root, the same idiom the shell uses — one window (or
  /// one CLI invocation) per repo, regardless of where you started.
  static Future<Session> open(
    Directory start, {
    PluginCoreRegistry? registry,
    FlutterSdkPath? flutterSdk,
  }) async {
    var root = findRepoRoot(start.path);
    if (root == null) {
      throw SessionException(
        'Not inside a flutterware project: ${start.path}\n'
        'Run this from a git worktree with a tool/flutterware.dart.',
      );
    }

    var sdk = flutterSdk ?? await _defaultSdk();

    var loaded = await ManifestLoader(dartExecutable: sdk.dart).tryLoad(root);
    if (loaded.error != null) {
      throw SessionException('tool/flutterware.dart failed:\n${loaded.error}');
    }
    // No config file is not an error — the worktree opens with no plugins,
    // exactly as it does in the GUI.
    var manifest = loaded.manifest ?? const PluginManifest([]);

    var workspace = Workspace(
      root: root,
      declared: manifest.packages.isEmpty
          ? const [Pkg('.')]
          : manifest.packages,
      discovered: discoverPackages(root),
      appContext: AppContext(logger: LogClient.print()),
      flutterSdk: sdk,
    );

    var worktrees = await WorktreeDiscovery().discover(root);
    var worktree = worktrees.firstWhere(
      (w) => w.path == root,
      orElse: () => Worktree(path: root),
    );

    return Session._(
      root,
      worktree,
      workspace,
      (registry ?? defaultCoreRegistry()).resolve(
        manifest,
        worktree,
        workspace,
      ),
    );
  }

  static Future<FlutterSdkPath> _defaultSdk() async {
    var found = (await FlutterSdkPath.findSdks()).firstOrNull;
    if (found == null) {
      throw SessionException(
        'No Flutter SDK found. flutterware needs one to run '
        'tool/flutterware.dart.',
      );
    }
    return found;
  }

  PluginCore? coreById(String id) =>
      cores.where((core) => core.id == id).firstOrNull;

  /// The core whose id ends with [name], so `fw run dependencies reload` works
  /// without spelling out `flutterware.dependencies`. Ambiguity is an error
  /// rather than a guess.
  PluginCore? coreByShortName(String name) {
    var exact = coreById(name);
    if (exact != null) return exact;
    var matches = cores
        .where((core) => core.id.split('.').last == name)
        .toList();
    if (matches.length > 1) {
      throw SessionException(
        '"$name" is ambiguous: ${matches.map((c) => c.id).join(', ')}',
      );
    }
    return matches.firstOrNull;
  }

  /// Every plugin's contract. A pure read — nothing here starts work.
  List<PluginReport> get reports => [for (var core in cores) core.report];

  void dispose() {
    for (var core in cores) {
      core.dispose();
    }
    workspace.dispose();
  }
}

/// The cores compiled into this binary.
///
/// Deliberately **not** every plugin the GUI has. A plugin appears here once
/// its behaviour is separable from its panel; until then it resolves to a
/// [MissingPluginCore] and `fw` says so out loud rather than omitting it.
PluginCoreRegistry defaultCoreRegistry() => PluginCoreRegistry({
  dependenciesPluginId: dependenciesCoreFactory,
  uiCatalogPluginId: uiCatalogCoreFactory,
});

class SessionException implements Exception {
  SessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    var it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

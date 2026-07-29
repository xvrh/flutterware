import 'dart:async';
import 'dart:io';

import 'package:flutterware/plugins.dart';

// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';

import '../context.dart';
import '../plugins/manifest_loader.dart';
import '../plugins/native/assets_core.dart';
import '../plugins/native/dependencies_core.dart';
import '../plugins/native/ui_catalog_core.dart';
import '../plugins/plugin_core.dart';
import '../shell/workspace.dart';
import '../shell/worktree.dart';
import '../shell/worktree_discovery.dart';
import '../utils/flutter_sdk.dart';
import 'job.dart';

/// One open worktree, and the plugin cores for it — the thing `fw`, MCP and
/// (later) the GUI all drive.
///
/// Pure Dart on purpose. It is what makes "no renderer is privileged" true
/// rather than aspirational: the CLI does not reimplement the GUI's behaviour,
/// it instantiates the same [PluginCore]s.
///
/// **Laziness is subscription.** A widget subscribes for as long as it is
/// mounted; `fw` subscribes for the duration of a request and releases. Same
/// sources, same rule, no GUI required.
///
/// What laziness buys is that *reading* a report is free — which is what lets
/// the GUI read one per sidebar row per frame. It is not a reason to make a
/// caller ask twice: a `fw` process has no history to be lazy about, so
/// `fw status` loads and then reports.
class Session {
  Session._(
    this.root,
    this.worktree,
    this.workspace,
    this.cores,
    this._ownsWorkspace,
  );

  /// Builds a session over pieces the caller has already resolved.
  ///
  /// The GUI's way in: the shell has run the config file and built the
  /// [Workspace] before it knows whether the worktree will open at all, so it
  /// cannot go through [open] — and a second resolution would be a second
  /// answer to "which plugins does this worktree have".
  ///
  /// The workspace stays the caller's to dispose; the cores are this session's.
  factory Session.resolved({
    required Worktree worktree,
    required Workspace workspace,
    required PluginManifest manifest,
    PluginCoreRegistry? registry,
  }) => Session._(
    worktree.path,
    worktree,
    workspace,
    (registry ?? defaultCoreRegistry()).resolve(manifest, worktree, workspace),
    false,
  );

  /// Whether disposing this session also disposes the workspace under it.
  ///
  /// True for [open], which built it; false for [Session.resolved], where the
  /// shell owns the workspace and outlives the session on a reload.
  final bool _ownsWorkspace;

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
      true,
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

  /// [coreByShortName], but a miss is an error rather than null.
  ///
  /// The message names what *is* declared, because that is the recovery path,
  /// and it lives here so every surface reports a bad plugin name the same way
  /// — whether it was about to run something or only about to describe it.
  PluginCore requireCore(String plugin) {
    var core = coreByShortName(plugin);
    if (core == null) {
      throw SessionException(
        'No plugin "$plugin". Declared: ${cores.map((c) => c.id).join(', ')}',
      );
    }
    return core;
  }

  /// Every plugin's contract. A pure read — nothing here starts work.
  List<PluginReport> get reports => [for (var core in cores) core.report];

  /// Runs one plugin action. **The only way an action is ever run.**
  ///
  /// Every renderer goes through here — `fw`, the MCP server, and a GUI panel's
  /// button — which is what makes the parity rule checkable rather than
  /// aspirational: a capability that is not a declared [PluginAction] is not
  /// expressible, because there is no other door.
  ///
  /// It is also the seam. Recording the run, joining two clients onto one
  /// execution, reporting progress, and one day forwarding the whole thing to a
  /// daemon are all changes to this method — one edit each, rather than one per
  /// renderer, which is the arrangement that lets a renderer quietly miss one.
  ///
  /// [plugin] may be a full id or its last dotted segment.
  ///
  /// **Throws for an unknown plugin; records an unknown action as a failed
  /// job.** The line is the same one [Address] draws: the framework owns the
  /// namespace up to and including the plugin, and everything past it belongs
  /// to the plugin. Naming a plugin that does not exist means no run happened
  /// and there is nothing to write down. Naming a bad action is a real
  /// invocation of a real plugin that came back with an error, which is worth
  /// recording — an agent guessing action names leaves a trail that says so.
  Job invoke(
    String plugin,
    String action, {
    Map<String, Object?> arguments = const {},
  }) {
    var core = requireCore(plugin);

    Map<String, Object?> coerced;
    try {
      coerced = _coerce(core, action, arguments);
    } on ArgumentError catch (e, stackTrace) {
      // A value of the wrong kind is a failed job, not a throw — the same line
      // an unknown action falls on. A real plugin and a real action were named
      // and the run did not survive its arguments, which is a run, and both
      // renderers already know how to report one.
      var controller = JobController(
        id: newJobId(),
        plugin: core.id,
        action: action,
        arguments: arguments,
      );
      controller.fail(e, stackTrace);
      return controller.job;
    }

    var controller = JobController(
      id: newJobId(),
      // The resolved id, not what the caller typed.
      plugin: core.id,
      action: action,
      arguments: coerced,
    );
    unawaited(_run(core, controller));
    return controller.job;
  }

  /// Arguments as the action declared them, not as the transport delivered
  /// them.
  ///
  /// A shell has no types: `--loud=true` arrives as the *string* `'true'`, and
  /// a plugin asking `arguments['loud'] == true` gets false — silently, and
  /// only on the CLI, while the same call over MCP (where JSON carries a real
  /// bool) works. Found by the surface-parity test rather than by a person,
  /// which is the point of having one.
  ///
  /// So the declared `ActionParameterKind` is applied here, once, at the single
  /// door — rather than in each renderer, or by hand in every core. Parameters
  /// the action does not declare are passed through untouched: the framework
  /// parses up to the plugin and no further, and an action is free to accept
  /// more than it advertises.
  Map<String, Object?> _coerce(
    PluginCore core,
    String action,
    Map<String, Object?> arguments,
  ) {
    if (arguments.isEmpty) return arguments;
    var declared = {
      for (var candidate in core.report.actions)
        if (candidate.id == action)
          for (var parameter in candidate.parameters) parameter.id: parameter,
    };
    if (declared.isEmpty) return arguments;

    return {
      for (var entry in arguments.entries)
        entry.key: switch (declared[entry.key]?.kind) {
          // Only text needs converting; anything already typed came from a
          // transport that has types, and second-guessing it would be how
          // `7.0` becomes `7`.
          null ||
          ActionParameterKind.string ||
          ActionParameterKind.choice => entry.value,
          ActionParameterKind.boolean => _asBoolean(entry.key, entry.value),
          ActionParameterKind.integer => _asInteger(entry.key, entry.value),
        },
    };
  }

  static Object? _asBoolean(String name, Object? value) => switch (value) {
    bool() || null => value,
    // The spellings a shell and a person actually produce. A bare `--flag` is
    // already `true` before it gets here.
    String text => switch (text.toLowerCase()) {
      'true' || 'yes' || '1' => true,
      'false' || 'no' || '0' => false,
      _ => throw ArgumentError.value(value, name, 'expected true or false'),
    },
    _ => throw ArgumentError.value(value, name, 'expected true or false'),
  };

  static Object? _asInteger(String name, Object? value) => switch (value) {
    int() || null => value,
    String text =>
      int.tryParse(text) ??
          (throw ArgumentError.value(value, name, 'expected an integer')),
    _ => throw ArgumentError.value(value, name, 'expected an integer'),
  };

  Future<void> _run(PluginCore core, JobController controller) async {
    try {
      var value = await core.invoke(
        controller.job.action,
        arguments: controller.job.arguments,
      );
      _checkDeclaredReturn(core, controller.job.action, value);
      controller.succeed(value);
    } catch (e, stackTrace) {
      controller.fail(e, stackTrace);
    }
  }

  /// Fails a run whose result is not the type its action promised.
  ///
  /// An action's `returns` is not a comment: the capability document resolves
  /// it statically and publishes that class's fields as the shape callers can
  /// expect. So a mismatch is not a style problem, it is a document describing
  /// a response nobody sends — and the cheapest moment to notice is the run
  /// that produced it, on whichever surface asked.
  ///
  /// Exact rather than `is`: a subclass would serialise fields the published
  /// shape does not mention, which is the same failure one layer quieter. (A
  /// `Type` cannot be used with `is` anyway, so the check has to name it.)
  void _checkDeclaredReturn(PluginCore core, String action, Object? value) {
    var declared = core.report.actions
        .where((candidate) => candidate.id == action)
        .map((candidate) => candidate.returns)
        .firstOrNull;
    if (declared == null || value == null) return;
    if (value.runtimeType == declared) return;
    throw StateError(
      '${core.id}/$action declares it returns $declared but returned '
      '${value.runtimeType}. Either the action or its `returns:` is wrong; '
      'the capability document believes the declaration.',
    );
  }

  void dispose() {
    for (var core in cores) {
      core.dispose();
    }
    if (_ownsWorkspace) workspace.dispose();
  }
}

/// The cores compiled into this binary.
///
/// Deliberately **not** every plugin the GUI has. A plugin appears here once
/// its behaviour is separable from its panel; until then it resolves to a
/// [MissingPluginCore] and `fw` says so out loud rather than omitting it.
PluginCoreRegistry defaultCoreRegistry() => PluginCoreRegistry({
  assetsPluginId: assetsCoreFactory,
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

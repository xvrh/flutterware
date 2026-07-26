import 'package:flutter/foundation.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../context.dart';
import '../plugins/manifest_loader.dart';
import '../plugins/registry.dart';
import '../plugins/worktree_session.dart';
import '../utils/flutter_sdk.dart';
import 'workspace.dart';
import 'worktree.dart';
import 'worktree_discovery.dart';

/// Why a worktree could not be opened. Kept per worktree so a broken config in
/// one checkout never takes down the shell.
class WorktreeError {
  const WorktreeError(this.worktree, this.message);
  final Worktree worktree;
  final String message;
}

/// Owns the shell's state: which worktrees exist, which are open, and what is
/// selected.
///
/// Only *open* worktrees have a [WorktreeSession] and a [Project]; the rest are
/// names in the switcher and cost nothing. Closing releases both, which is what
/// makes the open/close lifecycle real rather than cosmetic.
class ShellController extends ChangeNotifier {
  ShellController({
    required this.appContext,
    required this.flutterSdk,
    required this.registry,
    required this.manifestLoader,
    WorktreeDiscovery? discovery,
  }) : _discovery = discovery ?? WorktreeDiscovery();

  final AppContext appContext;
  final FlutterSdkPath flutterSdk;
  final PluginRegistry registry;
  final ManifestLoader manifestLoader;
  final WorktreeDiscovery _discovery;

  var _worktrees = <Worktree>[];
  final _sessions = <String, WorktreeSession>{};
  final _workspaces = <String, Workspace>{};
  final _errors = <String, WorktreeError>{};

  String? _selectedPath;
  String? _selectedPluginId;
  String? _selectedChildId;
  var _busy = false;

  /// Every worktree git reports, main first.
  List<Worktree> get worktrees => List.unmodifiable(_worktrees);

  /// The open ones, in the order they were opened.
  List<Worktree> get openWorktrees => [
    for (var path in _sessions.keys) _worktreeAt(path)!,
  ];

  List<Worktree> get closedWorktrees => [
    for (var w in _worktrees)
      if (!_sessions.containsKey(w.path)) w,
  ];

  bool isOpen(Worktree worktree) => _sessions.containsKey(worktree.path);

  WorktreeSession? sessionFor(Worktree worktree) => _sessions[worktree.path];

  WorktreeError? errorFor(Worktree worktree) => _errors[worktree.path];

  Workspace? workspaceFor(Worktree worktree) => _workspaces[worktree.path];

  Worktree? get selected =>
      _selectedPath == null ? null : _worktreeAt(_selectedPath!);

  WorktreeSession? get selectedSession =>
      _selectedPath == null ? null : _sessions[_selectedPath!];

  /// The plugin whose panel is mounted, or null when the worktree has none.
  String? get selectedPluginId => _selectedPluginId;

  /// The selected sub-entry of that plugin — a package path — or null.
  String? get selectedChildId => _selectedChildId;

  /// True while opening a worktree — the manifest runs a subprocess.
  bool get isBusy => _busy;

  Worktree? _worktreeAt(String path) =>
      _worktrees.where((w) => w.path == path).firstOrNull;

  /// Discovers the project's worktrees and opens **only** the one the app was
  /// launched in. Everything else is opened deliberately from the switcher.
  ///
  /// The launch directory is first walked **up** to its repo root, so starting
  /// in `packages/admin/lib` opens the one window for the whole repo rather
  /// than failing to match any worktree.
  Future<void> start(String launchDirectory) async {
    var root = findRepoRoot(launchDirectory) ?? launchDirectory;
    _worktrees = await _discovery.discover(root);
    notifyListeners();

    var rootPath = p.canonicalize(root);
    var launch =
        _worktrees
            .where((w) => p.canonicalize(w.path) == rootPath)
            .firstOrNull ??
        _worktrees.firstOrNull;
    if (launch != null) await open(launch);
  }

  /// Re-reads `git worktree list`. Open worktrees that disappeared are closed.
  Future<void> refresh() async {
    if (_worktrees.isEmpty) return;
    _worktrees = await _discovery.discover(_worktrees.first.path);
    for (var path in _sessions.keys.toList()) {
      if (_worktreeAt(path) == null) _closeAt(path);
    }
    notifyListeners();
  }

  /// Opens [worktree]: runs its config, resolves its plugins, and selects it.
  ///
  /// A worktree that fails to open is still selected, so the shell can show why
  /// rather than silently doing nothing.
  Future<void> open(Worktree worktree) async {
    if (isOpen(worktree)) {
      select(worktree);
      return;
    }

    _busy = true;
    _errors.remove(worktree.path);
    notifyListeners();

    try {
      var result = await manifestLoader.tryLoad(worktree.path);
      if (result.error != null) {
        _errors[worktree.path] = WorktreeError(worktree, result.error!);
      }

      // No config file is not an error — the worktree opens with no plugins.
      var manifest = result.manifest ?? const PluginManifest([]);
      var workspace = Workspace(
        root: worktree.path,
        declared: manifest.packages.isEmpty
            // A project that declares nothing still has itself.
            ? const [Pkg('.')]
            : manifest.packages,
        discovered: discoverPackages(worktree.path),
        appContext: appContext,
        flutterSdk: flutterSdk,
      );
      _workspaces[worktree.path] = workspace;

      // Never clobber a config-load failure: that is the more useful error,
      // and a broken config is often *why* the declarations look wrong.
      var unknown = workspace.unknownDeclarations;
      if (unknown.isNotEmpty && !_errors.containsKey(worktree.path)) {
        _errors[worktree.path] = WorktreeError(
          worktree,
          'Declared package(s) not found on disk: ${unknown.join(', ')}',
        );
      }

      _sessions[worktree.path] = WorktreeSession.resolve(
        worktree: worktree,
        manifest: manifest,
        registry: registry,
        workspace: workspace,
      )..addListener(notifyListeners);

      _selectedPath = worktree.path;
      _selectPluginInternal(_sessions[worktree.path]!.plugins.firstOrNull?.id);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Closes [worktree], disposing its plugins and its [Project].
  ///
  /// Refuses while a plugin hard-blocks teardown; the caller is expected to have
  /// shown the guard reasons already.
  bool close(Worktree worktree) {
    var session = _sessions[worktree.path];
    if (session == null) return true;
    if (session.isBlocked) return false;
    _closeAt(worktree.path);
    notifyListeners();
    return true;
  }

  void _closeAt(String path) {
    _sessions.remove(path)
      ?..removeListener(notifyListeners)
      ..dispose();
    _workspaces.remove(path)?.dispose();
    _errors.remove(path);
    if (_selectedPath == path) {
      _selectedPath = _sessions.keys.lastOrNull;
      _selectPluginInternal(selectedSession?.plugins.firstOrNull?.id);
    }
  }

  void select(Worktree worktree) {
    if (!isOpen(worktree)) return;
    _selectedPath = worktree.path;
    _selectPluginInternal(selectedSession?.plugins.firstOrNull?.id);
    notifyListeners();
  }

  void selectPlugin(String id) {
    _selectPluginInternal(id);
    notifyListeners();
  }

  /// Selects a plugin's sub-entry, and the plugin with it.
  void selectChild(String pluginId, String childId) {
    _selectedPluginId = pluginId;
    _selectedChildId = childId;
    notifyListeners();
  }

  /// Selecting a plugin defaults to its first child, so a panel always has a
  /// concrete sub-entry to render rather than an ambiguous null.
  void _selectPluginInternal(String? id) {
    _selectedPluginId = id;
    var plugin = id == null ? null : selectedSession?.pluginById(id);
    _selectedChildId = plugin?.report.children.firstOrNull?.id;
  }

  @override
  void dispose() {
    for (var path in _sessions.keys.toList()) {
      _closeAt(path);
    }
    super.dispose();
  }
}

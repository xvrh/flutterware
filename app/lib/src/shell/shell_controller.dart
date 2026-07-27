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

/// What a worktree's sidebar is pointed at. A null [pluginId] is the worktree's
/// home screen, which is where a freshly opened worktree lands.
typedef Selection = ({String? pluginId, String? childId});

const Selection _home = (pluginId: null, childId: null);

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

  /// Open worktrees, in the order they were opened. This — not [_sessions] — is
  /// what the tabs are drawn from, so a worktree gets its tab the moment it is
  /// opened rather than when its config finally finishes running.
  final _openPaths = <String>[];

  final _sessions = <String, WorktreeSession>{};
  final _workspaces = <String, Workspace>{};
  final _errors = <String, WorktreeError>{};
  final _selections = <String, Selection>{};

  /// Bumped per path on every load, so a load whose worktree was closed or
  /// reloaded underneath it drops its result instead of resurrecting a session.
  final _loads = <String, int>{};

  String? _selectedPath;

  /// Every worktree git reports, main first.
  List<Worktree> get worktrees => List.unmodifiable(_worktrees);

  /// The open ones, in the order they were opened — including those still
  /// loading.
  List<Worktree> get openWorktrees => [
    for (var path in _openPaths) ?_worktreeAt(path),
  ];

  List<Worktree> get closedWorktrees => [
    for (var w in _worktrees)
      if (!_openPaths.contains(w.path)) w,
  ];

  bool isOpen(Worktree worktree) => _openPaths.contains(worktree.path);

  /// Open, but its config has not finished running yet. The tab exists; the
  /// session does not.
  bool isLoading(Worktree worktree) =>
      isOpen(worktree) && !_sessions.containsKey(worktree.path);

  WorktreeSession? sessionFor(Worktree worktree) => _sessions[worktree.path];

  WorktreeError? errorFor(Worktree worktree) => _errors[worktree.path];

  Workspace? workspaceFor(Worktree worktree) => _workspaces[worktree.path];

  Worktree? get selected =>
      _selectedPath == null ? null : _worktreeAt(_selectedPath!);

  WorktreeSession? get selectedSession =>
      _selectedPath == null ? null : _sessions[_selectedPath!];

  /// The plugin whose panel is mounted, or null when the home screen is.
  String? get selectedPluginId {
    var id = _selection?.pluginId;
    if (id == null) return null;
    // A reloaded config may no longer declare it; fall back to home rather than
    // to a panel that cannot be built.
    var session = _sessions[_selectedPath!];
    if (session != null && session.pluginById(id) == null) return null;
    return id;
  }

  /// The selected sub-entry of that plugin — a package path — or null.
  String? get selectedChildId =>
      selectedPluginId == null ? null : _selection?.childId;

  /// True while the selected worktree is showing its home screen.
  bool get isHome => selectedPluginId == null;

  Selection? get _selection =>
      _selectedPath == null ? null : _selections[_selectedPath!];

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
  ///
  /// Cheap enough to run whenever the switcher is opened, which is what keeps
  /// the list current without a watcher.
  Future<void> rescanWorktrees() async {
    if (_worktrees.isEmpty) return;
    _worktrees = await _discovery.discover(_worktrees.first.path);
    for (var path in _openPaths.toList()) {
      if (_worktreeAt(path) == null) _closeAt(path);
    }
    notifyListeners();
  }

  /// Opens [worktree]: the tab appears immediately, then its config runs and
  /// its plugins resolve.
  ///
  /// A worktree that fails to open is still selected, so the shell can show why
  /// rather than silently doing nothing.
  Future<void> open(Worktree worktree) async {
    if (isOpen(worktree)) {
      select(worktree);
      return;
    }

    _openPaths.add(worktree.path);
    _selectedPath = worktree.path;
    _selections[worktree.path] = _home;
    // The tab is on screen before the manifest subprocess starts; everything
    // below it draws a loader until the session lands.
    notifyListeners();

    await _load(worktree);
  }

  /// Re-runs the selected worktree's config and rebuilds its plugins.
  ///
  /// Refuses while a plugin hard-blocks teardown: a reload disposes exactly what
  /// a close does, so it has to answer to the same guards.
  Future<bool> reloadConfig() async {
    var worktree = selected;
    if (worktree == null) return false;
    if (_sessions[worktree.path]?.isBlocked ?? false) return false;

    _releaseAt(worktree.path);
    notifyListeners();
    await _load(worktree);
    return true;
  }

  Future<void> _load(Worktree worktree) async {
    var path = worktree.path;
    var generation = (_loads[path] ?? 0) + 1;
    _loads[path] = generation;
    _errors.remove(path);

    PluginManifest? manifest;
    String? error;
    try {
      var result = await manifestLoader.tryLoad(path);
      manifest = result.manifest;
      error = result.error;
    } catch (e) {
      error = '$e';
    }

    // Closed, or superseded by a later reload, while the config ran.
    if (_loads[path] != generation || !_openPaths.contains(path)) return;

    if (error != null) _errors[path] = WorktreeError(worktree, error);

    // No config file is not an error — the worktree opens with no plugins.
    manifest ??= const PluginManifest([]);
    var workspace = Workspace(
      root: path,
      declared: manifest.packages.isEmpty
          // A project that declares nothing still has itself.
          ? const [Pkg('.')]
          : manifest.packages,
      discovered: discoverPackages(path),
      appContext: appContext,
      flutterSdk: flutterSdk,
    );
    _workspaces[path] = workspace;

    // Never clobber a config-load failure: that is the more useful error,
    // and a broken config is often *why* the declarations look wrong.
    var unknown = workspace.unknownDeclarations;
    if (unknown.isNotEmpty && !_errors.containsKey(path)) {
      _errors[path] = WorktreeError(
        worktree,
        'Declared package(s) not found on disk: ${unknown.join(', ')}',
      );
    }

    _sessions[path] = WorktreeSession.resolve(
      worktree: worktree,
      manifest: manifest,
      registry: registry,
      workspace: workspace,
    )..addListener(notifyListeners);

    notifyListeners();
  }

  /// Closes [worktree], disposing its plugins and its [Project].
  ///
  /// Refuses while a plugin hard-blocks teardown; the caller is expected to have
  /// shown the guard reasons already.
  bool close(Worktree worktree) {
    if (!isOpen(worktree)) return true;
    if (_sessions[worktree.path]?.isBlocked ?? false) return false;
    _closeAt(worktree.path);
    notifyListeners();
    return true;
  }

  void _closeAt(String path) {
    _releaseAt(path);
    _openPaths.remove(path);
    _selections.remove(path);
    _loads.remove(path);
    if (_selectedPath == path) _selectedPath = _openPaths.lastOrNull;
  }

  /// Drops everything a load produced, keeping the tab and its selection. What
  /// a reload starts from, and what a close finishes.
  void _releaseAt(String path) {
    _sessions.remove(path)
      ?..removeListener(notifyListeners)
      ..dispose();
    _workspaces.remove(path)?.dispose();
    _errors.remove(path);
  }

  void select(Worktree worktree) {
    if (!isOpen(worktree)) return;
    _selectedPath = worktree.path;
    notifyListeners();
  }

  /// Returns the selected worktree to its home screen.
  void selectHome() {
    if (_selectedPath == null) return;
    _selections[_selectedPath!] = _home;
    notifyListeners();
  }

  /// Selecting a plugin defaults to its first child, so a panel always has a
  /// concrete sub-entry to render rather than an ambiguous null.
  void selectPlugin(String id) {
    if (_selectedPath == null) return;
    var plugin = selectedSession?.pluginById(id);
    _selections[_selectedPath!] = (
      pluginId: id,
      childId: plugin?.report.children.firstOrNull?.id,
    );
    notifyListeners();
  }

  /// Selects a plugin's sub-entry, and the plugin with it.
  void selectChild(String pluginId, String childId) {
    if (_selectedPath == null) return;
    _selections[_selectedPath!] = (pluginId: pluginId, childId: childId);
    notifyListeners();
  }

  @override
  void dispose() {
    for (var path in _openPaths.toList()) {
      _closeAt(path);
    }
    super.dispose();
  }
}

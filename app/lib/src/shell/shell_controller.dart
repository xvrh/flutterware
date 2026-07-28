import 'package:flutter/foundation.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../context.dart';
import '../plugins/manifest_loader.dart';
import '../plugins/plugin_core.dart';
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
    this.coreRegistry,
    WorktreeDiscovery? discovery,
  }) : _discovery = discovery ?? WorktreeDiscovery();

  final AppContext appContext;
  final FlutterSdkPath flutterSdk;

  /// Which panels this build can draw.
  final PluginRegistry registry;

  /// Which cores this build can run. Null means the default set — the same one
  /// `fw` and MCP link, which is what keeps the three from drifting.
  final PluginCoreRegistry? coreRegistry;
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

  /// Where each open worktree was left, so switching tabs comes back to the
  /// same place rather than to its home screen. Keyed by path because that is
  /// what everything else here is keyed by; the value is an [Address] like any
  /// other, so restoring a tab is the same write as any other navigation.
  final _remembered = <String, Address>{};

  /// Bumped per path on every load, so a load whose worktree was closed or
  /// reloaded underneath it drops its result instead of resurrecting a session.
  final _loads = <String, int>{};

  /// **Where the shell is.** The one piece of navigation state; everything
  /// below is read off it, and every way of moving is a write to it.
  ///
  /// Null before the first worktree opens. Its `worktree` is a directory name
  /// (see [Worktree.name]) rather than a path, because that is what an address
  /// carries and what makes one pasted from `fw` or an artifact resolve here.
  Address? get address => _address;
  Address? _address;

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

  /// The open worktree the address names, or null when it names none.
  ///
  /// Resolved by name, so an address that arrived from outside — pasted, or
  /// carried by an artifact — lands on the right tab without the writer having
  /// known this machine's paths.
  Worktree? get selected {
    var name = _address?.worktree;
    if (name == null) return null;
    return openWorktrees.where((w) => w.name == name).firstOrNull;
  }

  WorktreeSession? get selectedSession {
    var path = selected?.path;
    return path == null ? null : _sessions[path];
  }

  /// The plugin whose panel is mounted, or null when the home screen is.
  String? get selectedPluginId {
    var id = _address?.plugin;
    if (id == null) return null;
    // A reloaded config may no longer declare it; fall back to home rather than
    // to a panel that cannot be built.
    var session = selectedSession;
    if (session != null && session.pluginById(id) == null) return null;
    return id;
  }

  /// The selected sub-entry of that plugin — a package path — or null.
  ///
  /// The first segment after the plugin. Anything deeper belongs to the plugin
  /// and the shell does not read it: a catalog entry is the catalog's business,
  /// which is what keeps this from growing a case per plugin.
  String? get selectedChildId =>
      selectedPluginId == null ? null : _address?.segments.firstOrNull;

  /// True while the selected worktree is showing its home screen.
  bool get isHome => selectedPluginId == null;

  /// Whether the plugin rail is showing.
  ///
  /// Hiding it gives the whole window to the panel, which is what a catalog
  /// wants once you are looking at a device rather than choosing what to look
  /// at. Not per worktree: it is a preference about the window, and having it
  /// come back on every tab switch would be its own small annoyance.
  bool get sidebarVisible => _sidebarVisible;
  var _sidebarVisible = true;

  void toggleSidebar() {
    _sidebarVisible = !_sidebarVisible;
    notifyListeners();
  }

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
    // Before the session exists: the tab and its address are what the loader
    // draws under.
    _address = Address(worktree: worktree.name);
    _remembered[worktree.path] = _address!;
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
      coreRegistry: coreRegistry,
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
    // Read before the tab goes: `selected` resolves through `openWorktrees`,
    // so after the removal it can no longer recognise the worktree it names
    // and the address would be left pointing at a closed tab.
    var wasSelected = selected?.path == path;
    _releaseAt(path);
    _openPaths.remove(path);
    _remembered.remove(path);
    _loads.remove(path);
    if (wasSelected) {
      var fallback = _openPaths.lastOrNull;
      _address = fallback == null ? null : _addressFor(fallback);
    }
  }

  /// Where a tab should reopen: where it was left, else its home screen.
  Address? _addressFor(String path) {
    var worktree = _worktreeAt(path);
    if (worktree == null) return null;
    return _remembered[path] ?? Address(worktree: worktree.name);
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

  /// **The one way the shell moves.** Every `select…` below is a call to this,
  /// and so is opening a search hit or a pasted address.
  ///
  /// Refuses an address whose worktree is not open — navigation must not
  /// silently land somewhere other than where it was told, and opening a
  /// worktree is a decision with a cost, made by [open].
  ///
  /// The address is remembered against its worktree on the way through, so a
  /// tab switched away from and back comes home to the same place.
  void go(Address destination) {
    var name = destination.worktree;
    var worktree = name == null
        ? null
        : openWorktrees.where((w) => w.name == name).firstOrNull;
    if (worktree == null) return;
    if (destination == _address) return;

    _address = destination;
    _remembered[worktree.path] = destination;
    notifyListeners();
  }

  /// Switches tabs, returning to wherever that tab was left.
  void select(Worktree worktree) {
    if (!isOpen(worktree)) return;
    var destination = _addressFor(worktree.path);
    if (destination != null) go(destination);
  }

  /// Returns the selected worktree to its home screen.
  void selectHome() {
    if (_address?.worktree case var name?) go(Address(worktree: name));
  }

  /// Selecting a plugin defaults to its first child, so a panel always has a
  /// concrete sub-entry to render rather than an ambiguous null.
  void selectPlugin(String id) {
    var name = _address?.worktree;
    if (name == null) return;
    var child = selectedSession
        ?.pluginById(id)
        ?.core
        .report
        .children
        .firstOrNull
        ?.id;
    go(Address(worktree: name, plugin: id, segments: [?child]));
  }

  /// Selects a plugin's sub-entry, and the plugin with it.
  void selectChild(String pluginId, String childId) {
    var name = _address?.worktree;
    if (name == null) return;
    go(Address(worktree: name, plugin: pluginId, segments: [childId]));
  }

  @override
  void dispose() {
    for (var path in _openPaths.toList()) {
      _closeAt(path);
    }
    super.dispose();
  }
}

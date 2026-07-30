import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterware/plugins.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../context.dart';
import '../plugins/manifest_diff.dart';
import '../plugins/manifest_loader.dart';
import '../plugins/plugin_core.dart';
import '../plugins/registry.dart';
import '../plugins/worktree_session.dart';
import '../utils/flutter_sdk.dart';
import 'config_load.dart';
import 'config_watcher.dart';
import 'workspace.dart';
import 'worktree.dart';
import 'worktree_discovery.dart';

final _logger = Logger('shell');

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
    DateTime Function()? now,
    Stream<WatchEvent> Function(String directory)? watchEvents,
    Duration? watchDebounce,
  }) : _discovery = discovery ?? WorktreeDiscovery(),
       _now = now ?? DateTime.now,
       // ignore: prefer_initializing_formals
       _watchEvents = watchEvents,
       // ignore: prefer_initializing_formals
       _watchDebounce = watchDebounce;

  /// Injectable so the reload log is deterministic under test.
  final DateTime Function() _now;

  /// Injectable so a test can drive a save without a filesystem.
  final Stream<WatchEvent> Function(String directory)? _watchEvents;
  final Duration? _watchDebounce;

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

  /// The manifest each open worktree's plugins were built from — what the next
  /// load is compared against.
  ///
  /// Kept across a *failed* load on purpose: the next success must diff against
  /// the config that is actually running, not against nothing, or fixing a
  /// syntax error would rebuild everything even when the fix restored the
  /// original file.
  final _manifests = <String, PluginManifest>{};

  /// Reload history per worktree, newest first, capped.
  final _log = <String, List<ConfigLoad>>{};

  final _watchers = <String, ConfigWatcher>{};

  /// Paths whose config changed while a plugin was hard-blocking teardown.
  ///
  /// **A watcher may not silently do nothing.** Refusing is the right answer for
  /// a button — you pressed it, you get told — but a save that quietly failed to
  /// take effect is indistinguishable from a watcher that is not working, which
  /// is the whole failure mode this feature has to avoid. So the change is held
  /// and applied the moment the guard clears.
  final _pending = <String>{};

  /// Whether saving `tool/flutterware.dart` reloads it.
  ///
  /// On by default — realtime reload is the point. The switch exists because a
  /// filesystem that does not deliver native watch events would otherwise leave
  /// a watcher that looks armed and is not, and turning it off says so.
  bool get watchEnabled => _watchEnabled;
  var _watchEnabled = true;

  set watchEnabled(bool value) {
    if (_watchEnabled == value) return;
    _watchEnabled = value;
    if (value) {
      for (var path in _openPaths) {
        if (_worktreeAt(path) case var worktree?) _startWatching(worktree);
      }
    } else {
      for (var watcher in _watchers.values) {
        unawaited(watcher.dispose());
      }
      _watchers.clear();
      _pending.clear();
    }
    notifyListeners();
  }

  /// True when [worktree]'s config changed but a guard is holding the reload.
  bool isReloadPending(Worktree worktree) => _pending.contains(worktree.path);

  /// The directory whose changes reach [worktree], or null when nothing is
  /// watched — the honest answer to "why did it not notice my edit".
  String? watchingFor(Worktree worktree) => _watchers[worktree.path]?.watching;

  void _startWatching(Worktree worktree) {
    if (!_watchEnabled || _watchers.containsKey(worktree.path)) return;
    var watcher = ConfigWatcher(
      worktreePath: worktree.path,
      onChanged: () => _onConfigChanged(worktree),
      watch: _watchEvents,
      debounce: _watchDebounce ?? const Duration(milliseconds: 250),
    );
    _watchers[worktree.path] = watcher;
    unawaited(watcher.start());
  }

  Future<void> _onConfigChanged(Worktree worktree) async {
    var path = worktree.path;
    // Closed between the save and the debounce settling.
    if (!_openPaths.contains(path)) return;

    if (_sessions[path]?.isBlocked ?? false) {
      _pending.add(path);
      notifyListeners();
      return;
    }
    _pending.remove(path);
    // Awaited so the watcher knows a reload is in flight and folds anything
    // that lands during it into one follow-up.
    await _load(worktree);
  }

  /// A session notification, which is also the only moment a guard is known to
  /// have cleared.
  void _onSessionChanged(String path) {
    notifyListeners();
    if (!_pending.contains(path)) return;
    if (_sessions[path]?.isBlocked ?? true) return;
    if (_worktreeAt(path) case var worktree?) {
      _pending.remove(path);
      unawaited(_load(worktree));
    }
  }

  static const _logLimit = 20;

  /// What the last load of [worktree]'s config did, or null before the first.
  ConfigLoad? lastLoad(Worktree worktree) => _log[worktree.path]?.firstOrNull;

  /// Every load of [worktree]'s config this session, newest first.
  List<ConfigLoad> loadLog(Worktree worktree) =>
      List.unmodifiable(_log[worktree.path] ?? const []);

  /// What [worktree]'s config resolved to — the manifest its plugins were built
  /// from, and what the next load is compared against.
  ///
  /// Null when no load has succeeded yet, which is not the same as a worktree
  /// with no plugins: that one has an empty manifest.
  PluginManifest? manifestFor(Worktree worktree) => _manifests[worktree.path];

  void _record(String path, ConfigLoad load) {
    var rows = _log.putIfAbsent(path, () => []);
    rows.insert(0, load);
    if (rows.length > _logLimit) rows.removeRange(_logLimit, rows.length);

    // Also to the terminal that launched the GUI. The screen is the surface for
    // someone using flutterware; this is the one for someone whose config just
    // reloaded while they were watching a log scroll past, and it is how a
    // reload is observable at all without a window in front of you.
    _logger.info(
      'config ${p.basename(path)}: ${load.summary} '
      '(${load.duration.inMilliseconds}ms)'
      '${load.error == null ? '' : '\n${load.error}'}',
    );
  }

  /// **Where the shell is.** The one piece of navigation state; everything
  /// below is read off it, and every way of moving is a write to it.
  ///
  /// Always present, though it may name nothing — `fw:///` before the first
  /// worktree opens, and again if the last one closes. A nullable address would
  /// make every reader below handle two empties.
  ///
  /// Its `worktree` is git's own name for the checkout (see [Worktree.name])
  /// rather than a path, because that is what an address carries and what makes
  /// one pasted from `fw` or an artifact resolve here.
  Address get address => _address.value;

  /// The address on its own, for widgets that want to rebuild when it moves and
  /// not when a session finishes loading.
  ///
  /// What `AddressRoot` listens to. Separate from [notifyListeners] on purpose:
  /// this notifier is how a change reaches exactly the widgets that read the
  /// part that changed, and routing it through the shell's blanket
  /// notification instead would rebuild the window for a slider.
  ValueListenable<Address> get addressListenable => _address;

  final _address = ValueNotifier<Address>(Address());

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
    var name = address.worktree;
    return name == null ? null : worktreeNamed(name, among: openWorktrees);
  }

  /// The worktree [name] refers to, by [Worktree.name] first and by branch
  /// second.
  ///
  /// **Forgiving input, canonical output.** Nothing ever *writes* a branch into
  /// an address — that would be an address that silently retargets when the
  /// branch is checked out somewhere else. But a branch is what a tab shows and
  /// therefore what someone types, so an address naming one still lands.
  ///
  /// Identity is checked across the whole set before any branch is, so a name
  /// that is one worktree's identity and another's branch resolves to the
  /// identity. The canonical form always wins, whichever order the list is in.
  Worktree? worktreeNamed(String name, {Iterable<Worktree>? among}) {
    var candidates = among ?? _worktrees;
    return candidates.where((w) => w.name == name).firstOrNull ??
        candidates.where((w) => w.branch == name).firstOrNull;
  }

  WorktreeSession? get selectedSession {
    var path = selected?.path;
    return path == null ? null : _sessions[path];
  }

  /// True while the address names the shell's own config screen.
  ///
  /// It occupies the plugin slot but is not a plugin, so it is neither
  /// [selectedPluginId] nor [isHome] — a third place, and the only one the
  /// shell itself owns.
  bool get isConfigScreen => address.plugin == Address.shellConfig;

  /// Moves to `fw://<worktree>/config`.
  void selectConfig() {
    if (address.worktree case var name?) {
      go(Address(worktree: name, plugin: Address.shellConfig));
    }
  }

  /// The plugin whose panel is mounted, or null when the home or config screen
  /// is.
  String? get selectedPluginId {
    var id = address.plugin;
    if (id == null || id == Address.shellConfig) return null;
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
      selectedPluginId == null ? null : address.segments.firstOrNull;

  /// True while the selected worktree is showing its home screen.
  bool get isHome => !isConfigScreen && selectedPluginId == null;

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

  /// Opens [worktree] at its home screen: the tab appears immediately, then its
  /// config runs and its plugins resolve.
  ///
  /// A worktree that fails to open is still selected, so the shell can show why
  /// rather than silently doing nothing.
  ///
  /// To open one *and* land somewhere inside it, pass the whole address to
  /// [go] — it opens what it needs to.
  Future<void> open(Worktree worktree) async {
    if (isOpen(worktree)) {
      select(worktree);
      return;
    }

    var loaded = _openTab(worktree);
    // Before the session exists: the tab and its address are what the loader
    // draws under.
    go(Address(worktree: worktree.name));
    await loaded;
  }

  /// Gives [worktree] a tab and starts its config running.
  ///
  /// Deliberately says nothing about the address. [open] lands on the home
  /// screen; [go] lands on wherever it was pointed, which is the whole reason
  /// this is separate from either.
  Future<void> _openTab(Worktree worktree) {
    _openPaths.add(worktree.path);
    _startWatching(worktree);
    // The tab is on screen before the manifest subprocess starts; everything
    // below it draws a loader until the session lands.
    notifyListeners();
    return _load(worktree);
  }

  /// Re-runs the selected worktree's config and applies whatever moved.
  ///
  /// Refuses while a plugin hard-blocks teardown. A reload can dispose what a
  /// close does — for the plugins it rebuilds — so it answers to the same
  /// guards. Returns false without logging a load: nothing ran.
  ///
  /// **Does not release anything up front.** Which plugins pay for a reload is
  /// decided after the config has run and been compared; releasing first would
  /// make a config that fails to compile cost the whole worktree.
  Future<bool> reloadConfig() async {
    var worktree = selected;
    if (worktree == null) return false;
    if (_sessions[worktree.path]?.isBlocked ?? false) return false;

    await _load(worktree);
    return true;
  }

  /// Runs a worktree's config and reconciles the plugin graph against it.
  ///
  /// Four outcomes, and the split is the whole point (see
  /// `2026-07-29-config-reload-findings.md`):
  ///
  /// - **failed** — nothing is torn down. The error surfaces and every plugin
  ///   keeps running, because a half-written file must not cost a worktree.
  /// - **unchanged** — the manifest matched, so not a single object moves.
  ///   Re-running the config *is* the comparison; a comment or a reformat lands
  ///   here without anything having to detect a comment.
  /// - **rebuilt** — `packages:` moved, so the workspace and every core go.
  /// - **reconciled** — only the plugins whose declaration moved are disposed
  ///   and rebuilt.
  Future<void> _load(Worktree worktree) async {
    var path = worktree.path;
    var generation = (_loads[path] ?? 0) + 1;
    _loads[path] = generation;
    var started = _now();
    var watch = Stopwatch()..start();

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

    void record(
      ConfigLoadOutcome outcome, {
      List<String> rebuilt = const [],
      Map<String, String> reasons = const {},
      String? error,
    }) => _record(
      path,
      ConfigLoad(
        at: started,
        duration: watch.elapsed,
        outcome: outcome,
        rebuilt: rebuilt,
        reasons: reasons,
        error: error,
      ),
    );

    if (error != null) {
      // Deliberately before any release, and deliberately keeping
      // `_manifests[path]`: the plugins built from the last good config are
      // still the ones running, and the next success must diff against the
      // config they came from rather than against nothing.
      _errors[path] = WorktreeError(worktree, error);

      // Nothing to preserve on a *first* load, and a tab with no session reads
      // as one that is still loading forever. Give it the empty session it used
      // to get, so the shell can explain instead of spinning.
      if (!_sessions.containsKey(path)) {
        _build(worktree, const PluginManifest([]));
        // Not `_manifests[path]`: an empty manifest is not what the config
        // said, and recording it would make the eventual fix look like an
        // ordinary reload that added every plugin.
        _manifests.remove(path);
      }

      record(ConfigLoadOutcome.failed, error: error);
      notifyListeners();
      return;
    }

    // No config file is not an error — the worktree opens with no plugins.
    manifest ??= const PluginManifest([]);
    _errors.remove(path);

    var previous = _manifests[path];
    var existing = _sessions[path];

    if (previous != null && existing != null && !existing.isDisposed) {
      ManifestDiff diff;
      try {
        diff = ManifestDiff.between(previous, manifest);
      } catch (e) {
        _errors[path] = WorktreeError(worktree, '$e');
        record(ConfigLoadOutcome.failed, error: '$e');
        notifyListeners();
        return;
      }

      if (diff.isEmpty) {
        record(ConfigLoadOutcome.unchanged);
        notifyListeners();
        return;
      }

      if (!diff.needsFullRebuild) {
        List<String> rebuilt;
        try {
          rebuilt = existing.reconcile(
            manifest,
            diff,
            registry: registry,
            coreRegistry: coreRegistry,
          );
        } catch (e) {
          // A core or panel constructor that throws on the new declaration.
          // `reconcile` builds before it disposes, so the session is intact —
          // this is the same shape as a config that would not compile, and it
          // gets the same answer: nothing is torn down and the reason is shown.
          // Without this the exception escapes an unawaited `_load` and the
          // worktree silently keeps its old plugins with nothing to say why.
          _errors[path] = WorktreeError(worktree, '$e');
          record(ConfigLoadOutcome.failed, error: '$e');
          notifyListeners();
          return;
        }
        _manifests[path] = manifest;
        record(
          ConfigLoadOutcome.reconciled,
          rebuilt: rebuilt,
          reasons: {for (var id in rebuilt) id: ?diff.reasonFor(id)},
        );
        notifyListeners();
        return;
      }
    }

    // Either the first load of this worktree, or `packages:` moved. Both build
    // from nothing; only the second one cost anything.
    var opening = previous == null || existing == null;
    _releaseAt(path);
    _build(worktree, manifest);
    record(
      opening ? ConfigLoadOutcome.built : ConfigLoadOutcome.rebuilt,
      rebuilt: [for (var p in manifest.plugins) p.id],
      reasons: opening
          ? const {}
          : {for (var p in manifest.plugins) p.id: 'packages changed'},
    );
    notifyListeners();
  }

  /// Builds the workspace and session for a manifest, from nothing.
  ///
  /// Everything here touches the disk, and since `go` opens a worktree without
  /// awaiting the load, there is no caller left to catch what it throws. A tab
  /// with no session and no reason is a worktree that looks like it opened and
  /// then does nothing.
  void _build(Worktree worktree, PluginManifest manifest) {
    var path = worktree.path;
    try {
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
      )..addListener(() => _onSessionChanged(path));
      _manifests[path] = manifest;
    } catch (e) {
      _errors.putIfAbsent(path, () => WorktreeError(worktree, '$e'));
    }
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
    // The retained manifest and the reload history belong to an *open*
    // worktree; keeping either would have a reopened tab diff against a config
    // whose plugins are long gone.
    _manifests.remove(path);
    _log.remove(path);
    _pending.remove(path);
    // A watcher outliving its tab is exactly the leak the open/close lifecycle
    // exists to prevent.
    unawaited(_watchers.remove(path)?.dispose());
    if (wasSelected) {
      var fallback = _openPaths.lastOrNull;
      _address.value =
          (fallback == null ? null : _addressFor(fallback)) ?? Address();
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
    _sessions.remove(path)?.dispose();
    _workspaces.remove(path)?.dispose();
    _errors.remove(path);
  }

  /// **The one way the shell moves.** Every `select…` below is a call to this,
  /// and so is opening a search hit or a pasted address.
  ///
  /// **Opening is the navigation.** An address naming a closed worktree opens
  /// it and lands inside it. This used to refuse, on the grounds that opening
  /// costs a subprocess and should be a deliberate act — but the cost is the
  /// user's to spend and they spent it by naming the worktree, and refusing to
  /// go where you were told is itself landing somewhere you were not.
  ///
  /// Still synchronous. The tab and the address are in place before the config
  /// starts, and everything under them draws a loader until the session lands —
  /// which is what [open] already did, and is why nothing here has to wait.
  ///
  /// A name matching no worktree git reports is the one refusal left, and it
  /// says so rather than returning nothing: something that lets you type an
  /// address has to explain what happened to it.
  ///
  /// The address is remembered against its worktree on the way through, so a
  /// tab switched away from and back comes home to the same place.
  GoResult go(Address destination) {
    var name = destination.worktree;
    var worktree = name == null ? null : worktreeNamed(name);
    if (worktree == null) return GoResult.worktreeUnknown;

    // The tab first, so the resolution below and everything that reads
    // `selected` afterwards can see it.
    if (!isOpen(worktree)) unawaited(_openTab(worktree));

    // **Canonicalised on the way in**, so a branch is only ever input. Accepting
    // one and then keeping it would put a name that moves with `git checkout`
    // into [_remembered], into the bar, and into every artifact minted from
    // where the shell is — which is the retarget the identity rule exists to
    // prevent. This is the one place that can rewrite it, because it is the one
    // place that knows which worktree the name found.
    destination = destination.copyWith(worktree: worktree.name);

    if (destination == address) return GoResult.unchanged;

    // Read before the write, so the comparison is against where we were.
    var moved = destination.bare != address.bare;

    _address.value = destination;
    _remembered[worktree.path] = destination;

    // **Only when the shell's own reading of the address changed.** Everything
    // this notification serves — the tabs, the rail, which panel is mounted —
    // is derived from the identity: the worktree, the plugin, the segments.
    // Applied parameters are for whoever reads them, and they reach exactly
    // those readers through [addressListenable] and the address scope above
    // them.
    //
    // Not an optimisation. Dragging a slider writes a value per frame, and
    // rebuilding the window at the frame rate of a drag is what the per-key
    // scope exists to prevent — it cannot, while every write also marks the
    // whole shell dirty.
    if (moved) notifyListeners();
    return GoResult.ok;
  }

  /// Switches tabs, returning to wherever that tab was left — opening the
  /// worktree first if it was closed, since [go] does.
  void select(Worktree worktree) {
    var destination = _addressFor(worktree.path);
    if (destination != null) go(destination);
  }

  /// Returns the selected worktree to its home screen.
  void selectHome() {
    if (address.worktree case var name?) go(Address(worktree: name));
  }

  /// Selecting a plugin defaults to its first child, so a panel always has a
  /// concrete sub-entry to render rather than an ambiguous null.
  ///
  /// The one place navigation fills in something it was not told, and it is
  /// allowed here because choosing a plugin off the rail carries no deeper
  /// intent. An address that arrived *already* naming something is never
  /// completed or corrected — see [GoResult].
  void selectPlugin(String id) {
    var name = address.worktree;
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
    var name = address.worktree;
    if (name == null) return;
    go(Address(worktree: name, plugin: pluginId, segments: [childId]));
  }

  /// **The same place, in another checkout.**
  ///
  /// Everything except the worktree rides along — the plugin, the package, the
  /// entry, the device, the theme, the knobs — because all of it is in the one
  /// value being copied. That is what makes this a *comparison* rather than a
  /// navigation: the same demo, framed the same way, on another branch.
  ///
  /// Distinct from [select], which is the other thing you might mean. Switching
  /// tabs takes you to where that worktree was left; this brings where you are
  /// to that worktree. Both are wanted and they are not the same move.
  ///
  /// A worktree that does not have what the address names is *not* handled
  /// here. The panel reports it — the catalog already refuses to quietly repair
  /// an address naming an entry it has never heard of — and that complaint is
  /// the answer to "was this only ever on my branch?".
  GoResult goToWorktree(Worktree worktree) =>
      go(address.copyWith(worktree: worktree.name));

  /// Flicks to the next open worktree, keeping the address. Negative goes back.
  ///
  /// **Open ones only**, which is the difference between this and picking from
  /// the switcher. A keystroke that spawned a config subprocess would be a
  /// keystroke you learn not to press; the ones already open are free, and with
  /// two of them this is the A/B flick the whole feature is for. Opening a
  /// third is a deliberate act, and it joins the rotation once it is done.
  GoResult cycleWorktree(int delta) {
    var open = openWorktrees;
    if (open.length < 2) return GoResult.unchanged;
    var current = selected;
    var index = current == null ? -1 : open.indexOf(current);
    // Dart's `%` is never negative for a positive divisor, so stepping back
    // from the first wraps to the last without a special case.
    return goToWorktree(open[(index + delta) % open.length]);
  }

  @override
  void dispose() {
    for (var path in _openPaths.toList()) {
      _closeAt(path);
    }
    _address.dispose();
    super.dispose();
  }
}

/// What [ShellController.go] did with an address.
///
/// Exists so the address bar can say what happened. A navigation that silently
/// does nothing is indistinguishable from a broken app, and that is precisely
/// the case a pasted address hits most.
enum GoResult {
  ok,

  /// Already there. Not a failure — just nothing to do.
  unchanged,

  /// No worktree by that name, or the address named none at all.
  worktreeUnknown,
}

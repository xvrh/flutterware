import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../address/address_scope.dart';
import '../../launcher_icon/model/scan.dart' show representativeIconPath;
import '../../previews/devices.dart';
import '../../previews/web_server.dart';
import '../../scenarios/web_export_dialog.dart';
import '../../scenarios/artifacts.dart';
import '../../scenarios/artifacts_io.dart';
import '../../scenarios/beat_view.dart';
import '../../scenarios/axes.dart';
import '../../scenarios/browsing.dart';
import '../../scenarios/discovery.dart';
import '../../scenarios/flow_view.dart';
import '../../scenarios/harness_entrypoint.dart';
import '../../scenarios/help_page.dart';
import '../../scenarios/list_tree.dart';
import '../../scenarios/new_scenario_dialog.dart';
import '../../scenarios/step_page.dart';
import '../../ui/aside.dart';
import '../../ui/empty_state.dart';
import '../../ui/matched_text.dart';
import '../../ui/menu.dart';
import '../../ui/popover.dart';
import '../../ui/popover_menu.dart';
import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../../utils/directory_watch.dart';
import '../native_plugin.dart';
import 'scenarios_address.dart';
import 'scenarios_core.dart';
import 'scenarios_results.dart';
import '../../ui/loading_state.dart';
import '../../ui/error_state.dart';
import 'no_packages.dart';

export 'scenarios_core.dart' show ScenariosCore, scenariosPluginId;

/// The GUI half of the scenarios plugin — dev_studio's proven shape on the
/// shell: the scenario list as a master pane on the left, the selected
/// scenario's run as a full-page flow of device-framed screenshots, and a
/// step pushed over it with a back button.
///
/// Everything the pages show comes out of [ScenariosCore.panelRunFor]; the
/// panel starts runs and draws state, and that is all it does.
class ScenariosPlugin extends NativePlugin<ScenariosCore> {
  ScenariosPlugin(super.core, {this.watchSources});

  /// How the panel watches the scan root, for tests that need the timing rules
  /// without a filesystem — the seam every other watcher in this app has
  /// (`WorktreeWatcher`, `WorkingTreeWatcher`, `ConfigWatcher`). Null is the
  /// real `dart:io` watch.
  final WatchDirectory? watchSources;

  /// A server per served directory, so re-exporting the same page reuses the
  /// port a browser tab already has open — the tab reloads onto the new run
  /// rather than pointing at a server that has gone.
  final _servers = <String, CatalogWebServer>{};

  final _browsing = <String, ScenarioBrowsing>{};

  /// How [package]'s list is folded, for as long as this worktree is open.
  ///
  /// Here rather than on the list pane, which the shell rebuilds from scratch
  /// on every visit to the plugin — see [ScenarioBrowsing] for what that cost.
  /// The same lifetime the catalog gives its own browser state, which lives on
  /// the session the previews plugin keeps per package.
  ScenarioBrowsing browsingFor(String package) =>
      _browsing.putIfAbsent(package, ScenarioBrowsing.new);

  @override
  String? get busyWith {
    if (core.anyPanelRunning) return 'running scenarios';
    if (core.packages.any(core.isScanning)) return 'scanning scenarios';
    return null;
  }

  @override
  Widget buildPanel(BuildContext context) => _ScenariosPanel(this);

  /// One command, on the row for the package it would export.
  ///
  /// On the row rather than in the panel because that is what it is *of*: a
  /// page is one package's whole suite, and the panel is always looking at one
  /// scenario of it.
  @override
  List<PluginChildCommand> childCommands(
    BuildContext context,
    String childId,
  ) => [
    PluginChildCommand(
      label: 'Export a web page…',
      icon: Icons.language,
      onSelected: (context) => unawaited(
        showScenarioWebExportDialog(
          context,
          core: core,
          package: childId,
          serve: serveExport,
        ),
      ),
    ),
  ];

  /// Serves an exported page and answers with the URL, starting a server only
  /// if this directory has not got one.
  ///
  /// Owned here rather than by the dialog that asks for it: the dialog is
  /// closed the moment you have the URL, and a server that died with it would
  /// leave the tab it just opened showing a connection error. The worktree is
  /// the right lifetime.
  ///
  /// A page **needs** this — it fetches its report and every artifact relative
  /// to itself, which a browser refuses on a `file://` page. There is no
  /// double-click-the-html path to offer.
  Future<Uri> serveExport(String output, {String basePath = '/'}) async {
    var directory = p.isAbsolute(output)
        ? output
        : p.join(host.worktree.path, output);
    var existing = _servers[directory];
    if (existing != null &&
        existing.basePath == CatalogWebServer.normaliseBasePath(basePath)) {
      return existing.url;
    }
    await existing?.close();
    var server = await CatalogWebServer.serve(directory, basePath: basePath);
    _servers[directory] = server;
    return server.url;
  }

  @override
  void dispose() {
    for (var server in _servers.values) {
      unawaited(server.close());
    }
    _servers.clear();
    for (var browsing in _browsing.values) {
      browsing.dispose();
    }
    _browsing.clear();
    super.dispose();
  }
}

/// Owns the subscription: mounting starts the scan, as the laziness rule
/// requires — a package is scanned because its panel is visible.
class _ScenariosPanel extends StatefulWidget {
  const _ScenariosPanel(this.plugin);

  final ScenariosPlugin plugin;

  @override
  State<_ScenariosPanel> createState() => _ScenariosPanelState();
}

class _ScenariosPanelState extends State<_ScenariosPanel> {
  ScenariosCore get _core => widget.plugin.core;

  /// The device last used in each **pool** of scenarios, keyed by the folder
  /// whose `flutter_test_config.dart` governs it (`''` for an ungoverned
  /// one). dev_studio's `_mobileDevice` / `_desktopDevice`, generalised to
  /// however many folders a project has.
  ///
  /// Without it the device is one sticky address parameter: pick an iPhone on
  /// a phone scenario, open a desktop one, and it renders a laptop layout at
  /// 390 points wide — overflow stripes rather than a picture. A pool is
  /// exactly the scope that choice makes sense in, and the folder is its
  /// identity, readable off the filesystem without compiling anything.
  final _deviceByPool = <String, String?>{};

  /// The pool the address's `?device=` currently belongs to, or null before
  /// the first scenario is opened.
  String? _pool;

  /// Memoised because [testConfigFolderFor] stats the disk and the answer
  /// changes only when a config file is added.
  final _poolCache = <(String, String), String>{};

  String _poolFor(String package, String file) =>
      _poolCache.putIfAbsent((package, file), () {
        return testConfigFolderFor(_core.packageRootFor(package), file) ?? '';
      });

  /// Swaps the remembered device when the opened scenario belongs to another
  /// pool: what was on screen is kept under the pool being left, and the pool
  /// being entered gets back whatever it last used — or nothing, which lets
  /// its own profile answer.
  ///
  /// The first pool observed **adopts** the address as it stands, so a pasted
  /// `?device=` link opens on the device it names.
  void _followPool(ScenarioPlace place) {
    if (place.file case var file?) {
      var pool = _poolFor(place.package, file);
      if (pool == _pool) return;
      var current = AddressScope.param(context, 'device');
      if (_pool case var leaving?) {
        _deviceByPool[leaving] = current;
      } else {
        _deviceByPool[pool] = current;
      }
      _pool = pool;
      var wanted = _deviceByPool[pool];
      if (wanted != current) {
        // After the frame: this runs from didChangeDependencies, and the
        // address is somebody else's state.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) AddressScope.write(context).setParam('device', wanted);
        });
      }
    }
  }

  /// The place the address names, or the first declared package when it names
  /// none — where selecting the plugin off the rail leaves you.
  ScenarioPlace? _resolve() {
    if (scenarioPlace(AddressScope.segments(context)) case var place?) {
      return place;
    }
    var package = _core.packages.firstOrNull;
    return package == null ? null : ScenarioPlace(package);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolve() case var place?) {
      _core.track(place.package);
      _watchSources(place.package);
      _followPool(place);
      // Only once a scenario is open: listing compiles the harness, and the
      // page that opens one is about to pay for that anyway.
      if (place.file != null) _core.trackListings(place.package);
    }
  }

  /// The directory [_sources] is watching — the *root*, not the package, so a
  /// configured `directory` that moves re-arms rather than going quietly deaf.
  String? _watching;
  DirectoryWatch? _sources;
  StreamSubscription<void>? _sourceEvents;

  /// Keeps the list pane honest about a suite that changes under it.
  ///
  /// The scan is otherwise one-shot for the life of the worktree session.
  /// `track` returns early once a package has been scanned, and the only two
  /// things that ever replaced that scan were finishing a run and writing a
  /// file through the New dialog — so an agent adding twenty scenarios while
  /// you watched the panel changed nothing on screen, and opening one made the
  /// list catch up for a reason that had nothing to do with the edit.
  ///
  /// Mounted-only, like the previews panel's poll: a package is scanned because
  /// its panel is visible, and it stays live for the same reason. The sidebar's
  /// per-package count is still as old as the last scan, which is the honest
  /// scope — watching every declared package's `test/` for a badge is the cost
  /// the laziness rule exists to avoid.
  ///
  /// Dart only, and that filter is what makes it affordable: the scan root is
  /// `test/`, but nothing stops a suite keeping golden images or fixtures
  /// beside its tests, and a rescan is worth exactly one thing — a
  /// `scenario('…')` call appearing, moving or going.
  void _watchSources(String package) {
    var root = p.join(
      _core.packageRootFor(package),
      _core.scanRootFor(package),
    );
    if (_watching == root) return;
    _watching = root;
    unawaited(_sourceEvents?.cancel());
    unawaited(_sources?.dispose());
    var sources = _sources = DirectoryWatch(
      directory: root,
      accept: (path) => path.endsWith('.dart'),
      // A parse of the whole scan root measured 26–34 ms off-isolate on a
      // 212-file suite, so the floor is here to bound an agent writing without
      // pause rather than to protect anything expensive.
      minInterval: const Duration(seconds: 1),
      watch: widget.plugin.watchSources,
    )..start();
    _sourceEvents = sources.changes.listen((_) {
      if (mounted) _core.rescan(package);
    });
  }

  @override
  void dispose() {
    unawaited(_sourceEvents?.cancel());
    unawaited(_sources?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var place = _resolve();
    if (place == null) {
      return const NoPackagesConfigured(icon: Icons.route_outlined);
    }

    // The axes ride the address as plain parameters, above the segments —
    // pick French and an iPhone once, and every scenario you open runs that
    // way. No `?device=` stays no device: the scenario's own folder answers
    // that, inside the harness. An unknown one is reported by the page, not
    // repaired here.
    var axes = ScenarioAxes(
      device: switch (AddressScope.param(context, 'device')) {
        var id? when !isDeviceId(id) => null,
        var id => id,
      },
      language: AddressScope.param(context, 'language'),
      textScale: double.tryParse(
        AddressScope.param(context, 'text-scale') ?? '',
      ),
      brightness: switch (AddressScope.param(context, 'brightness')) {
        'light' => 'light',
        'dark' => 'dark',
        _ => null,
      },
      boldText: AddressScope.param(context, 'bold-text') == 'true',
      highContrast: AddressScope.param(context, 'high-contrast') == 'true',
      invertColors: AddressScope.param(context, 'invert-colors') == 'true',
    );

    // The plugin already relays core.changes as ChangeNotifier notifications.
    return ListenableBuilder(
      listenable: widget.plugin,
      builder: (context, _) {
        Widget detail;
        if ((place.file, place.scenario) case (var file?, var scenario?)) {
          detail = _ScenarioPage(
            _core,
            place.package,
            file: file,
            scenario: scenario,
            step: place.step,
            axes: axes,
            key: ValueKey('${place.package}/$file#$scenario'),
          );
        } else if (place.help ||
            // A suite of none has nothing to pick, so the page that says what
            // to do is the page to be on. Only once the scan has answered —
            // "there are none" is a finding, not the absence of one.
            (_core.scanResultFor(place.package)?.scenarios.isEmpty ?? false)) {
          detail = ScenarioHelpPage(
            directory: _core.newScenarioDirectoryFor(place.package),
            onNew: () => unawaited(_newScenario(context, _core, place.package)),
          );
        } else {
          detail = EmptyState(
            icon: Icons.route_outlined,
            title: 'Pick a scenario',
            message: 'Opening one runs it.',
            action: TextButton(
              onPressed: () =>
                  AddressScope.write(context)
                      .setSegments(scenarioSegments(place.package, help: true)),
              child: const Text('How to write one'),
            ),
          );
        }
        // Every step below reads its frame and its trees through this. Here
        // they are files in the worktree the harness just wrote them into; on
        // the exported page the same widgets read the same steps over HTTP.
        return ScenarioArtifactsScope(
          artifacts: FileScenarioArtifacts(_core.host.worktree.path),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AsidePane(
                width: 240,
                child: _ScenarioListPane(
                  _core,
                  place.package,
                  browsing: widget.plugin.browsingFor(place.package),
                  selected: place,
                  key: ValueKey(place.package),
                ),
              ),
              Expanded(child: detail),
            ],
          ),
        );
      },
    );
  }
}

/// Writes a scenario and goes straight to it — which runs it, since opening a
/// scenario is what runs one. That is what this offers over the command the
/// help page names: you end up looking at the thing you just made.
///
/// Top-level because three surfaces offer it — the list header, the empty list,
/// and the help page — and they are in three different widgets.
Future<void> _newScenario(
  BuildContext context,
  ScenariosCore core,
  String package,
) async {
  var result = await showNewScenarioDialog(
    context,
    core: core,
    package: package,
  );
  if (result == null || !context.mounted) return;
  AddressScope.write(context).setSegments(
    scenarioSegments(package, file: result.file, scenario: result.name),
  );
}

/// The master pane: every scenario of the package, grouped by file, the
/// selected one highlighted. Always visible — running a scenario never hides
/// where you are in the suite.
class _ScenarioListPane extends StatefulWidget {
  const _ScenarioListPane(
    this.core,
    this.package, {
    required this.browsing,
    required this.selected,
    super.key,
  });

  final ScenariosCore core;
  final String package;

  /// How this package's tree is folded. Outlives the pane — see
  /// [ScenarioBrowsing].
  final ScenarioBrowsing browsing;

  final ScenarioPlace selected;

  @override
  State<_ScenarioListPane> createState() => _ScenarioListPaneState();
}

class _ScenarioListPaneState extends State<_ScenarioListPane> {
  /// The filter, owned here and nowhere else. It names no place, so it does
  /// not belong in the address — and the pane is keyed by package, so it
  /// survives opening scenario after scenario and resets when the suite does.
  final _query = TextEditingController();

  ScenariosCore get core => widget.core;
  String get package => widget.package;
  ScenarioBrowsing get browsing => widget.browsing;

  @override
  void initState() {
    super.initState();
    browsing.addListener(_onBrowsing);
  }

  @override
  void didUpdateWidget(_ScenarioListPane old) {
    super.didUpdateWidget(old);
    // A config reload swaps the plugin under a mounted panel, and the browsing
    // it hands over comes with it.
    if (!identical(old.browsing, browsing)) {
      old.browsing.removeListener(_onBrowsing);
      browsing.addListener(_onBrowsing);
    }
  }

  void _onBrowsing() => setState(() {});

  @override
  void dispose() {
    browsing.removeListener(_onBrowsing);
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to narrow until the scan has found something: a filter over a
    // suite of none is a control that can only disappoint.
    var scanned = core.scanResultFor(package)?.scenarios ?? const [];
    // The suite as its files sit on disk: the shared prefix dropped, folders
    // and files as collapsible branches, and a file's scenarios in
    // declaration order — ranking or sorting them would shuffle the suite out
    // of the shape the reader knows it by.
    var whole = buildScenarioTree(scanned);
    // Whether this suite is one you arrive scrolling, answered once — and
    // answered here, above everything built from it. The collapse-all button
    // reads the same set the tree does, so a fold taken further down would
    // leave it a frame behind, offering to collapse what is already folded.
    //
    // From the whole tree, never the filtered one: a filter is a question
    // rather than the shape of the suite.
    if (browsing.needsFoldDecision) {
      browsing.foldIfCrowded(
        scenarioTreeRows(whole),
        allScenarioBranches(whole),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ListPaneHeader(
          directory: _displayDirectory(),
          scanning: core.isScanning(package),
          onRefresh: () => core.refresh(package),
          onNew: () => unawaited(_newScenario(context, core, package)),
          onHelp: () =>
              AddressScope.write(context)
                  .setSegments(scenarioSegments(package, help: true)),
          helpSelected: widget.selected.help,
        ),
        if (scanned.isNotEmpty)
          _FilterField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            // One button for both directions: with nothing folded away the
            // only useful thing it can do is fold, and after that, unfold.
            trailing: IconButton(
              icon: Icon(
                browsing.anyClosed ? Icons.unfold_more : Icons.unfold_less,
                size: FwIconSize.md,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              tooltip: browsing.anyClosed ? 'Expand all' : 'Collapse all',
              onPressed: () {
                if (browsing.anyClosed) {
                  browsing.openAll();
                } else {
                  browsing.closeAll(allScenarioBranches(whole));
                }
              },
            ),
          ),
        const Divider(height: 1),
        Expanded(child: _body(context, whole)),
      ],
    );
  }

  /// What the header names: the directory the suite actually sits under when
  /// the scan has found one, the scan root while it has not.
  String _displayDirectory() {
    var scanned = core.scanResultFor(package)?.scenarios ?? const [];
    if (scanned.isEmpty) return core.scanRootFor(package);
    var common = commonScenarioDirectory([for (var ref in scanned) ref.file]);
    return common.isEmpty ? core.scanRootFor(package) : common;
  }

  Widget _body(BuildContext context, List<ScenarioListNode> whole) {
    var result = core.scanResultFor(package);
    if (result == null) {
      if (core.scanErrorFor(package) case var error?) {
        return ErrorState(title: 'The scan failed', message: '$error');
      }
      return const LoadingState(title: 'Scanning for scenarios…');
    }
    if (result.scenarios.isEmpty) {
      // Two doors and a sentence, because this column is 240px wide. What used
      // to be here — the whole authoring hint, wrapped to death — is the help
      // page the detail pane opens itself on, where a code example can be code.
      return SingleChildScrollView(
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () => unawaited(_newScenario(context, core, package)),
              icon: const Icon(Icons.add, size: FwIconSize.md),
              label: const Text('New scenario'),
            ),
            const Gap(FwSpacing.lg),
            Text(
              'No scenarios under ${core.scanRootFor(package)}/.',
              style: context.type.caption.copyWith(color: context.colors.mut),
            ),
          ],
        ),
      );
    }

    var query = _query.text.trim();
    var filtering = query.isNotEmpty;
    var tree = filterScenarioTree(whole, query);

    // Whatever is selected is *made* visible, once, when it arrives — a
    // selection routinely lands from outside the tree (the address bar, a
    // navigate, the New dialog) and may sit under a branch folded away.
    // After the frame, because opening a branch notifies and this is a build.
    if (widget.selected.file case var selectedFile?) {
      var key = '$selectedFile//${widget.selected.scenario}';
      if (browsing.needsReveal(key)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            browsing.revealSelection(key, scenarioBranchesTo(selectedFile));
          }
        });
      }
    }

    if (tree.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Text(
          'No scenario matches “$query”.',
          style: context.type.caption.copyWith(color: context.colors.mut3),
        ),
      );
    }

    var rows = <Widget>[];
    void walk(List<ScenarioListNode> nodes, int depth) {
      for (var node in nodes) {
        switch (node) {
          case ScenarioBranchNode():
            // A filtered tree is already the answer to a question; folding
            // part of it away would only hide what was asked for.
            var open = filtering || browsing.isOpen(node.id);
            rows.add(
              _BranchRow(
                node,
                depth: depth,
                open: open,
                onTap: filtering ? null : () => browsing.toggle(node.id),
              ),
            );
            if (open) walk(node.children, depth + 1);
          case ScenarioLeafNode(:var ref):
            rows.add(
              _ScenarioRow(
                ref,
                depth: depth,
                matched: node.marks,
                selected:
                    widget.selected.file == ref.file &&
                    widget.selected.scenario == ref.name,
                onTap: () => AddressScope.write(context).setSegments(
                  scenarioSegments(package, file: ref.file, scenario: ref.name),
                ),
              ),
            );
        }
      }
    }

    walk(tree, 0);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.md),
      children: [
        for (var diagnostic in result.diagnostics)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FwSpacing.lg,
              vertical: FwSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: FwIconSize.sm,
                  color: context.colors.amber,
                ),
                const Gap(FwSpacing.sm),
                Expanded(child: Text(diagnostic, style: context.type.caption)),
              ],
            ),
          ),
        ...rows,
      ],
    );
  }
}

/// Indent for [depth], so a branch's children start under its label.
EdgeInsets _treeRowPadding(int depth) =>
    EdgeInsets.only(left: FwSpacing.lg + depth * 14.0, right: FwSpacing.lg);

/// A folder or a file in the list: a chevron, the segment's name, and — while
/// closed — how many scenarios are folded away behind it.
class _BranchRow extends StatelessWidget {
  const _BranchRow(
    this.node, {
    required this.depth,
    required this.open,
    required this.onTap,
  });

  final ScenarioBranchNode node;
  final int depth;
  final bool open;

  /// Null while filtering: a filtered tree is held open, so the tap has
  /// nothing honest to do.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable.builder(
      onTap: onTap,
      builder: (context, hovered) => Container(
        color: hovered ? colors.panel : Colors.transparent,
        padding: _treeRowPadding(depth),
        child: SizedBox(
          height: 26,
          child: Row(
            children: [
              Icon(
                open ? Icons.expand_more : Icons.chevron_right,
                size: FwIconSize.sm,
                color: colors.mut,
              ),
              const Gap(FwSpacing.xs),
              Expanded(
                child: Tooltip(
                  // The label is a lone segment now, so the tooltip keeps the
                  // whole path.
                  message: node.file ?? node.id,
                  waitDuration: const Duration(milliseconds: 500),
                  child: MatchedText(
                    node.label,
                    matched: node.marks,
                    style: context.type.sectionLabel,
                  ),
                ),
              ),
              if (!open) ...[
                const Gap(FwSpacing.xs),
                Text(
                  '${node.scenarioCount}',
                  style: context.type.micro.copyWith(color: colors.mut2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The list pane's header: which directory this suite lives in, the way to add
/// to it, and the way back to how.
///
/// Above every state the pane has — loading, failed, empty, populated — because
/// neither "write another one" nor "how does `split` go again" is a question
/// you only have when there are none. The help used to live in the empty state
/// alone, which meant the first file you wrote took it away.
class _ListPaneHeader extends StatelessWidget {
  const _ListPaneHeader({
    required this.directory,
    required this.scanning,
    required this.onRefresh,
    required this.onNew,
    required this.onHelp,
    required this.helpSelected,
  });

  final String directory;

  /// Whether a scan is in flight — the refresh button's own feedback, and the
  /// only feedback there is: a rescan that finds the same scenarios changes
  /// nothing on screen, and a button that answers a press with nothing at all
  /// reads as broken.
  final bool scanning;

  final VoidCallback onRefresh;
  final VoidCallback onNew;
  final VoidCallback onHelp;
  final bool helpSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.lg,
        FwSpacing.sm,
        FwSpacing.sm,
        FwSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: directory,
              waitDuration: const Duration(milliseconds: 500),
              child: Text(
                directory,
                style: context.type.sectionLabel,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          _HeaderButton(
            icon: Icons.refresh,
            tooltip: 'Rescan for scenarios',
            onTap: onRefresh,
            busy: scanning,
          ),
          _HeaderButton(
            icon: Icons.help_outline,
            tooltip: 'How to write a scenario',
            onTap: onHelp,
            selected: helpSelected,
          ),
          _HeaderButton(icon: Icons.add, tooltip: 'New scenario', onTap: onNew),
          // Last in the row, because it is the only one here that acts on the
          // pane rather than on the suite in it — and because a flow of seven
          // steps in 726px is the reason this exists.
          const AsideExpandButton(),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  /// Draws a spinner in the icon's place, at the icon's size, so the row does
  /// not reflow as the work starts and stops.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: Tappable.builder(
        onTap: onTap,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.all(FwSpacing.xs),
          decoration: BoxDecoration(
            color: selected || hovered ? colors.panel : Colors.transparent,
            borderRadius: BorderRadius.circular(context.radii.radius),
          ),
          child: SizedBox.square(
            dimension: FwIconSize.md,
            child: busy
                ? CircularProgressIndicator(strokeWidth: 2, color: colors.mut)
                : Icon(
                    icon,
                    size: FwIconSize.md,
                    color: selected || hovered ? colors.ink : colors.mut,
                  ),
          ),
        ),
      ),
    );
  }
}

/// One size for both of the field's icon slots, filled or not. An
/// `InputDecorator` sizes itself around its icons, so a clear button that comes
/// and goes with the text takes the field's height with it.
const _iconSlot = BoxConstraints.tightFor(width: 24, height: 22);

/// The filter, as the catalog's tree filter wears it: short, a search glyph, a
/// clear button that only appears once there is something to clear.
///
/// The caller owns the controller and rebuilds on change, which is also what
/// makes the clear button appear — there is no state here worth keeping.
class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.controller,
    required this.onChanged,
    this.trailing,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// A control that belongs on the filter's row — the fold-all toggle.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var field = SizedBox(
      height: 28,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: context.type.caption.copyWith(color: colors.ink),
        decoration: InputDecoration(
          hintText: 'Filter',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
          prefixIcon: Icon(
            Icons.search,
            size: FwIconSize.sm,
            color: colors.mut2,
          ),
          prefixIconConstraints: _iconSlot,
          suffixIconConstraints: _iconSlot,
          suffixIcon: controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: Icon(
                    Icons.close,
                    size: FwIconSize.sm,
                    color: colors.mut2,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: _iconSlot,
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.md,
        0,
        FwSpacing.md,
        FwSpacing.md,
      ),
      child: trailing == null
          ? field
          : Row(
              children: [
                Expanded(child: field),
                const Gap(FwSpacing.xs),
                trailing!,
              ],
            ),
    );
  }
}

class _ScenarioRow extends StatelessWidget {
  const _ScenarioRow(
    this.ref, {
    required this.selected,
    required this.onTap,
    this.depth = 0,
    this.matched = const [],
  });

  final ScenarioRef ref;
  final bool selected;
  final VoidCallback onTap;

  /// How deep the row sits in the tree — always below its file's branch.
  final int depth;

  /// Which characters of the name the filter matched. Empty when it matched
  /// a branch instead — the row is on screen for a reason the row cannot
  /// show, and the lit branch label above it is where that reason is.
  final List<int> matched;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable.builder(
      onTap: onTap,
      builder: (context, hovered) => Container(
        color: selected
            ? colors.accentSoft
            : hovered
            ? colors.panel
            : Colors.transparent,
        padding: _treeRowPadding(depth)
            .add(const EdgeInsets.symmetric(vertical: FwSpacing.sm)),
        child: Row(
          children: [
            Icon(
              Icons.route_outlined,
              size: FwIconSize.sm,
              color: selected ? colors.accent : colors.mut2,
            ),
            const Gap(FwSpacing.md),
            Expanded(
              child: MatchedText(
                ref.name,
                matched: matched,
                style: context.type.body.copyWith(
                  color: selected ? colors.ink : colors.mut,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One scenario's page. Opening it runs it: a scenario that has not been run
/// yet runs now, and the Run button reruns — against the sources on disk,
/// since the warm runner refreshes first. The run draws as the flow; a step
/// address pushes [ScenarioStepPage] over it.
class _ScenarioPage extends StatefulWidget {
  const _ScenarioPage(
    this.core,
    this.package, {
    required this.file,
    required this.scenario,
    required this.axes,
    this.step,
    super.key,
  });

  final ScenariosCore core;
  final String package;
  final String file;
  final String scenario;

  /// The axis assignment the address asks for.
  final ScenarioAxes axes;

  /// The step the address pushes, or null for the flow.
  final int? step;

  @override
  State<_ScenarioPage> createState() => _ScenarioPageState();
}

class _ScenarioPageState extends State<_ScenarioPage> {
  /// The flow canvas's pan/zoom, owned here so a pushed step detail and its
  /// back button land exactly where the canvas was.
  final _flowTransform = TransformationController(
    ScenarioFlowView.initialTransform(),
  );

  ScenarioPanelRun? get _run => widget.core.panelRunFor(
    widget.package,
    file: widget.file,
    scenario: widget.scenario,
  );

  /// How long the run on screen has been going, and whether it has been going
  /// long enough to be worth a spinner. See [_startedWaiting].
  final _runFor = Stopwatch();
  Timer? _ticker;
  bool get _waitIsWorthSaying => _runFor.elapsed >= _loaderAppearsAfter;

  /// Longer than a warm run, shorter than a noticeable wait. A
  /// warm harness answers in a couple of hundred milliseconds, and the panel
  /// says nothing at all inside that.
  static const _loaderAppearsAfter = Duration(milliseconds: 250);

  void _start() {
    widget.core.startRun(
      widget.package,
      file: widget.file,
      scenario: widget.scenario,
      axes: widget.axes,
    );
    _startedWaiting();
  }

  /// Restarts the clock the loader reads, and ticks it while the spinner is
  /// the whole screen: the floor has to expire on its own, and past it a
  /// count that is climbing is the only thing distinguishing slow from hung.
  /// Stops itself the moment the first step lands — from there the flow
  /// filling in is the progress.
  void _startedWaiting() {
    _runFor
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(_loaderAppearsAfter, (timer) {
      var run = _run;
      if (!mounted || run == null || !run.running || run.steps.isNotEmpty) {
        timer.cancel();
        _ticker = null;
        _runFor.stop();
        return;
      }
      setState(() {});
    });
  }

  /// Runs when nothing has, and re-runs when the settled state was made under
  /// different axes than the address now asks for — which is how an axis
  /// picked in the toolbar becomes a fresh run. Compared against the last
  /// *attempt*'s axes, so a failure is not retried in a loop.
  void _maybeRun() {
    var run = _run;
    if (run == null || (!run.running && run.axes != widget.axes)) {
      _start();
    } else if (run.running && !_runFor.isRunning) {
      // Already running when the page arrived — the Run button on another
      // surface, or an agent. The wait is still this page's to narrate.
      _startedWaiting();
    }
  }

  @override
  void initState() {
    super.initState();
    _maybeRun();
  }

  @override
  void didUpdateWidget(_ScenarioPage old) {
    super.didUpdateWidget(old);
    // Which step the reader is walking off, so the one they land on knows
    // whether it was walked into. Held here rather than on the step page
    // because a document and a screen are different widgets, and the page is
    // rebuilt from scratch every time the walk crosses between them.
    if (old.step != widget.step) _cameFrom = old.step;
    _maybeRun();
  }

  /// The step that was open when this one was, or null for an arrival from
  /// the flow, a fresh run, or a shared link.
  int? _cameFrom;

  @override
  void dispose() {
    _ticker?.cancel();
    _flowTransform.dispose();
    super.dispose();
  }

  /// The device the canvas on screen was laid out for.
  String? _framedAt;

  /// Another device is another canvas. A flow's cells are the device's own
  /// size, so the same six steps are twice as wide on a tablet as on a phone —
  /// and a place panned to under one framing is, under the other, blank canvas
  /// with the flow drawn off behind it. Null is not a framing: a run reports no
  /// device until its first step lands, so reading it as one would send the
  /// canvas home on every rerun, including the ones that mean "same flow, look
  /// again".
  void _reframe(String? device) {
    if (device == null || device == _framedAt) return;
    var first = _framedAt == null;
    _framedAt = device;
    if (first) return;
    // After the frame: the controller has listeners, and moving it while the
    // tree that holds them is building marks them dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _flowTransform.value = ScenarioFlowView.initialTransform();
    });
  }

  void _openStep(ScenarioRunStep step) {
    AddressScope.write(context).setSegments(
      scenarioSegments(
        widget.package,
        file: widget.file,
        scenario: widget.scenario,
        step: step.index,
      ),
    );
  }

  void _closeStep() {
    AddressScope.write(context).setSegments(
      scenarioSegments(
        widget.package,
        file: widget.file,
        scenario: widget.scenario,
      ),
    );
  }

  /// What the banner names the app when a notification payload does not —
  /// the package is the closest thing to the project's own name here.
  String get _appLabel => p.basename(widget.package);

  /// The project's own launcher icon for the banner tile, found the way the
  /// icon plugin finds it. Once per page: a directory listing plus image
  /// headers, and the page is already keyed by scenario.
  late final ImageProvider? _appIcon = switch (representativeIconPath(
    packageRoot: widget.core.packageRootFor(widget.package),
  )) {
    var path? => FileImage(File(path)),
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    var run = _run;
    // Framed by what the run *did*, which for an unspecified device is what
    // its folder answered.
    var device = run?.device == null ? null : deviceById(run!.device!);
    _reframe(run?.device);

    // Dark runs default to light chrome, like a real phone would show.
    var statusFallback = run?.axes.brightness == 'dark'
        ? Brightness.light
        : Brightness.dark;

    // The pushed page: a step, with its back button. Full page — the flow is
    // exactly one back-tap away, per the reference GUI.
    var steps = run?.steps ?? const <ScenarioRunStep>[];
    if (widget.step != null) {
      var step = steps.firstWhereOrNull((s) => s.index == widget.step);
      // A beat that is not a screen renders as itself — the document, or the
      // banner over the screen it landed on.
      if (step != null) {
        if (step.kind != ScenarioStepKind.screen) {
          return ScenarioBeatPage(
            steps: steps,
            step: step,
            background: scenarioFrameFor(steps, step),
            device: device,
            onBack: _closeStep,
            onOpenStep: _openStep,
            statusFallback: statusFallback,
            appLabel: _appLabel,
            appIcon: _appIcon,
          );
        }
        return ScenarioStepPage(
          steps: steps,
          step: step,
          from: _cameFrom,
          device: device,
          onBack: _closeStep,
          onOpenStep: _openStep,
          statusFallback: statusFallback,
          // Source paths in the node detail shorten against the package —
          // the same string the scenario file itself is addressed by.
          displayRoot: widget.core.packageRootFor(widget.package),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, run),
        _AxesBar(
          axes: widget.axes,
          // What the last run resolved an unspecified device to — the only
          // way the panel learns a folder's default, since the profile lives
          // in the guest.
          resolved: run?.device,
          // What this scenario's folder profile offers, once the live listing
          // has landed: the pool goes to the top of the menu, and everything
          // else stays reachable below it.
          offered: widget.core.offeredDevicesFor(widget.package, widget.file),
          languages: widget.core.offeredLanguagesFor(
            widget.package,
            widget.file,
          ),
        ),
        const Divider(height: 1),
        // Said out loud rather than repaired, with the accepted values — the
        // reader is often an agent that guessed.
        if (unknownDeviceIn(AddressScope.param(context, 'device'))
            case var bad?)
          _ErrorBanner(
            'No device "$bad" — running as the folder says instead. '
            'Accepted: ${deviceIds.join(', ')}.',
          ),
        Expanded(child: _body(context, run, device, statusFallback)),
      ],
    );
  }

  Widget _header(BuildContext context, ScenarioPanelRun? run) {
    var colors = context.colors;
    var outcome = run?.outcome;
    var running = run?.running ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.scenario,
                  style: context.type.heading,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.file,
                  style: context.type.caption.copyWith(color: colors.mut2),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Gap(FwSpacing.md),
          if (running)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (outcome != null) ...[
            Icon(
              outcome.skipped
                  ? Icons.remove_circle_outline
                  : outcome.ok
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              size: FwIconSize.md,
              color: outcome.skipped
                  ? colors.mut2
                  : outcome.ok
                  ? colors.grn
                  : colors.red,
            ),
            const Gap(FwSpacing.xs),
            Text(
              outcome.skipped ? 'skipped' : '${outcome.ms} ms',
              style: context.type.caption.copyWith(color: colors.mut2),
            ),
          ],
          const Gap(FwSpacing.lg),
          _RunSplitButton(
            enabled: !running,
            onRun: _start,
            recordMotion: widget.core.recordMotion,
            onToggleRecordMotion: () =>
                widget.core.setRecordMotion(!widget.core.recordMotion),
            // The escape hatch, for the changes no incremental lane can see:
            // drops the warm harness and cold-starts — fresh bundle, fresh
            // kernel, fresh process.
            onFullRestart: () {
              widget.core.restartRunner(widget.package);
              _start();
            },
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ScenarioPanelRun? run,
    Device? device,
    Brightness statusFallback,
  ) {
    var steps = run?.steps ?? const <ScenarioRunStep>[];
    var running = run?.running ?? false;

    if (steps.isEmpty) {
      if (run?.error case var error? when !running) {
        return _RunFailure(error);
      }
      if (running || run == null) {
        // Nothing at all under the floor: a warm run lands in a few hundred
        // milliseconds, and a spinner that appears and leaves inside one is a
        // flash rather than news — which is what made walking the list
        // unpleasant. Past the floor the wait is real and gets said properly.
        if (!_waitIsWorthSaying) return const SizedBox.expand();
        // The runner narrates its cold start — rebuilding the asset bundle is
        // a very different wait from a hung harness — and the seconds are
        // what separate slow from hung. Once the first step lands, the flow
        // itself is the progress.
        return LoadingState(
          title:
              widget.core.runnerPhaseFor(widget.package) ??
              'Running the scenario',
          message: '${_runFor.elapsed.inSeconds}s',
        );
      }
      return const EmptyState(
        icon: Icons.image_not_supported_outlined,
        title: 'No steps captured',
        message:
            'The scenario ran without a screenshot — every tap and '
            'screen() captures one unless Shots.manual turned that off.',
      );
    }

    var outcome = run?.outcome;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (run?.error case var error?) _ErrorBanner(error),
        if (outcome != null)
          for (var error in outcome.errors.take(1)) _ErrorBanner(error.error),
        // Drawn from the streamed steps: the flow starts filling in with the
        // first capture, while the scenario is still running.
        Expanded(
          child: ScenarioFlowView(
            steps: steps,
            device: device,
            transform: _flowTransform,
            onOpenStep: _openStep,
            appLabel: _appLabel,
            appIcon: _appIcon,
            statusFallback: statusFallback,
          ),
        ),
      ],
    );
  }
}

/// The primary Run with its overflow: the main segment runs, the arrow opens
/// the rarer choices — today just "Full restart".
class _RunSplitButton extends StatelessWidget {
  const _RunSplitButton({
    required this.enabled,
    required this.onRun,
    required this.onFullRestart,
    required this.recordMotion,
    required this.onToggleRecordMotion,
  });

  final bool enabled;
  final VoidCallback onRun;
  final VoidCallback onFullRestart;

  /// Whether the next run records every transition's frames — the switch for
  /// the ~70ms a transition it costs, next to the other rare run choices.
  final bool recordMotion;
  final VoidCallback onToggleRecordMotion;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var fg = colors.onPrimary;
    return Container(
      height: 32,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: enabled ? colors.accent : colors.mut3,
        borderRadius: BorderRadius.circular(context.radii.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tappable(
            onTap: enabled ? onRun : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow, size: FwIconSize.md, color: fg),
                  const Gap(FwSpacing.xs),
                  Text('Run', style: context.type.button.copyWith(color: fg)),
                ],
              ),
            ),
          ),
          Container(width: 1, color: fg.withValues(alpha: 0.3)),
          Menu(
            align: PopoverAlign.end,
            entries: [
              MenuItem(
                'Record motion',
                // The state is the icon: the menu has no checkable item, and
                // a box that is ticked or not says it without one.
                icon: recordMotion
                    ? Icons.check_box_outlined
                    : Icons.check_box_outline_blank,
                onSelected: enabled ? onToggleRecordMotion : null,
              ),
              const MenuDivider(),
              MenuItem(
                'Full restart',
                icon: Icons.restart_alt,
                onSelected: enabled ? onFullRestart : null,
              ),
            ],
            builder: (context, controller) => Tooltip(
              message: 'More run options',
              child: Tappable(
                onTap: enabled ? controller.toggle : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FwSpacing.xs),
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: FwIconSize.lg,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A run that produced nothing to draw — a compile error, usually, which is
/// why the text is selectable and kept whole.
class _RunFailure extends StatelessWidget {
  const _RunFailure(this.error);

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FwSpacing.xxl),
        child: SelectableText(
          error,
          style: context.type.bodySmall.copyWith(color: context.colors.red),
        ),
      ),
    );
  }
}

/// A complaint over a page that still has content under it: a failing
/// scenario's error above its captured steps, or a failed re-run above the
/// previous result.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      width: double.infinity,
      color: colors.red.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.md,
      ),
      child: SelectableText(
        message,
        maxLines: 6,
        style: context.type.bodySmall.copyWith(color: colors.red),
      ),
    );
  }
}

/// The axis assignment, as controls: device, language, accessibility,
/// brightness. **Every control writes the address and holds nothing** — the
/// page notices the address moved and re-runs, so a picked axis and a pasted
/// `?device=` link are the same code path.
///
/// Plain parameters, deliberately above the segments' lifetime: pick French
/// once and every scenario you open runs French, exactly like the catalog's
/// device framing.
class _AxesBar extends StatelessWidget {
  const _AxesBar({
    required this.axes,
    required this.languages,
    this.offered = const [],
    this.resolved,
  });

  final ScenarioAxes axes;

  /// The devices this scenario's folder profile offers, its first one the
  /// default. Empty where no profile governs it, and before the live listing
  /// lands — in which case the menu is the whole table, as it was.
  final List<String> offered;

  /// What the last run made of an unspecified device — the folder profile's
  /// first device, or the global default. Null before the first run, when the
  /// panel does not know yet.
  final String? resolved;

  /// The locale tags the project's config declares — the whole language menu.
  final List<String> languages;

  @override
  Widget build(BuildContext context) {
    var device = axes.device == null ? null : deviceById(axes.device!);
    var byFolder = resolved == null ? null : deviceById(resolved!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.lg,
        0,
        FwSpacing.lg,
        FwSpacing.md,
      ),
      // A Wrap rather than a Row: four controls do not fit every panel width,
      // and a second line beats a clipped one.
      child: Wrap(
        spacing: FwSpacing.md,
        runSpacing: FwSpacing.xs,
        children: [
          Menu(
            entries: [
              MenuItem(
                // Named by what the folder resolved it to, once a run has
                // said — "Default" alone is true but useless.
                byFolder == null ? 'Default' : 'Default · ${byFolder.label}',
                onSelected: () =>
                    AddressScope.write(context).setParam('device', null),
              ),
              MenuItem(
                'Bare test surface',
                onSelected: () =>
                    AddressScope.write(context).setParam('device', fitDeviceId),
              ),
              // The folder's own pool first — the short list somebody meant
              // when they wrote the profile.
              if (offered.isNotEmpty) ...[
                const MenuHeader('This folder'),
                for (var id in offered)
                  if (deviceById(id) case var d?)
                    MenuItem(
                      d.label,
                      shortcut: describeDevice(d),
                      onSelected: () =>
                          AddressScope.write(context).setParam('device', d.id),
                    ),
              ],
              // …then everything, because "show me this phone screen at
              // desktop width" is a real question and a profile is an offer,
              // not a fence.
              for (var group in {for (var d in Devices.all) d.group}) ...[
                MenuHeader(group),
                for (var d in Devices.all.where((d) => d.group == group))
                  MenuItem(
                    d.label,
                    shortcut: describeDevice(d),
                    onSelected: () =>
                        AddressScope.write(context).setParam('device', d.id),
                  ),
              ],
            ],
            builder: (context, controller) => _AxisChip(
              label: 'Device',
              value: switch (axes.device) {
                // Unspecified reads as what it ran as, marked as not yours —
                // the chip lights up only when *you* picked something.
                null =>
                  byFolder == null ? 'Default' : '${byFolder.label} (default)',
                fitDeviceId => 'Bare surface',
                _ => device?.label ?? 'Default',
              },
              active: axes.device != null,
              onTap: controller.toggle,
            ),
          ),
          if (languages.isNotEmpty)
            Menu(
              entries: [
                MenuItem(
                  'Default',
                  onSelected: () =>
                      AddressScope.write(context).setParam('language', null),
                ),
                for (var language in languages)
                  MenuItem(
                    language,
                    onSelected: () =>
                        AddressScope.write(context)
                            .setParam('language', language),
                  ),
              ],
              builder: (context, controller) => _AxisChip(
                label: 'Language',
                value: axes.language ?? 'Default',
                active: axes.language != null,
                onTap: controller.toggle,
              ),
            ),
          Popover(
            side: PopoverSide.bottom,
            align: PopoverAlign.start,
            anchor: (context, controller) => _AxisChip(
              label: 'Accessibility',
              value: _describeAccessibility(axes),
              active: axes.anyAccessibility,
              onTap: controller.toggle,
            ),
            content: (context, controller) => PopoverMenuSurface(
              minWidth: 260,
              maxWidth: 320,
              child: _AccessibilityPanel(axes: axes),
            ),
          ),
          Menu(
            entries: [
              for (var (label, value) in [
                ('Default', null),
                ('Light', 'light'),
                ('Dark', 'dark'),
              ])
                MenuItem(
                  label,
                  onSelected: () =>
                      AddressScope.write(context).setParam('brightness', value),
                ),
            ],
            builder: (context, controller) => _AxisChip(
              label: 'Brightness',
              value: switch (axes.brightness) {
                'dark' => 'Dark',
                'light' => 'Light',
                _ => 'Default',
              },
              active: axes.brightness != null,
              onTap: controller.toggle,
            ),
          ),
        ],
      ),
    );
  }

  static String _describeAccessibility(ScenarioAxes axes) {
    var features = [
      if (axes.boldText) 'bold',
      if (axes.highContrast) 'high contrast',
      if (axes.invertColors) 'invert',
    ];
    var scale = axes.textScale;
    if (scale == null && features.isEmpty) return 'Default';
    var scaleText = 'Text ${((scale ?? 1.0) * 100).round()}%';
    return features.isEmpty ? scaleText : '$scaleText, ${features.join(', ')}';
  }
}

/// The accessibility features, as dev_studio offered them: the text scale
/// stepper and the platform switches. Every row writes the address on the
/// spot — with warm FakeAsync re-runs there is nothing to batch behind an
/// Apply button.
class _AccessibilityPanel extends StatelessWidget {
  const _AccessibilityPanel({required this.axes});

  final ScenarioAxes axes;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var scale = axes.textScale ?? 1.0;
    void setScale(double value) {
      AddressScope.write(context).setParam(
        'text-scale',
        (value - 1.0).abs() < 0.001 ? null : value.toStringAsFixed(2),
      );
    }

    Widget toggle(String label, String param, bool value) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: context.type.body)),
            Checkbox(
              value: value,
              visualDensity: VisualDensity.compact,
              onChanged: (checked) =>
                  AddressScope.write(context)
                      .setParam(param, (checked ?? false) ? 'true' : null),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(FwSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
          child: Text('ACCESSIBILITY', style: context.type.sectionLabel),
        ),
        const Gap(FwSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.lg,
            vertical: FwSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(child: Text('Text scale', style: context.type.body)),
              Tappable(
                onTap: () => setScale((scale - 0.1).clamp(0.5, 3.0)),
                child: Icon(
                  Icons.remove,
                  size: FwIconSize.md,
                  color: colors.mut,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
                child: Text(
                  '${(scale * 100).round()}%',
                  style: context.type.bodyStrong,
                ),
              ),
              Tappable(
                onTap: () => setScale((scale + 0.1).clamp(0.5, 3.0)),
                child: Icon(Icons.add, size: FwIconSize.md, color: colors.mut),
              ),
            ],
          ),
        ),
        toggle('Bold text', 'bold-text', axes.boldText),
        toggle('High contrast', 'high-contrast', axes.highContrast),
        toggle('Invert colors', 'invert-colors', axes.invertColors),
        const Gap(FwSpacing.md),
      ],
    );
  }
}

/// One axis as a compact dropdown trigger. Accent-tinted when set, so a page
/// running under non-default axes is recognisable at a glance.
class _AxisChip extends StatelessWidget {
  const _AxisChip({
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable(
      onTap: onTap,
      child: Container(
        height: 24,
        padding: const EdgeInsets.only(left: FwSpacing.md, right: FwSpacing.xs),
        decoration: BoxDecoration(
          color: active ? colors.accentSoft : colors.bg,
          border: Border.all(color: active ? colors.accent : colors.line),
          borderRadius: BorderRadius.circular(context.radii.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: context.type.caption.copyWith(color: colors.mut2),
            ),
            Text(
              value,
              style: context.type.caption.copyWith(color: colors.ink),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: FwIconSize.md,
              color: colors.mut2,
            ),
          ],
        ),
      ),
    );
  }
}

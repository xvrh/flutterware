import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../catalog/catalog_entry.dart';
import '../../catalog/catalog_session.dart';
import '../../catalog/discovery.dart';
import '../../catalog/package_config_locator.dart';
import '../../catalog/protocol.dart';
import '../../catalog/catalog_view.dart';
import '../../catalog/screenshot.dart';
import '../native_plugin.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const uiCatalogPluginId = 'flutterware.ui_catalog';

/// Where a package keeps its demos when it does not say otherwise.
const _defaultRoot = 'demo';

/// Entries the text projection lists before it starts counting. A projection is
/// read, not scrolled.
const _projectedEntries = 20;

/// Entry ids spelled out inline as action options. Beyond this the caller reads
/// them from the view, which is what `optionsFrom` says.
const _inlinedOptions = 50;

/// The UI catalog's entries, per declared package.
///
/// Two tiers, and the split is the point. The **scan** parses a package's demos
/// in ~38ms and touches no compiler, so `fw` and an agent can read the entry
/// list without building anything. The **session** is the compile loop — a
/// daemon, a guest engine, seconds of cold compile — and it is owned here so
/// that leaving the panel does not kill it and [report] can say how it is
/// going while you are looking elsewhere.
///
/// Follows the rule [DependenciesPlugin] establishes: the constructor allocates
/// nothing, [report] only reads what something already asked for, and work
/// begins in [track].
class UiCatalogPlugin extends NativePlugin {
  UiCatalogPlugin(super.host);

  /// Declared packages, filtered to those the workspace knows about, so a typo
  /// cannot make the plugin scan a directory that is not there.
  late final List<String> packages = [
    for (var path in host.packagePaths)
      if (host.workspace.declaredAt(path) != null) path,
  ];

  final _scans = <String, ScanResult>{};
  final _failures = <String, String>{};
  final _scanning = <String>{};
  final _sessions = <String, CatalogSession>{};

  /// Scans [path], unless it already has been. Idempotent.
  ///
  /// Deliberately does **not** start the compile loop: a scan reads files, a
  /// session spawns a daemon, and only mounting the panel justifies the second.
  void track(String path) {
    if (_scans.containsKey(path) ||
        _failures.containsKey(path) ||
        _scanning.contains(path)) {
      return;
    }
    _scanning.add(path);
    notifyChanged();
    _scan(path);
  }

  /// Releases [path]. The scan and the compile loop stay — demand says what
  /// work is justified, not what must be discarded. A cold compile you walked
  /// away from is exactly the one worth keeping.
  void untrack(String path) {}

  /// The live compile loop for [path], started on first ask — which is the
  /// panel mounting.
  ///
  /// Owned here rather than by the panel, so leaving the panel does not throw
  /// away a running daemon — and so [report] can say what the compiler is doing
  /// while something else is on screen.
  CatalogSession _sessionFor(String path) => _sessions.putIfAbsent(path, () {
    var session = CatalogSession(
      appPackageRoot: host.workspace.appContext.appToolDirectory.path,
      flutterSdkRoot: host.workspace.flutterSdk.root,
      projectRoot: p.join(host.worktree.path, path),
      roots: [_rootFor(path)],
    )..addListener(notifyChanged);
    unawaited(session.start());
    return session;
  });

  /// Re-runs every scan that has been asked for. What an editor's "refresh"
  /// does, and what `rescan` invokes.
  void rescan() {
    var known = {..._scans.keys, ..._failures.keys};
    _scans.clear();
    _failures.clear();
    for (var path in known) {
      track(path);
    }
  }

  Future<void> _scan(String path) async {
    var root = p.join(host.worktree.path, path);
    var entryRoot = _rootFor(path);
    try {
      // Off the UI isolate: a large catalog is tens of milliseconds of file
      // reads and parsing, which is a dropped frame if it runs here.
      var result = await Isolate.run(
        () => CatalogScanner(projectRoot: root, roots: [entryRoot]).scan(),
      );
      _scans[path] = result;
    } catch (e) {
      _failures[path] = '$e';
    } finally {
      _scanning.remove(path);
      notifyChanged();
    }
  }

  /// The package's demo directory: `entrypoint` when declared, else `demo/`.
  String _rootFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] != path) continue;
      var entrypoint = config['entrypoint'];
      if (entrypoint is String && entrypoint.isNotEmpty) return entrypoint;
    }
    return _defaultRoot;
  }

  /// True while any declared package is being scanned.
  bool get isScanning => _scanning.isNotEmpty;

  /// Every entry found so far, across packages, in scan order.
  List<CatalogEntry> get entries => [
    for (var path in packages) ...?_scans[path]?.entries,
  ];

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: _status,
    badge: _failures.isNotEmpty || _scans.values.any((scan) => !scan.ok)
        ? const StatusBadge.dot(Tone.error)
        : StatusBadge.none,
    children: [
      for (var path in packages)
        PluginChild(
          id: path,
          label: path == '.' ? 'root' : path,
          status: _packageStatus(path),
        ),
    ],
    actions: [
      const PluginAction(
        'rescan',
        'Rescan',
        description: 'Re-read the demo files and rebuild the entry list',
      ),
      PluginAction(
        'screenshot',
        'Screenshot',
        description: 'Render one entry to a PNG',
        parameters: [
          ActionParameter(
            'entry',
            'Entry',
            kind: ActionParameterKind.choice,
            description: 'The id of the entry to render',
            // Not inlined: a real catalog has hundreds of entries and they are
            // already in the view, so pointing at them beats repeating them.
            optionsFrom: 'view',
            options: [
              for (var entry in entries.take(_inlinedOptions))
                ActionOption(entry.id, label: entry.name),
            ],
          ),
          const ActionParameter(
            'output',
            'Output file',
            required: false,
            description: 'Where to write the PNG; a build path when omitted',
          ),
        ],
      ),
    ],
    view: _view,
  );

  /// What the compiler is doing for [path], or null when it is idle.
  ///
  /// This is the status worth a sidebar row: a cold compile is the only thing
  /// here that takes seconds, and a word that stays put until it goes away is
  /// what lets you look elsewhere and notice when it lands. No elapsed count —
  /// a figure ticking in the corner of the eye is movement, not information.
  Status? _busyStatus(String path) {
    if (_sessions[path]?.busyWith case var busy?) return Status.info(busy);
    return null;
  }

  /// Deliberately silent at rest. An entry count is not news — it cannot even
  /// be known until something opens the panel — and a row that fills in a
  /// number the moment you look at it is worse than an empty one.
  Status get _status {
    if (packages.isEmpty) return const Status.warn('no packages declared');
    if (_failures.isNotEmpty) {
      return Status.error('${_failures.length} failed to scan');
    }
    for (var path in packages) {
      if (_busyStatus(path) case var busy?) return busy;
    }
    if (_sessions.values.any((s) => s.phase == CatalogSessionPhase.error)) {
      return const Status.error('failed to start');
    }
    if (isScanning) return const Status.info('scanning…');
    if (_scans.isEmpty) return Status.none;

    // Discovery refuses on a duplicate id or an uncallable target, so the
    // catalog is not usable; staying quiet would be a lie.
    var broken = _scans.values.where((scan) => !scan.ok).length;
    if (broken > 0) {
      return Status.error(
        '$broken ${broken == 1 ? 'package' : 'packages'} failed discovery',
      );
    }
    if (entries.isEmpty) return const Status.warn('no entries');
    var warnings = _scans.values.fold(
      0,
      (sum, scan) => sum + scan.diagnostics.length,
    );
    return warnings == 0
        ? Status.none
        : Status.warn('$warnings ${warnings == 1 ? 'warning' : 'warnings'}');
  }

  Status _packageStatus(String path) {
    if (_failures[path] case var failure?) return Status.error(failure);
    if (_busyStatus(path) case var busy?) return busy;
    if (_sessions[path]?.phase == CatalogSessionPhase.error) {
      return const Status.error('failed to start');
    }
    if (_scanning.contains(path)) return const Status.info('scanning…');
    var scan = _scans[path];
    if (scan == null) return Status.none;
    if (!scan.ok) return const Status.error('discovery failed');
    if (scan.entries.isEmpty) return const Status.warn('no entries');
    return Status.none;
  }

  PluginView get _view {
    var nodes = <ViewNode>[];
    for (var path in packages) {
      if (_failures[path] case var failure?) {
        nodes.add(ViewSection(path, [ViewText(failure, tone: Tone.error)]));
        continue;
      }
      var scan = _scans[path];
      if (scan == null) continue;

      var children = <ViewNode>[
        ViewItems([
          for (var entry in scan.entries.take(_projectedEntries))
            ViewItem(
              entry.group == null
                  ? entry.name
                  : '${entry.group} / ${entry.name}',
              detail: entry.id,
            ),
        ], truncated: scan.entries.length - _projectedEntries),
        if (scan.diagnostics.isNotEmpty)
          ViewSection('Diagnostics', [
            for (var diagnostic in scan.diagnostics)
              ViewText(
                '$diagnostic',
                tone: diagnostic.isError ? Tone.error : Tone.warn,
              ),
          ]),
      ];
      nodes.add(ViewSection(path == '.' ? 'root' : path, children));
    }
    return PluginView(nodes);
  }

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    switch (actionId) {
      case 'rescan':
        rescan();
        return null;
      case 'screenshot':
        return _screenshot(arguments);
      default:
        return super.invoke(actionId, arguments: arguments);
    }
  }

  /// Renders one entry to a PNG and returns its path.
  ///
  /// Runs the whole pipeline headlessly, so the button, `fw` and an agent all
  /// reach the same artifact by the same route.
  Future<String> _screenshot(Map<String, Object?> arguments) async {
    var entryId = arguments['entry'];
    if (entryId is! String || entryId.isEmpty) {
      throw ArgumentError.value(entryId, 'entry', 'required');
    }
    var packagePath = packages.firstWhere(
      (path) => _scans[path]?.entries.any((e) => e.id == entryId) ?? false,
      orElse: () => throw ArgumentError.value(
        entryId,
        'entry',
        'no scanned entry with that id — has the package been scanned?',
      ),
    );

    var packageRoot = p.join(host.worktree.path, packagePath);
    var output =
        arguments['output'] as String? ??
        p.join(
          packageRoot,
          'build',
          'catalog',
          'screenshots',
          '${entryId.replaceAll(RegExp('[^A-Za-z0-9]+'), '_')}.png',
        );

    var file = await CatalogScreenshot(
      dartExecutable: p.join(host.workspace.flutterSdk.root, 'bin', 'dart'),
      hostPath: p.join(packageRoot, 'build', 'catalog', 'native', 'host'),
      config: DaemonConfig(
        appPackageRoot: packageRoot,
        projectRoot: packageRoot,
        packageConfig: requirePackageConfig(packageRoot),
        flutterSdkRoot: host.workspace.flutterSdk.root,
        roots: [_rootFor(packagePath)],
      ),
    ).capture(entryId: entryId, output: output);
    return file.path;
  }

  @override
  Widget buildPanel(BuildContext context, String? childId) =>
      _CatalogPanel(plugin: this, packagePath: childId ?? packages.firstOrNull);

  /// Closing the worktree is what ends the compile loops — nothing shorter
  /// does, which is the whole point of the plugin owning them.
  @override
  void dispose() {
    for (var session in _sessions.values) {
      session
        ..removeListener(notifyChanged)
        ..dispose();
    }
    _sessions.clear();
    super.dispose();
  }
}

class _CatalogPanel extends StatefulWidget {
  const _CatalogPanel({required this.plugin, required this.packagePath});

  final UiCatalogPlugin plugin;
  final String? packagePath;

  @override
  State<_CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends State<_CatalogPanel> {
  @override
  void initState() {
    super.initState();
    _track();
  }

  @override
  void didUpdateWidget(_CatalogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packagePath != widget.packagePath) {
      if (oldWidget.packagePath case var previous?) {
        widget.plugin.untrack(previous);
      }
      _track();
    }
  }

  @override
  void dispose() {
    if (widget.packagePath case var path?) widget.plugin.untrack(path);
    super.dispose();
  }

  /// Mounting the panel is the demand: the scan, and the compile loop the scan
  /// deliberately leaves alone.
  void _track() {
    if (widget.packagePath case var path?) {
      widget.plugin
        ..track(path)
        .._sessionFor(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    var path = widget.packagePath;
    if (path == null) {
      return const Center(child: Text('No package declared for this plugin.'));
    }
    return AnimatedBuilder(
      animation: widget.plugin,
      builder: (context, _) {
        // The scan's own failure, which is the one that arrives first and
        // explains why the daemon would refuse to start.
        if (widget.plugin._failures[path] case var failure?) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                failure,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }

        // The live loop. The plugin's own scan stays — it is what `fw` and an
        // agent read without a daemon running — but what the panel shows is the
        // compiled catalog, because only the daemon knows which entries
        // actually build.
        return CatalogView(
          key: ValueKey(path),
          session: widget.plugin._sessionFor(path),
        );
      },
    );
  }
}

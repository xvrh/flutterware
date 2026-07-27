import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../catalog/catalog_entry.dart';
import '../../catalog/discovery.dart';
import '../../catalog/protocol.dart';
import '../../catalog/screenshot.dart';
import '../../ui/theme.dart';
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
/// Only the **scan** happens here: parsing a package's demos costs ~38ms and
/// touches no compiler, so a sidebar can honestly say "42 entries" without
/// building anything. Rendering an entry is the expensive tier and belongs to
/// the session, which nothing in this class starts.
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

  /// Scans [path], unless it already has been. Idempotent.
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

  /// Releases [path]. The scan stays cached — demand says what work is
  /// justified, not what must be discarded.
  void untrack(String path) {}

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

  Status get _status {
    if (packages.isEmpty) return const Status.warn('no packages declared');
    if (_failures.isNotEmpty) {
      return Status.error('${_failures.length} failed to scan');
    }
    if (_scans.isEmpty) {
      return isScanning ? const Status.neutral('scanning…') : Status.none;
    }
    // Discovery refuses on a duplicate id or an uncallable target, so the
    // catalog is not usable; reporting a healthy count would be a lie.
    var broken = _scans.values.where((scan) => !scan.ok).length;
    if (broken > 0) {
      return Status.error(
        '$broken ${broken == 1 ? 'package' : 'packages'} failed discovery',
      );
    }
    var found = entries.length;
    var warnings = _scans.values.fold(
      0,
      (sum, scan) => sum + scan.diagnostics.length,
    );
    if (found == 0) return const Status.warn('no entries');
    return warnings == 0
        ? Status.good('$found ${found == 1 ? 'entry' : 'entries'}')
        : Status.warn('$found entries, $warnings warnings');
  }

  Status _packageStatus(String path) {
    if (_failures[path] case var failure?) return Status.error(failure);
    if (_scanning.contains(path)) return const Status.neutral('scanning…');
    var scan = _scans[path];
    if (scan == null) return Status.none;
    if (!scan.ok) return const Status.error('discovery failed');
    var found = scan.entries.length;
    if (found == 0) return const Status.warn('no entries');
    return Status.good('$found ${found == 1 ? 'entry' : 'entries'}');
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
        packageConfig: p.join(packageRoot, '.dart_tool', 'package_config.json'),
        roots: [_rootFor(packagePath)],
      ),
    ).capture(entryId: entryId, output: output);
    return file.path;
  }

  @override
  Widget buildPanel(BuildContext context, String? childId) =>
      _CatalogPanel(plugin: this, packagePath: childId ?? packages.firstOrNull);
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

  /// Mounting the panel is the demand that starts the scan.
  void _track() {
    if (widget.packagePath case var path?) widget.plugin.track(path);
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
        var scan = widget.plugin._scans[path];
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
        if (scan == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          children: [
            for (var diagnostic in scan.diagnostics)
              ListTile(
                dense: true,
                leading: Icon(
                  diagnostic.isError
                      ? Icons.error_outline
                      : Icons.warning_amber,
                  size: 18,
                  color: diagnostic.isError
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Text(
                  '$diagnostic',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            for (var entry in scan.entries)
              ListTile(
                dense: true,
                title: Text(
                  entry.group == null
                      ? entry.name
                      : '${entry.group} / ${entry.name}',
                ),
                subtitle: Text(
                  entry.id,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      },
    );
  }
}

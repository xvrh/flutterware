import 'dart:async';
import 'dart:isolate';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../catalog/catalog_entry.dart';
import '../../catalog/discovery.dart';
import '../../catalog/package_config_locator.dart';
import '../../catalog/protocol.dart';
import '../../catalog/screenshot.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';

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

/// The UI catalog's entries, per declared package — everything but the panel.
///
/// Two tiers, and the split is the point. The **scan** parses a package's demos
/// in ~38ms and touches no compiler, so `fw` and an agent read the entry list
/// without building anything. **Screenshots** run the real pipeline headlessly
/// — `CatalogScreenshot` needs no Flutter, which is what lets the button, `fw`
/// and an agent reach the same artifact by the same route.
///
/// What is *not* here is the live compile loop (`CatalogSession`): it drives a
/// guest engine into a texture, so it is Flutter-bound and belongs to the
/// panel. Its progress reaches [report] through [busyStatusFor], which the GUI
/// supplies and a CLI leaves null — correctly, since there is no session in a
/// CLI to be busy.
class UiCatalogCore extends PluginCore {
  UiCatalogCore(super.host);

  /// Declared packages, filtered to those the workspace knows about, so a typo
  /// cannot make the plugin scan a directory that is not there.
  late final List<String> packages = [
    for (var path in host.packagePaths)
      if (host.workspace.declaredAt(path) != null) path,
  ];

  final _scans = <String, ScanResult>{};
  final _failures = <String, String>{};
  final _scanning = <String>{};

  /// What the GUI's compile loop is doing for a package, when there is one.
  ///
  /// A hook rather than a dependency: the core cannot import the session
  /// without importing Flutter, and the sidebar would otherwise lose the only
  /// status here that takes seconds.
  Status? Function(String path)? busyStatusFor;

  /// The scan failure for [path], for a panel that wants to show it directly.
  String? failureFor(String path) => _failures[path];

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
    unawaited(_scan(path));
  }

  /// Releases [path]. The scan stays — demand says what work is justified, not
  /// what must be discarded.
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

  /// Scans every declared package and waits — what `fw` does for the duration
  /// of one request, where there is no panel to subscribe on its behalf.
  @override
  Future<void> computeAll() async {
    await Future.wait([
      for (var path in packages)
        if (!_scans.containsKey(path) && !_failures.containsKey(path))
          _scan(path),
    ]);
  }

  Future<void> _scan(String path) async {
    var root = p.join(host.worktree.path, path);
    var entryRoot = _rootFor(path);
    _scanning.add(path);
    try {
      // Off the calling isolate: a large catalog is tens of milliseconds of
      // file reads and parsing, which is a dropped frame if it runs on the UI
      // isolate.
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

  /// Where an entry *is*, as the one identifier every surface carries.
  ///
  /// ```
  /// fw://<worktree>/flutterware.ui_catalog/<package>/<file…>/<file.dart%23symbol>
  /// ```
  ///
  /// The entry id is split on `/` rather than carried as one opaque segment, so
  /// the path stays legible and only the `#` needs escaping. The package comes
  /// first because two packages may legitimately declare the same entry id, and
  /// an address that cannot tell them apart is not an identity.
  ///
  /// [axes] are *applied*, not identity — the same entry rendered differently —
  /// which is what makes an address with its axes resolved a complete capture
  /// spec rather than an under-specified one.
  Address addressFor(
    String packagePath,
    String entryId, {
    Map<String, String> axes = const {},
  }) => Address(
    worktree: p.basename(host.worktree.path),
    plugin: host.id,
    segments: [packagePath, ...entryId.split('/')],
    axes: axes,
  );

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
          // Declared because they change the pixels, and anything that changes
          // the pixels is recorded on the artifact's address.
          const ActionParameter(
            'width',
            'Width',
            kind: ActionParameterKind.integer,
            required: false,
            defaultValue: '$_defaultWidth',
          ),
          const ActionParameter(
            'height',
            'Height',
            kind: ActionParameterKind.integer,
            required: false,
            defaultValue: '$_defaultHeight',
          ),
        ],
      ),
    ],
    view: _view,
  );

  /// Deliberately silent at rest. An entry count is not news — it cannot even
  /// be known until something asks for a scan — and a row that fills in a
  /// number the moment you look at it is worse than an empty one.
  Status get _status {
    if (packages.isEmpty) return const Status.warn('no packages declared');
    if (_failures.isNotEmpty) {
      return Status.error('${_failures.length} failed to scan');
    }
    for (var path in packages) {
      if (busyStatusFor?.call(path) case var busy?) return busy;
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
    if (busyStatusFor?.call(path) case var busy?) return busy;
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
      if (scan == null) {
        // Honest: nothing has asked for this package, so nothing was scanned.
        // That is not the same as "no entries".
        nodes.add(
          ViewSection(path == '.' ? 'root' : path, const [
            ViewText('not computed'),
          ]),
        );
        continue;
      }

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

  /// Renders one entry to a PNG.
  ///
  /// Runs the whole pipeline headlessly, so the button, `fw` and an agent all
  /// reach the same artifact by the same route.
  ///
  /// Returns an [Artifact] rather than a path: a PNG that cannot say which
  /// entry it is of, at which size, is not reproducible — you cannot ask for
  /// the same picture again from the file alone. The [Address] it carries is
  /// exactly that question's answer.
  ///
  /// Scans on demand when nothing has yet: an agent naming an entry it read
  /// from a previous call should not have to know that the process it is
  /// talking to is a fresh one.
  Future<Artifact> _screenshot(Map<String, Object?> arguments) async {
    var entryId = arguments['entry'];
    if (entryId is! String || entryId.isEmpty) {
      throw ArgumentError.value(entryId, 'entry', 'required');
    }

    if (_scans.isEmpty && _failures.isEmpty) await computeAll();

    var packagePath = packages.firstWhere(
      (path) => _scans[path]?.entries.any((e) => e.id == entryId) ?? false,
      orElse: () => throw ArgumentError.value(
        entryId,
        'entry',
        'no entry with that id. Known: '
            '${entries.map((e) => e.id).take(10).join(', ')}'
            '${entries.length > 10 ? ', …' : ''}',
      ),
    );

    var packageRoot = p.join(host.worktree.path, packagePath);
    var width = _intArgument(arguments, 'width') ?? _defaultWidth;
    var height = _intArgument(arguments, 'height') ?? _defaultHeight;
    var entry = _scans[packagePath]!.entries.firstWhere((e) => e.id == entryId);

    var address = addressFor(
      packagePath,
      entryId,
      // Every axis that changed the pixels, resolved. Recording the size the
      // capture actually ran at — rather than only a size someone asked for —
      // is what lets the same frame be requested again.
      axes: {
        'width': '$width',
        'height': '$height',
        'formFactor': ?entry.formFactor,
      },
    );

    var output =
        arguments['output'] as String? ??
        p.join(
          packageRoot,
          'build',
          'catalog',
          'screenshots',
          _defaultFileName(address),
        );

    var file = await CatalogScreenshot(
      dartExecutable: p.join(host.workspace.flutterSdk.root, 'bin', 'dart'),
      config: DaemonConfig(
        appPackageRoot: packageRoot,
        projectRoot: packageRoot,
        packageConfig: requirePackageConfig(packageRoot),
        flutterSdkRoot: host.workspace.flutterSdk.root,
        roots: [_rootFor(packagePath)],
      ),
    ).capture(entryId: entryId, output: output, width: width, height: height);

    return Artifact(
      kind: Artifact.png,
      address: address,
      // Relative to the worktree root, so the value survives being read on
      // another machine — and so an agent whose tools are scoped to the repo
      // can open it.
      path: p.relative(file.path, from: host.worktree.path),
      meta: {
        'name': entry.name,
        'group': ?entry.group,
        'package': packagePath,
        'bytes': file.lengthSync(),
      },
    );
  }

  static const _defaultWidth = 900;
  static const _defaultHeight = 700;

  /// A file name that differs whenever the address does.
  ///
  /// The axes are in it because they are part of the address: capturing the
  /// same entry at two sizes used to write both to one path, so the second
  /// silently overwrote the first and two different addresses pointed at one
  /// file. An artifact that cannot be told apart from another artifact is not
  /// reproducible, which is the whole reason it carries an address.
  static String _defaultFileName(Address address) {
    var slug = _slug(address.segments.join('_'));
    var axes = address.axes.entries
        .map((axis) => '${_slug(axis.key)}-${_slug(axis.value)}')
        .join('_');
    return axes.isEmpty ? '$slug.png' : '${slug}__$axes.png';
  }

  static String _slug(String value) =>
      value.replaceAll(RegExp('[^A-Za-z0-9]+'), '_');

  /// Accepts an `int` or the string a CLI flag arrives as.
  static int? _intArgument(Map<String, Object?> arguments, String key) {
    var value = arguments[key];
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}

PluginCore uiCatalogCoreFactory(PluginHost host) => UiCatalogCore(host);

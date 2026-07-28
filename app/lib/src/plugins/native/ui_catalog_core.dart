import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../catalog/catalog_entry.dart';
import '../../catalog/devices.dart';
import '../../catalog/discovery.dart';
import '../../catalog/package_config_locator.dart';
import '../../catalog/protocol.dart';
import '../../catalog/headless_catalog.dart';
import '../plugin_core.dart';
import 'ui_catalog_address.dart';
import 'ui_catalog_results.dart';
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
/// — `HeadlessCatalog` needs no Flutter, which is what lets the button, `fw`
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
  /// The package comes first because two packages may legitimately declare the
  /// same entry id, and an address that cannot tell them apart is not an
  /// identity.
  ///
  /// The segments come from [catalogSegments], which the panel reads back
  /// through its inverse. Both halves live in one file so that this — the way
  /// in — and the way out cannot drift apart.
  ///
  /// [axes] are *applied*, not identity — the same entry rendered differently —
  /// which is what makes an address with its axes resolved a complete capture
  /// spec rather than an under-specified one.
  Address addressFor(
    String packagePath,
    String entryId, {
    Map<String, String> axes = const {},
  }) => Address(
    worktree: host.worktree.name,
    plugin: host.id,
    segments: catalogSegments(packagePath, entryId),
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
      PluginAction(
        'entries',
        'Entries',
        returns: CatalogEntriesResult,
        description:
            'Every catalog entry, with its id and address — the whole list, '
            'not the projection the report carries',
        parameters: [
          ActionParameter(
            'package',
            'Package',
            kind: ActionParameterKind.choice,
            required: false,
            description: 'Which declared package; all of them when omitted',
            options: [
              for (var path in packages)
                ActionOption(path, label: path == '.' ? 'root' : path),
            ],
          ),
        ],
      ),
      PluginAction(
        'check',
        'Check',
        returns: CatalogCheckResult,
        description:
            'Which entries the compiler can build, and the diagnostics for '
            'those it cannot',
        parameters: [
          ActionParameter(
            'package',
            'Package',
            kind: ActionParameterKind.choice,
            required: false,
            description: 'Which declared package; all of them when omitted',
            options: [
              for (var path in packages)
                ActionOption(path, label: path == '.' ? 'root' : path),
            ],
          ),
        ],
      ),
      const PluginAction(
        'describe',
        'Describe',
        returns: CatalogEntryDescription,
        description:
            'One entry: what it is, where it is, and the knobs it declares',
        parameters: [
          ActionParameter(
            'entry',
            'Entry',
            kind: ActionParameterKind.choice,
            description: 'The id of the entry to describe',
            optionsFrom: 'entries',
          ),
          ActionParameter(
            'knobs',
            'Read the knobs',
            kind: ActionParameterKind.boolean,
            required: false,
            defaultValue: 'false',
            description:
                'Compile the entry and run it to read the knobs it declares. '
                'Off by default because it costs a build; without it the '
                'answer is what the scan knows.',
          ),
        ],
      ),
      PluginAction(
        'screenshot',
        'Screenshot',
        returns: Artifact,
        description: 'Render one entry to a PNG',
        parameters: [
          ActionParameter(
            'entry',
            'Entry',
            kind: ActionParameterKind.choice,
            description: 'The id of the entry to render',
            // Points at the `entries` action, not at the report's view: the
            // view stops at 20 and this list does not, so the old pointer sent
            // a caller to a shorter list than the one it was truncating.
            optionsFrom: 'entries',
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
          const ActionParameter(
            'knobs',
            'Knobs',
            required: false,
            description:
                'Values to turn before the frame is taken, as `name=value` '
                'pairs or a JSON object. Ask `describe --knobs` what an entry '
                'offers. Recorded on the address, so two settings are two '
                'artifacts rather than one file written twice.',
          ),
          ActionParameter(
            'device',
            'Device',
            kind: ActionParameterKind.choice,
            required: false,
            description:
                'Render as a device: its screen, its pixel ratio and its safe '
                'areas, so the demo reads the phone from `MediaQuery` rather '
                'than a rectangle. Omitted means the panel. The same value the '
                'GUI writes as `?device=`, so an address captured here reopens '
                'framed the way it was shot.',
            options: [
              for (var id in deviceIds)
                ActionOption(
                  id,
                  label: id == fitDeviceId
                      ? 'Fit'
                      : catalogDevices.firstWhere((d) => d.id == id).label,
                ),
            ],
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
              // The same address the screenshot action and an artifact carry —
              // built here rather than left to a reader to reassemble from the
              // package and the id, which is how two surfaces come to disagree
              // about what an entry is called.
              address: addressFor(path, entry.id),
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
      case 'entries':
        return _entries(arguments);
      case 'check':
        return _check(arguments);
      case 'describe':
        return _describe(arguments);
      case 'screenshot':
        return _screenshot(arguments);
      default:
        return super.invoke(actionId, arguments: arguments);
    }
  }

  /// Every entry, in scan order, with the address that identifies each one.
  ///
  /// **Scans if nothing has.** A report may never start work; an action asked
  /// for by name may, and here must — `fw` and MCP open a session per request
  /// and hold nothing between them, so a query that only read the cache would
  /// answer "no entries" every time.
  ///
  /// The whole list, deliberately: the report's view stops at 20 entries and
  /// the screenshot action inlines at most 50 options, both of which are right
  /// for a projection meant to be read and wrong for the question "what can I
  /// screenshot".
  Future<CatalogEntriesResult> _entries(Map<String, Object?> arguments) async {
    var paths = _requestedPackages(arguments);

    // Always re-scans rather than answering from the cache. A scan is ~38ms
    // against a ~700ms process start, and the alternative is a `--refresh`
    // flag whose unset behaviour would be "possibly stale, no way to tell" —
    // which is not a useful thing to offer someone asking what exists.
    await Future.wait([for (var path in paths) _scan(path)]);

    return CatalogEntriesResult(
      packages: [for (var path in paths) _packageEntries(path)],
    );
  }

  /// Which packages an action was pointed at: the named one, or all declared.
  List<String> _requestedPackages(Map<String, Object?> arguments) {
    var requested = arguments['package'];
    if (requested != null && requested is! String) {
      throw ArgumentError.value(requested, 'package', 'must be a package path');
    }
    var paths = requested == null ? packages : [requested as String];
    for (var path in paths) {
      if (!packages.contains(path)) {
        throw ArgumentError.value(
          path,
          'package',
          'not declared for this plugin. Declared: ${packages.join(', ')}',
        );
      }
    }
    return paths;
  }

  CatalogPackageEntries _packageEntries(String path) {
    if (_failures[path] case var failure?) {
      return CatalogPackageEntries(path: path, error: failure);
    }
    var scan = _scans[path];
    return CatalogPackageEntries(
      path: path,
      entries: [
        for (var entry in scan?.entries ?? const <CatalogEntry>[])
          CatalogEntrySummary(
            id: entry.id,
            name: entry.name,
            group: entry.group,
            formFactor: entry.formFactor,
            // What every other surface identifies this by — hand it straight
            // back to `screenshot`, or later to `show`.
            address: '${addressFor(path, entry.id)}',
          ),
      ],
      diagnostics: [
        for (var diagnostic in scan?.diagnostics ?? const []) '$diagnostic',
      ],
    );
  }

  /// Which entries the compiler can build, per package.
  ///
  /// The one question the scan cannot answer: it parses a file and finds an
  /// entry, but whether that entry *compiles* is a fact only the compiler
  /// holds. Until now only the panel could ask, because only the panel ran a
  /// daemon.
  ///
  /// One daemon at a time rather than all at once: each package's daemon may
  /// have to build a host binary, and two cold builds racing helps nobody. A
  /// package that cannot be checked reports why in its own row instead of
  /// sinking the others.
  Future<CatalogCheckResult> _check(Map<String, Object?> arguments) async {
    var results = <CatalogPackageCheck>[];
    for (var path in _requestedPackages(arguments)) {
      try {
        var checked = await _headlessFor(path).check();
        results.add(
          CatalogPackageCheck(
            path: path,
            ok: checked.ok,
            servable: [for (var entry in checked.servable) entry.id],
            broken: [
              for (var broken in checked.quarantined)
                CatalogBrokenEntry(id: broken.entry.id, error: broken.error),
            ],
          ),
        );
      } catch (e) {
        results.add(CatalogPackageCheck(path: path, error: '$e'));
      }
    }
    return CatalogCheckResult(packages: results);
  }

  /// Everything known about one entry.
  ///
  /// The scan half is free. The knobs are not: a demo declares them by *asking*
  /// for them while it builds, so the only way to know is to compile it and run
  /// it — which is why `knobs` is opt-in and off by default. An agent deciding
  /// what to vary before a screenshot wants it; an agent listing entries does
  /// not.
  Future<CatalogEntryDescription> _describe(
    Map<String, Object?> arguments,
  ) async {
    var entryId = arguments['entry'];
    if (entryId is! String || entryId.isEmpty) {
      throw ArgumentError.value(entryId, 'entry', 'required');
    }
    if (_scans.isEmpty && _failures.isEmpty) await computeAll();

    var packagePath = _packageHolding(entryId);
    var entry = _scans[packagePath]!.entries.firstWhere((e) => e.id == entryId);

    CatalogEntryDescription describe({List<CatalogKnob>? knobs}) =>
        CatalogEntryDescription(
          id: entry.id,
          name: entry.name,
          group: entry.group,
          formFactor: entry.formFactor,
          package: packagePath,
          file: entry.path,
          symbol: entry.symbol,
          annotation: entry.annotation,
          address: '${addressFor(packagePath, entryId)}',
          knobs: knobs,
        );

    if (arguments['knobs'] != true) return describe();

    var report = await _headlessFor(packagePath).knobs(entryId: entryId);
    // An entry that declares none answers with an empty list: "it has no
    // knobs" and "we did not look" are different questions, and only one of
    // them was asked. Which is why the field is nullable and this is a list.
    return describe(
      knobs: [
        for (var knob in report.knobs)
          CatalogKnob(
            name: knob.name,
            kind: knob.kind.name,
            value: knob.value,
            defaultValue: knob.defaultValue,
            min: knob.min,
            max: knob.max,
            options: knob.options,
          ),
      ],
    );
  }

  /// Which declared package holds [entryId].
  String _packageHolding(String entryId) => packages.firstWhere(
    (path) => _scans[path]?.entries.any((e) => e.id == entryId) ?? false,
    orElse: () => throw ArgumentError.value(
      entryId,
      'entry',
      'no entry with that id. Known: '
          '${entries.map((e) => e.id).take(10).join(', ')}'
          '${entries.length > 10 ? ', …' : ''}',
    ),
  );

  /// The headless pipeline for one declared package.
  HeadlessCatalog _headlessFor(String packagePath) {
    var packageRoot = p.join(host.worktree.path, packagePath);
    return HeadlessCatalog(
      dartExecutable: p.join(host.workspace.flutterSdk.root, 'bin', 'dart'),
      config: DaemonConfig(
        appPackageRoot: packageRoot,
        projectRoot: packageRoot,
        packageConfig: requirePackageConfig(packageRoot),
        flutterSdkRoot: host.workspace.flutterSdk.root,
        roots: [_rootFor(packagePath)],
      ),
    );
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

    var packagePath = _packageHolding(entryId);
    var packageRoot = p.join(host.worktree.path, packagePath);
    var entry = _scans[packagePath]!.entries.firstWhere((e) => e.id == entryId);

    // Named rather than defaulted, and refused rather than approximated. A
    // device this build does not know is the one failure that has to be loud:
    // quietly framing as the panel produces a PNG that is wrong without looking
    // wrong, and something downstream files it as evidence.
    var deviceId = arguments['device'];
    if (deviceId != null && (deviceId is! String || !isDeviceId(deviceId))) {
      throw ArgumentError.value(
        deviceId,
        'device',
        'no such device. Accepted: ${deviceIds.join(', ')}',
      );
    }

    // Width and height still win where they are given: they are how you ask for
    // a size no device has, and on a device they stretch its screen rather than
    // dropping its ratio and its notch.
    // `fit` names the panel and resolves to no device, which is the same
    // viewport by a different route.
    var device = deviceId is String ? deviceById(deviceId) : null;
    var viewport = device == null
        ? CaptureViewport.panel
        : CaptureViewport.of(device);
    viewport = viewport.resized(
      width: _intArgument(arguments, 'width'),
      height: _intArgument(arguments, 'height'),
    );

    var knobs = parseKnobs(arguments['knobs']);

    var address = addressFor(
      packagePath,
      entryId,
      // Every axis that changed the pixels, resolved. Recording the size the
      // capture actually ran at — rather than only a size someone asked for —
      // is what lets the same frame be requested again.
      //
      // Knobs are axes too, and prefixed: a demo may declare a knob called
      // `width`, and an address where a knob quietly overwrote the viewport
      // would name a picture that was never taken.
      axes: {
        // The word the GUI reads, so an address that came out of a capture
        // reopens framed the way it was shot. Without it the two surfaces
        // describe the same picture in different vocabularies and the
        // round-trip silently loses the framing.
        'device': ?deviceId as String?,
        'width': '${viewport.width}',
        'height': '${viewport.height}',
        'formFactor': ?entry.formFactor,
        for (var knob in knobs.entries) 'knob.${knob.key}': knob.value,
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

    var captured = await _headlessFor(packagePath).capture(
      entryId: entryId,
      output: output,
      viewport: viewport,
      knobs: knobs,
    );

    return Artifact(
      kind: Artifact.png,
      address: address,
      // Relative to the worktree root, so the value survives being read on
      // another machine — and so an agent whose tools are scoped to the repo
      // can open it.
      path: p.relative(captured.file.path, from: host.worktree.path),
      meta: {
        'name': entry.name,
        'group': ?entry.group,
        'package': packagePath,
        'bytes': captured.file.lengthSync(),
        // What the entry reported after the values landed. A demo may clamp
        // one, and a caller comparing this with what it asked for is the only
        // way to notice.
        if (captured.knobs.isNotEmpty)
          'knobs': {for (var knob in captured.knobs) knob.name: knob.value},
      },
    );
  }

  /// Knob values, however they arrived.
  ///
  /// A map when an agent sent JSON, a string when a shell did — `fw` has no
  /// types to pass and no repeatable flags, so `name=value,name=value` is the
  /// form that survives a command line. A JSON object in that string works
  /// too, since an agent writing one is not wrong to expect it to.
  ///
  /// Values stay strings here: only the guest knows what kind each knob is,
  /// and guessing at this end would make `count=5` an int for one demo and a
  /// string for another.
  static Map<String, String> parseKnobs(Object? value) {
    if (value == null) return const {};
    if (value is Map) {
      return {
        for (var entry in value.entries) '${entry.key}': '${entry.value}',
      };
    }
    if (value is! String || value.trim().isEmpty) {
      throw ArgumentError.value(value, 'knobs', 'expected name=value pairs');
    }

    if (value.trimLeft().startsWith('{')) {
      var decoded = jsonDecode(value.trim());
      if (decoded is! Map) {
        throw ArgumentError.value(value, 'knobs', 'expected a JSON object');
      }
      return parseKnobs(decoded);
    }

    // Names are trimmed, values never: `label= x ` sets a string knob to a
    // value with spaces in it, which is a legitimate thing to want to look at.
    // So the argument as a whole is not trimmed either — the trailing space of
    // the last pair belongs to it.
    var knobs = <String, String>{};
    for (var pair in value.split(',')) {
      var equals = pair.indexOf('=');
      if (equals <= 0 || pair.substring(0, equals).trim().isEmpty) {
        throw ArgumentError.value(
          pair,
          'knobs',
          'expected name=value, separated by commas',
        );
      }
      knobs[pair.substring(0, equals).trim()] = pair.substring(equals + 1);
    }
    return knobs;
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

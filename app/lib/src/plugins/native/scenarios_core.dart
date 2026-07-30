import 'dart:isolate';

import 'package:flutterware/plugins.dart';

import '../../scenarios/discovery.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'scenarios_address.dart';
import 'scenarios_results.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const scenariosPluginId = 'flutterware.scenarios';

/// Scenarios for each declared package — the skeleton tier: the syntactic
/// scan, projected into the report and the `list` action. The runner (daemon,
/// `run` action, per-step artifacts) builds on top of this; see
/// `docs/superpowers/specs/2026-07-30-scenarios-design.md`.
///
/// Follows the dependencies core's rule: **nothing here starts work.** The
/// constructor allocates nothing and [report] only reads what somebody already
/// caused to scan. Scanning begins in [track], which the panel calls on mount
/// and `fw` calls for the duration of a request.
class ScenariosCore extends PluginCore {
  ScenariosCore(super.host);

  final _scans = <String, Future<void>>{};
  final _results = <String, ScenarioScanResult>{};
  final _errors = <String, Object>{};

  /// Declared packages, filtered to those the workspace knows about.
  late final List<String> packages = [
    for (var path in host.packagePaths)
      if (host.workspace.exists(path)) path,
  ];

  /// The scenario directory declared for [path], or the convention.
  String directoryFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] == path) {
        if (config['directory'] case String directory) return directory;
      }
    }
    return defaultScenariosDirectory;
  }

  /// Whether [path] has been scanned (or is scanning) — the laziness rule,
  /// made observable.
  bool isRealised(String path) => _scans.containsKey(path);

  bool isScanning(String path) =>
      _scans.containsKey(path) &&
      !_results.containsKey(path) &&
      !_errors.containsKey(path);

  /// The cached scan for [path], or null when nothing has looked at it yet.
  ScenarioScanResult? scanResultFor(String path) => _results[path];

  Object? scanErrorFor(String path) => _errors[path];

  /// Starts (and keeps) the scan for [path]. Idempotent.
  void track(String path) {
    if (_scans.containsKey(path)) return;
    var scanner = ScenarioScanner(
      packageRoot: host.workspace.packageFor(path).directory.path,
      directory: directoryFor(path),
    );
    // Parsing runs off-isolate, as the catalog's scan does.
    _scans[path] = Isolate.run(scanner.scan)
        .then<void>((result) => _results[path] = result)
        .catchError((Object error) => _errors[path] = error)
        .whenComplete(notifyChanged);
    notifyChanged();
  }

  /// A scan result is cheap and kept — releasing it would only buy a rescan.
  void untrack(String path) {}

  @override
  PluginReport get report {
    return PluginReport(
      id: host.id,
      label: host.label,
      status: _status(),
      children: [
        for (var path in packages)
          PluginChild(
            id: path,
            label: path == '.' ? 'root' : path,
            status: _packageStatus(path),
            badge: switch (_results[path]?.scenarios.length) {
              null || 0 => StatusBadge.none,
              var count => StatusBadge.count(count),
            },
          ),
      ],
      badge: _errors.isNotEmpty
          ? const StatusBadge.dot(Tone.error)
          : StatusBadge.none,
      actions: [
        PluginAction(
          'list',
          'List',
          returns: ScenarioListResult,
          description:
              'Every scenario of a package, with its source location — from '
              'the syntactic scan, without compiling or running anything',
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
      ],
      view: _view(),
    );
  }

  Status _status() {
    if (packages.isEmpty) return const Status.warn('no packages');
    if (_errors.isNotEmpty) return const Status.error('scan failed');
    var scanning = _scans.keys.where((p) => !_results.containsKey(p)).length;
    return scanning == 0 ? Status.none : const Status.info('scanning…');
  }

  Status _packageStatus(String path) {
    if (_errors.containsKey(path)) return const Status.error('scan failed');
    if (!_scans.containsKey(path)) return Status.none;
    if (!_results.containsKey(path)) return const Status.info('scanning…');
    return Status.none;
  }

  PluginView _view() {
    if (packages.isEmpty) {
      return const PluginView([
        ViewText(
          'This plugin has no packages. Add them in tool/flutterware.dart.',
          tone: Tone.warn,
        ),
      ]);
    }

    return PluginView([
      for (var path in packages)
        ViewSection(path, [
          if (_errors[path] case var error?)
            ViewField('Error', '$error', tone: Tone.error)
          else if (_results[path] case var result?) ...[
            ViewField('Scenarios', '${result.scenarios.length}'),
            for (var diagnostic in result.diagnostics)
              ViewText(diagnostic, tone: Tone.warn),
            ViewItems([
              for (var ref in result.scenarios)
                ViewItem(
                  ref.name,
                  detail: '${ref.file}:${ref.line}',
                  address: addressFor(path, ref),
                ),
            ]),
          ] else
            const ViewText('not computed'),
        ]),
    ]);
  }

  /// Where one scenario's page is — the same segments the panel writes.
  Address addressFor(String packagePath, ScenarioRef ref) => Address(
    worktree: host.worktree.name,
    plugin: host.id,
    segments: scenarioSegments(packagePath, file: ref.file, scenario: ref.name),
  );

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    if (actionId != 'list') {
      return super.invoke(actionId, arguments: arguments);
    }
    return _list(arguments);
  }

  /// The scenarios of one package, or of every declared package.
  ///
  /// **Loads what it needs** — a report may never start work; an action asked
  /// for by name may, and must.
  Future<ScenarioListResult> _list(Map<String, Object?> arguments) async {
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

    for (var path in paths) {
      track(path);
    }
    await Future.wait([for (var path in paths) _scans[path]!]);

    return ScenarioListResult(
      packages: [
        for (var path in paths)
          if (_errors[path] case var error?)
            ScenarioListPackage(
              path: path,
              directory: directoryFor(path),
              error: '$error',
            )
          else
            ScenarioListPackage(
              path: path,
              directory: directoryFor(path),
              scenarios: [
                for (var ref in _results[path]!.scenarios)
                  ScenarioListEntry(
                    name: ref.name,
                    file: ref.file,
                    line: ref.line,
                  ),
              ],
              diagnostics: _results[path]!.diagnostics,
            ),
      ],
    );
  }

  /// Scans every declared package and waits — what `fw` does for the duration
  /// of one request.
  @override
  Future<void> computeAll() async {
    for (var path in packages) {
      track(path);
    }
    await Future.wait(_scans.values);
  }
}

PluginCore scenariosCoreFactory(PluginHost host) => ScenariosCore(host);

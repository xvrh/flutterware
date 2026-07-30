import 'dart:async';
import 'dart:isolate';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../scenarios/discovery.dart';
import '../../scenarios/runner.dart';
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

  /// One warm runner per package, created by the first `run` and kept — a
  /// second run reuses the compiled harness and the live tester.
  final _runners = <String, ScenarioRunner>{};

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
        PluginAction(
          'run',
          'Run',
          returns: ScenarioRunResult,
          description:
              'Runs scenarios under FakeAsync in a directly-spawned '
              'flutter_tester, capturing a PNG, a widget tree and the visible '
              'texts per step. The paths in the result point at the '
              'artifacts; a failing scenario reports its error with the frame '
              'captured just before it.',
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
            const ActionParameter(
              'file',
              'File',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Run only this scenario file, package-relative — as `list` '
                  'reports it',
            ),
            const ActionParameter(
              'scenario',
              'Scenario',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Run only this scenario, by name. Needs `file` too — names '
                  'are unique per file, not per package.',
            ),
            const ActionParameter(
              'output',
              'Output directory',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Where step artifacts are written; a fresh directory under '
                  "the package's build/ when omitted",
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
    return switch (actionId) {
      'list' => _list(arguments),
      'run' => _run(arguments),
      _ => super.invoke(actionId, arguments: arguments),
    };
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

  /// Runs scenarios in the runner's `flutter_tester`.
  ///
  /// The runner per package is created on first use and **kept warm** — in
  /// the GUI a second run reuses the compiled harness and the live tester; in
  /// a one-shot `fw` process it lives for the request and dies with the
  /// session.
  Future<ScenarioRunResult> _run(Map<String, Object?> arguments) async {
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
    var file = arguments['file'] as String?;
    var scenario = arguments['scenario'] as String?;
    if (scenario != null && file == null) {
      throw ArgumentError(
        '`scenario` needs `file` too — names are unique per file, '
        'not per package.',
      );
    }
    var output = arguments['output'] as String?;

    var results = <ScenarioRunPackage>[];
    for (var path in paths) {
      var packageRoot = host.workspace.packageFor(path).directory.path;
      var outDir =
          output ??
          p.join(
            packageRoot,
            'build',
            'flutterware',
            'scenario_runs',
            '${DateTime.now().millisecondsSinceEpoch}',
          );
      try {
        var report = await _runnerFor(
          path,
        ).run(outDir: outDir, file: file, scenario: scenario);
        results.add(_describeRun(path, outDir, report));
      } catch (error) {
        results.add(
          ScenarioRunPackage(path: path, output: outDir, error: '$error'),
        );
      }
    }
    return ScenarioRunResult(packages: results);
  }

  ScenarioRunner _runnerFor(String path) => _runners.putIfAbsent(
    path,
    () => ScenarioRunner(
      packageRoot: host.workspace.packageFor(path).directory.path,
      directory: directoryFor(path),
      flutterSdkRoot: host.workspace.flutterSdk.root,
    ),
  );

  /// The harness's report, in the declared result shape and with each step
  /// given its `fw://` address.
  ScenarioRunPackage _describeRun(
    String path,
    String outDir,
    Map<String, Object?> report,
  ) {
    return ScenarioRunPackage(
      path: path,
      output: outDir,
      ms: report['ms'] as int? ?? 0,
      scenarios: [
        for (var outcome
            in (report['scenarios']! as List).cast<Map<String, dynamic>>())
          ScenarioRunOutcome(
            file: outcome['file']! as String,
            name: outcome['name']! as String,
            ok: outcome['ok'] == true,
            ms: outcome['ms'] as int? ?? 0,
            steps: [
              for (var step
                  in (outcome['steps']! as List).cast<Map<String, dynamic>>())
                ScenarioRunStep(
                  index: step['index']! as int,
                  name: step['name'] as String?,
                  auto: step['auto'] == true,
                  tags: (step['tags'] as List?)?.cast<String>() ?? const [],
                  png: step['png']! as String,
                  tree: step['tree']! as String,
                  texts: (step['texts']! as List).cast<String>(),
                  address: Address(
                    worktree: host.worktree.name,
                    plugin: host.id,
                    segments: scenarioSegments(
                      path,
                      file: outcome['file']! as String,
                      scenario: outcome['name']! as String,
                    ),
                  ).child('${step['index']}').toString(),
                ),
            ],
            errors: [
              for (var error
                  in (outcome['errors'] as List? ?? const [])
                      .cast<Map<String, dynamic>>())
                ScenarioRunError(
                  error: error['error']! as String,
                  stack: error['stack'] as String?,
                ),
            ],
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

  @override
  void dispose() {
    for (var runner in _runners.values) {
      unawaited(runner.dispose());
    }
    _runners.clear();
    super.dispose();
  }
}

PluginCore scenariosCoreFactory(PluginHost host) => ScenariosCore(host);

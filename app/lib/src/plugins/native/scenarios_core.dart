import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:flutterware/plugins.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../catalog/devices.dart';
import '../../scenarios/axes.dart';
import '../../scenarios/discovery.dart';
import '../../scenarios/runner.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'scenarios_address.dart';
import 'scenarios_results.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const scenariosPluginId = 'flutterware.scenarios';

/// One scenario's latest panel-driven run — what the flow page renders.
///
/// Replaced wholesale on every transition, never mutated: the panel compares
/// nothing, it just draws whatever this says.
class ScenarioPanelRun {
  ScenarioPanelRun({
    required this.running,
    required this.axes,
    this.steps = const [],
    this.outcome,
    this.error,
    this.output,
  });

  final bool running;

  /// The axis assignment of the latest *attempt*. Recorded on failure too,
  /// so the page can see "these axes were tried" and not retry them in a
  /// loop.
  final ScenarioAxes axes;

  /// The run's steps as the page draws them: **growing while the run
  /// executes** — each one announced by the harness the moment its artifacts
  /// hit disk — and the settled list afterwards. A failed run keeps what it
  /// captured before dying, which is the frame just before the failure.
  ///
  /// Starting a run clears this: for a long scenario, an empty flow filling
  /// in beats last run's pictures pretending to be this run's.
  final List<ScenarioRunStep> steps;

  /// The completed outcome of this attempt, or null while running (and after
  /// a failed attempt — [steps] and [error] are what remain of one).
  final ScenarioRunOutcome? outcome;

  /// What the attempt died of, or null.
  final String? error;

  /// The directory the artifacts live in.
  final String? output;
}

/// Scenarios for each declared package: the syntactic scan projected into the
/// report and the `list` action, the `run` action in a warm
/// [ScenarioRunner], and the panel's per-scenario run state on the same
/// runner; see `docs/superpowers/specs/2026-07-30-scenarios-design.md`.
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

  /// The panel's runs, one per scenario, keyed `(package, file, scenario)`.
  final _panelRuns = <(String, String, String), ScenarioPanelRun>{};

  /// The runner's last progress line per package — the only narration a cold
  /// start has, so the panel can say "building the asset bundle" rather than
  /// spinning silently for thirty seconds.
  final _runnerLogs = <String, String>{};

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

  /// The locale tags declared for [path] in `tool/flutterware.dart` —
  /// `Scenarios(packages: [.new(app, languages: ['en', 'fr'])])` — or empty.
  /// The language axis offers exactly this list; it is configuration, not
  /// free text, because a tag the app does not support runs the fallback
  /// locale and produces a picture that is wrong without looking wrong.
  List<String> languagesFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] == path) {
        if (config['languages'] case List<Object?> languages) {
          return languages.cast<String>();
        }
      }
    }
    return const [];
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

  /// The panel's latest run of one scenario, or null when it has never run.
  ScenarioPanelRun? panelRunFor(
    String package, {
    required String file,
    required String scenario,
  }) => _panelRuns[(package, file, scenario)];

  String? runnerLogFor(String package) => _runnerLogs[package];

  bool get anyPanelRunning => _panelRuns.values.any((run) => run.running);

  /// Starts one scenario's run for the panel. A no-op while that scenario is
  /// already running; a completed run may be started again.
  ///
  /// Same runner, same warm guest as the `run` action — the panel is another
  /// caller, not another path. The runner refreshes edited sources before a
  /// warm run, which is what makes the Run button honest after an edit.
  void startRun(
    String package, {
    required String file,
    required String scenario,
    ScenarioAxes axes = const ScenarioAxes(),
  }) {
    var key = (package, file, scenario);
    var previous = _panelRuns[key];
    if (previous?.running ?? false) return;
    // The immediate clear: the page shows *this* run filling in, never the
    // previous run's pictures under this run's spinner.
    _panelRuns[key] = ScenarioPanelRun(running: true, axes: axes);
    notifyChanged();
    unawaited(_panelRun(key, previous, axes));
  }

  /// One step, announced mid-run over the VM service — appended to the
  /// running attempt's [ScenarioPanelRun.steps] as it lands.
  void _onRunnerStep(String package, Map<String, Object?> event) {
    if ((event['file'], event['scenario']) case (
      String file,
      String scenario,
    )) {
      var key = (package, file, scenario);
      var state = _panelRuns[key];
      if (state == null || !state.running) return;
      var step = _stepFrom(
        (event['step']! as Map).cast<String, dynamic>(),
        package,
        file: file,
        scenario: scenario,
        axes: state.axes,
      );
      _panelRuns[key] = ScenarioPanelRun(
        running: true,
        axes: state.axes,
        steps: [...state.steps, step],
      );
      notifyChanged();
    }
  }

  Future<void> _panelRun(
    (String, String, String) key,
    ScenarioPanelRun? previous,
    ScenarioAxes axes,
  ) async {
    var (package, file, scenario) = key;
    var packageRoot = host.workspace.packageFor(package).directory.path;
    var outDir = p.join(
      packageRoot,
      'build',
      'flutterware',
      'scenario_runs',
      'panel-${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      // Raw pixels for the panel: it displays them natively, and skipping
      // PNG encoding is what makes a 50-step run feel instantaneous.
      var report = await _runnerFor(package).run(
        outDir: outDir,
        file: file,
        scenario: scenario,
        axes: axes,
        captureRaw: true,
      );
      var outcome = _describeRun(package, outDir, report, axes: axes).scenarios
          .where((s) => s.file == file && s.name == scenario)
          .firstOrNull;
      if (outcome == null) {
        _panelRuns[key] = ScenarioPanelRun(
          running: false,
          axes: axes,
          steps: _panelRuns[key]?.steps ?? const [],
          error:
              'The harness ran nothing named "$scenario" in $file — '
              'renamed since this page was opened?',
        );
        return;
      }
      _panelRuns[key] = ScenarioPanelRun(
        running: false,
        axes: axes,
        steps: outcome.steps,
        outcome: outcome,
        output: outDir,
      );
      // The superseded run's artifacts. The images already on screen are
      // decoded, so pulling the files is safe — and keeping them would grow a
      // directory per click.
      if (previous?.output case var old? when old != outDir) {
        try {
          Directory(old).deleteSync(recursive: true);
        } on FileSystemException {
          // Somebody looking at it, or already gone — either way not ours.
        }
      }
    } catch (error) {
      // The steps captured before the failure stay: the last one is the
      // frame just before it died.
      _panelRuns[key] = ScenarioPanelRun(
        running: false,
        axes: axes,
        steps: _panelRuns[key]?.steps ?? const [],
        error: '$error',
      );
    } finally {
      notifyChanged();
      // The run compiled the suite as it is on disk, which is newer truth
      // than the list pane's scan — catch the pane up.
      _rescan(package);
    }
  }

  /// Replaces the cached scan — what [track] deliberately never does.
  void _rescan(String path) {
    var scanner = ScenarioScanner(
      packageRoot: host.workspace.packageFor(path).directory.path,
      directory: directoryFor(path),
    );
    _scans[path] = Isolate.run(scanner.scan)
        .then<void>((result) => _results[path] = result)
        .catchError((Object error) => _errors[path] = error)
        .whenComplete(notifyChanged);
  }

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
            // The axes. Declared because they change the pixels, and anything
            // that changes the pixels is recorded on the artifact's address.
            ActionParameter(
              'device',
              'Device',
              kind: ActionParameterKind.choice,
              required: false,
              description:
                  'Run as a device: its screen, its pixel ratio, its safe '
                  'areas and its platform, so the app reads the phone from '
                  '`MediaQuery`. Omitted means the default form factor '
                  '($defaultScenarioDeviceId); `fit` means the bare 800×600 '
                  'test surface. The same vocabulary the UI catalog frames '
                  'with.',
              options: [
                for (var device in catalogDevices)
                  ActionOption(device.id, label: device.label),
                ActionOption(fitDeviceId, label: 'Bare test surface'),
              ],
            ),
            const ActionParameter(
              'language',
              'Language',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'A locale tag — `fr`, `fr-CA` — applied as the platform '
                  'locale for the whole run',
            ),
            const ActionParameter(
              'text-scale',
              'Text scale',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'The platform text scale factor — `1.3` is a common '
                  'accessibility setting',
            ),
            const ActionParameter(
              'brightness',
              'Brightness',
              kind: ActionParameterKind.choice,
              required: false,
              description: 'The platform brightness the app sees',
              options: [ActionOption('light'), ActionOption('dark')],
            ),
            const ActionParameter(
              'bold-text',
              'Bold text',
              kind: ActionParameterKind.choice,
              required: false,
              description: 'The bold-text accessibility switch',
              options: [ActionOption('true'), ActionOption('false')],
            ),
            const ActionParameter(
              'high-contrast',
              'High contrast',
              kind: ActionParameterKind.choice,
              required: false,
              description: 'The high-contrast accessibility switch',
              options: [ActionOption('true'), ActionOption('false')],
            ),
            const ActionParameter(
              'invert-colors',
              'Invert colors',
              kind: ActionParameterKind.choice,
              required: false,
              description: 'The invert-colors accessibility switch',
              options: [ActionOption('true'), ActionOption('false')],
            ),
            const ActionParameter(
              'capture-scale',
              'Capture scale',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Screenshot pixels per logical pixel, 1 (the default) to '
                  "4. The device's own ratio gives a true screenshot; 1 is "
                  '~10× faster and smaller, which is what keeps a long '
                  'FakeAsync run instantaneous. Not an axis: it changes the '
                  'artifact, never what the app sees.',
            ),
            const ActionParameter(
              'format',
              'Image format',
              kind: ActionParameterKind.choice,
              required: false,
              description:
                  '`png` (the default) is what everything opens. `raw` — '
                  'bare rgba8888 rows, width×height×4 bytes as the result '
                  'reports them — skips PNG encoding, which is ~80% of a '
                  "capture's cost; for pipelines that consume pixels "
                  'directly.',
              options: [ActionOption('png'), ActionOption('raw')],
            ),
          ],
        ),
        PluginAction(
          'restart',
          'Restart',
          returns: ScenarioRestartResult,
          description:
              'Drops the warm harness so the next run cold-starts from '
              'nothing: fresh asset bundle, fresh kernel, fresh tester '
              'process. The escape hatch for changes no incremental lane '
              "can see — a dependency's assets, or plain distrust.",
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

  /// The request's axis assignment, validated. Refused rather than
  /// approximated — a device this build does not know must fail loudly,
  /// because silently running at the default surface produces a picture that
  /// is wrong without looking wrong.
  static ScenarioAxes _axesFrom(Map<String, Object?> arguments) {
    var device = arguments['device'];
    if (device != null && (device is! String || !isDeviceId(device))) {
      throw ArgumentError.value(
        device,
        'device',
        'no such device. Accepted: ${deviceIds.join(', ')}',
      );
    }
    var language = arguments['language'];
    if (language != null &&
        (language is! String ||
            !RegExp(
              r'^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})?$',
            ).hasMatch(language))) {
      throw ArgumentError.value(
        language,
        'language',
        'not a locale tag — expected e.g. `fr` or `fr-CA`',
      );
    }
    double? textScale;
    if (arguments['text-scale'] case var raw?) {
      textScale = switch (raw) {
        num value => value.toDouble(),
        String value => double.tryParse(value),
        _ => null,
      };
      if (textScale == null) {
        throw ArgumentError.value(raw, 'text-scale', 'not a number');
      }
    }
    var brightness = arguments['brightness'];
    if (brightness != null && brightness != 'light' && brightness != 'dark') {
      throw ArgumentError.value(
        brightness,
        'brightness',
        'accepted: light, dark',
      );
    }
    bool flag(String name) {
      var raw = arguments[name];
      if (raw == null || raw == 'false' || raw == false) return false;
      if (raw == 'true' || raw == true) return true;
      throw ArgumentError.value(raw, name, 'accepted: true, false');
    }

    return ScenarioAxes(
      device: resolveScenarioDevice(device as String?),
      language: language as String?,
      textScale: textScale,
      brightness: brightness as String?,
      boldText: flag('bold-text'),
      highContrast: flag('high-contrast'),
      invertColors: flag('invert-colors'),
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
      'restart' => _restart(arguments),
      _ => super.invoke(actionId, arguments: arguments),
    };
  }

  Future<ScenarioRestartResult> _restart(Map<String, Object?> arguments) async {
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
      restartRunner(path);
    }
    return ScenarioRestartResult(restarted: paths);
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
    var axes = _axesFrom(arguments);
    double? captureScale;
    if (arguments['capture-scale'] case var raw?) {
      captureScale = switch (raw) {
        num value => value.toDouble(),
        String value => double.tryParse(value),
        _ => null,
      };
      if (captureScale == null || captureScale <= 0 || captureScale > 4) {
        throw ArgumentError.value(raw, 'capture-scale', 'a number in (0, 4]');
      }
    }
    var format = arguments['format'];
    if (format != null && format != 'png' && format != 'raw') {
      throw ArgumentError.value(format, 'format', 'accepted: png, raw');
    }

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
        var report = await _runnerFor(path).run(
          outDir: outDir,
          file: file,
          scenario: scenario,
          axes: axes,
          captureScale: captureScale,
          captureRaw: format == 'raw',
        );
        results.add(_describeRun(path, outDir, report, axes: axes));
      } catch (error) {
        results.add(
          ScenarioRunPackage(path: path, output: outDir, error: '$error'),
        );
      }
    }
    return ScenarioRunResult(
      packages: results,
      axes: axes.isEmpty ? null : axes.toParams(),
    );
  }

  /// The escape hatch: drops [path]'s warm harness, so the next run
  /// cold-starts from nothing — fresh asset bundle, fresh kernel, fresh
  /// tester process. For the changes no incremental lane can see, and for
  /// "I don't trust anything right now".
  void restartRunner(String path) {
    if (_runners.remove(path) case var runner?) {
      unawaited(runner.dispose());
    }
    _runnerLogs.remove(path);
    // Drop the bundle stamp too: a full restart means "rebuild it all",
    // including assets the stamp cannot see (a dependency's, say).
    var stamp = File(
      p.join(
        host.workspace.packageFor(path).directory.path,
        'build',
        'flutterware',
        'scenarios_assets',
        '.assets.stamp',
      ),
    );
    if (stamp.existsSync()) stamp.deleteSync();
    notifyChanged();
  }

  ScenarioRunner _runnerFor(String path) {
    var runner = _runners.putIfAbsent(
      path,
      () => ScenarioRunner(
        packageRoot: host.workspace.packageFor(path).directory.path,
        directory: directoryFor(path),
        flutterSdkRoot: host.workspace.flutterSdk.root,
        onLog: (line) {
          _runnerLogs[path] = line;
          notifyChanged();
        },
      ),
    );
    // (Re)attached on every ask, so an installed test runner streams too.
    runner.onStep = (event) => _onRunnerStep(path, event);
    return runner;
  }

  /// Installs a runner for [path], so a test can drive the run-state machinery
  /// without a real `flutter_tester` behind it.
  @visibleForTesting
  void debugInstallRunner(String path, ScenarioRunner runner) =>
      _runners[path] = runner;

  /// One step of the harness's vocabulary — the same map whether it arrived
  /// in the final report or as a mid-run event — with its `fw://` address,
  /// carrying [axes] as query parameters since the picture depends on them.
  ScenarioRunStep _stepFrom(
    Map<String, dynamic> step,
    String path, {
    required String file,
    required String scenario,
    required ScenarioAxes axes,
  }) {
    return ScenarioRunStep(
      index: step['index']! as int,
      name: step['name'] as String?,
      auto: step['auto'] == true,
      tags: (step['tags'] as List?)?.cast<String>() ?? const [],
      image: step['image']! as String,
      format: step['format'] as String? ?? 'png',
      width: step['width'] as int? ?? 0,
      height: step['height'] as int? ?? 0,
      tree: step['tree']! as String,
      texts: (step['texts']! as List).cast<String>(),
      statusBrightness: step['statusBrightness'] as String?,
      navBrightness: step['navBrightness'] as String?,
      address: Address(
        worktree: host.worktree.name,
        plugin: host.id,
        segments: scenarioSegments(path, file: file, scenario: scenario),
        axes: axes.toParams(),
      ).child('${step['index']}').toString(),
    );
  }

  /// The harness's report, in the declared result shape.
  ScenarioRunPackage _describeRun(
    String path,
    String outDir,
    Map<String, Object?> report, {
    ScenarioAxes axes = const ScenarioAxes(),
  }) {
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
                _stepFrom(
                  step,
                  path,
                  file: outcome['file']! as String,
                  scenario: outcome['name']! as String,
                  axes: axes,
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

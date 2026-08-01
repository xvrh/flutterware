import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:flutterware/plugins.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../scenarios/authoring.dart';
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
    this.device,
    this.steps = const [],
    this.outcome,
    this.error,
    this.output,
  });

  final bool running;

  /// The axis assignment of the latest *attempt*, **exactly as asked**.
  /// Recorded on failure too, so the page can see "these axes were tried" and
  /// not retry them in a loop — which is also why an unspecified device is
  /// not patched in here once the run answers it. That answer is [device].
  final ScenarioAxes axes;

  /// The device the run actually used — the folder profile's, where [axes]
  /// named none. What the page frames its pictures with, and what the device
  /// chip reports back.
  final String? device;

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

  /// The live listing per package — in flight, landed, and failed.
  final _listings = <String, Future<void>>{};
  final _listed = <String, List<ScenarioListing>>{};
  final _listingErrors = <String, Object>{};

  /// One warm runner per package, created by the first `run` and kept — a
  /// second run reuses the compiled harness and the live tester.
  final _runners = <String, ScenarioRunner>{};

  /// The panel's runs, one per scenario, keyed `(package, file, scenario)`.
  final _panelRuns = <(String, String, String), ScenarioPanelRun>{};

  /// The runner's last progress line per package — the only narration a cold
  /// start has, so the panel can say "compiling the harness" rather than
  /// spinning silently.
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

  /// The configured capture scale for [path] — output pixels per logical
  /// pixel on every run — or null for the measured default of 1. An explicit
  /// `capture-scale` on a run still wins; this is the project saying "always
  /// retina" once, in `tool/flutterware.dart`.
  double? captureScaleFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] == path) {
        if (config['captureScale'] case num scale) return scale.toDouble();
      }
    }
    return null;
  }

  /// The absolute root of [path]'s package — what the step page shortens a
  /// node's source paths against.
  String packageRootFor(String path) =>
      host.workspace.packageFor(path).directory.path;

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

  /// What the **live harness** says a package has: profiles, the devices and
  /// languages they offer, and each scenario's tags. None of it is visible to
  /// the syntactic scan — a profile is Dart in a `flutter_test_config.dart`,
  /// and tags are arguments the scanner never evaluates.
  ///
  /// Started on demand like everything else here, and by the one caller that
  /// is about to pay for a compiled harness anyway: opening a scenario runs
  /// it. Both calls queue on the runner's single turn, so listing first costs
  /// the ordering and nothing else.
  void trackListings(String path) {
    if (_listings.containsKey(path)) return;
    _listings[path] = _runnerFor(path)
        .list()
        .then<void>((listed) => _listed[path] = listed)
        .catchError((Object error) => _listingErrors[path] = error)
        .whenComplete(notifyChanged);
  }

  /// The live listing of [path], or null while nothing has asked or the ask
  /// has not landed. A failed listing reads as null too — the run that
  /// follows reports the same failure with the room to explain it.
  List<ScenarioListing>? listingsFor(String path) => _listed[path];

  /// The listing for one scenario, by the names the panel addresses it with.
  ScenarioListing? listingFor(
    String path, {
    required String file,
    required String scenario,
  }) => _listed[path]?.firstWhereOrNull(
    (l) => l.file == file && l.name == scenario,
  );

  /// The devices the profile governing [file] offers — the picker's pool, in
  /// the profile's own order, empty where the folder declares none.
  List<String> offeredDevicesFor(String path, String file) =>
      _listed[path]?.firstWhereOrNull((l) => l.file == file)?.devices ??
      const [];

  /// The languages to offer for [file]: the profile's, and the package's
  /// `tool/flutterware.dart` declaration where no profile speaks.
  List<String> offeredLanguagesFor(String path, String file) {
    var profiled = _listed[path]
        ?.firstWhereOrNull((l) => l.file == file)
        ?.languages;
    return (profiled == null || profiled.isEmpty)
        ? languagesFor(path)
        : profiled;
  }

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
      // Every step says what it is running as, so a request that named no
      // device frames its first picture correctly rather than snapping into a
      // phone when the run ends.
      var device = event['device'] as String? ?? state.axes.device;
      var step = _stepFrom(
        (event['step']! as Map).cast<String, dynamic>(),
        package,
        file: file,
        scenario: scenario,
        axes: state.axes.copyWith(device: device),
      );
      _panelRuns[key] = ScenarioPanelRun(
        running: true,
        axes: state.axes,
        device: device,
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
        unspecifiedDevice: defaultScenarioDeviceId,
        captureScale: captureScaleFor(package),
        captureRaw: true,
      );
      var described = _describeRun(package, outDir, report, axes: axes);
      var outcome = described.scenarios
          .where((s) => s.file == file && s.name == scenario)
          .firstOrNull;
      // The run says what it ran as, which the request may have left to the
      // folder's profile — and the page frames its pictures from this.
      var device = outcome?.device ?? axes.device;
      if (outcome == null) {
        _panelRuns[key] = ScenarioPanelRun(
          running: false,
          axes: axes,
          device: device,
          steps: _panelRuns[key]?.steps ?? const [],
          output: outDir,
          error:
              'The harness ran nothing named "$scenario" in $file — '
              'renamed since this page was opened?',
        );
        return;
      }
      _panelRuns[key] = ScenarioPanelRun(
        running: false,
        axes: axes,
        device: device,
        steps: outcome.steps,
        outcome: outcome,
        output: outDir,
      );
    } catch (error) {
      // The steps captured before the failure stay: the last one is the
      // frame just before it died — and its directory is recorded like any
      // other, or the next run would have nothing to supersede and both
      // would be stranded.
      _panelRuns[key] = ScenarioPanelRun(
        running: false,
        axes: axes,
        device: _panelRuns[key]?.device,
        steps: _panelRuns[key]?.steps ?? const [],
        output: outDir,
        error: '$error',
      );
    } finally {
      // The superseded run's artifacts, **whatever this attempt did**: a
      // failed attempt supersedes the previous one just as a successful one
      // does, and deleting only on success let a single failure strand two
      // directories. The images already on screen are decoded, so pulling the
      // files is safe — and keeping them would grow a directory per click.
      if (previous?.output case var old? when old != outDir) {
        try {
          Directory(old).deleteSync(recursive: true);
        } on FileSystemException {
          // Somebody looking at it, or already gone — either way not ours.
        }
      }
      notifyChanged();
      // The run compiled the suite as it is on disk, which is newer truth
      // than the list pane's scan — catch the pane up.
      _rescan(package);
      _relist(package);
    }
  }

  /// Replaces the cached listing after a run, so an edited
  /// `flutter_test_config.dart` or a re-tagged scenario shows up without a
  /// restart. Only for a package somebody already asked about.
  void _relist(String path) {
    if (!_listings.containsKey(path)) return;
    _listings[path] = _runnerFor(path)
        .list()
        .then<void>((listed) => _listed[path] = listed)
        .catchError((Object error) => _listingErrors[path] = error)
        .whenComplete(notifyChanged);
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
              'captured **at** the failure, whatever the capture policy.',
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
                  '`MediaQuery`. Omitted lets each scenario run as its own '
                  'folder says — the first device of the profile its '
                  '`flutter_test_config.dart` declares, or '
                  '$defaultScenarioDeviceId where a folder declares none. '
                  '`fit` means the bare 800×600 test surface. The same '
                  'vocabulary Previews frames with.',
              options: [
                for (var device in Devices.all)
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
              'devices',
              'Devices',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'A comma-separated matrix — `iphone-se,android-tall`. Runs '
                  'everything once per device, each into its own '
                  '`<output>/<device>-<language>/` directory with an '
                  '`index.json` beside them. The same plural vocabulary as '
                  '`flutter test --dart-define=fw.devices=`. Overrides '
                  '`device`.',
            ),
            const ActionParameter(
              'languages',
              'Languages',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'The other half of the matrix — `en,fr,de`. Crossed with '
                  '`devices`, and overrides `language`.',
            ),
            const ActionParameter(
              'tag',
              'Tag',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Run only scenarios carrying this tag — the same tag '
                  '`scenario(tags: [...])` declares and `flutter test --tags` '
                  'filters on',
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
                  'Screenshot pixels per logical pixel, up to 4. Omitted '
                  "means the package's configured captureScale "
                  "(tool/flutterware.dart), or 1. The device's own ratio "
                  'gives a true screenshot; 1 is ~10× faster and smaller, '
                  'which is what keeps a long FakeAsync run instantaneous. '
                  'Not an axis: it changes the artifact, never what the app '
                  'sees.',
            ),
            const ActionParameter(
              'clock',
              'Clock origin',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'An ISO-8601 timestamp `clock.now()` starts at — '
                  '`2026-01-01T09:00:00Z`. A scenario clock already '
                  'advances deterministically under FakeAsync, but it starts '
                  'at the wall time of the run, so any screen showing a date '
                  'differs run to run. Pinning it is what makes two runs '
                  'comparable. Reaches code that reads `package:clock`; a '
                  'direct `DateTime.now()` cannot be intercepted by anything.',
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
          'new',
          'New scenario',
          returns: ScenarioNewResult,
          description:
              'Writes a runnable scenario file where the package keeps them, '
              'and reports the command that runs it. The scaffold pumps a stub '
              'app and drives it, so it passes as written — replace the stub '
              'with your own widget. Start here when you have never written '
              'one: it is the API, in a file that already works.',
          parameters: [
            ActionParameter(
              'package',
              'Package',
              kind: ActionParameterKind.choice,
              required: false,
              description:
                  'Which declared package; the only one when there is one',
              options: [
                for (var path in packages)
                  ActionOption(path, label: path == '.' ? 'root' : path),
              ],
            ),
            const ActionParameter(
              'name',
              'Name',
              kind: ActionParameterKind.string,
              required: true,
              description:
                  "The scenario's name — what `run --scenario=` takes and what "
                  'the panel lists',
            ),
            const ActionParameter(
              'file',
              'File',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Package-relative path to write. Defaults to a snake_cased '
                  "`_test.dart` from the name, under the package's scenario "
                  'directory. Never overwrites.',
            ),
          ],
        ),
        PluginAction(
          'shots',
          'Store screenshots',
          returns: ScenarioShotsResult,
          description:
              'The store/documentation lane: runs the scenarios and keeps '
              'only their **named** shots, at the pixel ratio each device '
              'really has, '
              'into `<output>/<language>/<device>/NN-name.png`. Everything a '
              '`run` leaves behind — the automatic steps, the widget trees — '
              'is dropped. A separate action because every default differs; '
              '`run` stays the debugging lane.',
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
              'output',
              'Output directory',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Where the tree is written; '
                  '`build/flutterware/screenshots` '
                  'under the package when omitted. Emptied first, so what is '
                  'there afterwards is exactly this run.',
            ),
            const ActionParameter(
              'devices',
              'Devices',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'A comma-separated list — one directory per device. Omitted '
                  "runs each scenario on its folder profile's first device.",
            ),
            const ActionParameter(
              'languages',
              'Languages',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'A comma-separated list — one directory per language, '
                  'crossed with `devices`',
            ),
            const ActionParameter(
              'tag',
              'Shot tag',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Keep only shots carrying this tag — '
                  "`Shot('Home', tags: ['store'])`. Omitted keeps every named "
                  'shot, which is what a project that tags nothing wants.',
            ),
            const ActionParameter(
              'file',
              'File',
              kind: ActionParameterKind.string,
              required: false,
              description: 'Only this scenario file, package-relative',
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
      device: device as String?,
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
      'new' => _new(arguments),
      'shots' => _shots(arguments),
      'restart' => _restart(arguments),
      _ => super.invoke(actionId, arguments: arguments),
    };
  }

  /// Runs the scenarios and keeps only what a store listing or a manual can
  /// use: the named shots, at the device's own resolution, in a tree laid out
  /// by language and device.
  ///
  /// The run itself goes to a scratch directory under the output and is
  /// deleted afterwards — a store run should leave the images and nothing
  /// else, and copying out of a live run directory would leave both.
  Future<ScenarioShotsResult> _shots(Map<String, Object?> arguments) async {
    var paths = _requested(arguments);
    var file = arguments['file'] as String?;
    var tag = arguments['tag'] as String?;
    var devices = _axisList(arguments['devices'], 'devices');
    for (var id in devices) {
      if (!isDeviceId(id)) {
        throw ArgumentError.value(
          id,
          'devices',
          'no such device. Accepted: ${deviceIds.join(', ')}',
        );
      }
    }
    var languages = _axisList(arguments['languages'], 'languages');
    for (var locale in languages) {
      if (!_localePattern.hasMatch(locale)) {
        throw ArgumentError.value(
          locale,
          'languages',
          'not a locale tag — expected e.g. `fr` or `fr-CA`',
        );
      }
    }
    var assignments = <ScenarioAxes>[
      for (var device in devices.isEmpty ? [null] : devices)
        for (var language in languages.isEmpty ? [null] : languages)
          ScenarioAxes(device: device, language: language),
    ];

    var results = <ScenarioShotsPackage>[];
    var total = 0;
    for (var path in paths) {
      var packageRoot = host.workspace.packageFor(path).directory.path;
      var output =
          arguments['output'] as String? ??
          p.join(packageRoot, 'build', 'flutterware', 'screenshots');
      var root = Directory(output);
      // Emptied first: a store tree is a statement about the app as it is
      // now, and yesterday's screenshot of a screen that no longer exists
      // would ship beside today's.
      if (root.existsSync()) root.deleteSync(recursive: true);
      root.createSync(recursive: true);
      var scratch = p.join(output, '.runs');

      // Keyed by the directory the shot lands in — `<language>/<device>` —
      // which is worked out per *outcome*, because with no `devices` the
      // device comes from each scenario's own folder profile and a mixed
      // suite writes into more than one.
      var images = <String, List<String>>{};
      var failures = <String, int>{};
      var axesOf = <String, Map<String, String>>{};
      try {
        for (var assignment in assignments) {
          var report = await _runnerFor(path).run(
            outDir: p.join(scratch, axisSlug(assignment)),
            file: file,
            axes: assignment,
            unspecifiedDevice: defaultScenarioDeviceId,
            captureNative: true,
          );
          var described = _describeRun(
            path,
            p.join(scratch, axisSlug(assignment)),
            report,
            axes: assignment,
          );
          for (var outcome in described.scenarios) {
            var language = assignment.language ?? 'default';
            var device = outcome.device ?? fitDeviceId;
            var key = p.join(language, device);
            axesOf[key] = {'language': ?assignment.language, 'device': device};
            var into = Directory(p.join(output, key))
              ..createSync(recursive: true);
            var kept = images.putIfAbsent(key, () => []);
            if (!outcome.ok) {
              failures[key] = (failures[key] ?? 0) + 1;
            }
            for (var step in outcome.steps) {
              // Named shots only, and only the tag asked for: an automatic
              // capture is a debugging artefact, not a screenshot somebody
              // chose to show.
              if (step.name == null) continue;
              if (tag != null && !step.tags.contains(tag)) continue;
              var number = (kept.length + 1).toString().padLeft(2, '0');
              var name = '$number-${_shotSlug(step.name!)}.png';
              // `step.image` is relative to the worktree, which is what keeps
              // a result portable — the file itself is `imageFile`.
              step.imageFile.copySync(p.join(into.path, name));
              kept.add(name);
              total++;
            }
          }
        }
        results.add(
          ScenarioShotsPackage(
            path: path,
            output: output,
            sets: [
              for (var key in images.keys.toList()..sort())
                ScenarioShotSet(
                  directory: key,
                  axes: axesOf[key] ?? const {},
                  images: images[key]!,
                  failed: failures[key] ?? 0,
                ),
            ],
          ),
        );
      } catch (error) {
        results.add(
          ScenarioShotsPackage(path: path, output: output, error: '$error'),
        );
      } finally {
        if (Directory(scratch).existsSync()) {
          Directory(scratch).deleteSync(recursive: true);
        }
      }
    }
    return ScenarioShotsResult(packages: results, count: total);
  }

  /// `01-order-placed.png` from `Order placed` — a name that sorts, survives
  /// every filesystem, and still reads as what it shows.
  static String _shotSlug(String name) => name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// The package an action names, checked against the manifest.
  ///
  /// The message names what *is* declared, so a caller that guessed can
  /// correct itself without a second round-trip — the same courtesy
  /// `Session.invoke` extends for a plugin id.
  List<String> _requested(Map<String, Object?> arguments) {
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

  /// Writes a scenario file and says how to run it.
  ///
  /// The authoring door. Everything else here operates scenarios that already
  /// exist, which left "how do I write one" answerable only by reading
  /// flutterware's source — a question the GUI answered in an empty state that
  /// no other surface could see.
  Future<ScenarioNewResult> _new(Map<String, Object?> arguments) async {
    var paths = _requested(arguments);
    if (paths.length > 1) {
      throw ArgumentError(
        'Which package? `new` writes one file. Declared: ${packages.join(', ')}',
      );
    }
    var path = paths.single;

    var name = arguments['name'];
    if (name is! String || name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'required — the scenario name');
    }
    name = name.trim();

    var file = arguments['file'];
    if (file != null && file is! String) {
      throw ArgumentError.value(
        file,
        'file',
        'must be a package-relative path',
      );
    }
    var relative =
        (file as String?) ?? '${directoryFor(path)}/${scenarioFileName(name)}';
    if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
      throw ArgumentError.value(
        relative,
        'file',
        'must be relative to the package and stay inside it',
      );
    }
    if (!relative.endsWith('.dart')) {
      throw ArgumentError.value(relative, 'file', 'must end in `.dart`');
    }
    // `flutter test` collects `*_test.dart` and nothing else, so a scenario
    // spelled otherwise runs here and silently never runs in CI.
    if (!relative.endsWith('_test.dart')) {
      throw ArgumentError.value(
        relative,
        'file',
        'must end in `_test.dart` — `flutter test` collects nothing else, and '
            'a scenario CI never runs is worse than one that does not exist',
      );
    }

    var target = File(p.join(packageRootFor(path), relative));
    if (target.existsSync()) {
      throw ArgumentError.value(
        relative,
        'file',
        'already exists. Add the scenario to it, or name another file.',
      );
    }
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(scenarioScaffold(name));

    // The scan is now stale by exactly this file.
    _rescan(path);

    return ScenarioNewResult(
      package: path,
      file: relative,
      name: name,
      next:
          'fw run scenarios run --package=$path --file=$relative '
          '--scenario="$name"',
    );
  }

  Future<ScenarioRestartResult> _restart(Map<String, Object?> arguments) async {
    var paths = _requested(arguments);
    for (var path in paths) {
      restartRunner(path);
    }
    return ScenarioRestartResult(restarted: paths);
  }

  /// The scenarios of one package, or of every declared package.
  ///
  /// **Loads what it needs** — a report may never start work; an action asked
  /// for by name may, and must.
  Future<ScenarioListResult> _list(Map<String, Object?> arguments) async {
    var paths = _requested(arguments);
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
              // Only when there are none: an empty list is the one moment the
              // reader is certainly asking "so how do I write one".
              authoring: _results[path]!.scenarios.isEmpty
                  ? scenarioAuthoringHint(directoryFor(path))
                  : null,
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
    var paths = _requested(arguments);
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
    var rawTag = arguments['tag'];
    if (rawTag != null && rawTag is! String) {
      throw ArgumentError.value(rawTag, 'tag', 'must be a tag name');
    }
    var tag = rawTag as String?;
    // The matrix, as CI writes it — the same plural vocabulary
    // `--dart-define=fw.devices=` uses in the bare `flutter test` lane, so a
    // project learns one and gets both.
    var devices = _axisList(arguments['devices'], 'devices');
    for (var id in devices) {
      if (!isDeviceId(id)) {
        throw ArgumentError.value(
          id,
          'devices',
          'no such device. Accepted: ${deviceIds.join(', ')}',
        );
      }
    }
    var languages = _axisList(arguments['languages'], 'languages');
    for (var tag in languages) {
      if (!_localePattern.hasMatch(tag)) {
        throw ArgumentError.value(
          tag,
          'languages',
          'not a locale tag — expected e.g. `fr` or `fr-CA`',
        );
      }
    }
    // One point when nothing fanned out, which is every panel run and every
    // `fw run scenarios run` that names at most one of each.
    var assignments = <ScenarioAxes>[
      for (var device in devices.isEmpty ? [axes.device] : devices)
        for (var language in languages.isEmpty ? [axes.language] : languages)
          ScenarioAxes(
            device: device,
            language: language,
            textScale: axes.textScale,
            brightness: axes.brightness,
            boldText: axes.boldText,
            highContrast: axes.highContrast,
            invertColors: axes.invertColors,
          ),
    ];
    var fannedOut = assignments.length > 1;
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
    DateTime? clock;
    if (arguments['clock'] case var raw?) {
      clock = raw is String ? DateTime.tryParse(raw) : null;
      if (clock == null) {
        throw ArgumentError.value(
          raw,
          'clock',
          'not an ISO-8601 timestamp — expected e.g. `2026-01-01T09:00:00Z`',
        );
      }
    }

    var results = <ScenarioRunPackage>[];
    for (var path in paths) {
      var packageRoot = host.workspace.packageFor(path).directory.path;
      var base =
          output ??
          p.join(
            packageRoot,
            'build',
            'flutterware',
            'scenario_runs',
            '${DateTime.now().millisecondsSinceEpoch}',
          );
      for (var assignment in assignments) {
        // One directory per point of the matrix. Without it the second
        // assignment overwrites the first — same file, same scenario, same
        // step names — and only the last language survives on disk.
        var outDir = fannedOut ? p.join(base, axisSlug(assignment)) : base;
        try {
          var report = await _runnerFor(path).run(
            outDir: outDir,
            file: file,
            scenario: scenario,
            tag: tag,
            axes: assignment,
            unspecifiedDevice: defaultScenarioDeviceId,
            captureScale: captureScale ?? captureScaleFor(path),
            captureRaw: format == 'raw',
            clock: clock,
          );
          var described = _describeRun(
            path,
            outDir,
            report,
            axes: assignment,
            recordAxes: fannedOut,
          );
          // A selector that matched nothing used to come back as an empty list
          // and exit 0 — a typo reading as a green run. The harness compiled
          // from disk just now, so a fresh scan is the honest list to offer
          // back.
          if (described.scenarios.isEmpty &&
              (file != null || scenario != null || tag != null)) {
            results.add(
              ScenarioRunPackage(
                path: path,
                output: outDir,
                axes: fannedOut ? assignment.toParams() : null,
                error: await _selectorMiss(
                  path,
                  file: file,
                  scenario: scenario,
                  tag: tag,
                ),
              ),
            );
          } else {
            results.add(described);
          }
        } catch (error) {
          results.add(
            ScenarioRunPackage(
              path: path,
              output: outDir,
              axes: fannedOut ? assignment.toParams() : null,
              error: '$error',
            ),
          );
        }
      }
      if (fannedOut) _writeIndex(base, results.where((r) => r.path == path));
    }
    return ScenarioRunResult(
      packages: results,
      axes: fannedOut || axes.isEmpty ? null : axes.toParams(),
    );
  }

  /// Why a `file`/`scenario` selector ran nothing, naming what it could have
  /// named instead — so a misspelling costs one round-trip and not a debugging
  /// session against a result that looked like a pass.
  Future<String> _selectorMiss(
    String path, {
    required String? file,
    required String? scenario,
    String? tag,
  }) async {
    _rescan(path);
    await _scans[path];
    var result = _results[path];
    if (result == null) {
      return 'Nothing matched ${_describeSelector(file, scenario, tag)}, and the '
          'scan that would say what does failed: ${_errors[path]}';
    }
    if (result.scenarios.isEmpty) {
      return 'Nothing matched ${_describeSelector(file, scenario, tag)} — this '
          'package has no scenarios at all.\n\n'
          '${scenarioAuthoringHint(directoryFor(path))}';
    }
    // A tag-only miss: the scan cannot say which tags exist — it never
    // evaluates an argument — so this says what a tag is rather than guessing
    // at a list it does not have.
    if (file == null && tag != null) {
      return 'Nothing carries the tag "$tag". A scenario declares its tags as '
          "`scenario('…', tags: ['$tag'], (s) async { … })`.";
    }
    var inFile = result.scenarios.where((ref) => ref.file == file).toList();
    if (scenario != null && inFile.isNotEmpty) {
      return 'No scenario "$scenario" in $file. It declares: '
          '${inFile.map((ref) => '"${ref.name}"').join(', ')}.';
    }
    var files = {for (var ref in result.scenarios) ref.file};
    return 'No scenarios in "$file". This package declares them in: '
        '${files.join(', ')}.';
  }

  static String _describeSelector(String? file, String? scenario, String? tag) {
    var selector = switch ((file, scenario)) {
      (null, _) => null,
      (var f, null) => 'file "$f"',
      (var f, var s) => 'scenario "$s" in "$f"',
    };
    // A tag is a selector like any other, and a `--tag` nobody declared is
    // exactly as silent as a misspelled file was.
    return [?selector, if (tag != null) 'tag "$tag"'].join(' with ');
  }

  /// A comma-separated axis list, trimmed and emptied of blanks.
  static List<String> _axisList(Object? raw, String name) {
    if (raw == null) return const [];
    if (raw is List) return [for (var item in raw) '$item'.trim()];
    if (raw is! String) {
      throw ArgumentError.value(raw, name, 'a comma-separated list');
    }
    return [
      for (var part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  static final _localePattern = RegExp(
    r'^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})?$',
  );

  /// The map from assignment to directory, written beside them.
  ///
  /// A matrix's artifacts are a tree a CI job has to *find* things in; the
  /// result of the call says the same thing, but the call is gone by the time
  /// the upload step runs. Paths are relative to the index, which is what
  /// makes the whole directory movable.
  void _writeIndex(String base, Iterable<ScenarioRunPackage> runs) {
    var index = {
      'runs': [
        for (var run in runs)
          {
            'package': run.path,
            'axes': ?run.axes,
            'output': p.relative(run.output, from: base),
            'ok': run.error == null && run.scenarios.every((s) => s.ok),
            'scenarios': run.scenarios.length,
            'failed': run.scenarios.where((s) => !s.ok).length,
            'error': ?run.error,
          },
      ],
    };
    Directory(base).createSync(recursive: true);
    File(
      p.join(base, 'index.json'),
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(index));
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

  /// An artifact path as every surface reports it: relative to the worktree,
  /// so it survives being read on another machine and an agent whose tools are
  /// scoped to the repo can open it. A `--output` outside the worktree has no
  /// relative spelling, and keeps its absolute one.
  String _relative(String path) {
    var root = host.worktree.path;
    return p.isWithin(root, path) ? p.relative(path, from: root) : path;
  }

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
      parent: step['parent'] as int?,
      branch: step['branch'] as String?,
      name: step['name'] as String?,
      auto: step['auto'] == true,
      tags: (step['tags'] as List?)?.cast<String>() ?? const [],
      root: host.worktree.path,
      image: _relative(step['image']! as String),
      format: step['format'] as String? ?? 'png',
      width: step['width'] as int? ?? 0,
      height: step['height'] as int? ?? 0,
      tree: _relative(step['tree']! as String),
      texts: (step['texts']! as List).cast<String>(),
      statusBrightness: step['statusBrightness'] as String?,
      navBrightness: step['navBrightness'] as String?,
      // Absent means settled: the harness writes the field only when it is
      // not, so a healthy step's record stays the size it was.
      settled: step['settled'] as bool? ?? true,
      strayFrames: step['strayFrames'] as int? ?? 0,
      failure: step['failure'] as String?,
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
    bool recordAxes = false,
  }) {
    return ScenarioRunPackage(
      path: path,
      output: outDir,
      axes: recordAxes ? axes.toParams() : null,
      ms: report['ms'] as int? ?? 0,
      scenarios: [
        for (var outcome
            in (report['scenarios']! as List).cast<Map<String, dynamic>>())
          ScenarioRunOutcome(
            file: outcome['file']! as String,
            name: outcome['name']! as String,
            ok: outcome['ok'] == true,
            device: outcome['device'] as String?,
            ms: outcome['ms'] as int? ?? 0,
            steps: [
              for (var step
                  in (outcome['steps']! as List).cast<Map<String, dynamic>>())
                _stepFrom(
                  step,
                  path,
                  file: outcome['file']! as String,
                  scenario: outcome['name']! as String,
                  // The address on an artifact says what produced it, so an
                  // unspecified device is filled in with what the folder
                  // resolved it to — a link that reopens the same picture.
                  axes: axes.copyWith(device: outcome['device'] as String?),
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../inspect/lens.dart';
import '../../inspect/screen_read.dart';
import '../../previews/devices.dart' show orientationParameterDoc;
import '../../scenarios/authoring.dart';
import '../../scenarios/axes.dart';
import '../../scenarios/discovery.dart';
import '../../scenarios/runner.dart';
import '../../scenarios/web_export.dart';
import '../../scenarios/web_report.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'scenarios_address.dart';
import 'scenarios_results.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const scenariosPluginId = 'flutterware.scenarios';

/// The action that writes a run out as a page, named once so the CLI, the
/// dialog and the command the dialog echoes cannot drift apart.
const webExportActionId = 'export';

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

  /// The live listing per package — in flight and landed.
  final _listings = <String, Future<void>>{};
  final _listed = <String, List<ScenarioListing>>{};

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

  /// Where discovery looks for [path]'s scenarios: the declared directory, or
  /// all of `test/` — a scenario is an ordinary widget test and may sit next
  /// to the rest of them.
  String scanRootFor(String path) =>
      _configuredDirectoryFor(path) ?? defaultScenariosScanRoot;

  /// Where a new scenario file goes for [path]: the declared directory, or
  /// the `test/scenarios` convention. Narrower than [scanRootFor] on purpose —
  /// "where do we look" widened to `test/`, but "where should the next file
  /// go" still deserves a conventional answer.
  String newScenarioDirectoryFor(String path) =>
      _configuredDirectoryFor(path) ?? defaultScenariosDirectory;

  String? _configuredDirectoryFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] == path) {
        if (config['directory'] case String directory) return directory;
      }
    }
    return null;
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
      directory: scanRootFor(path),
    );
    // Parsing runs off-isolate, as the catalog's scan does.
    _scans[path] = Isolate.run(scanner.scan)
        .then<void>((result) {
          _results[path] = result;
          // A scan that lands clears the failure it recovers from — a save
          // caught mid-write fails one rescan, and that error may not outlive
          // the next scan that read the finished file.
          _errors.remove(path);
        })
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
        // Swallowed by design: a failed listing reads as null, and the run
        // that follows reports the same failure with the room to explain it.
        .catchError((Object _) {})
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

  /// Whether panel runs record the motion of every transition.
  ///
  /// On, because a recording you have to ask for is a recording nobody
  /// discovers: the whole feature is hovering an arrow and watching what
  /// happened. It costs the panel about 70ms a transition — measured, at the
  /// 30fps half-scale settings below — and the switch is here for the run
  /// where that is 70ms too many.
  ///
  /// Panel-only, deliberately. `fw run scenarios` and the MCP surface never
  /// record: nothing on the other end of those can watch a movie, and the
  /// frames would be artifacts nobody opens.
  var recordMotion = true;

  void setRecordMotion(bool value) {
    if (recordMotion == value) return;
    recordMotion = value;
    notifyChanged();
  }

  /// 30fps, at the same scale as the step's own screenshot.
  ///
  /// 30fps is the measured knee — a transition costs ~35ms of pumping here
  /// against ~150ms at 60fps, and no eye reading a page push on a flow canvas
  /// can tell the two apart. The *scale* is not a knob for the same reason:
  /// half scale was tried, and playback that blurs and then snaps sharp when
  /// it stops is worse than the work it saves. What that costs is memory —
  /// 1.29MB a frame decoded, on a phone — and that is bounded by
  /// `ScenarioMotionResidency` rather than by recording something smaller.
  ///
  /// See `docs/superpowers/specs/2026-08-11-scenario-motion-capture-findings.md`.
  static const panelMotionInterval = Duration(milliseconds: 33);
  static const panelMotionMaxFrames = 90;

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
        (event['step']! as Map).cast<String, Object?>(),
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
        recordInterval: recordMotion ? panelMotionInterval : null,
        recordMaxFrames: panelMotionMaxFrames,
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
        // Swallowed by design: a failed listing reads as null, and the run
        // that follows reports the same failure with the room to explain it.
        .catchError((Object _) {})
        .whenComplete(notifyChanged);
  }

  /// Re-reads the suite from disk — what [track] deliberately never does.
  ///
  /// The panel's watcher calls this on a save, which is why it is the *scan*
  /// alone: parsing `test/` is ~30ms on a spawned isolate, and a listing is a
  /// compiled harness. A file arriving must cost the first and never the
  /// second.
  void rescan(String path) => _rescan(path);

  /// [rescan], and the live listing with it — profiles, offered devices and
  /// languages, tags — for the one caller that is a person asking: the list
  /// pane's refresh button.
  ///
  /// A relisting is only queued for a package that has already got one, which
  /// is [_relist]'s rule and the reason this is safe to press: nobody pays for
  /// a harness compile by pressing refresh on a suite they have not opened.
  void refresh(String path) {
    _rescan(path);
    _relist(path);
  }

  /// Replaces the cached scan — what [track] deliberately never does.
  void _rescan(String path) {
    var scanner = ScenarioScanner(
      packageRoot: host.workspace.packageFor(path).directory.path,
      directory: scanRootFor(path),
    );
    _scans[path] = Isolate.run(scanner.scan)
        .then<void>((result) {
          _results[path] = result;
          // Same recovery rule as [track]: the watcher rescans on every
          // save, and the one that read a half-written file must not brand
          // the suite "scan failed" after the next one read it whole.
          _errors.remove(path);
        })
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
              'captured **at** the failure, whatever the capture policy. The '
              'answer summarises the steps (see `steps=`); `run.json` in the '
              'output directory always carries every one.',
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
                  'Where step artifacts are written, worktree-relative '
                  "unless absolute; a fresh directory under the package's "
                  'build/ when omitted. run.json lands in the same '
                  'directory as the images it names.',
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
            ActionParameter(
              'orientation',
              'Orientation',
              kind: ActionParameterKind.choice,
              required: false,
              description:
                  '$orientationParameterDoc Applies to whatever device the run '
                  "ends up as, including one a folder's profile chose rather "
                  'than this call.',
              options: [for (var id in orientationIds) ActionOption(id)],
            ),
            const ActionParameter(
              'language',
              'Language',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'A locale tag — `fr`, `fr-CA` — applied as the platform '
                  "locale and as the scenario's own assignment "
                  '(`s.assignment?.language`), the same pair `FW_LANGUAGES` '
                  'sets under `flutter test`',
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
              'orientations',
              'Orientations',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'The third axis — `portrait,landscape`. Crossed with the '
                  'other two, and overrides `orientation`. A device that '
                  'cannot turn contributes one point rather than two '
                  'identical ones, so mixing a desktop into the devices does '
                  'not double the run.',
            ),
            const ActionParameter(
              'matrix',
              'Matrix',
              kind: ActionParameterKind.choice,
              required: false,
              description:
                  '`declared` runs every point the folder profiles declare — '
                  'the union of their devices, languages and orientations, '
                  'crossed exactly as explicit lists are. What CI wants '
                  'instead of restating the declaration in `devices=` and '
                  'watching the two drift. Instead of the axis lists, not '
                  'beside them.',
              options: [ActionOption('declared')],
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
              'steps',
              'Steps',
              kind: ActionParameterKind.choice,
              required: false,
              defaultValue: 'failing',
              description:
                  'How many steps ride back in the answer. Every run writes '
                  'all of them to `run.json` in its output directory either '
                  'way and each package names that file — a script reads it '
                  'back typed with `package:flutterware/scenarios_report.dart` '
                  '— so this is about what '
                  'arrives without asking: `failing` (default) is the frame '
                  'each red scenario died on, `all` is every step of every '
                  'scenario — a matrix suite is hundreds — and `none` is the '
                  'summary alone. Every scenario reports its `stepCount` '
                  'whatever this says.',
              options: [
                ActionOption('failing'),
                ActionOption('all'),
                ActionOption('none'),
              ],
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
          'read',
          'Read a captured step',
          returns: ScenarioReadResult,
          description:
              'Asks a step a run already captured what is on it. Every run '
              'writes four legs per step — the picture, the widget tree, the '
              'semantics and the texts — and until now handed back paths and '
              'nothing that could read them. With no flags this answers the '
              'question worth asking first: **what is on this screen**, as a '
              'nested list of the things that carry words or respond to '
              'touch, with their boxes and their state. Everything heavier is '
              'one flag on the same capture: `find` for where something is, '
              '`at` for what is under a point, `styles` for the type ramp, '
              '`tree` for all of it. The same grammar `run act` answers with '
              'on a live app — a `find` here and a `find` there differ in '
              'which file was opened and in nothing you have to learn twice.',
          parameters: [
            ActionParameter(
              'package',
              'Package',
              kind: ActionParameterKind.choice,
              required: false,
              description:
                  'Which declared package the run belongs to; the only one '
                  'when there is one',
              options: [
                for (var path in packages)
                  ActionOption(path, label: path == '.' ? 'root' : path),
              ],
            ),
            const ActionParameter(
              'step',
              'Step',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Which capture. Any leg of it as `run` reported it — the '
                  '`tree` path, the `image` path, either works — or a plain '
                  'index into the run. Omitted takes the failing step when '
                  'exactly one scenario went red, which is the read that '
                  'happens most. Naming a directory instead lists what is in '
                  'it, so browsing costs a refusal rather than a guess.',
            ),
            const ActionParameter(
              'output',
              'Run directory',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'The run to read, when `step` is an index or omitted. The '
                  'newest completed run under the package when omitted — the '
                  'one you just did, never a panel session, which writes '
                  'captures but no run.json to count into.',
            ),
            ActionParameter(
              'lens',
              'Lens',
              kind: ActionParameterKind.choice,
              required: false,
              defaultValue: 'act',
              description:
                  'How much to hand back, as one word. `act` is the screen '
                  'alone; `look` adds the archived picture; `design` adds '
                  'every distinct text style; `raw` adds the whole tree and '
                  'costs about 20,000 tokens. The same four words `run` uses. '
                  'A flag you set explicitly always beats the lens.',
              options: [
                for (var lens in ObserveLens.values) ActionOption(lens.name),
              ],
            ),
            const ActionParameter(
              'screen',
              'Screen',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'true',
              description:
                  'The nested list of what is on the step — the default '
                  'answer. `false` when you only want a query.',
            ),
            const ActionParameter(
              'find',
              'Find',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Report only the nodes matching this, case-insensitively '
                  "against each node's type, its description and the words it "
                  'puts on screen. What to reach for instead of `tree` when '
                  'the question is "is the error message in there".',
            ),
            const ActionParameter(
              'at',
              'At a point',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'The chain of widgets under this point as `x,y`, innermost '
                  'last — in the same logical pixels every box in this reply '
                  'is in, so a point read off the screen lands here without a '
                  'transform.',
            ),
            const ActionParameter(
              'styles',
              'Text styles',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'false',
              description:
                  'Every distinct text size, weight and colour on the step, '
                  'most-used first with a sample of each. ~185 tokens, and it '
                  'settles most typography arguments — two greys that should '
                  'be one, a ramp with both 11.5 and 12.5 in it.',
            ),
            const ActionParameter(
              'texts',
              'Texts',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'false',
              description:
                  'The flat list of every string the step showed, as the '
                  'capture recorded it. The screen carries the same words '
                  'attached to what owns them; this is for grepping.',
            ),
            const ActionParameter(
              'tree',
              'Widget tree',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'false',
              description:
                  'The whole widget tree. **~20,000 tokens** on a real '
                  'screen — an order of magnitude past everything else here, '
                  'and `find`, `at` and `styles` answer most of what anyone '
                  'reads a tree for. Narrow it with `treeRoot` and '
                  '`treeDepth`.',
            ),
            const ActionParameter(
              'treeRoot',
              'Tree root',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Narrow `tree` to this node id and below. Ids come from '
                  'tree shape, so one a `find` gave still names this node.',
            ),
            const ActionParameter(
              'treeDepth',
              'Tree depth',
              kind: ActionParameterKind.integer,
              required: false,
              description: 'Stop `tree` this many levels below its root',
            ),
            const ActionParameter(
              'treeNoise',
              'Keep wrappers',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'true',
              description:
                  'Drop the framework wrappers nobody wrote — `Padding`, '
                  '`Semantics`, the twenty nodes under every '
                  '`MaterialApp`. On by default; `false` keeps them.',
            ),
            const ActionParameter(
              'screenshot',
              'Picture',
              kind: ActionParameterKind.boolean,
              required: false,
              defaultValue: 'false',
              description:
                  'Hand back the archived PNG as a picture rather than as a '
                  'path. Off by default because the screen answers most '
                  'questions for a fifth of the tokens; `lens: look` is the '
                  'short way to say yes.',
            ),
          ],
        ),
        PluginAction(
          webExportActionId,
          'Export a web page',
          returns: ScenarioWebExportResult,
          description:
              'Runs the scenarios and writes the result as a browsable page: '
              'the same flow canvas, step pages and inspect dock the GUI '
              'draws, over the run it just did. Takes every selector and axis '
              '`run` takes — the page shows what was run, so what to run is '
              'the question it asks. Needs serving over HTTP; the result says '
              'how. For a CI artifact, a review link, or anyone who has the '
              'app but not the checkout.',
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
                  'Export only this scenario file, package-relative — as '
                  '`list` reports it',
            ),
            const ActionParameter(
              'scenario',
              'Scenario',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Export only this scenario, by name. Needs `file` too.',
            ),
            const ActionParameter(
              'tag',
              'Tag',
              kind: ActionParameterKind.string,
              required: false,
              description: 'Export only scenarios carrying this tag',
            ),
            const ActionParameter(
              'output',
              'Output directory',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Where the page goes, worktree-relative unless absolute; '
                  'defaults to `${ScenarioWebExporter.defaultOutput}` under '
                  'the package. Emptied before writing.',
            ),
            const ActionParameter(
              'base-href',
              'Base href',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'What the page is mounted under when it is not the root — '
                  '`/scenarios/`. Leading and trailing slash.',
            ),
            const ActionParameter(
              'offline',
              'Self-contained',
              kind: ActionParameterKind.choice,
              required: false,
              description:
                  'Bundle CanvasKit into the page instead of fetching it '
                  "from Google's CDN. Bigger, and the only form that works "
                  'behind a firewall or after the engine revision stops being '
                  'hosted.',
              options: [ActionOption('true'), ActionOption('false')],
            ),
            // The axes, exactly as `run` declares them: a page is a picture of
            // a run, and a picture is under-specified without them.
            ActionParameter(
              'device',
              'Device',
              kind: ActionParameterKind.choice,
              required: false,
              description: 'Run as a device before capturing the page',
              options: [for (var id in deviceIds) ActionOption(id)],
            ),
            ActionParameter(
              'orientation',
              'Orientation',
              kind: ActionParameterKind.choice,
              required: false,
              description: 'Which way up that device is, before capturing',
              options: [for (var id in orientationIds) ActionOption(id)],
            ),
            const ActionParameter(
              'language',
              'Language',
              kind: ActionParameterKind.string,
              required: false,
              description: 'A locale tag — `fr`, `fr-CA`',
            ),
            const ActionParameter(
              'devices',
              'Devices',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'A matrix — `iphone-se,ipad`. Every point lands on the same '
                  'page, each scenario labelled with what it ran as.',
            ),
            const ActionParameter(
              'languages',
              'Languages',
              kind: ActionParameterKind.string,
              required: false,
              description: 'The other half of the matrix — `en,fr,de`',
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
              'capture-scale',
              'Capture scale',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'Screenshot pixels per logical pixel, up to 4. A page is '
                  'read on a retina screen, so 2 is worth the bytes where 1 is '
                  'right for a panel.',
            ),
            const ActionParameter(
              'clock',
              'Clock origin',
              kind: ActionParameterKind.string,
              required: false,
              description:
                  'An ISO-8601 timestamp `clock.now()` starts at. Pin it and '
                  'two exported pages of the same suite are comparable.',
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
                  'Where the tree is written, worktree-relative unless '
                  'absolute; `build/flutterware/screenshots` under the '
                  'package when omitted. Emptied first, so what is there '
                  'afterwards is exactly this run.',
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
    var orientation = arguments['orientation'];
    if (orientation != null &&
        (orientation is! String || !isOrientationId(orientation))) {
      throw ArgumentError.value(
        orientation,
        'orientation',
        'no such orientation. Accepted: ${orientationIds.join(', ')}',
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
      orientation: orientation as String?,
      language: language as String?,
      textScale: textScale,
      brightness: brightness as String?,
      boldText: flag('bold-text'),
      highContrast: flag('high-contrast'),
      invertColors: flag('invert-colors'),
    );
  }

  /// What a run of this core is doing, while one runs — read by the sidebar and
  /// forwarded by MCP as progress. A matrix is one process per point and each
  /// takes seconds, so the point being run is the news.
  final _busy = <String, Status>{};

  void _setBusy(String path, Status? status) {
    if (status == null) {
      _busy.remove(path);
    } else {
      _busy[path] = status;
    }
    notifyChanged();
  }

  Status _status() {
    if (packages.isEmpty) return Status.none;
    if (_errors.isNotEmpty) return const Status.error('scan failed');
    for (var path in packages) {
      if (_busy[path] case var busy?) return busy;
    }
    var scanning = _scans.keys.where((p) => !_results.containsKey(p)).length;
    return scanning == 0 ? Status.none : const Status.info('scanning…');
  }

  Status _packageStatus(String path) {
    if (_busy[path] case var busy?) return busy;
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
      webExportActionId => _exportWeb(arguments),
      'new' => _new(arguments),
      'shots' => _shots(arguments),
      'read' => _read(arguments),
      'restart' => _restart(arguments),
      _ => super.invoke(actionId, arguments: arguments),
    };
  }

  /// One archived step, answered.
  ///
  /// **The reader half of the archive.** A run has written four legs per step
  /// for two milestones and handed back paths; an agent debugging a red
  /// scenario got one inlined frame and a pile of file names. This opens the
  /// tree beside the picture and answers the same questions the live surfaces
  /// answer, in the same shape — `Screen.of` is a pure function of an
  /// `InspectTree`, and a step's tree is one on disk.
  ///
  /// Nothing is re-run. A capture is a settled moment that already happened,
  /// which is the one thing this surface has that the live ones do not: the
  /// answer cannot drift between the question and the reply.
  Future<ScenarioReadResult> _read(Map<String, Object?> arguments) async {
    var lens = _lensFrom(arguments);
    var picked = _pickStep(arguments);

    var treeFile = File('${picked.base}.tree.json');
    if (!treeFile.existsSync()) {
      throw ArgumentError.value(
        _relative(picked.base),
        'step',
        'that capture has a picture but no widget tree beside it — a `raw` '
            'run or a `shots` run keeps only pixels. Re-run it with `run` to '
            'get a step this can read.',
      );
    }
    InspectTree tree;
    try {
      tree = InspectTree.fromJson(
        (jsonDecode(treeFile.readAsStringSync()) as Map)
            .cast<String, Object?>(),
      );
    } on FormatException catch (e) {
      throw ArgumentError.value(
        _relative(picked.base),
        'step',
        'its widget tree is not readable JSON ($e). Re-run the scenario.',
      );
    }

    var wantsShot = ScreenRead.boolArgument(
      arguments['screenshot'] ?? lens.picture,
    );
    var read = ScreenRead.of(
      tree,
      arguments,
      wantsTree: ScreenRead.boolArgument(arguments['tree'] ?? lens.tree),
      wantsStyles: ScreenRead.boolArgument(arguments['styles'] ?? lens.styles),
      worktree: host.worktree.path,
    );

    var image = picked.image;
    var showable =
        wantsShot &&
        image != null &&
        p.extension(image) == '.png' &&
        File(p.join(host.worktree.path, image)).existsSync();

    return ScenarioReadResult(
      step: _relative('${picked.base}.tree.json'),
      lens: lens.name,
      scenario: picked.scenario,
      file: picked.file,
      index: picked.index,
      failure: picked.failure,
      image: image,
      screen: read.screen,
      texts: ScreenRead.boolArgument(arguments['texts'])
          ? _textsOf(picked.base)
          : null,
      tree: read.tree,
      nodes: read.nodes,
      find: read.find,
      at: read.at,
      styles: read.styles,
      note: read.note,
      next: ScreenRead.offer,
      steps: picked.siblings,
      picture: showable
          ? Artifact(
              kind: Artifact.png,
              address: Address(
                worktree: host.worktree.name,
                plugin: host.id,
                segments: ['read', p.basename(picked.base)],
              ),
              path: image,
            )
          : null,
    );
  }

  /// The lens named for this call, or `act`.
  ///
  /// Per call and not pinnable, unlike the run plugin's. A pin pays for itself
  /// in a loop against one long-lived subject; a scenario read names its
  /// capture afresh every time, so a pin here would be hidden state with no
  /// loop to amortise it.
  static ObserveLens _lensFrom(Map<String, Object?> arguments) {
    var name = arguments['lens'] as String?;
    if (name == null || name.isEmpty) return ObserveLens.act;
    return ObserveLens.byName(name) ??
        (throw ArgumentError.value(name, 'lens', ObserveLens.unknown(name)));
  }

  /// The capture's texts leg, as the harness recorded it.
  ///
  /// Read off the report rather than off a `.texts.json`, because a scenario
  /// step keeps its texts in `run.json` where every other surface writes a
  /// fourth file.
  List<String>? _textsOf(String base) => _stepRecordFor(base)?.$2.texts;

  /// The legs a capture is written as, longest first so `.tree.json` is not
  /// read as a `.json`.
  static const _captureLegs = [
    '.semantics.json',
    '.capture.json',
    '.events.json',
    '.tree.json',
    '.png',
    '.raw',
  ];

  static String? _baseOf(String path) {
    for (var leg in _captureLegs) {
      if (path.endsWith(leg)) {
        return path.substring(0, path.length - leg.length);
      }
    }
    return null;
  }

  String _absolute(String path) =>
      p.isAbsolute(path) ? path : p.join(host.worktree.path, path);

  /// Which capture the call meant.
  ///
  /// **One parameter with a browse ladder, not four selectors.** A path names
  /// a capture; a directory refuses with what is in it; an index counts into
  /// a run; nothing at all takes the failing step, which is the read that
  /// happens most. Every refusal lists the values that would have worked,
  /// which is what makes browsing cost a call rather than a guess.
  _PickedStep _pickStep(Map<String, Object?> arguments) {
    var raw = arguments['step']?.toString().trim();
    if (raw != null && raw.isNotEmpty && int.tryParse(raw) == null) {
      var path = _absolute(raw);
      if (_baseOf(path) case var base?) return _describe(base);
      var directory = Directory(path);
      if (directory.existsSync()) {
        throw ArgumentError.value(raw, 'step', _listing(directory));
      }
      throw ArgumentError.value(
        raw,
        'step',
        'no such file. Give a step as `run` reported it — its `tree` or its '
            '`image` path — or an index into the run, or nothing at all for '
            'the step a scenario failed on.',
      );
    }

    var runDir = _runDirectory(arguments);
    var report = _reportIn(runDir);
    var index = raw == null || raw.isEmpty ? null : int.parse(raw);

    if (report == null) {
      throw ArgumentError.value(
        _relative(runDir),
        'output',
        'no $scenarioRunReportFile in that directory, so there is no run to '
            'count steps into. Name a capture directly with `step`.',
      );
    }

    var outcomes = [
      for (var package in report.packages)
        for (var outcome in package.scenarios) outcome,
    ];
    if (index != null) {
      var hits = [
        for (var outcome in outcomes)
          for (var step in outcome.steps)
            if (step.index == index) (outcome, step),
      ];
      if (hits.length == 1) return _fromRecord(hits.single.$1, hits.single.$2);
      throw ArgumentError.value(
        index,
        'step',
        hits.isEmpty
            ? 'no step $index in that run. ${_listing(Directory(runDir))}'
            : 'step $index exists in ${hits.length} scenarios of that run — '
                  'an index counts within a scenario, so name the capture '
                  'itself. ${_listing(Directory(runDir))}',
      );
    }

    var failed = [
      for (var outcome in outcomes)
        if (!outcome.ok && outcome.steps.isNotEmpty) outcome,
    ];
    if (failed.length == 1) {
      return _fromRecord(failed.single, failed.single.steps.last);
    }
    throw ArgumentError.value(
      null,
      'step',
      failed.isEmpty
          ? 'nothing failed in that run, so there is no obvious step to read. '
                '${_listing(Directory(runDir))}'
          : '${failed.length} scenarios failed in that run, so "the failing '
                'step" names more than one. ${_listing(Directory(runDir))}',
    );
  }

  /// The run to count into: the one named, or the newest the package has.
  String _runDirectory(Map<String, Object?> arguments) {
    if (arguments['output'] case String given when given.isNotEmpty) {
      var path = _absolute(given);
      if (!Directory(path).existsSync()) {
        throw ArgumentError.value(given, 'output', 'no such directory');
      }
      return path;
    }
    var candidates = <Directory>[];
    for (var path in _requested(arguments)) {
      var runs = Directory(
        p.join(
          host.workspace.packageFor(path).directory.path,
          'build',
          'flutterware',
          'scenario_runs',
        ),
      );
      if (!runs.existsSync()) continue;
      candidates.addAll(runs.listSync().whereType<Directory>());
    }
    if (candidates.isEmpty) {
      throw ArgumentError.value(
        null,
        'output',
        'this package has no scenario run on disk. Run one first — `run '
            'scenarios run` — or give `output` a directory that holds a '
            '$scenarioRunReportFile.',
      );
    }
    // Only directories that can answer. A panel session writes captures but
    // no report — and its `panel-` prefix sorts *after* every millisecond
    // stamp, so without this the "newest" default named a panel directory on
    // every read once one existed, forever.
    var runs = [
      for (var candidate in candidates)
        if (File(p.join(candidate.path, scenarioRunReportFile)).existsSync())
          candidate,
    ];
    // Newest by name, which is the millisecond stamp `run` writes. Reading it
    // off the directory name rather than off the filesystem keeps a checkout
    // or a copy from reordering a run history.
    candidates.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    if (runs.isEmpty) {
      throw ArgumentError.value(
        _relative(candidates.last.path),
        'output',
        '${candidates.length} capture '
            'director${candidates.length == 1 ? 'y' : 'ies'} on disk, but '
            'none holds a $scenarioRunReportFile — panel sessions write '
            'captures without one. Run `run scenarios run` first, or name a '
            'capture directly with `step`.',
      );
    }
    runs.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return runs.last.path;
  }

  ScenarioRunResult? _reportIn(String runDir) {
    var file = File(p.join(runDir, scenarioRunReportFile));
    if (!file.existsSync()) return null;
    try {
      return ScenarioRunResult.fromJson(
        (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>(),
      );
    } on FormatException {
      return null;
    }
  }

  /// The report record for a capture, found by the tree path it names.
  (ScenarioRunOutcome, ScenarioRunStep)? _stepRecordFor(String base) {
    var report = _reportIn(p.dirname(p.dirname(p.dirname(base))));
    if (report == null) return null;
    var wanted = '$base.tree.json';
    for (var package in report.packages) {
      for (var outcome in package.scenarios) {
        for (var step in outcome.steps) {
          if (_absolute(step.tree) == wanted) return (outcome, step);
        }
      }
    }
    return null;
  }

  _PickedStep _describe(String base) {
    if (_stepRecordFor(base) case var record?) {
      return _fromRecord(record.$1, record.$2);
    }
    // No report to read — a hand-placed capture, or a run directory that was
    // moved. The tree is still readable, and saying less is better than
    // refusing something that works.
    var directory = Directory(p.dirname(base));
    var siblings = <String>[
      if (directory.existsSync())
        for (var file in directory.listSync().whereType<File>())
          if (file.path.endsWith('.tree.json')) p.basename(file.path),
    ]..sort();
    return _PickedStep(
      base: base,
      siblings: siblings,
      image: [
        for (var extension in const ['.png', '.raw'])
          if (File('$base$extension').existsSync())
            _relative('$base$extension'),
      ].firstOrNull,
    );
  }

  _PickedStep _fromRecord(ScenarioRunOutcome outcome, ScenarioRunStep step) =>
      _PickedStep(
        base: _baseOf(_absolute(step.tree))!,
        file: outcome.file,
        scenario: outcome.name,
        index: step.index,
        failure:
            step.failure ??
            (outcome.steps.last == step
                ? outcome.errors.firstOrNull?.error
                : null),
        image: step.image,
        siblings: [for (var other in outcome.steps) p.basename(other.tree)],
      );

  /// What is in a directory, as values that can be passed straight back.
  String _listing(Directory directory) {
    var steps = [
      for (var file in directory.listSync().whereType<File>())
        if (file.path.endsWith('.tree.json')) _relative(file.path),
    ]..sort();
    if (steps.isNotEmpty) {
      return '${steps.length} captures there: ${steps.join(', ')}';
    }
    if (_reportIn(directory.path) case var report?) {
      var lines = <String>[
        for (var package in report.packages)
          for (var outcome in package.scenarios)
            [
              outcome.file,
              outcome.name,
              '${outcome.stepCount} steps',
              if (outcome.unchangedCount > 0)
                '${outcome.unchangedCount} unchanged',
              outcome.skipped
                  ? 'skipped'
                  : outcome.ok
                  ? 'ok'
                  : 'FAILED',
              ?outcome.steps.lastOrNull?.tree,
            ].join(' · '),
      ];
      return 'that run holds:\n${lines.join('\n')}';
    }
    var children = [
      for (var child in directory.listSync().whereType<Directory>())
        _relative(child.path),
    ]..sort();
    return children.isEmpty
        ? 'nothing readable in there'
        : 'directories there: ${children.join(', ')}';
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
    var orientations = _orientationList(arguments['orientations']);
    var assignments = <ScenarioAxes>[
      for (var device in devices.isEmpty ? [null] : devices)
        for (var orientation in _orientationsFor(device, orientations, null))
          for (var language in languages.isEmpty ? [null] : languages)
            ScenarioAxes(
              device: device,
              orientation: orientation,
              language: language,
            ),
    ];

    var results = <ScenarioShotsPackage>[];
    var total = 0;
    for (var path in paths) {
      var packageRoot = host.workspace.packageFor(path).directory.path;
      // Same base as `run`'s `output`: the worktree, unless absolute.
      var output = switch (arguments['output'] as String?) {
        var given? when given.isNotEmpty => _absolute(given),
        _ => p.join(packageRoot, 'build', 'flutterware', 'screenshots'),
      };
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
            // The orientation joins the device in the directory name, not
            // beside it: without it the two ways up of one device share a key
            // and the second run overwrites the first. Portrait adds nothing,
            // so a store tree that never asked for landscape is the tree it
            // was before.
            var key = p.join(
              language,
              assignment.isLandscape ? '$device-landscape' : device,
            );
            axesOf[key] = {
              'language': ?assignment.language,
              'device': device,
              if (assignment.isLandscape)
                'orientation': ScreenOrientation.landscape.name,
            };
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
              // a result portable; `step.root` is this machine's copy of it.
              File(
                p.join(step.root, step.image),
              ).copySync(p.join(into.path, name));
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
        (file as String?) ??
        '${newScenarioDirectoryFor(path)}/${scenarioFileName(name)}';
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
              directory: scanRootFor(path),
              error: '$error',
            )
          else
            ScenarioListPackage(
              path: path,
              directory: scanRootFor(path),
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
                  ? scenarioAuthoringHint(newScenarioDirectoryFor(path))
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
    // Resolved here, once, worktree-relative unless absolute — because a
    // relative path handed through verbatim reaches two writers with
    // different working directories: `fw` writes `run.json` from wherever it
    // was invoked, the tester writes the PNGs from the package root.
    // Measured on a real suite as an index in one directory pointing at
    // artifacts in another, with `image` paths that every worktree-relative
    // reader — `read`, MCP artifacts, the web export, `shots` — resolved to
    // files that were not there.
    var output = switch (arguments['output'] as String?) {
      var given? when given.isNotEmpty => _absolute(given),
      _ => null,
    };
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
    var orientations = _orientationList(arguments['orientations']);
    var matrix = arguments['matrix'];
    if (matrix != null && matrix != 'declared') {
      throw ArgumentError.value(
        matrix,
        'matrix',
        'accepted: declared — every point the folder profiles declare',
      );
    }
    if (matrix != null &&
        (devices.isNotEmpty ||
            languages.isNotEmpty ||
            orientations.isNotEmpty)) {
      throw ArgumentError(
        '`matrix=declared` reads devices, languages and orientations from '
        'the declaration — drop the explicit lists, or keep them and drop '
        '`matrix`.',
      );
    }
    List<ScenarioAxes> cross(
      List<String> devices,
      List<String> orientations,
      List<String> languages,
    ) => [
      for (var device in devices.isEmpty ? [axes.device] : devices)
        for (var orientation in _orientationsFor(
          device,
          orientations,
          axes.orientation,
        ))
          for (var language in languages.isEmpty ? [axes.language] : languages)
            ScenarioAxes(
              device: device,
              orientation: orientation,
              language: language,
              textScale: axes.textScale,
              brightness: axes.brightness,
              boldText: axes.boldText,
              highContrast: axes.highContrast,
              invertColors: axes.invertColors,
            ),
    ];
    var assignments = cross(devices, orientations, languages);
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

    var steps = arguments['steps'] as String? ?? 'failing';
    if (!const ['failing', 'all', 'none'].contains(steps)) {
      throw ArgumentError.value(steps, 'steps', 'accepted: failing, all, none');
    }

    var results = <ScenarioRunPackage>[];
    var assignmentsFor = <String, List<ScenarioAxes>>{};
    for (var path in paths) {
      if (matrix == null) {
        assignmentsFor[path] = assignments;
        continue;
      }
      // The declared matrix, read from the harness's own listing — the same
      // probe that fills the panel's pickers, and the run is about to pay
      // for the compiled harness anyway. The union across the package's
      // folders, crossed exactly as explicit lists are: CI stops restating
      // in `devices=` what `flutter_test_config.dart` already says, so
      // adding a device to the declaration adds it to CI.
      _setBusy(path, const Status.info('reading the declared matrix…'));
      try {
        var declaredDevices = <String>{};
        var declaredOrientations = <String>{};
        var declaredLanguages = <String>{};
        for (var listing in await _runnerFor(path).list()) {
          declaredDevices.addAll(listing.devices);
          declaredOrientations.addAll(listing.orientations);
          declaredLanguages.addAll(listing.languages);
        }
        assignmentsFor[path] = cross(
          declaredDevices.toList(),
          declaredOrientations.toList(),
          declaredLanguages.toList(),
        );
      } catch (_) {
        // A harness that cannot even list will not run either; one point is
        // enough for the run below to fail with the real error, in the
        // per-package shape everything downstream knows.
        assignmentsFor[path] = assignments;
      } finally {
        _setBusy(path, null);
      }
    }
    var points = assignmentsFor.values.fold(
      0,
      (sum, list) => sum + list.length,
    );
    var anyFannedOut = assignmentsFor.values.any((list) => list.length > 1);
    var point = 0;
    for (var path in paths) {
      var pathAssignments = assignmentsFor[path]!;
      var fannedOut = pathAssignments.length > 1;
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
      for (var assignment in pathAssignments) {
        // One directory per point of the matrix. Without it the second
        // assignment overwrites the first — same file, same scenario, same
        // step names — and only the last language survives on disk.
        var outDir = fannedOut ? p.join(base, axisSlug(assignment)) : base;
        // One process per point, seconds each — so which point is running is
        // the news a sidebar shows and MCP forwards. The matrix count only
        // when there is a matrix: "1 of 1" is noise.
        _setBusy(
          path,
          Status.info(
            points > 1
                ? 'running ${++point} of $points · ${axisSlug(assignment)}'
                : 'running…',
          ),
        );
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
            log: _harnessLog(path),
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
              log: _harnessLog(path),
              error: '$error',
            ),
          );
        } finally {
          _setBusy(path, null);
        }
      }
      if (fannedOut) _writeIndex(base, results.where((r) => r.path == path));
    }
    var whole = ScenarioRunResult(
      packages: [for (var run in results) _withReportOnDisk(run)],
      axes: anyFannedOut || axes.isEmpty ? null : axes.toParams(),
    );
    return _carrying(whole, steps);
  }

  /// Writes the package's own run beside its artifacts and names the file.
  ///
  /// Written before anything is trimmed, so the file is the whole answer no
  /// matter what the caller asked to be handed. Best effort: a run that
  /// produced pictures is not a failure because the directory turned
  /// read-only between writing them and writing this.
  ScenarioRunPackage _withReportOnDisk(ScenarioRunPackage run) {
    if (run.scenarios.isEmpty) return run;
    var file = p.join(run.output, scenarioRunReportFile);
    try {
      Directory(run.output).createSync(recursive: true);
      File(file).writeAsStringSync(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(ScenarioRunResult(packages: [run]).toJson()),
      );
    } catch (_) {
      return run;
    }
    return ScenarioRunPackage(
      path: run.path,
      output: run.output,
      axes: run.axes,
      ms: run.ms,
      scenarios: run.scenarios,
      report: file,
      log: run.log,
      error: run.error,
    );
  }

  /// [whole] with the steps [mode] asks for — the rest are in the file each
  /// package names.
  static ScenarioRunResult _carrying(ScenarioRunResult whole, String mode) {
    if (mode == 'all') return whole;
    var keepFailing = mode == 'failing';
    return ScenarioRunResult(
      axes: whole.axes,
      packages: [
        for (var run in whole.packages)
          ScenarioRunPackage(
            path: run.path,
            output: run.output,
            axes: run.axes,
            ms: run.ms,
            report: run.report,
            log: run.log,
            error: run.error,
            scenarios: [
              for (var outcome in run.scenarios)
                if (keepFailing && !outcome.ok)
                  // The frame it died on, not the trail that led there: one
                  // scenario with split branches is nineteen steps, and four
                  // red ones were 99k characters of pictures nobody had asked
                  // to see. The trail is in the file, one read away.
                  outcome.withFailingStepOnly()
                else
                  outcome.withoutSteps(),
            ],
          ),
      ],
    );
  }

  /// Runs the scenarios and writes the result as a page.
  ///
  /// **Re-runs rather than publishing the last run.** A page is dated, shared,
  /// and read by people who cannot check it — the one thing it may not be is a
  /// picture of a suite as it stood at some earlier moment nobody recorded.
  /// Which is also why every selector and axis `run` takes is taken here: what
  /// to run is the whole question the export asks.
  ///
  /// Takes the same argument map the action does, so the command the dialog
  /// echoes is the call the button makes.
  Future<ScenarioWebExportResult> exportWeb(
    Map<String, Object?> arguments, {
    void Function(String line)? onOutput,
  }) async {
    var baseHref = arguments['base-href'] as String?;
    if (baseHref != null &&
        baseHref.isNotEmpty &&
        (!baseHref.startsWith('/') || !baseHref.endsWith('/'))) {
      throw ArgumentError.value(
        baseHref,
        'base-href',
        'must begin and end with a slash — `/scenarios/`',
      );
    }
    // One at a time: an export empties its output directory before writing,
    // and two of them pointed at the same one would each delete the other's
    // page halfway through copying it.
    if (_export != null) {
      throw StateError(
        'An export is already running. Wait for it, or close the worktree to '
        'stop it.',
      );
    }

    // `output` names the page here and the raw artifacts in `run`, so the run
    // is left to its own default directory and the page copies out of it.
    // Every step, because the page *is* the steps — the summary the action
    // hands an agent would export a viewer with nothing in it.
    var runResult = await _run(
      {...arguments, 'steps': 'all'}..remove('output'),
    );

    // Same base as `run`'s `output`: the worktree, unless absolute. This was
    // the third answer — package-relative — and three bases for one flag
    // name is how a consumer lost an afternoon to an empty directory.
    var page = switch (arguments['output'] as String?) {
      var given? when given.isNotEmpty => _absolute(given),
      _ => ScenarioWebExporter.defaultOutputIn(
        packageRootFor(_requested(arguments).first),
      ),
    };

    var exporter = _export = ScenarioWebExporter(
      flutterExecutable: host.workspace.flutterSdk.flutter,
      appToolRoot: host.workspace.appContext.appToolDirectory.path,
      worktreeRoot: host.worktree.path,
    );
    ScenarioWebExport written;
    try {
      written = await exporter.export(
        report: ScenarioWebReport(
          // The worktree rather than the plugin: a page says what it is a page
          // *of*, and "Scenarios" tells a reader nothing they did not know
          // from the link they followed.
          title: host.worktree.name,
          generated: DateTime.now(),
          run: runResult,
        ),
        output: page,
        baseHref: baseHref == null || baseHref.isEmpty ? null : baseHref,
        offline: arguments['offline'] == 'true' || arguments['offline'] == true,
        onOutput: onOutput,
      );
    } finally {
      _export = null;
    }

    var failed = runResult.packages
        .expand((package) => package.scenarios)
        .where((scenario) => !scenario.ok)
        .length;
    return ScenarioWebExportResult(
      output: _relative(written.output),
      indexHtml: _relative(written.indexHtml),
      scenarios: written.scenarios,
      steps: written.steps,
      artifacts: written.artifacts,
      durationMs: written.duration.inMilliseconds,
      failed: failed,
      serve:
          'Serve it with any static server — `cd ${_relative(written.output)} '
          '&& python3 -m http.server`. Opening index.html as a file leaves the '
          'browser unable to fetch the report beside it, and the page says so '
          'rather than appearing empty. (The GUI serves it for you: "Export a '
          'web page…" on the package, then Open in browser.)',
    );
  }

  Future<ScenarioWebExportResult> _exportWeb(Map<String, Object?> arguments) =>
      exportWeb(arguments);

  /// The export in flight, so a second is refused and the first can be killed
  /// when the worktree goes.
  ScenarioWebExporter? _export;

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
          '${scenarioAuthoringHint(newScenarioDirectoryFor(path))}';
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

  /// The orientation list a matrix asked for, checked. Empty stays empty — the
  /// caller decides what "nothing fanned out" falls back to.
  static List<String> _orientationList(Object? raw) {
    var list = _axisList(raw, 'orientations');
    for (var id in list) {
      if (!isOrientationId(id)) {
        throw ArgumentError.value(
          id,
          'orientations',
          'no such orientation. Accepted: ${orientationIds.join(', ')}',
        );
      }
    }
    return list;
  }

  /// Which orientations [device] actually contributes to the matrix.
  ///
  /// **One point, not two, for anything that cannot turn.** Crossing a desktop
  /// or the bare surface with both orientations would run it twice for
  /// byte-identical pixels — a doubled CI bill for a picture nobody asked for
  /// twice. The same rule the bare `flutter test` lane applies in
  /// `scenarioAssignments`, because the two lanes have to agree on how many
  /// points a matrix has.
  ///
  /// An *unnamed* device keeps whatever was asked: the folder profile that
  /// resolves it only speaks inside the harness, so there is nothing to ask
  /// here, and `Device.oriented` collapses it there instead.
  static List<String?> _orientationsFor(
    String? device,
    List<String> requested,
    String? fallback,
  ) {
    if (device != null && !(deviceById(device)?.canRotate ?? false)) {
      return const [null];
    }
    return requested.isEmpty ? [fallback] : requested;
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
    var index = ScenarioRunIndex(
      runs: [
        for (var run in runs)
          ScenarioRunIndexEntry(
            package: run.path,
            axes: run.axes,
            output: p.relative(run.output, from: base),
            ok: run.error == null && run.scenarios.every((s) => s.ok),
            scenarios: run.scenarios.length,
            failed: run.scenarios.where((s) => !s.ok).length,
            skipped: run.scenarios.where((s) => s.skipped).length,
            error: run.error,
          ),
      ],
    );
    Directory(base).createSync(recursive: true);
    File(p.join(base, scenarioRunIndexFile)).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(index.toJson()),
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
    notifyChanged();
  }

  ScenarioRunner _runnerFor(String path) {
    var runner = _runners.putIfAbsent(
      path,
      () => ScenarioRunner(
        packageRoot: host.workspace.packageFor(path).directory.path,
        directory: scanRootFor(path),
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

  /// One step of the harness's vocabulary — the same record whether it
  /// arrived in the final report or as a mid-run event — located: paths made
  /// worktree-relative, and its `fw://` address assigned, carrying [axes] as
  /// query parameters since the picture depends on them.
  ScenarioRunStep _stepFrom(
    Map<String, Object?> step,
    String path, {
    required String file,
    required String scenario,
    required ScenarioAxes axes,
  }) => _locate(
    ScenarioRunStep.fromJson(step),
    path,
    file: file,
    scenario: scenario,
    axes: axes,
  );

  ScenarioRunStep _locate(
    ScenarioRunStep step,
    String path, {
    required String file,
    required String scenario,
    required ScenarioAxes axes,
  }) {
    return step.locate(
      root: host.worktree.path,
      path: _relative,
      address: Address(
        worktree: host.worktree.name,
        plugin: host.id,
        segments: scenarioSegments(path, file: file, scenario: scenario),
        axes: axes.toParams(),
      ).child('${step.index}').toString(),
    );
  }

  /// The harness console file for [path], when a run has left one behind.
  String? _harnessLog(String path) {
    var log = _runnerFor(path).logPath;
    return File(log).existsSync() ? log : null;
  }

  /// The harness's report, in the declared result shape.
  ScenarioRunPackage _describeRun(
    String path,
    String outDir,
    Map<String, Object?> report, {
    ScenarioAxes axes = const ScenarioAxes(),
    bool recordAxes = false,
    String? log,
  }) {
    return ScenarioRunPackage(
      path: path,
      output: outDir,
      axes: recordAxes ? axes.toParams() : null,
      log: log,
      ms: report['ms'] as int? ?? 0,
      scenarios: [
        for (var entry
            in (report['scenarios']! as List).cast<Map<String, Object?>>())
          () {
            var outcome = ScenarioRunOutcome.fromJson(entry);
            return outcome.carrying([
              for (var step in outcome.steps)
                _locate(
                  step,
                  path,
                  file: outcome.file,
                  scenario: outcome.name,
                  // The address on an artifact says what produced it, so an
                  // unspecified device is filled in with what the folder
                  // resolved it to — a link that reopens the same picture.
                  axes: axes.copyWith(device: outcome.device),
                ),
            ]);
          }(),
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
    // A `flutter build web` outlives its parent on macOS, and the one this
    // started is writing into the worktree that is going away.
    unawaited(_export?.cancel());
    _export = null;
    super.dispose();
  }
}

PluginCore scenariosCoreFactory(PluginHost host) => ScenariosCore(host);

/// One archived capture, chosen — and what the run record knows about it.
class _PickedStep {
  _PickedStep({
    required this.base,
    this.siblings = const [],
    this.file,
    this.scenario,
    this.index,
    this.failure,
    this.image,
  });

  /// Absolute, without an extension: every leg is `$base.<leg>`.
  final String base;

  /// The other captures of the same scenario, as `step:` values — what makes
  /// walking a failing flow backwards one call each.
  final List<String> siblings;

  final String? file;
  final String? scenario;
  final int? index;
  final String? failure;

  /// Worktree-relative, as the run reported it.
  final String? image;
}

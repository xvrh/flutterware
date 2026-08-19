import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import '../embedder/tester_host.dart';
import 'axes.dart';
import 'discovery.dart';
import 'harness_entrypoint.dart';

/// One scenario listed by the live harness — ground truth, where the scan is
/// provisional.
class ScenarioListing {
  ScenarioListing({
    required this.file,
    required this.name,
    this.profile,
    this.devices = const [],
    this.languages = const [],
    this.orientations = const [],
    this.tags = const [],
  });

  final String file;
  final String name;

  /// The name of the profile its folder's `flutter_test_config.dart` declared,
  /// or null where the folder has none.
  final String? profile;

  /// What that profile offers — the picker's list, and the first of each is
  /// what a run takes when nobody chose.
  final List<String> devices;
  final List<String> languages;
  final List<String> orientations;

  /// What `scenario(tags: [...])` declared — the vocabulary `run --tag` and
  /// `shots --tag` filter on. Only the live harness can see these; the
  /// syntactic scan does not evaluate arguments.
  final List<String> tags;
}

/// Runs a package's scenarios in a directly-spawned `flutter_tester`, exactly
/// as spike S4 proved (`2026-07-30-s4-flutter-tester-findings.md`): our own
/// resident `frontend_server`, the SDK's tester binary, FakeAsync inside,
/// driven over the VM service.
///
/// Deliberately Flutter-free: `fw run scenarios run` links this, and the
/// purity guardrail (`entry_point_purity_test.dart`) holds it to that.
///
/// Not passing `--use-test-fonts` / `--disable-asset-fonts` — the two flags
/// `flutter test` always passes — is what makes captures render real fonts;
/// the harness loads `FontManifest.json` on top.
///
/// A warm runner stays honest: [run] re-syncs with the sources on disk before
/// every warm run, so the Run button never replays code that has since been
/// edited. See [refresh] for the two lanes that takes.
/// The scenario half of a [TesterHost]: which files make up the program, and
/// what the harness they generate calls itself.
class _ScenarioProgram extends TesterProgram {
  _ScenarioProgram({required this.packageRoot, required this.directory});

  final String packageRoot;
  final String directory;

  @override
  String get name => 'scenarios';

  @override
  String get readyLine => 'scenarios harness ready';

  /// The streaming half of a run — `{file, scenario, step}` with the artifacts
  /// already on disk, which is how a panel fills the flow in while the scenario
  /// executes.
  @override
  String get eventStream => 'flutterware.scenarios.step';

  @override
  List<String> sources() {
    var scan = ScenarioScanner(
      packageRoot: packageRoot,
      directory: directory,
    ).scan();
    var files = {for (var ref in scan.scenarios) ref.file}.toList()..sort();
    if (files.isEmpty) {
      throw StateError(
        'No scenarios found under $directory. '
        "Write one with scenario('…', (s) async { … }).",
      );
    }
    return files;
  }

  @override
  String writeEntrypoint(List<String> sources) =>
      writeHarnessEntrypoint(packageRoot, sources);
}

/// Runs a package's scenarios in a directly-spawned `flutter_tester` — see
/// [TesterHost], which is everything here that is not about scenarios in
/// particular.
///
/// Deliberately Flutter-free: `fw run scenarios run` links this, and the
/// purity guardrail (`entry_point_purity_test.dart`) holds it to that.
///
/// A warm runner stays honest: [run] re-syncs with the sources on disk before
/// every warm run, so the Run button never replays code that has since been
/// edited.
class ScenarioRunner {
  ScenarioRunner({
    required this.packageRoot,
    required this.directory,
    required String flutterSdkRoot,
    void Function(String line)? onLog,
  }) : _host = TesterHost(
         packageRoot: packageRoot,
         flutterSdkRoot: flutterSdkRoot,
         program: _ScenarioProgram(
           packageRoot: packageRoot,
           directory: directory,
         ),
         onLog: onLog,
       ) {
    _host.onEvent = (event) => onStep?.call(event);
  }

  final String packageRoot;

  /// Scenario directory relative to [packageRoot].
  final String directory;

  final TesterHost _host;

  /// Where the harness process's console is teed — see [TesterHost.logPath].
  String get logPath => _host.logPath;

  /// Called for every step the harness announces **mid-run**. The blocking
  /// [run] response remains the complete report; this is the streaming half.
  ///
  /// Mutable rather than constructor-fixed so the owner can attach after the
  /// runner exists.
  void Function(Map<String, Object?> event)? onStep;

  Future<void> start() => _host.start();

  Future<void> refresh() => _host.refresh();

  Future<List<ScenarioListing>> list() => _host.exclusive(() async {
    await _host.ensureGuest();
    var response = await _host.vm.requireExtension(
      'ext.flutterware.scenarios.list',
    );
    return [
      for (var entry
          in (response!['scenarios']! as List).cast<Map<String, dynamic>>())
        ScenarioListing(
          file: entry['file']! as String,
          name: entry['name']! as String,
          profile: entry['profile'] as String?,
          devices: (entry['devices'] as List?)?.cast<String>() ?? const [],
          languages: (entry['languages'] as List?)?.cast<String>() ?? const [],
          orientations:
              (entry['orientations'] as List?)?.cast<String>() ?? const [],
          tags: (entry['tags'] as List?)?.cast<String>() ?? const [],
        ),
    ];
  });

  /// Runs scenarios — all of them, one file's, or one — writing each step's
  /// PNG and tree under [outDir] and returning the harness's report verbatim.
  /// [axes] is applied for the whole request and reset after it.
  ///
  /// An axis assignment that names no device leaves the choice to each
  /// scenario's folder profile, and to [unspecifiedDevice] where a folder has
  /// none — a policy the runner holds no opinion about, so a caller that
  /// passes nothing gets the bare test surface.
  ///
  /// A warm runner refreshes first, so what runs is always what is on disk.
  Future<Map<String, Object?>> run({
    required String outDir,
    String? file,
    String? scenario,
    String? tag,
    ScenarioAxes axes = const ScenarioAxes(),
    String? unspecifiedDevice,
    double? captureScale,
    bool captureRaw = false,
    bool captureNative = false,
    Duration? recordInterval,

    /// Null records at the same scale as the step's own screenshot, which is
    /// the only setting where playback does not visibly change resolution
    /// when it stops.
    double? recordScale,
    int recordMaxFrames = 90,
    DateTime? clock,
  }) => _host.exclusive(() async {
    var wasWarm = _host.isWarm;
    await _host.ensureGuest();
    if (wasWarm) await _host.sync();
    Directory(outDir).createSync(recursive: true);
    var response = await _host.vm.requireExtension(
      'ext.flutterware.scenarios.run',
      args: {
        'out': outDir,
        'file': ?file,
        'scenario': ?scenario,
        'tag': ?tag,
        if (captureScale != null) 'captureScale': '$captureScale',
        if (captureRaw) 'captureRaw': 'true',
        if (captureNative) 'captureNative': 'true',
        // Present only when recording: the interval is what turns motion
        // capture on, so its absence is the off switch and no run that did
        // not ask pays for one.
        if (recordInterval != null) ...{
          'recordIntervalMs': '${recordInterval.inMilliseconds}',
          if (recordScale != null) 'recordScale': '$recordScale',
          'recordMaxFrames': '$recordMaxFrames',
        },
        if (clock != null) 'clock': clock.toIso8601String(),
        ...axes.harnessArgs(unspecifiedDevice: unspecifiedDevice),
      },
    );
    if (response!['error'] case String error) {
      throw StateError('the harness failed:\n$error\n${response['stack']}');
    }
    // A scenario blew its deadline, so its body is still in there holding the
    // binding. The report is good — it is what the run got to — but the guest
    // is not, and a warm one is exactly what the next run would reuse.
    if (response['abandoned'] == true) {
      _host.onLog?.call(
        '[scenarios] a scenario timed out — restarting the harness',
      );
      await _host.restartGuest();
    }
    return response.cast<String, Object?>();
  });

  /// Kills the guest out from under the runner, so a test can assert that the
  /// next call notices and respawns rather than talking to a dead service.
  /// Awaits the exit, so what follows is testing the recovery rather than
  /// racing the kill.
  @visibleForTesting
  Future<void> debugKillGuest() => _host.killGuest();

  Future<void> dispose() => _host.dispose();
}

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_api/src/backend/declarer.dart';
import 'package:test_api/src/backend/group.dart';
import 'package:test_api/src/backend/group_entry.dart';
import 'package:test_api/src/backend/live_test.dart';
import 'package:test_api/src/backend/runtime.dart';
import 'package:test_api/src/backend/suite.dart';
import 'package:test_api/src/backend/suite_platform.dart';
import 'package:test_api/src/backend/test.dart';

import '../inspect/guest_inspect.dart';
import 'profile.dart';
import 'run_args.dart';
import 'scenario.dart';
import 'run_listener.dart';

// ignore_for_file: implementation_imports

/// The scenario harness `main`, called by the generated entrypoint the runner
/// compiles into `flutter_tester`:
///
/// ```dart
/// // GENERATED — build/flutterware/scenarios_harness.dart
/// import 'package:flutterware/src/scenarios/harness.dart' as harness;
/// import '../../test/scenarios/counter_test.dart' as s0;
///
/// void main() => harness.runHarness({
///   'test/scenarios/counter_test.dart': s0.main,
/// });
/// ```
///
/// Runs under `AutomatedTestWidgetsFlutterBinding` — FakeAsync, instantaneous
/// — in a directly-spawned `flutter_tester` (S4,
/// `2026-07-30-s4-flutter-tester-findings.md`). The host drives it over the VM
/// service:
///
/// - `ext.flutterware.scenarios.list` → every declared scenario, by file.
/// - `ext.flutterware.scenarios.run` → runs scenarios (optionally one, by
///   `file` + `scenario`), writing each step's PNG and widget tree under the
///   request's `out` directory and returning the step list. The
///   request/response shape is the barrier an agent needs: no watch mode, no
///   races.
///
/// Fonts load once at startup from the asset bundle's `FontManifest.json` —
/// the harness's job, not every user's (S4's fonts finding).
Future<void> runHarness(
  Map<String, void Function()> scenarioMains, {
  Map<String, Future<void> Function(FutureOr<void> Function())> configs =
      const {},
}) async {
  // The whole harness — including every extension handler, which runs in the
  // zone it was registered in — is guarded: a failing scenario can leak an
  // async error after its LiveTest completes, and unguarded that reaches
  // `tester_main.cc`'s unhandled handler, which kills the process. A shared
  // harness dying because one scenario failed is the one outcome this may
  // never have.
  unawaited(
    runZonedGuarded(() => _runHarness(scenarioMains, configs), (error, stack) {
      stderr.writeln('[harness] uncaught: $error\n$stack');
    }),
  );
}

Future<void> _runHarness(
  Map<String, void Function()> scenarioMains,
  Map<String, Future<void> Function(FutureOr<void> Function())> configs,
) async {
  var binding = _HarnessBinding();
  var fonts = await _loadBundleFonts();
  var profiles = await _probeProfiles(configs);

  var inspector = GuestInspector(
    rootOf: () => binding.rootElement,
    entryIdOf: () => null,
  );

  developer.registerExtension('ext.flutterware.scenarios.list', (_, _) async {
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'scenarios': _list(scenarioMains, profiles)}),
    );
  });

  developer.registerExtension('ext.flutterware.scenarios.run', (_, args) async {
    try {
      var report = await _run(
        scenarioMains,
        inspector: inspector,
        outDir: args['out']!,
        file: args['file'],
        scenario: args['scenario'],
        tag: args['tag'],
        runArgs: _parseRunArgs(args),
        profiles: profiles,
        // The host resolved a device id to geometry, or said it had nobody's
        // choice to resolve — in which case the folder's profile speaks and
        // the geometry that did arrive is only the host's fallback.
        device: args['device'],
        deviceUnspecified: args['deviceUnspecified'] == 'true',
      );
      return developer.ServiceExtensionResponse.result(jsonEncode(report));
    } catch (error, stack) {
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'error': '$error', 'stack': '$stack'}),
      );
    }
  });

  // The engine keeps the process alive; the timer keeps the isolate from ever
  // reading as idle between host calls.
  Timer.periodic(const Duration(days: 1), (_) {});
  print('flutterware scenarios harness ready — fonts: ${fonts.join(', ')}');
}

class _HarnessBinding extends AutomatedTestWidgetsFlutterBinding {
  // A hot reload schedules a warm-up frame; outside a test that frame
  // asserts. Same guard S4 and the 2026-05 port carried.
  @override
  void scheduleWarmUpFrame() {
    if (inTest) super.scheduleWarmUpFrame();
  }
}

/// Loads every font the asset bundle's `FontManifest.json` declares — the
/// project's own families plus `MaterialIcons`.
Future<List<String>> _loadBundleFonts() async {
  var manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json'))
          as List<dynamic>;
  var families = <String>[];
  for (var entry in manifest.cast<Map<String, dynamic>>()) {
    var family = entry['family']! as String;
    var loader = FontLoader(family);
    for (var font in (entry['fonts']! as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset']! as String));
    }
    await loader.load();
    families.add(family);
  }
  return families;
}

/// Declares every scenario file as a group named by its path, so a test's
/// file is recoverable from the group it sits in.
///
/// Deliberately **not** `Declarer(fullTestName:)`: `test_api` composes a full
/// name out of every enclosing group, so a scenario the author wrapped in a
/// `group('…')` of their own is named `<file> <group> <scenario>` and never
/// matched the `<file> <scenario>` a caller asks with — it listed fine and
/// could not be run. Declaring registers closures, it does not execute them,
/// so the filtering costs nothing where it now happens: in the walk, against
/// the same leaf name the listing reports.
/// The declared tree, plus which of its tests are **scenarios**.
///
/// A `test/scenarios/` folder may hold ordinary `testWidgets` — a helper, a
/// unit test that drifted in — and those produce no steps, cannot be opened
/// in the panel, and used to be run anyway: `list` (the syntactic scan) and
/// `run` (this walk) disagreed about what the folder contained. `scenario()`
/// announces itself as it declares, which is the only reading that cannot be
/// wrong about a name the scan could not evaluate.
({Group root, Map<String, Set<String>> scenarios}) _declare(
  Map<String, void Function()> scenarioMains,
) {
  var declarer = Declarer();
  var scenarios = <String, Set<String>>{};
  declarer.declare(() {
    for (var entry in scenarioMains.entries) {
      group(entry.key, () {
        var sink = <String>[];
        scenarioDeclarationSink = sink;
        try {
          entry.value();
        } finally {
          scenarioDeclarationSink = null;
        }
        scenarios[entry.key] = sink.toSet();
      });
    }
  });
  return (root: declarer.build(), scenarios: scenarios);
}

/// Asks each folder's `flutter_test_config.dart` what it is for.
///
/// The config is *run*, not parsed: it is Dart, it may import its profile from
/// anywhere, and executing it is the only reading that cannot be wrong. Its
/// own setup runs too — the same setup `flutter test` gives that folder, which
/// this runner skipped entirely until now.
Future<Map<String, ScenarioProfile>> _probeProfiles(
  Map<String, Future<void> Function(FutureOr<void> Function())> configs,
) async {
  var profiles = <String, ScenarioProfile>{};
  for (var MapEntry(key: directory, value: config) in configs.entries) {
    scenarioProbing = true;
    scenarioProbedProfile = null;
    try {
      await config(() {});
      if (scenarioProbedProfile case var profile?) {
        profiles[directory] = profile;
      }
    } catch (error, stack) {
      stderr.writeln('[harness] $directory config: $error\n$stack');
    } finally {
      scenarioProbing = false;
      scenarioProbedProfile = null;
    }
  }
  return profiles;
}

/// The profile whose folder contains [file] — the nearest one above it, which
/// is the rule `flutter test` itself resolves configs by.
ScenarioProfile? _profileFor(
  String file,
  Map<String, ScenarioProfile> profiles,
) {
  ScenarioProfile? best;
  var bestLength = -1;
  for (var MapEntry(key: directory, value: profile) in profiles.entries) {
    if ((file == directory || file.startsWith('$directory/')) &&
        directory.length > bestLength) {
      best = profile;
      bestLength = directory.length;
    }
  }
  return best;
}

List<Map<String, Object?>> _list(
  Map<String, void Function()> scenarioMains,
  Map<String, ScenarioProfile> profiles,
) {
  var declared = _declare(scenarioMains);
  var scenarios = <Map<String, Object?>>[];
  void walk(Group group, String? file) {
    for (var entry in group.entries) {
      switch (entry) {
        case Test():
          if (!_isScenario(declared.scenarios, file, entry, group)) break;
          var profile = _profileFor(file ?? '', profiles);
          scenarios.add({
            'file': file ?? '',
            'name': _leafName(entry, group),
            if (entry.metadata.tags.isNotEmpty)
              'tags': entry.metadata.tags.toList()..sort(),
            if (profile != null) ...{
              'profile': profile.name,
              'devices': [for (var d in profile.devices) d.id],
              'languages': profile.languages,
            },
          });
        case Group():
          walk(entry, file ?? entry.name);
        case GroupEntry():
          break;
      }
    }
  }

  walk(declared.root, null);
  return scenarios;
}

/// Whether a declared test came from `scenario()` rather than a plain
/// `testWidgets` that happens to live in the same folder.
bool _isScenario(
  Map<String, Set<String>> scenarios,
  String? file,
  Test test,
  Group group,
) => scenarios[file ?? '']?.contains(_leafName(test, group)) ?? false;

/// The scenario's own name, with the enclosing groups' prefix stripped —
/// `test_api` composes full names with spaces.
String _leafName(GroupEntry test, Group group) {
  if (group.name.isEmpty) return test.name;
  if (!test.name.startsWith(group.name)) return test.name;
  if (test.name.length == group.name.length) return '';
  return test.name.substring(group.name.length + 1);
}

/// The run request's axis assignment, from the flat string args the runner
/// sends. Geometry arrives resolved — the device vocabulary (`iphone-se` →
/// numbers) belongs to the host, and the harness applies numbers.
ScenarioRunArgs? _parseRunArgs(Map<String, String> args) {
  double? number(String key) {
    var raw = args[key];
    return raw == null ? null : double.parse(raw);
  }

  Size? size;
  if ((number('width'), number('height')) case (var width?, var height?)) {
    size = Size(width, height);
  }
  var insets = EdgeInsets.fromLTRB(
    number('insetLeft') ?? 0,
    number('insetTop') ?? 0,
    number('insetRight') ?? 0,
    number('insetBottom') ?? 0,
  );
  var locale = switch (args['language']) {
    null => null,
    var tag => () {
      var parts = tag.split(RegExp('[-_]'));
      return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
    }(),
  };
  var runArgs = ScenarioRunArgs(
    size: size,
    pixelRatio: number('pixelRatio'),
    padding: insets == EdgeInsets.zero ? null : insets,
    platform: switch (args['platform']?.toLowerCase()) {
      null => null,
      // By lowercase name: the wire says `ios`, the enum says `iOS`.
      var name => TargetPlatform.values.firstWhere(
        (p) => p.name.toLowerCase() == name,
      ),
    },
    locale: locale,
    textScale: number('textScale'),
    brightness: switch (args['brightness']) {
      null => null,
      'dark' => Brightness.dark,
      _ => Brightness.light,
    },
    accessibility: ScenarioRunAccessibility(
      boldText: args['boldText'] == 'true',
      highContrast: args['highContrast'] == 'true',
      invertColors: args['invertColors'] == 'true',
    ),
    captureScale: number('captureScale'),
    captureRaw: args['captureRaw'] == 'true',
    captureNative: args['captureNative'] == 'true',
    clockOrigin: switch (args['clock']) {
      null => null,
      var raw => DateTime.parse(raw),
    },
  );
  var untouched =
      runArgs.size == null &&
      runArgs.pixelRatio == null &&
      runArgs.padding == null &&
      runArgs.platform == null &&
      runArgs.locale == null &&
      runArgs.textScale == null &&
      runArgs.brightness == null &&
      runArgs.accessibility.isDefault &&
      runArgs.captureScale == null &&
      !runArgs.captureRaw &&
      !runArgs.captureNative &&
      runArgs.clockOrigin == null;
  return untouched ? null : runArgs;
}

Future<Map<String, Object?>> _run(
  Map<String, void Function()> scenarioMains, {
  required GuestInspector inspector,
  required String outDir,
  String? file,
  String? scenario,
  String? tag,
  ScenarioRunArgs? runArgs,
  Map<String, ScenarioProfile> profiles = const {},
  String? device,
  bool deviceUnspecified = false,
}) async {
  var mains = file == null
      ? scenarioMains
      : {
          for (var entry in scenarioMains.entries)
            if (entry.key == file) entry.key: entry.value,
        };
  var declared = _declare(mains);
  var root = declared.root;

  var outcomes = <Map<String, Object?>>[];
  var watch = Stopwatch()..start();

  // What each file runs as, worked out once per file. A request that named a
  // device is that device everywhere; a request that named none takes what the
  // file's folder profile puts first — which is how one run over a mixed suite
  // frames the mobile folder as a phone and the desktop folder as a window,
  // without the caller having to know either folder exists.
  var framings = <String, (ScenarioRunArgs?, String?)>{};
  (ScenarioRunArgs?, String?) framingFor(String file) =>
      framings.putIfAbsent(file, () {
        if (!deviceUnspecified) return (runArgs, device);
        var chosen = _profileFor(file, profiles)?.devices.firstOrNull;
        if (chosen == null) return (runArgs, device);
        return (
          (runArgs ?? const ScenarioRunArgs()).withDevice(chosen),
          chosen.id,
        );
      });

  /// Mirrors `test_core`'s engine (`runner/engine.dart`, `_runGroup`): the
  /// group's `setUpAll` before its entries, its entries only if that passed,
  /// and its `tearDownAll` afterwards **whatever happened** — cleanup a
  /// failure skipped is cleanup that never runs, and this harness outlives the
  /// run by design.
  Future<void> walk(
    Group group,
    Suite suite,
    List<Group> parents,
    String? groupFile,
  ) async {
    // Before paying for a group's `setUpAll`, ask whether anything in it will
    // run at all. `test_core` never has to: it filters by rebuilding the group
    // tree, so an empty group never reaches the engine. We filter as we walk,
    // and the panel runs one scenario at a time — without this, running one
    // scenario would start every other file's fixtures.
    if (!_runsAnything(declared.scenarios, group, groupFile, scenario, tag)) {
      return;
    }
    var scope = [...parents, group];

    var setUpAllError = group.setUpAll == null
        ? null
        : await _runHook(group.setUpAll!, suite, scope);

    for (var entry in group.entries) {
      switch (entry) {
        case Test():
          // The name the listing shows, matched against the name the caller
          // asks for — the same vocabulary at both ends, whatever groups the
          // author nested the scenario in. Two scenarios sharing a leaf name
          // in one file both run, which is the honest reading of a request
          // that names only what the panel displays.
          var name = _leafName(entry, group);
          if (!_isScenario(declared.scenarios, groupFile, entry, group)) break;
          if (!_selects(entry, group, scenario, tag)) break;
          var (framedArgs, framedDevice) = framingFor(groupFile ?? '');
          if (setUpAllError != null) {
            // Reported against each scenario that would have run, not once
            // against the group: a caller who asked for one scenario must find
            // that scenario in the answer, failed and saying why.
            outcomes.add({
              'file': groupFile ?? '',
              'name': name,
              'device': ?framedDevice,
              'ok': false,
              'ms': 0,
              'steps': <Map<String, Object?>>[],
              'errors': [setUpAllError],
            });
            break;
          }
          // Read by `scenario()` inside the test body, applied through the
          // binding's own test values, reset by its tearDown — the run-args
          // zone of the design. Set per scenario rather than per request,
          // because the framing is per folder.
          scenarioRunArgs = framedArgs;
          outcomes.add(
            await _runOne(
              entry.load(suite, groups: scope),
              file: groupFile ?? '',
              name: name,
              device: framedDevice,
              inspector: inspector,
              outDir: outDir,
            ),
          );
        case Group():
          if (setUpAllError == null) {
            await walk(entry, suite, scope, groupFile ?? entry.name);
          }
        case GroupEntry():
          break;
      }
    }

    if (group.tearDownAll case var hook?) {
      if (await _runHook(hook, suite, scope) case var error?) {
        // Its own outcome: a cleanup failure belongs to nobody's scenario, and
        // marking a scenario that passed as failed would be a lie.
        outcomes.add({
          'file': groupFile ?? '',
          'name': 'tearDownAll',
          'ok': false,
          'ms': 0,
          'steps': <Map<String, Object?>>[],
          'errors': [error],
        });
      }
    }
  }

  var suite = Suite(root, SuitePlatform(Runtime.vm));
  try {
    await walk(root, suite, const [], null);
  } finally {
    scenarioRunArgs = null;
  }

  return {'ms': watch.elapsedMilliseconds, 'scenarios': outcomes};
}

/// Whether anything under [group] survives the scenario filter — the question
/// that decides whether its `setUpAll` is worth running.
bool _runsAnything(
  Map<String, Set<String>> scenarios,
  Group group,
  String? file,
  String? scenario,
  String? tag,
) {
  for (var entry in group.entries) {
    switch (entry) {
      case Test():
        if (_isScenario(scenarios, file, entry, group) &&
            _selects(entry, group, scenario, tag)) {
          return true;
        }
      case Group():
        if (_runsAnything(
          scenarios,
          entry,
          file ?? entry.name,
          scenario,
          tag,
        )) {
          return true;
        }
      case GroupEntry():
        break;
    }
  }
  return false;
}

/// Whether a request naming [scenario] and/or [tag] wants this test.
///
/// The tag is `test_api`'s own — what `scenario(tags: …)` passes to
/// `testWidgets`, which is also what `flutter test --tags` filters on, so a
/// suite tagged for one runner is tagged for both.
bool _selects(Test test, Group group, String? scenario, String? tag) {
  if (scenario != null && _leafName(test, group) != scenario) return false;
  if (tag != null && !test.metadata.tags.contains(tag)) return false;
  return true;
}

/// Runs a group's `setUpAll` or `tearDownAll` — a synthetic test `test_api`
/// hangs off the group rather than putting in its entries, which is exactly
/// why a walk over `entries` alone never ran them.
///
/// Returns the failure, or null when it passed.
Future<Map<String, Object?>?> _runHook(
  Test hook,
  Suite suite,
  List<Group> scope,
) async {
  var live = hook.load(suite, groups: scope);
  // `test_api` builds both hooks as **unguarded** tests (`guarded: false`):
  // they run no error zone of their own, on the understanding that whoever
  // runs them has one. Ours would be `runHarness`'s outermost guard, which
  // logs and swallows — and the LiveTest stays green, so the group would run
  // against a fixture that never got built. So the hook gets a zone here, and
  // what escapes into it is what failed.
  Object? escaped;
  StackTrace? escapedStack;
  await runZonedGuarded(() => live.run(), (error, stack) {
    escaped ??= error;
    escapedStack ??= stack;
  });
  // One turn of the event loop for an error raised on the way out.
  await Future<void>.delayed(Duration.zero);

  if (escaped == null && live.state.result.isPassing && live.errors.isEmpty) {
    return null;
  }
  var error = live.errors.firstOrNull;
  return {
    'error': '${hook.name}: ${escaped ?? error?.error ?? 'failed'}',
    'stack': '${escapedStack ?? error?.stackTrace}',
  };
}

Future<Map<String, Object?>> _runOne(
  LiveTest live, {
  required String file,
  required String name,
  required GuestInspector inspector,
  required String outDir,
  String? device,
}) async {
  var steps = <Map<String, Object?>>[];
  var directory = Directory('$outDir/${_fileSafe(file)}/${_fileSafe(name)}')
    ..createSync(recursive: true);

  scenarioRunListener = (capture) {
    var base =
        '${directory.path}/${capture.index}-'
        '${_fileSafe(capture.failure != null ? 'failed' : capture.name ?? 'step ${capture.index}')}';
    var imagePath = '$base.${capture.format == 'raw' ? 'raw' : 'png'}';
    File(imagePath).writeAsBytesSync(capture.bytes);
    // The tree next to the pixels — the step triple's third leg. Written to a
    // file rather than inlined: a run's response stays readable, and the tree
    // is fetched per step by whoever wants it.
    var tree = inspector.read().toJson();
    File('$base.tree.json').writeAsStringSync(jsonEncode(tree));
    var step = {
      'index': capture.index,
      'parent': ?capture.parent,
      'branch': ?capture.branch,
      if (capture.name != null) 'name': capture.name,
      'auto': capture.name == null,
      if (capture.tags.isNotEmpty) 'tags': capture.tags,
      'image': imagePath,
      'format': capture.format,
      'width': capture.width,
      'height': capture.height,
      'tree': '$base.tree.json',
      'texts': capture.texts,
      'statusBrightness': ?capture.statusBrightness,
      'navBrightness': ?capture.navBrightness,
      // Both omitted in the healthy case, so a normal step's record stays the
      // size it was.
      if (!capture.settled) 'settled': false,
      if (capture.strayFrames > 0) 'strayFrames': capture.strayFrames,
      'failure': ?capture.failure,
    };
    steps.add(step);
    // Announced the moment it exists — the artifacts are already on disk —
    // so a host drawing the flow can fill it in while the scenario still
    // runs. The response at the end stays the complete report: streaming is
    // for watching, the barrier is for agents.
    developer.postEvent('flutterware.scenarios.step', {
      'file': file,
      'scenario': name,
      // Said on every step, not only in the final report: a host drawing the
      // flow live has to frame the first picture, and by then the answer is
      // already known.
      'device': ?device,
      'step': step,
    });
  };

  // The binding's failure path bypasses the LiveTest: `reportTestException`
  // dumps to console and throws from the binding's own zone, so the LiveTest
  // stays green and the error surfaces as an uncaught zone error. Intercepting
  // the reporter is how the failure lands in the outcome — the same hook
  // `flutter test`'s own bootstrap uses.
  var failures = <Map<String, Object?>>[];
  var priorReporter = reportTestException;
  reportTestException = (details, testDescription) {
    failures.add({
      'error': details.exceptionAsString(),
      'stack': '${details.stack}',
    });
  };

  var watch = Stopwatch()..start();
  try {
    await live.run();
  } finally {
    reportTestException = priorReporter;
    scenarioRunListener = null;
  }

  var errors = [
    ...failures,
    for (var error in live.errors)
      {'error': '${error.error}', 'stack': '${error.stackTrace}'},
  ];
  var passed = live.state.result.isPassing && errors.isEmpty;
  return {
    'file': file,
    'name': name,
    // What it actually ran as — which the caller may not have said, having
    // left the folder's profile to answer.
    'device': ?device,
    'ok': passed,
    'ms': watch.elapsedMilliseconds,
    'steps': steps,
    if (!passed) 'errors': errors,
  };
}

String _fileSafe(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

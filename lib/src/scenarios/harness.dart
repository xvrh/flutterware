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
import 'run_args.dart';
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
Future<void> runHarness(Map<String, void Function()> scenarioMains) async {
  // The whole harness — including every extension handler, which runs in the
  // zone it was registered in — is guarded: a failing scenario can leak an
  // async error after its LiveTest completes, and unguarded that reaches
  // `tester_main.cc`'s unhandled handler, which kills the process. A shared
  // harness dying because one scenario failed is the one outcome this may
  // never have.
  unawaited(
    runZonedGuarded(() => _runHarness(scenarioMains), (error, stack) {
      stderr.writeln('[harness] uncaught: $error\n$stack');
    }),
  );
}

Future<void> _runHarness(Map<String, void Function()> scenarioMains) async {
  var binding = _HarnessBinding();
  var fonts = await _loadBundleFonts();

  var inspector = GuestInspector(
    rootOf: () => binding.rootElement,
    entryIdOf: () => null,
  );

  developer.registerExtension('ext.flutterware.scenarios.list', (_, _) async {
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'scenarios': _list(scenarioMains)}),
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
        runArgs: _parseRunArgs(args),
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
/// full name is `<file> <scenario>` and both halves are recoverable.
Group _declare(Map<String, void Function()> scenarioMains, {String? only}) {
  var declarer = Declarer(fullTestName: only);
  declarer.declare(() {
    for (var entry in scenarioMains.entries) {
      group(entry.key, entry.value);
    }
  });
  return declarer.build();
}

List<Map<String, Object?>> _list(Map<String, void Function()> scenarioMains) {
  var scenarios = <Map<String, Object?>>[];
  void walk(Group group, String? file) {
    for (var entry in group.entries) {
      switch (entry) {
        case Test():
          scenarios.add({'file': file ?? '', 'name': _leafName(entry, group)});
        case Group():
          walk(entry, file ?? entry.name);
        case GroupEntry():
          break;
      }
    }
  }

  walk(_declare(scenarioMains), null);
  return scenarios;
}

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
  );
  var untouched =
      runArgs.size == null &&
      runArgs.pixelRatio == null &&
      runArgs.padding == null &&
      runArgs.platform == null &&
      runArgs.locale == null &&
      runArgs.textScale == null &&
      runArgs.brightness == null &&
      runArgs.accessibility.isDefault;
  return untouched ? null : runArgs;
}

Future<Map<String, Object?>> _run(
  Map<String, void Function()> scenarioMains, {
  required GuestInspector inspector,
  required String outDir,
  String? file,
  String? scenario,
  ScenarioRunArgs? runArgs,
}) async {
  var only = file != null && scenario != null ? '$file $scenario' : null;
  var mains = file == null
      ? scenarioMains
      : {
          for (var entry in scenarioMains.entries)
            if (entry.key == file) entry.key: entry.value,
        };
  var root = _declare(mains, only: only);

  var outcomes = <Map<String, Object?>>[];
  var watch = Stopwatch()..start();

  Future<void> walk(Group group, Suite suite, String? groupFile) async {
    for (var entry in group.entries) {
      switch (entry) {
        case Test():
          outcomes.add(
            await _runOne(
              entry.load(suite, groups: [group]),
              file: groupFile ?? '',
              name: _leafName(entry, group),
              inspector: inspector,
              outDir: outDir,
            ),
          );
        case Group():
          await walk(entry, suite, groupFile ?? entry.name);
        case GroupEntry():
          break;
      }
    }
  }

  var suite = Suite(root, SuitePlatform(Runtime.vm));
  // Read by `scenario()` inside each test body, applied through the binding's
  // own test values, reset by its tearDown — the run-args zone of the design.
  scenarioRunArgs = runArgs;
  try {
    await walk(root, suite, null);
  } finally {
    scenarioRunArgs = null;
  }

  return {'ms': watch.elapsedMilliseconds, 'scenarios': outcomes};
}

Future<Map<String, Object?>> _runOne(
  LiveTest live, {
  required String file,
  required String name,
  required GuestInspector inspector,
  required String outDir,
}) async {
  var steps = <Map<String, Object?>>[];
  var directory = Directory('$outDir/${_fileSafe(file)}/${_fileSafe(name)}')
    ..createSync(recursive: true);

  scenarioRunListener = (capture) {
    var base =
        '${directory.path}/${capture.index}-'
        '${_fileSafe(capture.name ?? 'step ${capture.index}')}';
    File('$base.png').writeAsBytesSync(capture.png);
    // The tree next to the pixels — the step triple's third leg. Written to a
    // file rather than inlined: a run's response stays readable, and the tree
    // is fetched per step by whoever wants it.
    var tree = inspector.read().toJson();
    File('$base.tree.json').writeAsStringSync(jsonEncode(tree));
    steps.add({
      'index': capture.index,
      if (capture.name != null) 'name': capture.name,
      'auto': capture.name == null,
      if (capture.tags.isNotEmpty) 'tags': capture.tags,
      'png': '$base.png',
      'tree': '$base.tree.json',
      'texts': capture.texts,
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
    'ok': passed,
    'ms': watch.elapsedMilliseconds,
    'steps': steps,
    if (!passed) 'errors': errors,
  };
}

String _fileSafe(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

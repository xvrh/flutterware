import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:test_api/src/backend/declarer.dart';
import 'package:test_api/src/backend/group.dart';
import 'package:test_api/src/backend/group_entry.dart';
import 'package:test_api/src/backend/live_test.dart';
import 'package:test_api/src/backend/message.dart';
import 'package:test_api/src/backend/runtime.dart';
import 'package:test_api/src/backend/suite.dart';
import 'package:test_api/src/backend/suite_platform.dart';
import 'package:test_api/src/backend/test.dart';

import '../devices.dart';
import '../inspect/guest_inspect.dart';
import 'async_watchdog.dart';
import 'events.dart';
import 'fonts.dart';
import 'motion.dart';
import 'profile.dart';
import 'run_args.dart';
import 'scenario.dart';
import 'run_listener.dart';
import '../inspect/semantics_capture.dart';
import '../translations/index.dart';

// ignore_for_file: implementation_imports

/// How many event summaries ride inline on a step. The full list is always on
/// disk beside the pixels; this is the part a reader gets without asking, and
/// a screen that logs in a build method must not turn one step's record into
/// a wall.
const _maxInlineTitles = 12;

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
/// flutterware's job, not every user's (S4's fonts finding). [runScenarios]
/// does the same for the `flutter test` lane, so the two agree about how wide
/// a line of text is.
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
  // Declared before anything is, because `scenario()` reads it as it declares.
  // Without this the harness's deadline is dead letter: `testWidgets` stamps
  // the binding's ten minutes on every test, `Timeout.apply` honours it, and
  // a wedged scenario takes ten real minutes to be called wedged.
  scenarioDefaultTimeout = const Timeout(_defaultScenarioTimeout);
  var fonts = await loadScenarioFonts();

  // **The runner's own lane has to arm the index itself.** `runScenarios` also
  // sets this, but under the harness that call is a *probe*: it returns as soon
  // as it has handed back the folder's profile, before it reaches the flag. So
  // the one line there covered a bare `flutter test` and nothing else, and a
  // project with the seam wired saw every export come back empty. It costs
  // nothing when no catalog is registered — the walk reads the flag and
  // returns — which is why it is on here rather than behind a request field.
  TranslationIndex.recording = true;

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
        // Travels as an axis rather than baked into the geometry above,
        // because the device it applies to may still be undecided: when the
        // folder's profile is the one that picks, the rotation has to happen
        // in here, after it has spoken.
        orientation: switch (args['orientation']) {
          null => null,
          var name => orientationById(name),
        },
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

  @override
  TestDefaultBinaryMessenger createBinaryMessenger() =>
      _SpyMessenger(super.createBinaryMessenger());

  // Watched at the binding rather than only at `s.runAsync`, because the whole
  // point of `s.tester` is that a scenario may reach past us — and a
  // `tester.runAsync` that wedges takes the run down just as quietly.
  @override
  Future<T?> runAsync<T>(Future<T> Function() callback) =>
      watchRunAsync(() => super.runAsync(callback));
}

/// Every platform message, as a transition event.
///
/// Under the test binding all channel traffic passes through the messenger the
/// binding constructs, so this is where a plugin's conversation with its host
/// becomes visible with no cooperation from the app. What it does *not* see is
/// traffic that never happens: a plugin whose platform interface is gated on
/// the dart plugin registrant (sqflite) throws before sending, and an ffi
/// implementation never sends at all
/// (`2026-08-11-scenario-events-spike-findings.md`).
class _SpyMessenger extends TestDefaultBinaryMessenger {
  /// The configured messenger becomes the **delegate**, not the donor.
  ///
  /// It carries outbound handlers the binding installed — `flutter/keyboard`
  /// among them — and those are private. Rebuilding around its `delegate`
  /// instead drops them, `getKeyboardState` then goes to the engine, is never
  /// answered, and every run hangs. Measured, at length, by the spike.
  _SpyMessenger(super.inner);

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    var system = channel.startsWith('flutter/');
    var call = _decode(message);
    recordScenarioEvent(
      ScenarioEvent.custom(
        channel: system ? ScenarioChannel.system : ScenarioChannel.platform,
        title: call == null ? channel : '$channel ${call.method}',
        detail: call == null ? '${message?.lengthInBytes ?? 0} bytes' : null,
        data: _arguments(call),
      ),
    );
    var result = super.send(channel, message);
    if (system) return result;
    // Replies are recorded only when they say something went wrong. A
    // successful envelope in a widget test is either empty or a mock's canned
    // value — the spike measured nine identical 6-byte success envelopes from
    // one `enterText` — and a channel with nobody on the other end is the
    // "your fake is not wired" diagnostic worth keeping.
    result?.then(
      (reply) {
        if (reply == null) {
          recordScenarioEvent(
            ScenarioEvent.custom(
              channel: ScenarioChannel.platform,
              title: '$channel — no implementation',
              detail: call?.method,
              error: true,
            ),
          );
          return;
        }
        try {
          const StandardMethodCodec().decodeEnvelope(reply);
        } catch (error) {
          recordScenarioEvent(
            ScenarioEvent.custom(
              channel: ScenarioChannel.platform,
              title: '$channel ${call?.method ?? ''} failed'.trim(),
              body: '$error',
              error: true,
            ),
          );
        }
      },
      onError: (Object error) => recordScenarioEvent(
        ScenarioEvent.custom(
          channel: ScenarioChannel.platform,
          title: '$channel ${call?.method ?? ''} threw'.trim(),
          body: '$error',
          error: true,
        ),
      ),
    );
    return result;
  }

  /// The two codecs the framework and its plugins actually use, in the order
  /// they are common. A message neither decodes is reported by its size —
  /// binary payloads (`flutter/assets`) have nothing else to say.
  MethodCall? _decode(ByteData? message) {
    if (message == null) return null;
    try {
      return const StandardMethodCodec().decodeMethodCall(message);
    } catch (_) {
      try {
        return const JSONMethodCodec().decodeMethodCall(message);
      } catch (_) {
        return null;
      }
    }
  }

  Map<String, Object?> _arguments(MethodCall? call) =>
      switch (call?.arguments) {
        null => const {},
        Map<Object?, Object?> map => {
          for (var entry in map.entries) '${entry.key}': entry.value,
        },
        var other => {'arguments': other},
      };
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
              'orientations': [for (var o in profile.orientations) o.name],
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
  // What the request *named*, kept beside the numbers it resolved to: the
  // body reads its axes off `s.assignment`, and both lanes have to answer the
  // same there. An unspecified device stays out — the geometry that arrived
  // with it is only the host's fallback, and the folder's profile may yet
  // speak (see `ScenarioRunArgs.withDevice`).
  var assignment = ScenarioAssignment(
    device: args['deviceUnspecified'] == 'true'
        ? null
        : deviceById(args['device'] ?? ''),
    orientation: switch (args['orientation']) {
      null => null,
      var name => orientationById(name),
    },
    language: args['language'],
  );
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
    record: switch (number('recordIntervalMs')) {
      null => null,
      var interval => MotionRecording(
        interval: Duration(microseconds: (interval * 1000).round()),
        scale: number('recordScale'),
        maxFrames: number('recordMaxFrames')?.round() ?? 90,
      ),
    },
    clockOrigin: switch (args['clock']) {
      null => null,
      var raw => DateTime.parse(raw),
    },
    assignment: assignment.isEmpty ? null : assignment,
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
      runArgs.record == null &&
      runArgs.clockOrigin == null &&
      runArgs.assignment == null;
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
  ScreenOrientation? orientation,
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
          (runArgs ?? const ScenarioRunArgs()).withDevice(
            chosen,
            orientation: orientation,
          ),
          chosen.id,
        );
      });

  /// Set when a scenario blew its deadline: the walk unwinds, and the report
  /// says the run stopped rather than that the rest passed.
  var abandoned = false;

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
      if (abandoned) return;
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
          var outcome = await _runOne(
            entry.load(suite, groups: scope),
            file: groupFile ?? '',
            name: name,
            device: framedDevice,
            inspector: inspector,
            outDir: outDir,
          );
          outcomes.add(outcome);
          // A scenario that timed out is still running in there, holding the
          // binding — the next one would fail on its leftovers and blame
          // itself. So the walk stops and the run answers with what it has,
          // which is the point of having a deadline at all.
          if (outcome['timedOut'] == true) {
            abandoned = true;
            return;
          }
        case Group():
          if (setUpAllError == null) {
            await walk(entry, suite, scope, groupFile ?? entry.name);
          }
        case GroupEntry():
          break;
      }
    }

    // Cleanup is skipped only here, and for the one reason that outranks it:
    // a `tearDownAll` runs on the binding the abandoned scenario is still
    // holding, so it is as likely to hang as to clean up — and the guest is
    // being thrown away regardless.
    if (group.tearDownAll case var hook? when !abandoned) {
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

  return {
    'ms': watch.elapsedMilliseconds,
    'scenarios': outcomes,
    // Says the list is short because the run stopped, not because that was
    // everything — and tells the host its guest is spent.
    if (abandoned) 'abandoned': true,
  };
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
    'stack': ?(escapedStack ?? error?.stackTrace)?.toString(),
  };
}

/// Whether the binding's manufactured "Multiple exceptions (N)…" details is
/// fully covered by what the scenario buffered — by count when the sentence
/// carries one, by identity for anything else the binding hands over without
/// a stack.
bool _accountsFor(
  FlutterErrorDetails details,
  List<ScenarioCaughtError> caught,
) {
  var counted = RegExp(
    r'^Multiple exceptions \((\d+)\) were detected',
  ).firstMatch(details.exceptionAsString());
  if (counted != null) return int.parse(counted.group(1)!) <= caught.length;
  return caught.any((c) => identical(c.exception, details.exception));
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
  var directory = Directory('$outDir/${scenarioFileSafe(file)}/${scenarioFileSafe(name)}')
    ..createSync(recursive: true);
  // Each step's tree as written, kept for one comparison: a verb whose tree
  // is byte-identical to its parent's changed nothing on screen, which is
  // what a stalled walk looks like from the inside — no exception, no failed
  // matcher, and (measured on a consumer suite) seven identical captures
  // passing as seven pages. By parent rather than by predecessor, so a
  // `split`'s branches each compare against the step they actually follow.
  var treeByIndex = <int, String>{};
  // Per scenario, so the read set below belongs to *one* assignment. A matrix
  // runs its locales sequentially in one process, and an index carried across
  // them would report the last locale's value for every key — which is exactly
  // the value the falling-back-to-the-template report has to compare against.
  TranslationIndex.reset();

  scenarioRunListener = (capture) {
    // The verb and what it was aimed at, which is what an automatic capture
    // is called now that it is not called `step 3`.
    var did = [?capture.verb, ?capture.target].join(' ').trim();
    var label = capture.name ?? (did.isEmpty ? 'step ${capture.index}' : did);
    // The stem shares its component with the index that precedes it and the
    // suffix that follows, so what is left over is what the label may use.
    var prefix = '${capture.index}-';
    var base =
        '${directory.path}/$prefix'
        '${scenarioFileSafe(capture.failure != null ? 'failed' : label, max: scenarioNameMax - prefix.length - _longestStepSuffix.length)}';
    var imagePath = '$base.${capture.format == 'raw' ? 'raw' : 'png'}';
    File(imagePath).writeAsBytesSync(capture.bytes);
    // The tree next to the pixels — the step triple's third leg. Written to a
    // file rather than inlined: a run's response stays readable, and the tree
    // is fetched per step by whoever wants it.
    var read = inspector.read();
    var tree = read.toJson();
    var treeJson = jsonEncode(tree);
    File('$base.tree.json').writeAsStringSync(treeJson);
    // Only a verb that acts can be told it acted for nothing: a `screen` is
    // a deliberate second picture of the same frame, and a failure's capture
    // already says everything. The flag is a fact, not a verdict — a capture
    // parked mid-flight with `Settle.none` is legitimately unchanged.
    var unchanged =
        capture.verb != null &&
        capture.verb != 'screen' &&
        capture.failure == null &&
        treeByIndex[capture.parent] == treeJson;
    treeByIndex[capture.index] = treeJson;
    // The seventh, and only when a catalog was wired up: which translation
    // keys this screen shows and where. Flattened out of the tree it was just
    // read from — an export asking "which screens show this key" should not
    // have to parse every node of every step to find out.
    var keys = read.translationKeys();
    var unkeyed = read.unkeyedText();
    if (keys.isNotEmpty || unkeyed.isNotEmpty) {
      File('$base.keys.json').writeAsStringSync(
        jsonEncode({
          'keys': [for (var key in keys) key.toJson()],
          if (unkeyed.isNotEmpty)
            'unkeyed': [for (var text in unkeyed) text.toJson()],
        }),
      );
    }
    // And the fourth: what a screen reader gets. Absent rather than empty
    // when there is no semantics tree to read — which under `testWidgets`'s
    // default handle is never, but a capture must not invent a screen.
    var semantics = captureSemanticsTree();
    if (semantics != null) {
      File('$base.semantics.json').writeAsStringSync(jsonEncode(semantics));
    }
    // And the fifth: what the app *did* on the way to this frame. A file like
    // the trees, for the same reason — a run's response stays readable, and
    // the payloads are fetched by whoever opens the step. What rides in the
    // record is the digest.
    if (capture.events.isNotEmpty) {
      File('$base.events.json').writeAsStringSync(
        jsonEncode(
          [for (var event in capture.events) event.toJson()],
          // An event's payload is whatever the reporter had in hand — a
          // channel's decoded arguments, a fake's own objects — and the one
          // thing this may not do is throw. A viewer that cannot encode a
          // value shows what it printed as; a `JsonUnsupportedObjectError`
          // here would fail the step it was only describing.
          toEncodable: (value) => '$value',
        ),
      );
    }
    // And the sixth: what the transition *looked like*. A directory of
    // numbered frames rather than one blob, so a player can decode the frame
    // it is on and no other, and so the panel's ordinary image plumbing —
    // which already reads a step's pixels off disk — reads these unchanged.
    String? framesDir;
    if (capture.motion.hasMotion) {
      var directory = Directory('$base.frames')..createSync(recursive: true);
      var extension = capture.format == 'raw' ? 'raw' : 'png';
      for (var (index, frame) in capture.motion.bytes.indexed) {
        File(
          '${directory.path}/'
          '${index.toString().padLeft(4, '0')}.$extension',
        ).writeAsBytesSync(frame);
      }
      framesDir = directory.path;
    }
    // And the seventh: whatever the flow *produced* on the way here that is
    // not a widget. Files like the trees, and for a stronger version of the
    // same reason — a PDF has no business inside a JSON report, and what a
    // reader wants is to open it.
    var attachments = [
      for (var (index, attachment) in capture.attachments.indexed)
        () {
          var path =
              '$base.${scenarioAttachmentFileName(capture.attachments, index)}';
          File(path).writeAsBytesSync(attachment.bytes);
          return {
            'name': attachment.name,
            'file': path,
            'mimeType': ?attachment.mimeType,
            'bytes': attachment.bytes.length,
          };
        }(),
    ];
    var counts = <String, int>{};
    for (var event in capture.events) {
      counts[event.channel] = (counts[event.channel] ?? 0) + 1;
    }
    var step = {
      'index': capture.index,
      'position': capture.position,
      'parent': ?capture.parent,
      'branch': ?capture.branch,
      if (capture.name != null) 'name': capture.name,
      // How the target was named, beside the name itself: a comparison reads
      // it to know how far the label can be trusted, since visible text is
      // translated where a key is the author's own word.
      'auto': capture.name == null,
      if (capture.tags.isNotEmpty) 'tags': capture.tags,
      'image': imagePath,
      'format': capture.format,
      'width': capture.width,
      'height': capture.height,
      'tree': '$base.tree.json',
      if (keys.isNotEmpty) 'keys': '$base.keys.json',
      if (semantics != null) 'semantics': '$base.semantics.json',
      'texts': capture.texts,
      'statusBrightness': ?capture.statusBrightness,
      'navBrightness': ?capture.navBrightness,
      // The transition into this step: the verb that caused it, and what the
      // app did on the way.
      'verb': ?capture.verb,
      'target': ?capture.target,
      if (capture.events.isNotEmpty) ...{
        'events': '$base.events.json',
        'eventCount': capture.events.length,
        'eventChannels': counts,
        // The one-line summaries, inline and capped: the part an agent
        // reasons about without opening a file. `system` is left out — it is
        // the channel a reader filters away, and it is most of the volume.
        'eventTitles': [
          for (var event in capture.events)
            if (event.channel != ScenarioChannel.system)
              '${event.title}${event.detail == null ? '' : ' → ${event.detail}'}',
        ].take(_maxInlineTitles).toList(),
      },
      if (capture.eventsDropped > 0) 'eventsDropped': capture.eventsDropped,
      if (attachments.isNotEmpty) 'attachments': attachments,
      if (framesDir != null) ...{
        'frames': framesDir,
        'frameCount': capture.motion.bytes.length,
        'frameWidth': capture.motion.width,
        'frameHeight': capture.motion.height,
        // The fake milliseconds between two frames — what a player runs at to
        // show the animation at the speed the app would have played it.
        'frameIntervalMs': capture.motionInterval!.inMilliseconds,
        if (capture.motion.dropped > 0) 'framesDropped': capture.motion.dropped,
      },
      // All omitted in the healthy case, so a normal step's record stays the
      // size it was.
      if (!capture.settled) 'settled': false,
      if (!capture.landed) 'landed': false,
      if (capture.strayFrames > 0) 'strayFrames': capture.strayFrames,
      if (unchanged) 'unchanged': true,
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
    var caught = scenarioCaughtErrors ?? const [];
    if (details.stack == null && caught.isNotEmpty) {
      // A details with no stack is the binding's own manufacture — "Multiple
      // exceptions (2) were detected…", a count of what it declined to show.
      // The scenario buffered the real ones as they were reported; each gets
      // its own entry, message and stack intact. The manufactured sentence
      // survives only when the buffer cannot account for it — an exception
      // raised outside the body proper — because dropping an error the run
      // knows happened is worse than one vague line.
      for (var error in caught) {
        failures.add({
          'error': error.description,
          'stack': ?error.stack?.toString(),
        });
      }
      if (!_accountsFor(details, caught)) {
        failures.add({'error': details.exceptionAsString()});
      }
    } else {
      failures.add({
        'error': details.exceptionAsString(),
        'stack': ?details.stack?.toString(),
      });
    }
  };

  // The three automatic lanes, installed **here** and not around the scenario
  // body: out here it is ordinary async, once per run rather than once per
  // split replay. Inside the body they would be under FakeAsync, where
  // `await subscription.cancel()` never returns — cancel hands back a
  // root-zone future and the fake clock does not drain the real microtask
  // queue. That hangs the whole run, silently, including scenarios that log
  // nothing (`2026-08-11-scenario-events-spike-findings.md`).
  scenarioEventBuffer = ScenarioEventBuffer();
  scenarioCaughtErrors = [];
  var records = Logger.root.onRecord.listen(
    (record) => recordScenarioEvent(
      ScenarioEvent.log(
        record.message,
        level: record.level.name,
        logger: record.loggerName.isEmpty ? null : record.loggerName,
      ),
    ),
  );
  // Prints need no zone of ours. `test_api`'s Invoker already forks one with
  // its own print spec — which does not delegate upward, so a zone here would
  // see nothing — and republishes each line on this stream. Nobody used to
  // listen, which is why a `print` inside a scenario went nowhere at all.
  var messages = live.onMessage.listen((message) {
    // The stream also carries `skip` — the reason a skipped test gives — which
    // is a fact about the test, not something the app printed.
    if (message.type != MessageType.print) return;
    recordScenarioEvent(
      ScenarioEvent.custom(channel: ScenarioChannel.print, title: message.text),
    );
  });

  // What the scenario declared, over `flutter test`'s own default —
  // `scenario(timeout: Timeout(…))`, and `Timeout.none` to opt out entirely.
  var deadline = live.test.metadata.timeout.apply(_defaultScenarioTimeout);
  var watch = Stopwatch()..start();
  var timedOut = false;
  // Anything the previous scenario's watchdog left is that scenario's, and it
  // may not be quoted at this one.
  scenarioAsyncStall = null;
  try {
    var running = live.run();
    await (deadline == null ? running : running.timeout(deadline));
  } on TimeoutException {
    timedOut = true;
  } finally {
    await records.cancel();
    await messages.cancel();
    // Whatever the app did after the last capture goes with it: there is no
    // step for it to belong to, and inventing one would put teardown —
    // `TextInput.clearClient` and its like — on the flow.
    scenarioEventBuffer = null;
    scenarioCaughtErrors = null;
    reportTestException = priorReporter;
    scenarioRunListener = null;
  }

  var errors = [
    if (timedOut) {'error': _timedOutMessage(deadline!)},
    ...failures,
    for (var error in live.errors)
      {'error': '${error.error}', 'stack': '${error.stackTrace}'},
  ];
  var passed = !timedOut && live.state.result.isPassing && errors.isEmpty;
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
    // Every key every catalog was asked for on the way through this
    // scenario, and what it answered — **including the keys whose value never
    // reached a glyph.** The steps say where a key was *seen*; only this says
    // it was read at all, which is the difference between "not on this screen"
    // and "this product never asks for it". Written per scenario, merged
    // across the run by whoever reads them, because a key reached by one
    // scenario is reached.
    if (TranslationIndex.read case var read when read.isNotEmpty)
      'translations': read,
    // Read by the host, not by a reader: the body is still running in there,
    // so this harness is spent and the next run needs a fresh one.
    if (timedOut) 'timedOut': true,
  };
}

/// How long one scenario may take before the run gives up on it.
///
/// `package:test`'s own default, and reached through
/// [scenarioDefaultTimeout] — `testWidgets` stamps the binding's ten minutes
/// on anything that does not name a timeout, so a runner that wants a deadline
/// of its own has to say so as the scenario is declared. It exists because a
/// scenario that never returns used to take the **whole run** with it: every
/// scenario before it had written its artifacts and none of them were ever
/// reported, which is a worse answer than a red scenario by a wide margin.
///
/// A scenario that genuinely needs longer — a long matrix, a capture-heavy
/// flow at 3× — says `scenario(timeout: …)`, which the message below offers.
const _defaultScenarioTimeout = Duration(seconds: 30);

String _timedOutMessage(Duration deadline) {
  var why =
      scenarioAsyncStall ??
      'something is waiting on a real future no pump can complete: an '
          '`s.runAsync` that never returns, or a platform channel with nobody '
          'on the other end.';
  return 'the scenario did not finish within ${deadline.inSeconds}s. A '
      'scenario runs under fake time, so this is not slowness — $why The '
      'steps it captured before it stopped are on disk. Give it longer, or '
      'opt out, with `scenario(timeout: …)`.';
}

/// `NAME_MAX` — 255 bytes on APFS, ext4 and NTFS alike, and per path
/// *component* rather than per path.
const scenarioNameMax = 255;

/// The longest suffix a step writes under its own stem, so a label can be
/// budgeted against it. Attachments add a name the scenario chose and are not
/// budgeted for: nothing here can bound what a caller passes.
const _longestStepSuffix = '.semantics.json';

/// Sanitises [name] into one path component, and **caps it**.
///
/// The cap is why this exists rather than a bare `replaceAll`. An automatic
/// capture is labelled by its verb and its target, and a target given as a
/// `Finder` describes itself with the matched widget's whole `toString()` —
/// `TextStyle` dump included. That ran past `NAME_MAX` and threw
/// `FileSystemException`, failing a scenario that had in fact run: the work
/// was done, and only writing it down was impossible.
String scenarioFileSafe(String name, {int max = scenarioNameMax}) {
  var safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return safe.length <= max ? safe : safe.substring(0, max);
}

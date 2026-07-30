import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_core.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_results.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/scenarios/axes.dart';
import 'package:flutterware_app/src/scenarios/runner.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// The panel's run-state machinery — transitions, kept outcomes, artifact
/// cleanup — over a fake runner, because the real one's behaviour is already
/// covered end-to-end by `runner_test.dart` and a second cold `flutter_tester`
/// here would prove nothing new about state handling.
void main() {
  late Directory root;

  ScenariosCore core({_FakeRunner? runner}) {
    var worktree = Worktree(path: root.path);
    var subject = ScenariosCore(
      PluginHost(
        id: scenariosPluginId,
        label: 'Scenarios',
        worktree: worktree,
        workspace: Workspace(
          root: worktree.path,
          declared: [Pkg('.')],
          discovered: ['.'],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
        config: {
          'packages': [
            {'path': '.'},
          ],
        },
      ),
    );
    if (runner != null) subject.debugInstallRunner('.', runner);
    return subject;
  }

  Future<ScenarioPanelRun> settled(ScenariosCore subject) async {
    while (true) {
      var run = subject.panelRunFor(
        '.',
        file: 'test/scenarios/a_test.dart',
        scenario: 'A',
      );
      if (run != null && !run.running) return run;
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  void start(ScenariosCore subject) =>
      subject.startRun('.', file: 'test/scenarios/a_test.dart', scenario: 'A');

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_scenarios_core_test');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('a run lands as the outcome, with its artifact directory', () async {
    var runner = _FakeRunner();
    var subject = core(runner: runner);
    start(subject);
    expect(
      subject
          .panelRunFor('.', file: 'test/scenarios/a_test.dart', scenario: 'A')!
          .running,
      isTrue,
    );
    expect(subject.anyPanelRunning, isTrue);

    var run = await settled(subject);
    expect(run.error, isNull);
    expect(run.outcome!.ok, isTrue);
    expect(run.outcome!.steps.single.texts, ['hello']);
    expect(run.output, isNotNull);
    expect(runner.runs, 1);
    expect(subject.anyPanelRunning, isFalse);
  });

  test('a re-run clears immediately; a failed one keeps its error and '
      'whatever it captured', () async {
    var runner = _FakeRunner();
    var subject = core(runner: runner);
    start(subject);
    await settled(subject);

    runner.failure = 'the harness does not compile';
    runner.gate = Completer<void>();
    start(subject);
    // The immediate clear: the page never shows the previous run's pictures
    // under this run's spinner.
    var during = subject.panelRunFor(
      '.',
      file: 'test/scenarios/a_test.dart',
      scenario: 'A',
    )!;
    expect(during.running, isTrue);
    expect(during.steps, isEmpty);
    expect(during.outcome, isNull);

    runner.gate!.complete();
    var second = await settled(subject);
    expect(second.error, contains('does not compile'));
    expect(second.outcome, isNull);
  });

  test(
    'steps stream into the running state as the harness announces them',
    () async {
      var runner = _FakeRunner()
        ..gate = Completer<void>()
        ..emitSteps = true;
      var subject = core(runner: runner);
      start(subject);

      // The fake announced step 0 and is now gated mid-run: the state already
      // holds the step, before any response.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      var during = subject.panelRunFor(
        '.',
        file: 'test/scenarios/a_test.dart',
        scenario: 'A',
      )!;
      expect(during.running, isTrue);
      expect(during.steps, hasLength(1));
      expect(during.steps.single.texts, ['hello']);
      expect(during.steps.single.address, contains('/a_test.dart/A/0'));

      runner.gate!.complete();
      var final_ = await settled(subject);
      expect(final_.outcome, isNotNull);
      expect(final_.steps, hasLength(1));
    },
  );

  test('a superseding run deletes the previous artifacts', () async {
    var runner = _FakeRunner();
    var subject = core(runner: runner);
    start(subject);
    var first = await settled(subject);
    var oldDir = Directory(first.output!)..createSync(recursive: true);

    // Same-millisecond runs would share the directory name; nudge past it.
    await Future<void>.delayed(const Duration(milliseconds: 2));
    start(subject);
    var second = await settled(subject);
    expect(second.output, isNot(first.output));
    expect(oldDir.existsSync(), isFalse);
  });

  test('starting while running is a no-op', () async {
    var runner = _FakeRunner()..gate = Completer<void>();
    var subject = core(runner: runner);
    start(subject);
    start(subject);
    start(subject);
    runner.gate!.complete();
    await settled(subject);
    expect(runner.runs, 1);
  });

  test('the run action carries its axes into the runner, the result and '
      'every step address', () async {
    var runner = _FakeRunner();
    var subject = core(runner: runner);
    var result =
        (await subject.invoke(
              'run',
              arguments: {
                'package': '.',
                'file': 'test/scenarios/a_test.dart',
                'scenario': 'A',
                'device': 'iphone-se',
                'language': 'fr-CA',
                'text-scale': '1.3',
                'brightness': 'dark',
              },
            ))!
            as ScenarioRunResult;

    expect(
      runner.seenAxes.single,
      const ScenarioAxes(
        device: 'iphone-se',
        language: 'fr-CA',
        textScale: 1.3,
        brightness: 'dark',
      ),
    );
    expect(result.axes, {
      'device': 'iphone-se',
      'language': 'fr-CA',
      'text-scale': '1.3',
      'brightness': 'dark',
    });
    var address = result.packages.single.scenarios.single.steps.single.address;
    expect(address, contains('device=iphone-se'));
    expect(address, contains('brightness=dark'));
  });

  test('the run action refuses axes it does not know', () async {
    var subject = core(runner: _FakeRunner());
    Future<Object?> run(Map<String, Object?> arguments) =>
        subject.invoke('run', arguments: {'package': '.', ...arguments});
    await expectLater(run({'device': 'iphone-99'}), throwsArgumentError);
    await expectLater(run({'brightness': 'dim'}), throwsArgumentError);
    await expectLater(run({'text-scale': 'big'}), throwsArgumentError);
    await expectLater(run({'language': 'not a tag'}), throwsArgumentError);
    await expectLater(run({'bold-text': 'maybe'}), throwsArgumentError);
  });

  test('the device defaults to the phone form factor; fit is the bare '
      'surface', () async {
    var runner = _FakeRunner();
    var subject = core(runner: runner);
    Future<void> run(Map<String, Object?> arguments) async {
      await subject.invoke(
        'run',
        arguments: {
          'package': '.',
          'file': 'test/scenarios/a_test.dart',
          'scenario': 'A',
          ...arguments,
        },
      );
    }

    await run({});
    expect(runner.seenAxes.last.device, 'iphone-13');
    await run({'device': 'fit'});
    expect(runner.seenAxes.last.device, isNull);
  });

  test('the accessibility switches travel as axes', () async {
    var runner = _FakeRunner();
    var subject = core(runner: runner);
    var result =
        (await subject.invoke(
              'run',
              arguments: {
                'package': '.',
                'file': 'test/scenarios/a_test.dart',
                'scenario': 'A',
                'bold-text': 'true',
                'high-contrast': 'true',
              },
            ))!
            as ScenarioRunResult;
    expect(runner.seenAxes.last.boldText, isTrue);
    expect(runner.seenAxes.last.highContrast, isTrue);
    expect(runner.seenAxes.last.invertColors, isFalse);
    expect(result.axes!['bold-text'], 'true');
    expect(result.axes!['high-contrast'], 'true');
    expect(result.axes!.containsKey('invert-colors'), isFalse);
  });
}

class _FakeRunner extends ScenarioRunner {
  _FakeRunner()
    : super(packageRoot: '/none', directory: 'none', flutterSdkRoot: '/none');

  var runs = 0;
  String? failure;
  final seenAxes = <ScenarioAxes>[];

  /// When set, [run] waits on it — so a test can observe the running state.
  Completer<void>? gate;

  /// Announce each step through [onStep] before returning, as the real
  /// runner's VM-service subscription does.
  var emitSteps = false;

  @override
  Future<Map<String, Object?>> run({
    required String outDir,
    String? file,
    String? scenario,
    ScenarioAxes axes = const ScenarioAxes(),
    double? captureScale,
  }) async {
    runs++;
    seenAxes.add(axes);
    var step = {
      'index': 0,
      'name': 'shot',
      'auto': false,
      'png': '$outDir/0-shot.png',
      'tree': '$outDir/0-shot.tree.json',
      'texts': ['hello'],
    };
    if (emitSteps) {
      onStep?.call({'file': file, 'scenario': scenario, 'step': step});
    }
    if (gate case var gate?) await gate.future;
    if (failure case var failure?) throw StateError(failure);
    return {
      'ms': 5,
      'scenarios': [
        {
          'file': file,
          'name': scenario,
          'ok': true,
          'ms': 3,
          'steps': [step],
        },
      ],
    };
  }

  @override
  Future<void> dispose() async {}
}

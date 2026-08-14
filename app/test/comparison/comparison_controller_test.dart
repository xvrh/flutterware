import 'dart:async';

import 'package:flutterware_app/src/comparison/artifact.dart';
import 'package:flutterware_app/src/comparison/channels.dart';
import 'package:flutterware_app/src/comparison/comparison_controller.dart';
import 'package:flutterware_app/src/comparison/runner.dart';
import 'package:flutterware_app/src/comparison/scenario_comparison.dart';
import 'package:flutterware_app/src/comparison/shot_cache.dart';
import 'package:test/test.dart';

/// The sequencing: the base is prepared on the panel, a half runs on its tab.
///
/// Driven through a fake environment, because none of this needs a compiler, a
/// guest or a git worktree to be wrong.
void main() {
  late _FakeEnvironment environment;
  late ComparisonController controller;

  setUp(() {
    environment = _FakeEnvironment();
    controller = ComparisonController(environment);
  });
  tearDown(() => controller.dispose());

  group('preparing', () {
    // **The panel builds this and then leaves it alone.** Opening the Changes
    // screen used to prepare the base and price both tabs; on a real catalog
    // that was minutes of git, `pub get` and sha1 charged to somebody who came
    // to read a diff. Nothing is owed until a tab is opened.
    test('building it touches nothing', () async {
      await pumpEventQueue();

      expect(environment.prepared, 0);
      expect(environment.ranPreviews, 0);
      expect(environment.ranScenarios, 0);
      expect(controller.baseRoot, isNull);
    });

    // The panel does not call this any more — `open` does, on its way to
    // running one half. What it still has to guarantee is that materialising
    // the base runs neither.
    test('preparing readies both halves and runs neither', () async {
      await controller.prepare();

      expect(controller.previews.stage, HalfStage.ready);
      expect(controller.scenarios.stage, HalfStage.ready);
      expect(environment.ranPreviews, 0);
      expect(environment.ranScenarios, 0);
    });

    test('arriving twice prepares once', () async {
      await Future.wait([controller.prepare(), controller.prepare()]);
      await controller.prepare();

      expect(environment.prepared, 1);
    });

    test('a base that will not check out refuses both halves', () async {
      environment.baseError = 'fatal: invalid reference: nope';

      await controller.prepare();

      expect(controller.refusal, contains('invalid reference'));
      expect(controller.previews.stage, HalfStage.refused);
      expect(controller.scenarios.stage, HalfStage.refused);
    });

    // An SDK mismatch refuses at plan time, and the plan is per half — so it
    // should stop that tab rather than the panel.
    test('one half refusing leaves the other alone', () async {
      environment.previewsRunError = 'two checkouts on different SDKs';

      await controller.open(ComparisonHalfKind.previews);

      expect(controller.previews.stage, HalfStage.refused);
      expect(controller.previews.refusal, contains('different SDKs'));
      expect(controller.scenarios.stage, HalfStage.ready);
    });

    test('a half whose plugin is not declared has no tab', () {
      var only = ComparisonController(_FakeEnvironment()..hasScenarios = false);
      addTearDown(only.dispose);

      expect(only.scenarios.stage, HalfStage.undeclared);
      expect(only.declared.map((h) => h.kind), [ComparisonHalfKind.previews]);
    });
  });

  group('opening a tab', () {
    test('opening runs only that half', () async {
      await controller.open(ComparisonHalfKind.previews);

      expect(environment.ranPreviews, 1);
      expect(environment.ranScenarios, 0);
      expect(controller.previews.stage, HalfStage.done);
      expect(controller.scenarios.stage, HalfStage.ready);
    });

    test('opening prepares first, so a tab is enough on its own', () async {
      await controller.open(ComparisonHalfKind.scenarios);

      expect(environment.prepared, 1);
      expect(controller.scenarios.scenarioResults, isNotNull);
    });

    // Clicking back and forth between two tabs is a thing people do, and a
    // comparison that restarted on each visit would never finish one.
    test('a run already in flight is joined, not restarted', () async {
      var gate = Completer<void>();
      environment.previewsGate = gate;

      var first = controller.open(ComparisonHalfKind.previews);
      var second = controller.open(ComparisonHalfKind.previews);
      gate.complete();
      await Future.wait([first, second]);

      expect(environment.ranPreviews, 1);
    });

    test('a half that has run is not run again on the way back', () async {
      await controller.open(ComparisonHalfKind.previews);
      await controller.open(ComparisonHalfKind.previews);

      expect(environment.ranPreviews, 1);
    });

    test('a half that refused is not attempted again', () async {
      environment.previewsRunError = 'two checkouts on different SDKs';
      await controller.open(ComparisonHalfKind.previews);
      environment.previewsRunError = null;

      await controller.open(ComparisonHalfKind.previews);

      expect(environment.ranPreviews, 1);
      expect(controller.previews.stage, HalfStage.refused);
    });

    test('a run that throws becomes the tab reason, not a crash', () async {
      environment.scenariosRunError = 'The scenario harness does not compile';

      await controller.open(ComparisonHalfKind.scenarios);

      expect(controller.scenarios.stage, HalfStage.refused);
      expect(controller.scenarios.refusal, contains('does not compile'));
    });
  });

  group('rows as they land', () {
    test('a row is visible before the run finishes', () async {
      var gate = Completer<void>();
      environment
        ..previewsGate = gate
        ..streamRows = [
          const ComparedItem(id: 'demo/a.dart#a', state: ComparedState.changed),
        ];

      var running = controller.open(ComparisonHalfKind.previews);
      await pumpEventQueue();

      expect(controller.previews.isRunning, isTrue);
      expect(controller.previews.rows, hasLength(1));
      gate.complete();
      await running;
    });

    // The top row should be the thing most likely to be a mistake, whatever
    // order the renders happened to finish in.
    test('rows sort worst first as they arrive', () async {
      environment.streamRows = [
        const ComparedItem(id: 'z', state: ComparedState.same),
        const ComparedItem(id: 'a', state: ComparedState.changed),
        const ComparedItem(id: 'm', state: ComparedState.broke),
      ];

      await controller.open(ComparisonHalfKind.previews);

      expect(controller.previews.rows.map((r) => r.id), ['m', 'a', 'z']);
    });

    test('scenarios sort worst first too', () async {
      environment.streamScenarios = [
        _scenario('z', ComparedState.same),
        _scenario('a', ComparedState.broke),
      ];

      await controller.open(ComparisonHalfKind.scenarios);

      expect(controller.scenarios.scenarios.map((s) => s.scenario), ['a', 'z']);
    });
  });

  group('refresh', () {
    // The reason you are refreshing is that the worktree moved, so whatever
    // the half concluded last time is thrown away and the run happens again.
    test('it runs again', () async {
      await controller.open(ComparisonHalfKind.previews);

      await controller.refresh(ComparisonHalfKind.previews);

      expect(environment.ranPreviews, 2);
      expect(controller.previews.stage, HalfStage.done);
    });

    test('refreshing one half leaves the other where it was', () async {
      await controller.open(ComparisonHalfKind.scenarios);

      await controller.refresh(ComparisonHalfKind.scenarios);

      expect(environment.ranPreviews, 0);
    });
  });

  test('the artifact is both halves once the previews half has run', () async {
    expect(controller.artifact, isNull);

    await controller.open(ComparisonHalfKind.previews);
    await controller.open(ComparisonHalfKind.scenarios);

    expect(controller.artifact, isA<ComparisonArtifact>());
    expect(controller.artifact!.scenarios, isNotNull);
  });
}

ScenarioComparison _scenario(String id, ComparedState state) =>
    ScenarioComparison.notRun(scenario: id, state: state);

/// A comparison's world, with nothing behind it.
class _FakeEnvironment implements ComparisonEnvironment {
  @override
  String get headRoot => '/work/head';

  @override
  String get baseLabel => 'master';

  @override
  var hasPreviews = true;

  @override
  var hasScenarios = true;

  @override
  final shots = ShotCache('/unused');

  String? baseError;
  String? previewsRunError;
  String? scenariosRunError;

  /// Held open so a test can look at a half mid-run.
  Completer<void>? previewsGate;

  List<ComparedItem> streamRows = const [];
  List<ScenarioComparison> streamScenarios = const [];

  var prepared = 0;
  var ranPreviews = 0;
  var ranScenarios = 0;

  @override
  Future<String> prepareBase() async {
    prepared++;
    if (baseError case var error?) throw StateError(error);
    return '/work/base';
  }

  @override
  Future<ComparisonResult> runPreviews(
    String baseRoot, {
    required void Function(ComparedItem row) onRow,
  }) async {
    ranPreviews++;
    if (previewsRunError case var error?) throw StateError(error);
    for (var row in streamRows) {
      onRow(row);
    }
    await previewsGate?.future;
    return ComparisonResult(
      items: streamRows,
      baseSha: 'abc123',
      headRoot: headRoot,
      elapsed: Duration.zero,
      rendered: 0,
    );
  }

  @override
  Future<ScenarioResults> runScenarios(
    String baseRoot, {
    required void Function(ScenarioComparison scenario) onScenario,
  }) async {
    ranScenarios++;
    if (scenariosRunError case var error?) throw StateError(error);
    for (var scenario in streamScenarios) {
      onScenario(scenario);
    }
    return ScenarioResults.of(
      items: streamScenarios,
      ran: 0,
      skipped: 0,
      elapsed: Duration.zero,
    );
  }
}

import 'package:path/path.dart' as p;

import '../scenarios/runner.dart';
import 'artifact.dart';
import 'cancel.dart';
import 'channels.dart';
import 'import_graph.dart';
import 'scenario_comparison.dart';
import 'scenarios_side.dart';
import 'shot_cache.dart';
import 'skip.dart';

/// One side-pair of scenarios, as the runner needs to talk to them.
///
/// The twin of `ComparisonSide`, and it exists for the same reason that one
/// does: the orchestration — which scenario is new, what the closure says
/// nothing touched, what order rows rank in — is most of the risk here and
/// none of it needs a `flutter_tester`, a harness build or a Flutter SDK to be
/// wrong. A fake source makes all of that testable in milliseconds, which the
/// version of this that lived inside `fw compare` never was.
abstract interface class ScenarioSource {
  /// Every scenario id one side declares.
  Future<List<String>> list({required bool base});

  /// Where a scenario's source lives, relative to a checkout root.
  String fileOf(String id);

  /// Replays [id] on one side and reads back every step it captured.
  Future<List<ScenarioStepShot>> shots(
    String id, {
    required bool base,
    required String outDir,
  });

  /// Releases both harnesses.
  Future<void> dispose();
}

/// The real thing: a [ScenariosSide] with a live runner bound to each checkout.
///
/// Owns the two runners, so a caller cannot forget to dispose one — which is
/// two `flutter_tester` processes and a build directory each.
class LiveScenarioSource implements ScenarioSource {
  LiveScenarioSource({
    required this.side,
    required String headRoot,
    required String baseRoot,
  }) : _head = side.runnerFor(headRoot),
       _base = side.runnerFor(baseRoot);

  final ScenariosSide side;
  final ScenarioRunner _head;
  final ScenarioRunner _base;

  ScenarioRunner _runner({required bool base}) => base ? _base : _head;

  @override
  Future<List<String>> list({required bool base}) =>
      side.scenarios(_runner(base: base));

  @override
  String fileOf(String id) => side.fileOf(id);

  @override
  Future<List<ScenarioStepShot>> shots(
    String id, {
    required bool base,
    required String outDir,
  }) => side.run(
    _runner(base: base),
    id,
    outDir: p.join(outDir, base ? 'base' : 'head'),
  );

  @override
  Future<void> dispose() async {
    await _head.dispose();
    await _base.dispose();
  }
}

/// What the scenario half already knows before it replays anything.
///
/// The twin of `ComparisonPlan`, and it costs the same nothing: two harness
/// listings and a sha1 per file in each scenario's closure.
class ScenariosPlan {
  const ScenariosPlan({
    required this.settled,
    required this.toRun,
    required this.total,
  });

  /// Scenarios answered without replaying: added, removed, skipped.
  final List<ScenarioComparison> settled;

  /// The ids that have to be replayed on both sides.
  final List<String> toRun;

  final int total;
}

/// Runs the scenario half: decide, replay what is left, align, report.
///
/// **Lifted out of `fw compare`, where it was the only copy.** The GUI needs
/// the same decisions the CLI makes, and a second implementation of those in a
/// panel is two answers to one question. It mirrors `ComparisonRunner`
/// deliberately, down to [plan] and [run], because a caller holding both halves
/// should not have to hold two shapes.
class ScenariosRunner {
  ScenariosRunner({
    required this.headRoot,
    required this.baseRoot,
    required this.source,
    required this.cache,
    this.pixels,
    this.only,
    this.onScenario,
    this.onPlan,
    this.onProgress,
    this.cancel,
  });

  final String headRoot;
  final String baseRoot;
  final ScenarioSource source;
  final ShotCache cache;

  /// The pixel inputs the closure does not name — see [PixelInputs]. A
  /// parameter rather than derived here because [source] deliberately hides
  /// where the package lives.
  final PixelInputs? pixels;

  /// Compare only these scenario ids.
  final List<String>? only;

  /// Called as each scenario is decided, so a panel can fill a list in rather
  /// than wait for the slowest replay.
  final void Function(ScenarioComparison scenario)? onScenario;

  /// Called once the plan is made — how many scenarios there are, and which
  /// still owe a replay.
  final void Function(ScenariosPlan plan)? onPlan;

  /// One sentence of what the run is doing right now, replaced as it moves.
  final void Function(String phase)? onProgress;

  /// Checked between replays — a scenario is a process, and stopping takes
  /// effect at the next one.
  final CancelToken? cancel;

  Future<ScenariosPlan> plan({ImportGraph? graph}) async {
    // The listing is the expensive-looking part of a scenario plan: each side
    // answers from a live harness, so the first ask builds and boots one.
    onProgress?.call('listing the scenarios on both sides');
    var headIds = await source.list(base: false);
    cancel?.check();
    var baseIds = await source.list(base: true);
    cancel?.check();
    if (only case var only?) {
      headIds = [
        for (var id in headIds)
          if (only.contains(id)) id,
      ];
      baseIds = [
        for (var id in baseIds)
          if (only.contains(id)) id,
      ];
    }

    var imports =
        graph ??
        ImportGraph.read(
          root: headRoot,
          packageConfig: p.join(headRoot, '.dart_tool', 'package_config.json'),
        );

    var settled = <ScenarioComparison>[];
    var toRun = <String>[];
    for (var id in headIds) {
      if (!baseIds.contains(id)) {
        settled.add(
          ScenarioComparison.notRun(scenario: id, state: ComparedState.added),
        );
        continue;
      }
      cache.memo.remember(id, imports.closureOf(source.fileOf(id)));
      if (SkipDecision.of(
        entryId: id,
        memo: cache.memo,
        baseRoot: baseRoot,
        headRoot: headRoot,
        pixels: pixels,
      ).skip) {
        settled.add(
          ScenarioComparison.notRun(scenario: id, state: ComparedState.skipped),
        );
        continue;
      }
      toRun.add(id);
    }
    for (var id in baseIds) {
      if (!headIds.contains(id)) {
        settled.add(
          ScenarioComparison.notRun(scenario: id, state: ComparedState.removed),
        );
      }
    }

    return ScenariosPlan(
      settled: settled,
      toRun: toRun,
      total: settled.length + toRun.length,
    );
  }

  /// Replays what [plan] left and aligns the two runs.
  ///
  /// **One scenario on both sides before the next.** A scenario is a process;
  /// replaying the whole head side and then the whole base side would double
  /// the time before the first row could be answered, and the first row is what
  /// a reader is waiting for.
  Future<ScenarioResults> run({
    required String outDir,
    ScenariosPlan? from,
    ImportGraph? graph,
  }) async {
    var watch = Stopwatch()..start();
    cancel?.check();
    var plan = from ?? await this.plan(graph: graph);
    onPlan?.call(plan);

    var items = <ScenarioComparison>[];
    void report(ScenarioComparison scenario) {
      items.add(scenario);
      onScenario?.call(scenario);
    }

    for (var settled in plan.settled) {
      report(settled);
    }
    var done = 0;
    for (var id in plan.toRun) {
      cancel?.check();
      done++;
      var name = id.contains('#') ? id.substring(id.indexOf('#') + 1) : id;
      var count = '$done of ${plan.toRun.length}';
      onProgress?.call('replaying "$name" on the base side · $count');
      var base = await source.shots(id, base: true, outDir: outDir);
      cancel?.check();
      onProgress?.call('replaying "$name" on this side · $count');
      var head = await source.shots(id, base: false, outDir: outDir);
      report(ScenarioComparison.of(scenario: id, base: base, head: head));
    }

    return ScenarioResults.of(
      items: items,
      ran: plan.toRun.length,
      skipped: plan.settled
          .where((s) => s.state == ComparedState.skipped)
          .length,
      elapsed: watch.elapsed,
    );
  }
}

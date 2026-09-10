import 'scenario_diff.dart';

import 'package:flutterware/comparison_report.dart';
import 'package:path/path.dart' as p;

import '../scenarios/runner.dart';
import 'artifact.dart';
import '../embedder/build_directory.dart';
import 'cancel.dart';
import 'closure.dart';
import 'import_graph.dart';
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

  /// Every scenario id one side declares, read from its sources instead of
  /// from a running harness — or null where the sources cannot answer for the
  /// whole set.
  ///
  /// Synchronous and nearly free, which is the entire point of its existing
  /// beside [list]. [list] costs a harness build and a boot **on each side**,
  /// and that is what a comparison spends its fixed time on: measured
  /// 2026-09-09 on this repo, a run whose every scenario was skipped spent
  /// 60.5 of its 63 seconds getting two harnesses up to ask them a question
  /// the sources had already answered.
  List<String>? scan({required bool base});

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
    required this.headRoot,
    required this.baseRoot,
  });

  final ScenariosSide side;
  final String headRoot;
  final String baseRoot;

  /// Built on the first ask, because a plan answered from [scan] never asks.
  /// A runner is a claimed build directory before it is anything else, so
  /// making them lazy is what lets a comparison that replays nothing leave
  /// nothing behind in either checkout.
  ScenarioRunner? _head;
  ScenarioRunner? _base;

  ScenarioRunner _runner({required bool base}) => base
      ? _base ??= side.runnerFor(baseRoot)
      : _head ??= side.runnerFor(headRoot);

  @override
  Future<List<String>> list({required bool base}) =>
      side.scenarios(_runner(base: base));

  @override
  List<String>? scan({required bool base}) =>
      side.scannedScenarios(base ? baseRoot : headRoot);

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
    // Only the ones that were built. A run answered from the scan alone made
    // neither, and there is nothing to tear down or release.
    for (var runner in [_head, _base]) {
      if (runner == null) continue;
      await runner.dispose();
      // The runners built in claimed directories — `runnerFor` says why — and
      // the claim ends with the runner that held it.
      releaseBuildDirectory(
        runner.packageRoot,
        runner.buildDirectory,
        root: comparisonBuildRoot,
      );
    }
    // Not cleared. A null field here means "never built", and a source that
    // forgot it had been disposed would answer the next ask by building a
    // fresh runner in a fresh claim rather than by failing.
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
    this.because = const {},
  });

  /// Scenarios answered without replaying: added, removed, skipped.
  final List<ScenarioComparison> settled;

  /// The ids that have to be replayed on both sides.
  final List<String> toRun;

  final int total;

  /// Why [toRun] has to be replayed, folded — see [foldReasons].
  final Map<String, int> because;
}

/// Runs the scenario half: decide, replay what is left, align, report.
///
/// Lifted out of `fw compare`, where it was the only copy. The GUI needs
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
    this.locks,
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

  /// Both sides' lockfiles, read per package — see [LockSides]. Passed for
  /// the same reason [pixels] is, and used the same way: a scenario carries
  /// the resolution of the packages it reaches and no others.
  final LockSides? locks;

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

  /// What has to be replayed, decided without starting anything where the
  /// sources can say.
  ///
  /// Two listings answer "which scenarios does each side declare", and they
  /// cost wildly different amounts. [ScenarioSource.scan] parses the files;
  /// [ScenarioSource.list] builds and boots a harness on **each** side, which
  /// is the whole fixed cost of this half and is paid before a single closure
  /// has been hashed. So the scan goes first, and the listing is asked for
  /// only when something has to be replayed — at which point a harness is
  /// starting anyway and the plan is remade from the answer that knows about
  /// `skip:` and about names no parser can read.
  ///
  /// The scan is therefore never trusted to *decide* a replay, only to decide
  /// that there is none. What it can get wrong on that path is `added` and
  /// `removed` — and only on a run where nothing is replayed, since the next
  /// run that replays anything re-asks the harness.
  Future<ScenariosPlan> plan({ImportGraph? graph}) async {
    cancel?.check();
    var imports =
        graph ??
        ImportGraph.read(
          root: headRoot,
          packageConfig: p.join(headRoot, '.dart_tool', 'package_config.json'),
        );
    // One pass's digests, so the library every scenario imports is hashed
    // once rather than once per scenario — and once across both decisions
    // below, on the runs that make two. Scoped to this plan and no longer:
    // see [DigestCache].
    var digests = DigestCache();

    onProgress?.call('reading the scenarios on both sides');
    var scannedHead = source.scan(base: false);
    var scannedBase = source.scan(base: true);
    // Both sides empty is not an answer, it is the absence of one: a package
    // whose scenarios the scan cannot see at all is exactly the case where
    // the harness's refusal to build is the message, and short-circuiting
    // here would replace it with a clean, silent, empty half.
    if (scannedHead != null &&
        scannedBase != null &&
        (scannedHead.isNotEmpty || scannedBase.isNotEmpty)) {
      var provisional = _decide(
        headIds: scannedHead,
        baseIds: scannedBase,
        imports: imports,
        digests: digests,
      );
      if (provisional.toRun.isEmpty) return provisional;
    }

    // Both at once, because they are two harnesses: a separate checkout, a
    // separate build directory and a separate `flutter_tester` each, sharing
    // nothing but the machine. Asking one and then the other spent the base
    // side's build waiting on this side's.
    onProgress?.call('listing the scenarios on both sides');
    var listed = await Future.wait([
      source.list(base: false),
      source.list(base: true),
    ]);
    cancel?.check();
    return _decide(
      headIds: listed[0],
      baseIds: listed[1],
      imports: imports,
      digests: digests,
    );
  }

  /// The plan two id listings imply — added, removed, skipped, and what is
  /// left to replay.
  ///
  /// Pure and synchronous: whichever listing it is given, the deciding is the
  /// same, which is what lets [plan] run it twice for the price of one digest
  /// pass.
  ScenariosPlan _decide({
    required List<String> headIds,
    required List<String> baseIds,
    required ImportGraph imports,
    required DigestCache digests,
  }) {
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

    var settled = <ScenarioComparison>[];
    var toRun = <String>[];
    var reasons = <String>[];
    for (var id in headIds) {
      if (!baseIds.contains(id)) {
        settled.add(
          ScenarioComparison.notRun(scenario: id, state: ComparedState.added),
        );
        continue;
      }
      var file = source.fileOf(id);
      cache.memo.remember(id, imports.closureOf(file));
      var decision = SkipDecision.of(
        entryId: id,
        memo: cache.memo,
        baseRoot: baseRoot,
        headRoot: headRoot,
        pixels: pixels,
        digests: digests,
        lock: locks?.forPackages(imports.packagesOf(file)),
      );
      if (decision.skip) {
        settled.add(
          ScenarioComparison.notRun(scenario: id, state: ComparedState.skipped),
        );
        continue;
      }
      toRun.add(id);
      if (decision.reason case var reason?) reasons.add(reason);
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
      because: foldReasons(reasons),
    );
  }

  /// Replays what [plan] left and aligns the two runs.
  ///
  /// One scenario on both sides before the next. A scenario is a process;
  /// replaying the whole head side and then the whole base side would double
  /// the time before the first row could be answered, and the first row is what
  /// a reader is waiting for.
  ///
  /// The two sides of one scenario run **together**. They are two harnesses on
  /// two checkouts with a build directory each, so there is nothing to
  /// serialize them for — and a replay is where a comparison spends its time.
  /// `Future.wait` rather than a record's `.wait`: a side that fails is
  /// usually a compile error, and the message a reader needs is that error
  /// itself rather than a `ParallelWaitError` wrapping it.
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
      onProgress?.call('replaying "$name" on both sides · $count');
      var replayed = await Future.wait([
        source.shots(id, base: true, outDir: outDir),
        source.shots(id, base: false, outDir: outDir),
      ]);
      report(
        compareScenarioSteps(
          scenario: id,
          base: replayed[0],
          head: replayed[1],
        ),
      );
    }

    return ScenarioResults.of(
      items: items,
      ran: plan.toRun.length,
      skipped: plan.settled
          .where((s) => s.state == ComparedState.skipped)
          .length,
      elapsed: watch.elapsed,
      because: plan.because,
    );
  }
}

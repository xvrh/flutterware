import 'package:path/path.dart' as p;

import '../scenarios/discovery.dart';
import 'closure.dart';
import 'import_graph.dart';
import 'scenarios_side.dart';
import 'skip.dart';

/// How many scenarios a comparison would replay, worked out by **parsing**.
///
/// **The runtime listing is ground truth, and it is not free.**
/// `ScenarioRunner.list()` compiles the harness and spawns a guest on each
/// side, which is the bulk of what replaying costs — so an estimate that used
/// it would be the work rather than an estimate of it, and the tab would have
/// nothing to say until the thing it was warning you about had already
/// happened.
///
/// `ScenarioScanner` answers the same question by parsing, on any checkout,
/// with no compiler. It can be *wrong*: a `scenario(someName, …)` whose name is
/// not a literal is invisible to a parse and visible to the harness. That is
/// the disagreement `discovery.dart` already calls a diagnostic rather than a
/// failure — and an estimate is allowed to be an estimate. What actually runs
/// is still decided by `ScenariosRunner.plan()` against the live listing.
class ScenariosEstimate {
  const ScenariosEstimate({required this.toRun, required this.total});

  /// How many the closure says are worth replaying.
  final int toRun;

  /// Every scenario head declares.
  final int total;

  /// *5 of 43* — what a tab says before it costs anything.
  String get label => '$toRun of $total';

  /// Reads both checkouts and decides, in parsing time.
  ///
  /// Skips on the same rule the run does, and deliberately through the same
  /// [SkipDecision]: an estimate computed by a second rule would drift from
  /// the thing it estimates, which is the one way an estimate becomes a lie
  /// rather than an approximation.
  static ScenariosEstimate of({
    required String headRoot,
    required String baseRoot,
    required ScenariosSide side,
    required ClosureMemo memo,
    ImportGraph? graph,
  }) {
    var head = _scan(headRoot, side);
    var base = _scan(baseRoot, side).toSet();
    var imports =
        graph ??
        ImportGraph.read(
          root: headRoot,
          packageConfig: p.join(headRoot, '.dart_tool', 'package_config.json'),
        );

    var toRun = 0;
    for (var id in head) {
      // A scenario head alone has is settled without replaying it, exactly as
      // the plan settles it.
      if (!base.contains(id)) continue;
      memo.remember(id, imports.closureOf(side.fileOf(id)));
      if (!SkipDecision.of(
        entryId: id,
        memo: memo,
        baseRoot: baseRoot,
        headRoot: headRoot,
      ).skip) {
        toRun++;
      }
    }
    return ScenariosEstimate(
      toRun: toRun,
      total: head.length + base.difference(head.toSet()).length,
    );
  }

  static List<String> _scan(String checkout, ScenariosSide side) => [
    for (var ref in ScenarioScanner(
      packageRoot: p.normalize(p.join(checkout, side.packagePath)),
      directory: side.directory,
    ).scan().scenarios)
      ScenariosSide.idFor(file: ref.file, scenario: ref.name),
  ];
}

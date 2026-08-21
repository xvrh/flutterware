import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../shell/worktree.dart';
import 'channels.dart';
import 'runner.dart';
import 'scenario_comparison.dart';

/// One worktree's corner of the shared comparisons cache: `index.json` and
/// the `scenarios/` frames it references, together.
///
/// Keyed by the canonical *path*, because the worktree's name is unique only
/// within its repository — every repository's main checkout is named `~` —
/// and this directory is shared by every project on the machine. Two agents
/// comparing in two worktrees used to write the same
/// `comparisons/scenarios/<file>/<scenario>` frames and read back each
/// other's pixels. The directory name keeps the checkout's directory name in
/// front so a human browsing the cache can still tell which is which.
String comparisonDirFor(String cacheRoot, Worktree worktree) => p.join(
  cacheRoot,
  'comparisons',
  '${worktree.directoryName}-'
      '${sha1.convert(utf8.encode(p.canonicalize(worktree.path))).toString().substring(0, 12)}',
);

/// The scenario half of a comparison, as the artifact records it.
///
/// The twin of [ComparisonResult] and deliberately not the same class: a
/// preview run counts *renders*, because the skip rule is what it is trying to
/// prove, and a scenario run counts whole scenarios, because one of those is a
/// process and the pictures inside it are not the unit anybody thinks in.
class ScenarioResults {
  const ScenarioResults({
    required this.items,
    required this.ran,
    required this.skipped,
    required this.elapsed,
    this.note,
  });

  /// Every scenario, worst first — the ones that ran, and the ones that exist
  /// on one side only.
  final List<ScenarioComparison> items;

  /// How many were actually replayed on both sides.
  final int ran;

  final int skipped;
  final Duration elapsed;

  /// Why there is nothing here, when there is nothing here.
  ///
  /// Recorded rather than only printed. A harness that will not build
  /// leaves the same empty list as a project with no scenarios at all, and a
  /// reader who cannot tell those apart will read a silent artifact as a clean
  /// one.
  final String? note;

  int countOf(ComparedState state) =>
      items.where((item) => item.state == state).length;

  /// Assembles the half, ranking it the way the previews half ranks: worst
  /// first, since [ComparedState] is declared in that order.
  static ScenarioResults of({
    required List<ScenarioComparison> items,
    required int ran,
    required int skipped,
    required Duration elapsed,
    String? note,
  }) => ScenarioResults(
    items: [...items]
      ..sort((a, b) {
        var byState = a.state.index.compareTo(b.state.index);
        return byState != 0 ? byState : a.scenario.compareTo(b.scenario);
      }),
    ran: ran,
    skipped: skipped,
    elapsed: elapsed,
    note: note,
  );

  Map<String, Object?> toJson() => {
    'ran': ran,
    'skipped': skipped,
    'ms': elapsed.inMilliseconds,
    'note': ?note,
    'counts': {
      for (var state in ComparedState.values)
        if (countOf(state) > 0) state.name: countOf(state),
    },
    'items': [for (var item in items) item.toJson()],
  };
}

/// Everything one comparison concluded, both halves, as one file.
///
/// One artifact, not two. The GUI, an agent and a static page all read this
/// rather than each computing their own, and a reader asking "did this branch
/// break anything" is asking about the branch — not about previews and then
/// separately about scenarios. Which is also why the halves are named rather
/// than merged: they are compared by different machinery and a row from one is
/// not interchangeable with a row from the other.
class ComparisonArtifact {
  const ComparisonArtifact({required this.previews, this.scenarios});

  final ComparisonResult previews;

  /// Absent when the project declares no scenarios at all. A run that tried
  /// and could not is present, with a [ScenarioResults.note].
  final ScenarioResults? scenarios;

  /// Every row either half produced, counted by state.
  ///
  /// The header a reader wants first — one preview that broke and one scenario
  /// that broke is two broken things, and asking which half they came from is
  /// the second question, not the first.
  Map<ComparedState, int> get counts {
    var counts = <ComparedState, int>{};
    for (var state in [
      for (var item in previews.items) item.state,
      for (var item in scenarios?.items ?? const <ScenarioComparison>[])
        item.state,
    ]) {
      counts[state] = (counts[state] ?? 0) + 1;
    }
    return counts;
  }

  /// True when nothing either half looked at came out worse than [same].
  bool get clean => !counts.keys.any(
    (state) => state != ComparedState.same && state != ComparedState.skipped,
  );

  Map<String, Object?> toJson() => {
    'base': previews.baseSha,
    'head': previews.headRoot,
    'ms':
        previews.elapsed.inMilliseconds +
        (scenarios?.elapsed.inMilliseconds ?? 0),
    'counts': {
      for (var state in ComparedState.values)
        if ((counts[state] ?? 0) > 0) state.name: counts[state],
    },
    // Named halves rather than one flat list: `items` at the top of a file
    // holding both would mean previews to whoever wrote it and everything to
    // whoever reads it.
    'previews': previews.toJson(),
    'scenarios': ?scenarios?.toJson(),
  };

  /// Writes the artifact, creating its directory.
  File writeTo(String path) {
    var file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
    return file;
  }
}

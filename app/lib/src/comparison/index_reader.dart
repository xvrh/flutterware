import 'channels.dart';
import 'scenario_comparison.dart';

/// A whole `index.json`, read back.
///
/// The exported page's model — and deliberately *not* the writer's classes.
/// `ComparisonResult` and `ScenarioResults` exist to conclude a run and carry
/// things a file cannot (the elapsed stopwatch, the render count's meaning);
/// a reader holds what the file says and nothing it would have to invent.
class ComparisonIndex {
  const ComparisonIndex({
    required this.base,
    required this.against,
    required this.previewItems,
    required this.scenarios,
    this.scenariosNote,
  });

  /// The base sha, as the artifact records it.
  final String base;

  /// What the header says the comparison is against — the ref's name where the
  /// export wrote one, the abbreviated sha where it did not.
  final String against;

  final List<ComparedItem> previewItems;
  final List<ScenarioComparison> scenarios;

  /// Why the scenario half has nothing to say, when it has nothing to say.
  final String? scenariosNote;

  static ComparisonIndex fromJson(Map<String, Object?> json) {
    var base = json['base'] as String? ?? '';
    var previews = json['previews'] as Map<String, Object?>? ?? const {};
    var scenarios = json['scenarios'] as Map<String, Object?>?;
    return ComparisonIndex(
      base: base,
      against:
          json['against'] as String? ??
          (base.length > 8 ? base.substring(0, 8) : base),
      previewItems: [
        for (var item in previews['items'] as List? ?? const [])
          ComparedItem.fromJson((item as Map).cast<String, Object?>()),
      ],
      scenarios: [
        for (var scenario in scenarios?['items'] as List? ?? const [])
          ScenarioComparison.fromJson(
            (scenario as Map).cast<String, Object?>(),
          ),
      ],
      scenariosNote: scenarios?['note'] as String?,
    );
  }

  /// Findings across both halves, worst first — the header's chips.
  Map<ComparedState, int> get findingCounts {
    var counts = <ComparedState, int>{};
    for (var state in [
      for (var item in previewItems) item.state,
      for (var scenario in scenarios) scenario.state,
    ]) {
      if (state != ComparedState.same && state != ComparedState.skipped) {
        counts[state] = (counts[state] ?? 0) + 1;
      }
    }
    return Map.fromEntries(
      counts.entries.toList()
        ..sort((a, b) => a.key.index.compareTo(b.key.index)),
    );
  }
}

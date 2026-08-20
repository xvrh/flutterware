/// One step that moved between two runs of the same suite.
class ScenarioStepDrift {
  const ScenarioStepDrift({
    required this.package,
    required this.file,
    required this.scenario,
    required this.position,
    this.axes,
    this.name,
  });

  final String package;

  /// The axis slug this point ran under, for a matrix run — steps are only
  /// ever compared against the same point of it.
  final String? axes;

  final String file;
  final String scenario;

  /// The step's shape-stable position, which is what the two runs are matched
  /// by. [ScenarioRunStep.index] shifts when a step is inserted anywhere
  /// before it; a position shifts only within its own branch.
  final String position;

  /// The `Shot`'s name, where it had one — what a reader recognises the step
  /// by.
  final String? name;

  /// How it reads in a line of output.
  String get label => [scenario, name ?? position, ?axes].join(' · ');

  @override
  String toString() => '$file $label';

  Map<String, Object?> toJson() => {
    'package': package,
    if (axes != null) 'axes': axes,
    'file': file,
    'scenario': scenario,
    'position': position,
    if (name != null) 'name': name,
  };

  static ScenarioStepDrift fromJson(Map<String, Object?> json) =>
      ScenarioStepDrift(
        package: json['package'] as String? ?? '',
        axes: json['axes'] as String?,
        file: json['file'] as String? ?? '',
        scenario: json['scenario'] as String? ?? '',
        position: json['position'] as String? ?? '',
        name: json['name'] as String?,
      );
}

/// What changed between two runs of one suite — nothing, if the suite is
/// deterministic.
///
/// See [compareScenarioRuns] for why this is worth asking.
class ScenarioRunDrift {
  const ScenarioRunDrift({
    required this.compared,
    required this.changed,
    required this.added,
    required this.removed,
  });

  /// Steps both runs captured, both carrying a digest — the denominator.
  final int compared;

  /// Steps both runs captured whose pixels are not the same pixels.
  final List<ScenarioStepDrift> changed;

  /// Steps only the later run captured, and only the earlier one.
  final List<ScenarioStepDrift> added;
  final List<ScenarioStepDrift> removed;

  bool get isEmpty => changed.isEmpty && added.isEmpty && removed.isEmpty;

  /// The one line worth printing after a run, or null when the two runs agree
  /// about everything and there is nothing to say.
  String? get summary {
    if (isEmpty) return null;
    return [
      if (changed.isNotEmpty) '${changed.length} of $compared steps differ',
      if (added.isNotEmpty) '${added.length} new',
      if (removed.isNotEmpty) '${removed.length} gone',
    ].join(' · ');
  }

  /// [maxSteps] caps each list, the way every other projection in this report
  /// caps: a suite that moved everywhere would otherwise spend the whole
  /// answer saying so, and the count above the list is the part that matters.
  Map<String, Object?> toJson({int maxSteps = 20}) => {
    'compared': compared,
    if (changed.isNotEmpty) ...{
      'changed': changed.length,
      'changedSteps': [for (var s in changed.take(maxSteps)) s.toJson()],
    },
    if (added.isNotEmpty) ...{
      'added': added.length,
      'addedSteps': [for (var s in added.take(maxSteps)) s.toJson()],
    },
    if (removed.isNotEmpty) ...{
      'removed': removed.length,
      'removedSteps': [for (var s in removed.take(maxSteps)) s.toJson()],
    },
  };

  /// Decodes what [toJson] wrote. The lists come back capped as they were
  /// written; the counts are whole, so `changed.length` and the count they
  /// were made from can disagree.
  static ScenarioRunDrift fromJson(Map<String, Object?> json) =>
      ScenarioRunDrift(
        compared: json['compared'] as int? ?? 0,
        changed: _steps(json['changedSteps']),
        added: _steps(json['addedSteps']),
        removed: _steps(json['removedSteps']),
      );

  static List<ScenarioStepDrift> _steps(Object? raw) => switch (raw) {
    List list => [
      for (var entry in list)
        if (entry is Map<String, Object?>) ScenarioStepDrift.fromJson(entry),
    ],
    _ => const [],
  };
}

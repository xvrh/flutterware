import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';

part 'scenarios_results.g.dart';

/// `list` — every scenario of every requested package, from the syntactic
/// scan.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioListResult implements PluginResult {
  ScenarioListResult({required this.packages});

  final List<ScenarioListPackage> packages;

  @override
  Map<String, Object?> toJson() => _$ScenarioListResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioListPackage {
  ScenarioListPackage({
    required this.path,
    required this.directory,
    this.scenarios = const [],
    this.diagnostics = const [],
    this.error,
  });

  final String path;

  /// The scanned directory, relative to the package.
  final String directory;

  final List<ScenarioListEntry> scenarios;

  /// What the scan noticed but could not act on — non-literal names,
  /// duplicates. Empty is the healthy case.
  final List<String> diagnostics;

  /// Set when the package could not be scanned, in which case [scenarios]
  /// means nothing.
  final String? error;

  Map<String, Object?> toJson() => _$ScenarioListPackageToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioListEntry {
  ScenarioListEntry({
    required this.name,
    required this.file,
    required this.line,
  });

  final String name;

  /// Package-relative source file.
  final String file;

  final int line;

  Map<String, Object?> toJson() => _$ScenarioListEntryToJson(this);
}

/// `run` — scenarios executed in the runner's `flutter_tester`, with one
/// artifact triple (PNG, widget tree, texts) per captured step.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRunResult implements PluginResult {
  ScenarioRunResult({required this.packages, this.axes});

  final List<ScenarioRunPackage> packages;

  /// The axis assignment the whole request ran under —
  /// `{device: iphone-se, language: fr}` — or null for the test defaults.
  /// Recorded because a screenshot is under-specified without it; the same
  /// values ride every step's address as query parameters.
  final Map<String, String>? axes;

  @override
  Map<String, Object?> toJson() => _$ScenarioRunResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRunPackage {
  ScenarioRunPackage({
    required this.path,
    required this.output,
    this.ms = 0,
    this.scenarios = const [],
    this.error,
  });

  final String path;

  /// Where this run's artifacts were written.
  final String output;

  /// Whole-run wall time inside the harness.
  final int ms;

  final List<ScenarioRunOutcome> scenarios;

  /// Set when the package could not be run at all — the harness did not
  /// compile, the tester did not start — in which case [scenarios] is empty.
  final String? error;

  Map<String, Object?> toJson() => _$ScenarioRunPackageToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRunOutcome {
  ScenarioRunOutcome({
    required this.file,
    required this.name,
    required this.ok,
    this.ms = 0,
    this.steps = const [],
    this.errors = const [],
  });

  final String file;
  final String name;
  final bool ok;
  final int ms;
  final List<ScenarioRunStep> steps;

  /// The failure, when [ok] is false. The last captured step is the frame
  /// just before it.
  final List<ScenarioRunError> errors;

  Map<String, Object?> toJson() => _$ScenarioRunOutcomeToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRunStep {
  ScenarioRunStep({
    required this.index,
    required this.auto,
    required this.png,
    required this.tree,
    required this.texts,
    required this.address,
    this.name,
    this.tags = const [],
  });

  /// 1-based position in the scenario's capture sequence.
  final int index;

  /// The `Shot`'s name; null for an automatic capture.
  final String? name;

  /// True when nothing named this capture — a collapsible detail step.
  final bool auto;

  final List<String> tags;

  /// Path to the captured PNG.
  final String png;

  /// Path to the widget-tree JSON captured at the same moment.
  final String tree;

  /// The visible texts — the projection an agent reads next to the pixels.
  final List<String> texts;

  /// The step's `fw://` address.
  final String address;

  Map<String, Object?> toJson() => _$ScenarioRunStepToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRunError {
  ScenarioRunError({required this.error, this.stack});

  final String error;
  final String? stack;

  Map<String, Object?> toJson() => _$ScenarioRunErrorToJson(this);
}

/// `restart` — the warm harness dropped, so the next run cold-starts from
/// nothing: fresh asset bundle, fresh kernel, fresh tester process.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class ScenarioRestartResult implements PluginResult {
  ScenarioRestartResult({required this.restarted});

  /// The package paths whose harness was dropped.
  final List<String> restarted;

  @override
  Map<String, Object?> toJson() => _$ScenarioRestartResultToJson(this);
}

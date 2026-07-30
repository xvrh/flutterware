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

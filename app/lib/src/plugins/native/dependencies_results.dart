import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';

part 'dependencies_results.g.dart';

/// `list` — every dependency of every requested package.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class DependencyListResult implements PluginResult {
  DependencyListResult({required this.packages});

  final List<DependencyListPackage> packages;

  @override
  Map<String, Object?> toJson() => _$DependencyListResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class DependencyListPackage {
  DependencyListPackage({
    required this.path,
    this.direct = 0,
    this.transitive = 0,
    this.dependencies = const [],
    this.error,
  });

  final String path;

  /// Counts are always both, even when only the direct ones are listed: a list
  /// that silently dropped 156 packages and said nothing would read as "this
  /// package has 14 dependencies".
  final int direct;
  final int transitive;

  final List<DependencyEntry> dependencies;

  /// Set when the package could not be loaded, in which case the counts mean
  /// nothing.
  final String? error;

  Map<String, Object?> toJson() => _$DependencyListPackageToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class DependencyEntry {
  DependencyEntry({
    required this.name,
    required this.direct,
    this.version,
    this.source,
  });

  final String name;

  /// Declared in this package's own pubspec, as opposed to pulled in by
  /// something else.
  final bool direct;

  /// Null for a package whose pubspec declares none.
  final String? version;

  /// `hosted`, `git`, `path` — where pub resolved it from.
  final String? source;

  Map<String, Object?> toJson() => _$DependencyEntryToJson(this);
}

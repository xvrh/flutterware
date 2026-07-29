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
    this.dev = 0,
    this.transitive = 0,
    this.dependencies = const [],
    this.error,
  });

  final String path;

  /// Counts are always all three, even when only the declared ones are listed:
  /// a list that silently dropped 156 packages and said nothing would read as
  /// "this package has 14 dependencies".
  final int direct;
  final int dev;
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
    required this.source,
    this.dev = false,
    this.version,
    this.constraint,
    this.origin,
  });

  final String name;

  /// Declared in this package's own pubspec, as opposed to pulled in by
  /// something else. True for a dev dependency too — see [dev] to tell them
  /// apart.
  final bool direct;

  /// Declared in `dev_dependencies:` rather than `dependencies:`.
  final bool dev;

  /// The resolved version — what is on disk. `0.0.0` for an SDK package, whose
  /// [source] is the useful field instead.
  final String? version;

  /// The constraint the depending package wrote — `^1.2.0`, `any`. Null for a
  /// transitive dependency, which this package did not declare.
  final String? constraint;

  /// `hosted`, `git`, `path`, `sdk`, `root` — where pub resolved it from.
  ///
  /// **Never null.** It used to be read off a lockfile entry that is absent for
  /// every member of a pub workspace, so every package of a workspace reported
  /// no source at all.
  final String source;

  /// The identifying detail behind [source]: the git repository and ref, the
  /// relative path, a non-pub.dev server. Null when [source] says everything.
  final String? origin;

  Map<String, Object?> toJson() => _$DependencyEntryToJson(this);
}

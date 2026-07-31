import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';

part 'motion_results.g.dart';

/// `list` — every motion of every requested package, from the syntactic scan.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class MotionListResult implements PluginResult {
  MotionListResult({required this.packages});

  final List<MotionListPackage> packages;

  @override
  Map<String, Object?> toJson() => _$MotionListResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class MotionListPackage {
  MotionListPackage({
    required this.path,
    required this.directory,
    this.motions = const [],
    this.diagnostics = const [],
    this.error,
  });

  final String path;

  /// The scanned directory, relative to the package.
  final String directory;

  final List<MotionListMotion> motions;

  /// What the scan noticed and could not act on. **Read these before trusting
  /// the list**: a target named by an expression rather than a literal is
  /// invisible here and perfectly real at run time, and that turned out to be
  /// the second demo anybody wrote.
  final List<String> diagnostics;

  /// Set when the package could not be scanned, in which case [motions] means
  /// nothing.
  final String? error;

  Map<String, Object?> toJson() => _$MotionListPackageToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class MotionListMotion {
  MotionListMotion({
    required this.file,
    required this.line,
    this.values,
    this.address,
    this.targets = const [],
  });

  /// Package-relative source file.
  final String file;

  final int line;

  /// The identifier passed to `motion:`, which names the values file's const.
  /// Absent when it was not a plain identifier.
  final String? values;

  /// Where to open it, playhead included — append `?t=` to park it.
  final String? address;

  final List<MotionListTarget> targets;

  Map<String, Object?> toJson() => _$MotionListMotionToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class MotionListTarget {
  MotionListTarget({
    required this.name,
    required this.line,
    this.properties = const [],
    this.boxed = false,
  });

  final String name;
  final int line;

  /// Vocabulary properties read at a call site.
  final List<String> properties;

  /// Whether a `MotionBox` was handed this target, which applies eight
  /// properties without reading any of them here. A target with no
  /// [properties] and `boxed` is fully wired, not unwired.
  final bool boxed;

  Map<String, Object?> toJson() => _$MotionListTargetToJson(this);
}

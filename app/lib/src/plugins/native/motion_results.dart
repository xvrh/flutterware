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

  /// What the scan noticed and could not act on. Read these before trusting the
  /// list: a target named by an expression rather than a literal is invisible
  /// here and perfectly real at run time, which the second demo written already
  /// hit.
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

/// `verify` — whether a motion renders the same clip every time.
///
/// The question this answers is the one nothing downstream can: a frame of the
/// wrong moment looks exactly as plausible as a frame of the right one, so a
/// clip cannot be checked by watching it. What *can* be checked is whether the
/// pictures depend on anything but the playhead.
///
/// Two claims, and the second is the stronger:
///
///   * **repeats** — the same stops rendered twice are byte-identical. A
///     motion that fails this is not renderable at all; something in it reads
///     a clock, a random, or the machine.
///   * **orderFree** — the same stops rendered *backwards* are the same
///     pictures. A motion that fails this renders its history rather than its
///     playhead: an implicit animation, a spring, a scroll position. It can
///     still be exported with the `time` clock, which drives such a screen
///     deliberately, but it is not a scene and a `playhead` render of it is
///     of the wrong moments.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class MotionVerifyResult implements PluginResult {
  MotionVerifyResult({
    required this.motion,
    required this.file,
    required this.stops,
    required this.durationMs,
    required this.repeats,
    required this.orderFree,
    this.differingStops = const [],
    this.scope,
    this.scopes = const [],
  });

  final String motion;
  final String file;

  /// How many playhead positions were compared.
  final int stops;

  final int durationMs;

  final bool repeats;
  final bool orderFree;

  /// The playhead positions that came out different, so a failure names the
  /// moments to look at rather than only the verdict.
  final List<double> differingStops;

  final String? scope;

  /// Every playhead that was mounted, when there was more than one — a verdict
  /// about the wrong one is worth being able to see.
  final List<String> scopes;

  /// Whether this motion can be rendered as a scene.
  bool get ok => repeats && orderFree;

  @override
  Map<String, Object?> toJson() => _$MotionVerifyResultToJson(this);
}

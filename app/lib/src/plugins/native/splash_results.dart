import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';

part 'splash_results.g.dart';

/// `describe` — one surface × theme resolved in full.
///
/// Carries [properties] with their originating key rather than a flat map of
/// values, because "what colour is it" is rarely the question. The question is
/// "why is it *that* colour", and only the key answers it.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class SplashDescribeResult implements PluginResult {
  SplashDescribeResult({
    required this.package,
    required this.address,
    required this.surface,
    required this.theme,
    required this.configPath,
    required this.configKind,
    required this.enabled,
    required this.placement,
    this.flavor,
    this.properties = const [],
    this.fallsBackToLight = false,
    this.problems = const [],
  });

  final String package;

  /// The address of this exact cell — pasteable back into `capture`.
  final String address;

  final String surface;
  final String theme;

  /// Which file the config was read from, and in what form. A project reading
  /// its pubspec while its author edits `flutter_native_splash.yaml` is a real
  /// and baffling failure, and this is what makes it obvious.
  final String configPath;
  final String configKind;
  final String? flavor;

  /// False when the project switched this platform off.
  final bool enabled;

  /// Where the image lands, in words — so the CLI answers the question without
  /// rendering anything.
  final String placement;

  final List<SplashProperty> properties;

  /// The dark chain resolved nothing, so the OS will show the light splash.
  final bool fallsBackToLight;

  final List<SplashProblemEntry> problems;

  @override
  Map<String, Object?> toJson() => _$SplashDescribeResultToJson(this);
}

/// One resolved property, and the key it came from.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class SplashProperty {
  SplashProperty({required this.name, required this.value, this.from});

  /// `color`, `image`, `branding`.
  final String name;

  final String value;

  /// The config key that won the cascade — `color_dark_android`. Null for a
  /// property that is computed rather than configured.
  final String? from;

  Map<String, Object?> toJson() => _$SplashPropertyToJson(this);
}

/// One thing wrong, flattened for the wire.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class SplashProblemEntry {
  SplashProblemEntry({
    required this.tone,
    required this.message,
    this.key,
    this.surface,
    this.theme,
    this.blocksGeneration = false,
  });

  final String tone;
  final String message;
  final String? key;
  final String? surface;
  final String? theme;

  /// `create` will exit rather than write anything.
  final bool blocksGeneration;

  Map<String, Object?> toJson() => _$SplashProblemEntryToJson(this);
}

/// `generate` — what running the real generator did.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class SplashGenerateResult implements PluginResult {
  SplashGenerateResult({
    required this.package,
    required this.ok,
    required this.exitCode,
    required this.output,
    this.flavor,
    this.artifacts = const [],
  });

  final String package;
  final String? flavor;

  final bool ok;
  final int exitCode;

  /// The generator's own output, kept whole. It names the file it choked on,
  /// and paraphrasing that would lose the only thing worth having on a failure.
  final String output;

  /// What exists afterwards — the point of having run it.
  final List<SplashArtifactEntry> artifacts;

  @override
  Map<String, Object?> toJson() => _$SplashGenerateResultToJson(this);
}

/// `artifacts` — the real generated files, as they are on disk.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class SplashArtifactsResult implements PluginResult {
  SplashArtifactsResult({
    required this.package,
    required this.generated,
    this.artifacts = const [],
    this.stale = false,
  });

  final String package;

  /// False when nothing has been generated yet, which is what distinguishes
  /// "run `generate` first" from "the generator produced nothing".
  final bool generated;

  /// The config has been edited since these were written.
  final bool stale;

  final List<SplashArtifactEntry> artifacts;

  @override
  Map<String, Object?> toJson() => _$SplashArtifactsResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class SplashArtifactEntry {
  SplashArtifactEntry({
    required this.path,
    required this.surface,
    required this.theme,
    required this.modified,
    this.density,
  });

  /// Worktree-relative, so an agent whose tools are scoped to the repo can open
  /// it.
  final String path;

  final String surface;
  final String theme;
  final String? density;
  final String modified;

  Map<String, Object?> toJson() => _$SplashArtifactEntryToJson(this);
}

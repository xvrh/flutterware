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
    required this.generated,
    this.flavor,
    this.predictedBecause,
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

  /// [placement] was read back from the files `create` wrote, rather than
  /// derived from the config.
  ///
  /// **The first thing a caller should look at.** A false here means the answer
  /// is this plugin's reading of a third-party generator's rules — useful, and
  /// not the same kind of claim. The properties below are config either way.
  final bool generated;

  /// Why there was nothing to read back. Null when [generated].
  final String? predictedBecause;

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
    this.device,
    this.blocksGeneration = false,
  });

  final String tone;
  final String message;
  final String? key;
  final String? surface;
  final String? theme;

  /// The screen this is about, for the rules that sweep the device table —
  /// `iphone-se`. The panel's own axis is a size class rather than a device, so
  /// a link into it lands on the nearest one; the exact device stays here
  /// because "clipped on an iPhone 13 mini" is the actionable sentence.
  final String? device;

  /// `create` will exit rather than write anything.
  final bool blocksGeneration;

  Map<String, Object?> toJson() => _$SplashProblemEntryToJson(this);
}

/// `reload` — the config re-read off disk, now.
///
/// [changed] is the whole reason this returns anything at all. A reload that
/// finds nothing different is the answer to "my edit is not showing up": the
/// edit did not land where the project reads from, and the next thing to look at
/// is [configPath].
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class SplashReloadResult implements PluginResult {
  SplashReloadResult({
    required this.package,
    required this.scannedAt,
    required this.changed,
    this.configPath,
  });

  final String package;

  /// Which file the re-read found, or null when the package has no splash
  /// config at all.
  final String? configPath;

  final String scannedAt;

  /// Something the scan depends on had moved since the last read.
  final bool changed;

  @override
  Map<String, Object?> toJson() => _$SplashReloadResultToJson(this);
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
    this.flavor,
    this.artifacts = const [],
    this.stale = false,
  });

  final String package;

  /// Which config these belong to. A flavor writes its own files, so a list
  /// that did not say which one it was for could not be checked.
  final String? flavor;

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
    required this.role,
    required this.modified,
    this.density,
    this.pixelWidth,
    this.pixelHeight,
    this.logicalWidth,
  });

  /// Worktree-relative, so an agent whose tools are scoped to the repo can open
  /// it.
  final String path;

  final String surface;
  final String theme;

  /// Which layer this is — `image`, `background`, `branding`, `icon`. A splash
  /// is a stack of files, and without this there is no way to tell which of
  /// three PNGs in one folder is the logo.
  final String role;

  final String? density;

  final int? pixelWidth;
  final int? pixelHeight;

  /// The size it occupies on screen. **Android only** — the rule is checked
  /// against the generator there and nowhere else, so the other platforms get
  /// null rather than a number nobody has verified.
  final double? logicalWidth;

  final String modified;

  Map<String, Object?> toJson() => _$SplashArtifactEntryToJson(this);
}

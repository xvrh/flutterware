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
    this.fix,
    this.fixLabel,
    this.blocksGeneration = false,
  });

  final String tone;
  final String message;
  final String? key;
  final String? surface;
  final String? theme;

  /// The screen this is about, for the rules that sweep the device table —
  /// `iphone-se`. Append it to the address as `?device=` to see it.
  final String? device;

  /// The id to hand `fix`, when this one can be repaired by writing a key.
  ///
  /// This is the whole discovery path: `describe` lists the problems, each
  /// repairable one names its own remedy, and an agent needs no second call to
  /// find out what is on offer.
  final String? fix;

  /// What that fix will do, in words — so a caller can decide before running it.
  final String? fixLabel;

  /// `create` will exit rather than write anything.
  final bool blocksGeneration;

  Map<String, Object?> toJson() => _$SplashProblemEntryToJson(this);
}

/// `fix` — the keys one repair wrote.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class SplashFixResult implements PluginResult {
  SplashFixResult({
    required this.package,
    required this.fix,
    required this.label,
    required this.configPath,
    required this.writes,
    required this.remainingProblems,
    this.flavor,
  });

  final String package;
  final String? flavor;

  final String fix;
  final String label;

  /// Which file was edited, package-relative. Worth returning even though the
  /// caller could have looked it up: a project with both a
  /// `flutter_native_splash.yaml` and a pubspec section reads only one, and
  /// this says which one just changed.
  final String configPath;

  final List<SplashWriteEntry> writes;

  /// How many problems the re-scan found afterwards. The point of running a fix
  /// is that this goes down; a caller that has to run `describe` again to find
  /// out is a caller that will not bother.
  final int remainingProblems;

  @override
  Map<String, Object?> toJson() => _$SplashFixResultToJson(this);
}

/// `set` — one key written by hand.
///
/// The wider door beside `fix`, and deliberately a separate one: a fix is a
/// remedy the plugin worked out, this is a value somebody chose. Keeping them
/// apart means the fix list stays a list of things that are actually wrong.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class SplashSetResult implements PluginResult {
  SplashSetResult({
    required this.package,
    required this.key,
    required this.configPath,
    required this.remainingProblems,
    this.value,
    this.flavor,
  });

  final String package;
  final String? flavor;

  final String key;

  /// Absent when the key was removed.
  final Object? value;

  final String configPath;

  /// What the re-scan found afterwards — the cheap check that a hand-written
  /// value did not break something else.
  final int remainingProblems;

  @override
  Map<String, Object?> toJson() => _$SplashSetResultToJson(this);
}

/// `prepare` — a source image turned into the file one target actually wants.
///
/// The numbers come back because they are the answer, not bookkeeping. Nobody
/// knows that an Android 12 icon is 1152 square with a 768 circle inside it, and
/// a caller that just made one should be told what it made.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class SplashPrepareResult implements PluginResult {
  SplashPrepareResult({
    required this.package,
    required this.target,
    required this.theme,
    required this.key,
    required this.output,
    required this.width,
    required this.height,
    required this.explanation,
    required this.remainingProblems,
    this.flavor,
    this.sourceCopiedTo,
    this.cornerOverhang = 0,
  });

  final String package;
  final String? flavor;

  final String target;
  final String theme;

  /// The config key it was written to — derived from the target and the theme,
  /// so a caller cannot make the file and point the wrong key at it.
  final String key;

  /// Package-relative path of the PNG.
  final String output;

  final int width;
  final int height;

  /// Why the canvas is that size, in words.
  final String explanation;

  /// Where the original was copied to, when it came from outside the package.
  /// Null when the source was already in the project and a copy would be
  /// clutter.
  final String? sourceCopiedTo;

  /// How far the image reaches past a circular mask, in pixels. **Not an
  /// error**: a logo with transparent corners is unaffected. Reported because
  /// only the person looking at it knows which kind they have.
  final double cornerOverhang;

  final int remainingProblems;

  @override
  Map<String, Object?> toJson() => _$SplashPrepareResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class SplashWriteEntry {
  SplashWriteEntry({required this.key, this.value});

  /// Dotted for the nested section — `android_12.image`.
  final String key;

  /// Absent when the key was removed.
  final Object? value;

  Map<String, Object?> toJson() => _$SplashWriteEntryToJson(this);
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

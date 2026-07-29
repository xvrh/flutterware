import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';

part 'assets_results.g.dart';

/// `list` — every key each requested package's bundle resolves to.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class AssetListResult implements PluginResult {
  AssetListResult({required this.packages});

  final List<AssetListPackage> packages;

  @override
  Map<String, Object?> toJson() => _$AssetListResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class AssetListPackage {
  AssetListPackage({
    required this.path,
    this.assets = const [],
    this.own = 0,
    this.fromPackages = 0,
    this.bytes = 0,
    this.error,
  });

  final String path;

  /// Counts are always both, even when only the package's own assets are
  /// listed: a list that silently dropped 340 dependency assets would read as
  /// "this bundle has nine things in it".
  final int own;
  final int fromPackages;

  /// Every byte in the bundle, dependencies included, whatever was listed.
  final int bytes;

  final List<AssetEntry> assets;

  /// Set when the package could not be scanned, in which case the counts mean
  /// nothing.
  final String? error;

  Map<String, Object?> toJson() => _$AssetListPackageToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class AssetEntry {
  AssetEntry({
    required this.key,
    required this.kind,
    required this.bytes,
    required this.address,
    this.package,
    this.densities = const [],
  });

  /// What `Image.asset` is given.
  final String key;

  final String kind;

  /// The asset and its density variants together.
  final int bytes;

  /// Where it is, so a caller can act on it without a second lookup.
  final String address;

  /// The package that declared it; absent for the bundle's own.
  final String? package;

  /// Which densities exist beside the main file — `[2.0, 3.0]`.
  final List<double> densities;

  Map<String, Object?> toJson() => _$AssetEntryToJson(this);
}

/// `describe` — one asset, including what the file itself says.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class AssetDescription implements PluginResult {
  AssetDescription({
    required this.key,
    required this.kind,
    required this.address,
    required this.declaration,
    required this.file,
    required this.bytes,
    required this.totalBytes,
    required this.code,
    this.package,
    this.densities = const [],
    this.raster,
    this.animation,
    this.font,
  });

  final String key;
  final String kind;
  final String address;

  /// The pubspec entry that pulled it in — for a directory declaration this is
  /// the only answer to "why is this in my bundle".
  final String declaration;

  /// Where the main file is, relative to its package.
  final String file;

  /// The main file, and then every density together.
  final int bytes;
  final int totalBytes;

  /// The Dart that loads it. The line an agent otherwise guesses at.
  final String code;

  final String? package;
  final List<AssetDensity> densities;

  /// Present for a raster whose header could be read.
  final RasterFactsResult? raster;

  /// Present for a `.json` that turned out to be an animation.
  final AnimationFactsResult? animation;

  /// Present for a file a `fonts:` entry named.
  final FontFactsResult? font;

  @override
  Map<String, Object?> toJson() => _$AssetDescriptionToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class AssetDensity {
  AssetDensity({required this.scale, required this.file, required this.bytes});

  /// Null for the main asset, which serves whatever no variant covers.
  final double? scale;

  final String file;
  final int bytes;

  Map<String, Object?> toJson() => _$AssetDensityToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class RasterFactsResult {
  RasterFactsResult({
    required this.width,
    required this.height,
    this.frames = 1,
  });

  final int width;
  final int height;

  /// Above one for an animated GIF or WebP.
  final int frames;

  Map<String, Object?> toJson() => _$RasterFactsResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class AnimationFactsResult {
  AnimationFactsResult({
    required this.width,
    required this.height,
    required this.frameRate,
    required this.frames,
    required this.durationMs,
    this.version,
    this.layers = const [],
    this.markers = const [],
  });

  final int width;
  final int height;
  final double frameRate;
  final int frames;
  final int durationMs;
  final String? version;

  /// Outermost first, the order the document lists them.
  final List<AnimationLayerResult> layers;

  /// Named points an exporter left behind — what a caller would seek to.
  final List<String> markers;

  Map<String, Object?> toJson() => _$AnimationFactsResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class AnimationLayerResult {
  AnimationLayerResult({required this.name, required this.type});

  final String name;
  final String type;

  Map<String, Object?> toJson() => _$AnimationLayerResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class FontFactsResult {
  FontFactsResult({required this.family, this.weight, this.style});

  /// The family the pubspec declared, package prefix included where there is
  /// one.
  final String family;

  /// What the pubspec *claims*. Whether the file agrees is a question nothing
  /// here asks yet.
  final int? weight;
  final String? style;

  Map<String, Object?> toJson() => _$FontFactsResultToJson(this);
}

/// `audit` — everything wrong with a bundle that can be found without running
/// the app.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class AssetAuditResult implements PluginResult {
  AssetAuditResult({
    required this.checked,
    required this.bytes,
    this.findings = const [],
    this.unreadable = const [],
  });

  /// How many keys were looked at — the denominator, so an empty findings list
  /// means "nothing wrong" rather than "nothing examined".
  final int checked;

  /// Every byte in the audited bundles.
  final int bytes;

  /// Only what is wrong. A clean repo audits to a line, not a page, or nobody
  /// runs it twice.
  final List<AssetFinding> findings;

  /// Packages that could not be scanned at all, which is not the same as a
  /// package with nothing wrong. Kept out of [checked] deliberately: an audit
  /// that counted an unreachable package as clean would report green on the
  /// strength of not having looked.
  final List<String> unreadable;

  @override
  Map<String, Object?> toJson() => _$AssetAuditResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class AssetFinding {
  AssetFinding({
    required this.kind,
    required this.summary,
    required this.detail,
    this.package,
    this.key,
    this.address,
    this.path,
  });

  /// A stable slug, so a caller can filter without matching prose:
  /// `declared-missing`, `unreachable-file`, `density-gap`, `duplicate`,
  /// `oversized`, `over-budget`.
  final String kind;

  /// One line, for a human reading a list.
  final String summary;

  /// What was found, specifically — the sizes, the paths, the densities.
  final String detail;

  /// The package whose bundle this is about.
  final String? package;

  /// The asset key, where the finding is about one.
  final String? key;

  /// Where to look, where there is somewhere. A declaration that resolves to
  /// nothing has no address by construction — that is what is wrong with it.
  final String? address;

  /// A path relative to the package, for findings about a file rather than a
  /// key.
  final String? path;

  Map<String, Object?> toJson() => _$AssetFindingToJson(this);
}

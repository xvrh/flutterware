/// The wire between [RenderPool] and the render guest: what a bundle's
/// manifest declares, and the line protocol spoken over the guest's stdio.
///
/// Servers do not import this — `client.dart` is their door. It is public
/// so the guest driver (which lives in the flutterware package) and the
/// bundler can speak the same spelling without an implementation import.
library;

/// Guest → server lines carrying protocol JSON start with this marker;
/// every other stdout line is the app's own logging, forwarded as a log.
const renderProtocolMarker = '@fw-render ';

/// Bumped when the manifest or the line protocol changes shape.
const renderProtocolVersion = 1;

/// What `fw render bundle` writes next to the artifacts: the one directory
/// is self-describing, and the versions it binds together cannot drift
/// apart without rebuilding it.
class RenderBundleManifest {
  RenderBundleManifest({
    required this.protocol,
    required this.platform,
    required this.engineVersion,
    required this.flutterVersion,
    required this.tester,
    required this.icuData,
    required this.kernel,
    this.assets,
    this.fonts = const [],
  });

  factory RenderBundleManifest.fromJson(Map<String, Object?> json) {
    return RenderBundleManifest(
      protocol: json['protocol']! as int,
      platform: json['platform']! as String,
      engineVersion: json['engineVersion']! as String,
      flutterVersion: json['flutterVersion']! as String,
      tester: json['tester']! as String,
      icuData: json['icuData']! as String,
      kernel: json['kernel']! as String,
      assets: json['assets'] as String?,
      fonts: [
        for (var font in json['fonts'] as List? ?? const [])
          BundleFont.fromJson((font as Map).cast<String, Object?>()),
      ],
    );
  }

  final int protocol;

  /// The tester's target, e.g. `linux-x64`, `darwin-arm64`.
  final String platform;
  final String engineVersion;
  final String flutterVersion;

  /// Paths relative to the bundle directory.
  final String tester;
  final String icuData;
  final String kernel;
  final String? assets;
  final List<BundleFont> fonts;

  Map<String, Object?> toJson() => {
    'protocol': protocol,
    'platform': platform,
    'engineVersion': engineVersion,
    'flutterVersion': flutterVersion,
    'tester': tester,
    'icuData': icuData,
    'kernel': kernel,
    if (assets != null) 'assets': assets,
    if (fonts.isNotEmpty) 'fonts': [for (var font in fonts) font.toJson()],
  };
}

/// One font file the guest loads at startup — into the engine for shaping,
/// and as capture bytes for embedding and glyph outlines.
class BundleFont {
  BundleFont({
    required this.family,
    required this.path,
    this.bold = false,
    this.italic = false,
  });

  factory BundleFont.fromJson(Map<String, Object?> json) => BundleFont(
    family: json['family']! as String,
    path: json['path']! as String,
    bold: json['bold'] as bool? ?? false,
    italic: json['italic'] as bool? ?? false,
  );

  final String family;

  /// Relative to the bundle directory.
  final String path;
  final bool bold;
  final bool italic;

  Map<String, Object?> toJson() => {
    'family': family,
    'path': path,
    if (bold) 'bold': bold,
    if (italic) 'italic': italic,
  };
}

/// One render point as the guest's ready event announces it.
class RenderPointInfo {
  RenderPointInfo({required this.name, required this.kind});

  factory RenderPointInfo.fromJson(Map<String, Object?> json) =>
      RenderPointInfo(
        name: json['name']! as String,
        kind: RenderPointKind.values.byName(json['kind']! as String),
      );

  final String name;
  final RenderPointKind kind;

  Map<String, Object?> toJson() => {'name': name, 'kind': kind.name};

  @override
  String toString() => '$name (${kind.name})';
}

enum RenderPointKind { widget, document }

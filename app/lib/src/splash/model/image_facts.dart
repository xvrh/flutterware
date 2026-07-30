/// What one referenced image turned out to be.
///
/// The config says `image: assets/splash.png`; this says whether that file is
/// there, whether it is a PNG, and how big it is. Both the composition (which
/// needs the natural size) and the validation (which needs the Android 12
/// canvas dimensions) read it, so it is measured once per scan and shared.
library;

/// The dimensions and existence of a referenced image.
class SplashImageFacts {
  const SplashImageFacts({
    required this.path,
    required this.exists,
    this.absolutePath,
    this.pixelWidth,
    this.pixelHeight,
    this.isPng = false,
  });

  /// Missing, as the config wrote it.
  const SplashImageFacts.missing(String path) : this(path: path, exists: false);

  /// Package-relative, exactly as the config spelled it — so a message about it
  /// quotes what the author would search for.
  final String path;

  final bool exists;

  /// Where it actually is, for a renderer that has to load it. Null when it is
  /// not there.
  final String? absolutePath;

  final int? pixelWidth;
  final int? pixelHeight;

  /// The generator only accepts PNG. A JPEG that exists is still wrong.
  final bool isPng;

  bool get isMeasured => pixelWidth != null && pixelHeight != null;

  /// `1024×1024`, or null when it could not be read.
  String? get dimensions => isMeasured ? '$pixelWidth×$pixelHeight' : null;

  Map<String, Object?> toJson() => {
    'path': path,
    'exists': exists,
    if (absolutePath != null) 'absolutePath': absolutePath,
    if (pixelWidth != null) 'width': pixelWidth,
    if (pixelHeight != null) 'height': pixelHeight,
    if (exists) 'png': isPng,
  };

  static SplashImageFacts fromJson(Map<String, Object?> json) =>
      SplashImageFacts(
        path: json['path']! as String,
        exists: json['exists'] == true,
        absolutePath: json['absolutePath'] as String?,
        pixelWidth: json['width'] as int?,
        pixelHeight: json['height'] as int?,
        isPng: json['png'] == true,
      );
}

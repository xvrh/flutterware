// @dart=2.12
/// GENERATED FILE: do not edit
/// This file was generated with the script tool/generate_assets_constants.dart

class AssetImageInfo {
  final String path;
  final double width, height;

  const AssetImageInfo(this.path, {required this.width, required this.height});
}

final assets = _Assets();

class _Assets {
  final images = _AssetsImages();
}

class _AssetsImages {
  AssetImageInfo get confluence =>
      const AssetImageInfo('assets/images/confluence.png',
          width: 99, height: 95);
  AssetImageInfo get googleAnalytics =>
      const AssetImageInfo('assets/images/google_analytics.png',
          width: 99, height: 99);
}

/* imageinfo cache:
{
  "assets/images/confluence.png 0fe4e4cbb0077aa5bf7ba79f82e9fd60003c7e5b": {
    "width": 99,
    "height": 95
  },
  "assets/images/google_analytics.png 66cffc4b52212c1800794ae5925265b7e670b95f": {
    "width": 99,
    "height": 99
  }
}
*/

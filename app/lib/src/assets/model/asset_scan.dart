import 'package:path/path.dart' as p;

import 'asset_catalog.dart';

/// One bundle, with the questions a reader actually asks already answered.
///
/// [AssetCatalog] says what resolves. This says how many, how heavy, and who is
/// responsible — which is a different job, and one with a cost: every byte
/// figure here is a `stat`.
///
/// That cost is why this exists at all. `PluginReport` is a pure read called on
/// every keystroke, so it cannot be the thing that touches the filesystem.
/// Computing the totals once, off the main isolate, is what lets the report
/// stay free.
class AssetScan {
  AssetScan._({
    required this.catalog,
    required this.own,
    required this.fromPackages,
    required this.ownBytes,
    required this.dependencyBytes,
  });

  factory AssetScan.of(AssetCatalog catalog) {
    var own = <ResolvedAsset>[];
    var byOwner = <String, List<ResolvedAsset>>{};
    for (var asset in catalog.assets) {
      if (asset.package == null) {
        own.add(asset);
      } else {
        byOwner.putIfAbsent(asset.package!, () => []).add(asset);
      }
    }
    own.sort((a, b) => a.key.compareTo(b.key));

    var owners = [
      for (var entry in byOwner.entries)
        AssetOwner(
          package: entry.key,
          assets: entry.value..sort((a, b) => a.key.compareTo(b.key)),
        ),
    ];
    // Heaviest first: the question a dependency list is asked is "what is in my
    // bundle that I did not put there", and the answer is sorted by weight.
    owners.sort((a, b) => b.bytes - a.bytes);

    return AssetScan._(
      catalog: catalog,
      own: own,
      fromPackages: owners,
      ownBytes: _bytesOf(own),
      dependencyBytes: owners.fold(0, (sum, owner) => sum + owner.bytes),
    );
  }

  final AssetCatalog catalog;

  /// The package's own assets, sorted by key.
  final List<ResolvedAsset> own;

  /// What each dependency contributes, heaviest first.
  final List<AssetOwner> fromPackages;

  final int ownBytes;
  final int dependencyBytes;

  int get totalBytes => ownBytes + dependencyBytes;
  int get totalCount => catalog.assets.length;

  List<FontFamily> get fonts => catalog.fonts;
  List<AssetProblem> get problems => catalog.problems;

  /// How many of the package's own assets are of each kind, most first.
  /// Dependency assets are left out: they are somebody else's shape.
  ///
  /// Ties break on [AssetKind]'s own order rather than on whichever key was
  /// inserted first, because this is projected into text that `fw` prints and a
  /// test asserts on — two runs over the same tree must read the same.
  late final Map<AssetKind, int> ownKinds = () {
    var counts = <AssetKind, int>{};
    for (var asset in own) {
      var kind = assetKindOf(asset.key);
      counts[kind] = (counts[kind] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) {
        var byCount = b.value - a.value;
        return byCount != 0 ? byCount : a.key.index - b.key.index;
      }),
    );
  }();
}

/// One dependency's contribution to a bundle.
class AssetOwner {
  AssetOwner({required this.package, required this.assets})
    : bytes = _bytesOf(assets);

  final String package;
  final List<ResolvedAsset> assets;
  final int bytes;
}

int _bytesOf(List<ResolvedAsset> assets) =>
    assets.fold(0, (sum, asset) => sum + asset.totalBytes);

/// What an asset is, as far as a list needs to group it.
///
/// Extension-based, so it costs nothing and is occasionally wrong. The one that
/// matters: a Lottie animation is a `.json` and is reported as [data] until
/// something opens it, because telling them apart means parsing the file and
/// this runs over every asset in the bundle.
enum AssetKind {
  image('Image', 'Images'),
  vector('Vector', 'Vectors'),
  font('Font', 'Fonts'),
  media('Media', 'Media'),
  data('Data', 'Data'),
  other('Other', 'Other');

  const AssetKind(this.label, this.plural);

  /// What one asset of this kind is. A filter chip counts a group and says
  /// [plural]; a detail pane describes one thing and says this.
  final String label;

  final String plural;
}

AssetKind assetKindOf(String key) {
  var extension = p.extension(key).toLowerCase();
  if (_images.contains(extension)) return AssetKind.image;
  if (extension == '.svg') return AssetKind.vector;
  if (_fonts.contains(extension)) return AssetKind.font;
  if (_media.contains(extension)) return AssetKind.media;
  if (_data.contains(extension)) return AssetKind.data;
  return AssetKind.other;
}

const _images = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico'};
const _fonts = {'.ttf', '.otf', '.ttc', '.woff', '.woff2'};
const _media = {'.mp3', '.wav', '.m4a', '.aac', '.mp4', '.mov', '.webm'};
const _data = {'.json', '.yaml', '.yml', '.txt', '.csv', '.md', '.xml'};

/// Bytes as a human reads them, in the same 1024-based units as the rest of the
/// app. Precise enough to compare two rows, short enough to sit in a column.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} kB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

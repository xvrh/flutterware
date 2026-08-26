import 'package:flutterware/plugins.dart';
import 'package:json_annotation/json_annotation.dart';

part 'store_results.g.dart';

/// `export` — the tree a store listing is uploaded from.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class StoreExportResult implements PluginResult {
  StoreExportResult({required this.packages, required this.count});

  final List<StoreExportPackage> packages;

  /// How many images were written, over every package, listing and locale.
  final int count;

  @override
  Map<String, Object?> toJson() => _$StoreExportResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class StoreExportPackage {
  StoreExportPackage({
    required this.path,
    required this.output,
    this.sets = const [],
    this.error,
  });

  final String path;

  /// The root of the tree — the layout decides what sits beneath it.
  final String output;

  final List<StoreExportSet> sets;

  /// Set when the package could not be run at all.
  final String? error;

  Map<String, Object?> toJson() => _$StoreExportPackageToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class StoreExportSet {
  StoreExportSet({
    required this.store,
    required this.deviceClass,
    required this.locale,
    required this.directory,
    required this.width,
    required this.height,
    required this.images,
    this.failed = 0,
  });

  /// `app-store` or `play`.
  final String store;

  /// The display class — `iphone-6-9`, `phone`.
  final String deviceClass;

  /// The **store's** locale tag, which is what the directory is named for.
  final String locale;

  /// Relative to [StoreExportPackage.output], so the whole tree can be moved
  /// or uploaded as it stands.
  final String directory;

  /// The canvas, in physical pixels — what the store receives.
  final int width;
  final int height;

  /// File names, in the order they were captured, which is the order they were
  /// numbered in and the order the store will show them.
  final List<String> images;

  /// Scenarios that failed while producing this set.
  final int failed;

  Map<String, Object?> toJson() => _$StoreExportSetToJson(this);
}

/// `open` — where the file manager was pointed.
@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class StoreOpenResult implements PluginResult {
  StoreOpenResult({required this.paths});

  /// One per package, absolute — the tree's root, not a file inside it.
  final List<String> paths;

  @override
  Map<String, Object?> toJson() => _$StoreOpenResultToJson(this);
}

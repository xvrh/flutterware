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
  StoreExportResult({required this.apps, required this.count});

  final List<StoreExportApp> apps;

  /// How many images were written, over every app, listing and locale.
  final int count;

  @override
  Map<String, Object?> toJson() => _$StoreExportResultToJson(this);
}

@JsonSerializable(
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class StoreExportApp {
  StoreExportApp({
    required this.app,
    required this.output,
    this.sets = const [],
    this.error,
  });

  /// The declared app's name — what `--app` takes and what its tree is
  /// called.
  final String app;

  /// The root of **this app's** tree, the app's own segment included. The
  /// layout decides what sits beneath it.
  final String output;

  final List<StoreExportSet> sets;

  /// Set when the app could not be run at all.
  final String? error;

  Map<String, Object?> toJson() => _$StoreExportAppToJson(this);
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
    this.framesFailed = 0,
  });

  /// `app-store` or `play`.
  final String store;

  /// The display class — `iphone-6-9`, `phone`.
  final String deviceClass;

  /// The **store's** locale tag, which is what the directory is named for.
  final String locale;

  /// Relative to [StoreExportApp.output], so the whole tree can be moved
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

  /// Shots whose frame could not be composed, and so were not written.
  ///
  /// Counted apart from [failed] because the two go wrong at different passes
  /// and a reader can act on only one of them: a scenario that failed produced
  /// no capture, while this had a capture the frame pass could not read.
  final int framesFailed;

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

  /// One per app, absolute — the tree's root, not a file inside it.
  final List<String> paths;

  @override
  Map<String, Object?> toJson() => _$StoreOpenResultToJson(this);
}

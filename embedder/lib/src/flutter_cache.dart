import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates artifacts inside a Flutter checkout's `bin/cache` directory.
class FlutterCache {
  FlutterCache(this.cacheDir);

  /// Path to `<flutter>/bin/cache`.
  final String cacheDir;

  /// Derives the cache directory from the running Dart executable, which must
  /// be the Dart SDK bundled in a Flutter checkout
  /// (`<flutter>/bin/cache/dart-sdk/bin/dart`).
  factory FlutterCache.fromRunningSdk() {
    var dart = Platform.resolvedExecutable;
    // <cache>/dart-sdk/bin/dart -> <cache>
    var cache = p.dirname(p.dirname(p.dirname(dart)));
    if (!Directory(p.join(cache, 'artifacts', 'engine')).existsSync()) {
      throw StateError(
          'Could not locate the Flutter cache from "$dart". Run this tool '
          'with the Dart SDK bundled in your Flutter checkout.');
    }
    return FlutterCache(cache);
  }

  String get _engine => p.join(cacheDir, 'artifacts', 'engine');

  /// The Flutter patched SDK directory, used as `--sdk-root` for the compiler.
  String get flutterPatchedSdkDir =>
      p.join(_engine, 'common', 'flutter_patched_sdk');

  /// The platform kernel passed as `--platform` to the compiler.
  String get platformDill =>
      p.join(flutterPatchedSdkDir, 'platform_strong.dill');

  /// ICU data the engine needs at startup.
  String get icuData => p.join(_engine, 'darwin-x64', 'icudtl.dat');

  /// The engine revision the cached artifacts were built at. Used to fetch the
  /// matching `FlutterEmbedder.framework` from Flutter's artifact storage.
  String get engineRevision =>
      File(p.join(cacheDir, 'engine.stamp')).readAsStringSync().trim();
}

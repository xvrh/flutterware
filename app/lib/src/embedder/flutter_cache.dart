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
        'with the Dart SDK bundled in your Flutter checkout.',
      );
    }
    return FlutterCache(cache);
  }

  /// The Flutter checkout root — `<flutter>`, the parent of `bin/cache`.
  String get flutterRoot => p.dirname(p.dirname(cacheDir));

  String get _engine => p.join(cacheDir, 'artifacts', 'engine');

  /// The Dart SDK bundled in this checkout — `<cache>/dart-sdk`.
  String get dartSdkDir => p.join(cacheDir, 'dart-sdk');

  String get _exe => Platform.isWindows ? '.exe' : '';

  /// The Dart VM, for anything that must run as a plain Dart process.
  String get dart => p.join(dartSdkDir, 'bin', 'dart$_exe');

  /// The AOT runtime the compiler runs on.
  String get dartAotRuntime => p.join(dartSdkDir, 'bin', 'dartaotruntime$_exe');

  /// The `frontend_server` snapshot [dartAotRuntime] runs.
  ///
  /// Named and located exactly as `flutter_tools` expects it
  /// (`Artifact.frontendServerSnapshotForEngineDartSdk`), because it is the
  /// same artifact — we spawn it ourselves rather than let a package infer the
  /// executable from whatever binary happens to be running.
  String get frontendServerSnapshot => p.join(
    dartSdkDir,
    'bin',
    'snapshots',
    'frontend_server_aot.dart.snapshot',
  );

  /// The Flutter patched SDK directory, used as `--sdk-root` for the compiler.
  String get flutterPatchedSdkDir =>
      p.join(_engine, 'common', 'flutter_patched_sdk');

  /// The platform kernel passed as `--platform` to the compiler.
  String get platformDill =>
      p.join(flutterPatchedSdkDir, 'platform_strong.dill');

  /// ICU data the *embedder guest's* engine needs at startup. macOS-only,
  /// like the `FlutterEmbedder.framework` it is loaded next to; the tester
  /// lane reads [testerIcuData] instead.
  //
  // `darwin-x64` is the canonical macOS desktop artifact directory for every
  // host architecture (including Apple Silicon) — there is no `darwin-arm64`
  // engine dir, and the engine binaries shipped here are universal.
  String get icuData => p.join(_engine, 'darwin-x64', 'icudtl.dat');

  /// The Impeller shader compiler, a host tool shipped in every desktop
  /// host's engine directory.
  String get impellerc => p.join(_hostEngineDir, 'impellerc$_exe');

  /// The include directory with impellerc's standard library.
  String get shaderLib => p.join(_hostEngineDir, 'shader_lib');

  /// The JIT isolate snapshot bundled as `isolate_snapshot_data` in a debug
  /// asset directory.
  String get isolateSnapshotData =>
      p.join(_hostEngineDir, 'isolate_snapshot.bin');

  /// The engine revision the cached artifacts were built at. Used to fetch the
  /// matching `FlutterEmbedder.framework` from Flutter's artifact storage.
  String get engineRevision =>
      File(p.join(cacheDir, 'engine.stamp')).readAsStringSync().trim();

  /// The host platform's engine artifact directory — unlike [icuData] this is
  /// not embedder-specific, so it covers the three desktop hosts.
  ///
  /// macOS is always `darwin-x64` — the binaries there are universal and no
  /// `darwin-arm64` dir exists — but Linux and Windows cache per architecture,
  /// so the suffix comes from the VM actually running this.
  String get _hostEngineDir {
    if (Platform.isMacOS) return p.join(_engine, 'darwin-x64');
    var os = Platform.isLinux ? 'linux' : 'windows';
    var arch = Platform.version.contains('arm64') ? 'arm64' : 'x64';
    return p.join(_engine, '$os-$arch');
  }

  /// The headless test shell `flutter test` runs — and the scenario runner
  /// spawns directly (S4, `2026-07-30-s4-flutter-tester-findings.md`).
  String get flutterTester => p.join(_hostEngineDir, 'flutter_tester$_exe');

  /// ICU data beside [flutterTester], for its `--icu-data-file-path`.
  String get testerIcuData => p.join(_hostEngineDir, 'icudtl.dat');
}

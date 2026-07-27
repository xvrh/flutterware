import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/catalog/asset_bundle.dart';
import 'package:flutterware_app/src/catalog/catalog_entry.dart';
import 'package:flutterware_app/src/catalog/discovery.dart';
import 'package:flutterware_app/src/catalog/protocol.dart';
import 'package:flutterware_app/src/catalog/entrypoint_generator.dart';
import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/resident_compiler.dart';
import 'package:path/path.dart' as p;

/// The catalog's build and compile half, as a plain Dart process.
///
/// It **must not** run inside a Flutter app: `FrontendServerClient` spawns the
/// compiler through `Platform.resolvedExecutable`, so an app that compiles
/// in-process relaunches itself, recursively. Hence a daemon.
///
/// Usage — the GUI spawns this with the Flutter SDK's `dart`:
///
/// ```sh
/// dart run tool/catalog/compiler_daemon.dart <config.json>
/// ```
///
/// stdout is line-delimited JSON protocol and nothing else; logs go to stderr.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: compiler_daemon.dart <config.json>');
    exit(64);
  }

  var config = DaemonConfig.fromJson(
    jsonDecode(File(args.single).readAsStringSync()) as Map<String, dynamic>,
  );
  var daemon = _Daemon(config);
  try {
    await daemon.prepare();
  } catch (e, s) {
    _emit(DaemonFailed(message: '$e', stackTrace: '$s'));
    exit(1);
  }

  await for (var line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    var json = tryDecodeLine(line);
    if (json == null) continue;
    switch (DaemonRequest.decode(json)) {
      case SelectRequest(:var id, :var full):
        await daemon.select(id, full: full);
      case ShutdownRequest():
        await daemon.shutdown();
        return;
    }
  }
  await daemon.shutdown();
}

class _Daemon {
  _Daemon(this.config)
    : _buildDir = p.join(config.appPackageRoot, 'build', 'catalog');

  final DaemonConfig config;
  final String _buildDir;

  late final FlutterCache _cache;
  late final EntrypointGenerator _generator;
  ResidentCompiler? _compiler;
  var _entries = <CatalogEntry>[];

  String get _assetsDir => p.join(_buildDir, 'assets');

  CatalogEntry _entryById(String id) => _entries.firstWhere((e) => e.id == id);

  /// Everything slow and one-time: the engine framework, the asset bundle, the
  /// first compile, and the C host.
  Future<void> prepare() async {
    var phase = Stopwatch()..start();
    void mark(String what) {
      stderr.writeln('[catalog] $what ${phase.elapsedMilliseconds}ms');
      phase.reset();
    }

    _cache = FlutterCache(p.join(config.flutterSdkRoot, 'bin', 'cache'));

    var scan = CatalogScanner(
      projectRoot: config.projectRoot,
      roots: config.roots,
      previewAnnotations: config.previewAnnotations,
    ).scan();
    if (!scan.ok) {
      // A duplicate id or an uncallable target means an entry would be missing
      // or unreachable; refusing beats starting a catalog that lies.
      throw StateError(
        'discovery failed:\n'
        '${scan.diagnostics.where((d) => d.isError).join('\n')}',
      );
    }
    mark('scan');
    _entries = scan.entries;
    if (_entries.isEmpty) {
      throw StateError(
        'no catalog entries found under ${config.roots.join(', ')} — is the '
        'annotation registered? (looking for '
        '${config.previewAnnotations.map((a) => '@$a').join(', ')})',
      );
    }
    _generator = EntrypointGenerator(
      outputDir: p.join(_buildDir, 'entrypoint'),
      projectRoot: config.projectRoot,
      emitProbe: config.emitProbe,
    );
    _generator.select(_entries.first);

    var engineDir = p.join(config.appPackageRoot, '.engine');
    await ensureEmbedderFramework(_cache, engineDir);
    mark('engine framework');
    await _ensureAssetBundle();
    mark('asset bundle');

    var watch = Stopwatch()..start();
    var compiler = _compiler = await ResidentCompiler.start(
      entrypoint: _generator.entrypointPath,
      outputDill: p.join(_assetsDir, 'kernel_blob.bin'),
      packageConfig: config.packageConfig,
      cache: _cache,
    );
    mark('compiler start');
    var cold = await compiler.compile();
    mark('cold compile');
    if (!cold.ok) {
      throw StateError(
        'the first entry did not compile:\n${cold.output.join('\n')}',
      );
    }

    var hostPath = await buildHost(
      nativeSourceDir: p.join(config.appPackageRoot, 'native'),
      nativeBuildDir: p.join(_buildDir, 'native'),
      engineDir: engineDir,
    );
    mark('host build');

    _emit(
      DaemonReady(
        hostPath: hostPath,
        assetsDir: _assetsDir,
        icuData: _cache.icuData,
        coldCompile: watch.elapsed,
        entries: _entries,
        diagnostics: [
          for (var d in scan.diagnostics)
            if (!d.isError) '$d',
        ],
      ),
    );
  }

  Future<void> select(String id, {bool full = false}) async {
    var entry = _entryById(id);
    var invalidated = _generator.select(entry);
    if (full) {
      // A fresh compiler's first compile writes the whole kernel to
      // kernel_blob.bin, which is what a guest spawned from scratch loads.
      // Everything else the daemon built — asset bundle, C host — is reused.
      await _compiler!.shutdown();
      _compiler = await ResidentCompiler.start(
        entrypoint: _generator.entrypointPath,
        outputDill: p.join(_assetsDir, 'kernel_blob.bin'),
        packageConfig: config.packageConfig,
        cache: _cache,
      );
    }
    var compiled = await _compiler!.compile(full ? const [] : invalidated);
    _emit(
      DaemonCompiled(
        id: id,
        dill: compiled.ok ? compiled.dillOutput : null,
        compile: compiled.elapsed,
        newSourceCount: compiled.newSourceCount,
        error: compiled.ok ? null : compiled.output.join('\n'),
      ),
    );
  }

  /// The asset directory the guest reads: manifests written here, payloads
  /// symlinked. Milliseconds, against seconds for `flutter build bundle` —
  /// see [AssetBundleBuilder]. Rebuilt every start, since it is cheap and a
  /// stale manifest is worse than a rebuild.
  Future<void> _ensureAssetBundle() async {
    await AssetBundleBuilder(
      cache: _cache,
      rootPackageRoot: config.appPackageRoot,
      packageConfigPath: config.packageConfig,
    ).build(_assetsDir);
  }

  Future<void> shutdown() async {
    await _compiler?.shutdown();
  }
}

void _emit(DaemonResponse message) {
  stdout.writeln(encodeLine(message));
}

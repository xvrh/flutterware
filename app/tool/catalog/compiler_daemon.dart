import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/catalog/catalog_entry.dart';
import 'package:flutterware_app/src/catalog/daemon_protocol.dart';
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
    jsonDecode(File(args.single).readAsStringSync()) as Map<String, Object?>,
  );
  var daemon = _Daemon(config);
  try {
    await daemon.prepare();
  } catch (e, s) {
    _emit({'type': 'error', 'message': '$e', 'stack': '$s'});
    exit(1);
  }

  await for (var line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    var message = jsonDecode(line) as Map<String, Object?>;
    switch (message['type']) {
      case 'select':
        await daemon.select(message['id']! as String);
      case 'shutdown':
        await daemon.shutdown();
        return;
      default:
        _emit({
          'type': 'error',
          'message': 'unknown message ${message['type']}',
        });
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

  String get _assetsDir => p.join(_buildDir, 'assets');

  CatalogEntry _entryById(String id) =>
      config.entries.firstWhere((e) => e.id == id);

  /// Everything slow and one-time: the engine framework, the asset bundle, the
  /// first compile, and the C host.
  Future<void> prepare() async {
    if (config.entries.isEmpty) throw StateError('the catalog has no entries');
    _cache = FlutterCache.fromRunningSdk();
    _generator = EntrypointGenerator(
      outputDir: p.join(_buildDir, 'entrypoint'),
      projectRoot: config.projectRoot,
      emitProbe: config.emitProbe,
    );
    _generator.select(config.entries.first);

    var engineDir = p.join(config.appPackageRoot, '.engine');
    await ensureEmbedderFramework(_cache, engineDir);
    await _ensureAssetBundle();

    var watch = Stopwatch()..start();
    var compiler = _compiler = await ResidentCompiler.start(
      entrypoint: _generator.entrypointPath,
      outputDill: p.join(_assetsDir, 'kernel_blob.bin'),
      packageConfig: config.packageConfig,
      cache: _cache,
    );
    var cold = await compiler.compile();
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

    _emit(
      DaemonReady(
        hostPath: hostPath,
        assetsDir: _assetsDir,
        icuData: _cache.icuData,
        coldCompile: watch.elapsed,
      ).toJson(),
    );
  }

  Future<void> select(String id) async {
    var entry = _entryById(id);
    var invalidated = _generator.select(entry);
    var compiled = await _compiler!.compile(invalidated);
    _emit(
      DaemonCompiled(
        id: id,
        ok: compiled.ok,
        dill: compiled.dillOutput,
        compile: compiled.elapsed,
        newSourceCount: compiled.newSourceCount,
        error: compiled.ok ? null : compiled.output.join('\n'),
      ).toJson(),
    );
  }

  /// The Flutter asset bundle — fonts, MaterialIcons, the manifests. Slow
  /// (~11s) and rarely changing, so it is cached; the resident compiler writes
  /// its kernel over the top.
  Future<void> _ensureAssetBundle() async {
    if (File(p.join(_assetsDir, 'FontManifest.json')).existsSync()) return;
    stderr.writeln('[catalog] building the Flutter asset bundle');
    var result = await Process.run(
      p.join(_cache.flutterRoot, 'bin', 'flutter'),
      [
        'build',
        'bundle',
        '-t',
        _generator.entrypointPath,
        '--asset-dir',
        _assetsDir,
      ],
      workingDirectory: config.appPackageRoot,
    );
    if (result.exitCode != 0) {
      throw StateError('flutter build bundle failed:\n${result.stderr}');
    }
  }

  Future<void> shutdown() async {
    await _compiler?.shutdown();
  }
}

void _emit(Map<String, Object?> message) {
  stdout.writeln(jsonEncode(message));
}

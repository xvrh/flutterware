import 'dart:io';

import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:path/path.dart' as p;

/// Ensures the embedder engine framework, compiles `scene.dart`, and builds the
/// C guest. On success prints three lines — `ASSETS_DIR=`, `ICU_DATA=`, and
/// `HOST_PATH=`. Run with the Flutter SDK's `dart`.
///
/// Usage: dart run tool/embedder/build_guest.dart
Future<void> main() async {
  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var repoRoot = p.dirname(packageRoot);
  var cache = FlutterCache.fromRunningSdk();

  var buildDir = p.join(packageRoot, 'build', 'embedder');
  var assetsDir = p.join(buildDir, 'assets');
  var engineDir = p.join(packageRoot, '.engine');
  Directory(buildDir).createSync(recursive: true);

  await ensureEmbedderFramework(cache, engineDir);
  await compileScene(
    scenePath: p.join(packageRoot, 'tool', 'embedder', 'scene.dart'),
    kernelBlob: p.join(assetsDir, 'kernel_blob.bin'),
    packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
    cache: cache,
  );
  var hostPath = await buildHost(
    nativeSourceDir: p.join(packageRoot, 'native'),
    nativeBuildDir: p.join(buildDir, 'native'),
    engineDir: engineDir,
  );

  stdout.writeln('ASSETS_DIR=$assetsDir');
  stdout.writeln('ICU_DATA=${cache.icuData}');
  stdout.writeln('HOST_PATH=$hostPath');
}

import 'dart:io';

import 'package:flutterware_app/src/embedder/compiler.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/raw_frame.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Downloads FlutterEmbedder.framework if needed, compiles scene.dart, builds
/// the C host, renders one frame, and encodes it to a PNG.
Future<void> main() async {
  // <app>/tool/embedder/run.dart -> <app>
  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  // This is a pub workspace: package_config.json lives at the repo root.
  var repoRoot = p.dirname(packageRoot);
  var cache = FlutterCache.fromRunningSdk();

  var buildDir = p.join(packageRoot, 'build', 'embedder');
  var assetsDir = p.join(buildDir, 'assets');
  var kernelBlob = p.join(assetsDir, 'kernel_blob.bin');
  var nativeBuildDir = p.join(buildDir, 'native');
  var engineDir = p.join(packageRoot, '.engine');
  var rawFrame = p.join(buildDir, 'scene.rawframe');
  var pngPath = p.join(buildDir, 'scene.png');

  await _ensureEmbedderFramework(cache, engineDir);

  stdout.writeln('[run] compiling scene.dart -> kernel_blob.bin');
  await compileToKernel(
    entrypoint: p.join(packageRoot, 'tool', 'embedder', 'scene.dart'),
    outputDill: kernelBlob,
    packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
    cache: cache,
  );

  stdout.writeln('[run] configuring + building the C host');
  await _run('cmake', [
    '-S',
    p.join(packageRoot, 'native'),
    '-B',
    nativeBuildDir,
    '-DFLUTTER_FRAMEWORK_DIR=$engineDir',
  ]);
  await _run('cmake', ['--build', nativeBuildDir]);

  stdout.writeln('[run] rendering the scene');
  var host = await Process.start(
    p.join(nativeBuildDir, 'host'),
    [assetsDir, cache.icuData, rawFrame],
    mode: ProcessStartMode.inheritStdio,
  );
  var hostExit = await host.exitCode;
  if (hostExit != 0) {
    stderr.writeln('[run] host failed ($hostExit)');
    exit(hostExit);
  }

  stdout.writeln('[run] encoding PNG');
  var image = decodeRawFrame(File(rawFrame).readAsBytesSync());
  File(pngPath).writeAsBytesSync(img.encodePng(image));
  stdout.writeln('[run] wrote $pngPath');
}

/// Ensures `FlutterEmbedder.framework` (the C embedder API, not part of the
/// local Flutter cache) is present under [engineDir], downloading it from
/// Flutter's artifact storage if it is missing or built for a different engine
/// revision.
Future<void> _ensureEmbedderFramework(
    FlutterCache cache, String engineDir) async {
  var revision = cache.engineRevision;
  var frameworkDir = p.join(engineDir, 'FlutterEmbedder.framework');
  var stamp = File(p.join(engineDir, 'engine.revision'));
  if (Directory(frameworkDir).existsSync() &&
      stamp.existsSync() &&
      stamp.readAsStringSync().trim() == revision) {
    return;
  }

  stdout.writeln('[run] downloading FlutterEmbedder.framework ($revision)');
  if (Directory(frameworkDir).existsSync()) {
    Directory(frameworkDir).deleteSync(recursive: true);
  }
  Directory(engineDir).createSync(recursive: true);

  var url = 'https://storage.googleapis.com/flutter_infra_release/flutter/'
      '$revision/darwin-x64/FlutterEmbedder.framework.zip';
  var zip = p.join(engineDir, 'FlutterEmbedder.framework.zip');
  await _run('curl', ['-fSL', url, '-o', zip]);
  // The zip's root entries are the framework's contents, so extract straight
  // into the `FlutterEmbedder.framework` directory.
  await _run('unzip', ['-q', '-o', zip, '-d', frameworkDir]);
  File(zip).deleteSync();
  stamp.writeAsStringSync(revision);
}

Future<void> _run(String executable, List<String> args) async {
  var process = await Process.start(executable, args,
      mode: ProcessStartMode.inheritStdio);
  var code = await process.exitCode;
  if (code != 0) {
    stderr.writeln('[run] `$executable ${args.join(' ')}` failed ($code)');
    exit(code);
  }
}

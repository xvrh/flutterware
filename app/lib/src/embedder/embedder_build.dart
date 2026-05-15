import 'dart:io';

import 'package:path/path.dart' as p;

import 'compiler.dart';
import 'flutter_cache.dart';

/// Ensures `FlutterEmbedder.framework` (the C embedder API, not part of the
/// local Flutter cache) is present under [engineDir], downloading it from
/// Flutter's artifact storage if it is missing or built for a different
/// engine revision.
Future<void> ensureEmbedderFramework(
    FlutterCache cache, String engineDir) async {
  var revision = cache.engineRevision;
  var frameworkDir = p.join(engineDir, 'FlutterEmbedder.framework');
  var stamp = File(p.join(engineDir, 'engine.revision'));
  if (Directory(frameworkDir).existsSync() &&
      stamp.existsSync() &&
      stamp.readAsStringSync().trim() == revision) {
    return;
  }

  stdout
      .writeln('[embedder] downloading FlutterEmbedder.framework ($revision)');
  if (Directory(frameworkDir).existsSync()) {
    Directory(frameworkDir).deleteSync(recursive: true);
  }
  Directory(engineDir).createSync(recursive: true);

  var url = 'https://storage.googleapis.com/flutter_infra_release/flutter/'
      '$revision/darwin-x64/FlutterEmbedder.framework.zip';
  var zip = p.join(engineDir, 'FlutterEmbedder.framework.zip');
  await _run('curl', ['-fSL', url, '-o', zip]);
  await _run('unzip', ['-q', '-o', zip, '-d', frameworkDir]);
  File(zip).deleteSync();
  stamp.writeAsStringSync(revision);
}

/// Compiles the embedder scene at [scenePath] to a kernel blob at [kernelBlob].
Future<void> compileScene({
  required String scenePath,
  required String kernelBlob,
  required String packageConfig,
  required FlutterCache cache,
}) async {
  stdout.writeln('[embedder] compiling ${p.basename(scenePath)} -> kernel');
  await compileToKernel(
    entrypoint: scenePath,
    outputDill: kernelBlob,
    packageConfig: packageConfig,
    cache: cache,
  );
}

/// Configures and builds the C host with CMake into [nativeBuildDir].
/// Returns the path to the built `host` executable.
Future<String> buildHost({
  required String nativeSourceDir,
  required String nativeBuildDir,
  required String engineDir,
}) async {
  stdout.writeln('[embedder] configuring + building the C host');
  await _run('cmake', [
    '-S',
    nativeSourceDir,
    '-B',
    nativeBuildDir,
    '-DFLUTTER_FRAMEWORK_DIR=$engineDir',
  ]);
  await _run('cmake', ['--build', nativeBuildDir]);
  return p.join(nativeBuildDir, 'host');
}

Future<void> _run(String executable, List<String> args) async {
  var process = await Process.start(executable, args,
      mode: ProcessStartMode.inheritStdio);
  var code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, args, 'exited with $code', code);
  }
}

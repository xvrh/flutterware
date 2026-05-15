import 'dart:io';

import 'package:frontend_server_client/frontend_server_client.dart';

import 'src/flutter_cache.dart';

/// Compiles [entrypoint] to a Flutter-target kernel blob at [outputDill] using
/// the Flutter cache's `frontend_server`.
///
/// [cache] defaults to the cache of the running Dart SDK. Returns the written
/// kernel file. Throws [StateError] on compilation errors.
Future<File> compileToKernel({
  required String entrypoint,
  required String outputDill,
  required String packageConfig,
  FlutterCache? cache,
}) async {
  cache ??= FlutterCache.fromRunningSdk();
  File(outputDill).parent.createSync(recursive: true);

  var client = await FrontendServerClient.start(
    entrypoint,
    outputDill,
    cache.platformDill,
    sdkRoot: cache.flutterPatchedSdkDir,
    target: 'flutter',
    packagesJson: packageConfig,
  );
  try {
    var result = await client.compile();
    if (result.dillOutput == null) {
      throw StateError('frontend_server produced no kernel output.');
    }
    if (result.errorCount > 0) {
      throw StateError('Compilation failed:\n'
          '${result.compilerOutputLines.join('\n')}');
    }
    client.accept();
    return File(result.dillOutput!);
  } finally {
    await client.shutdown();
  }
}

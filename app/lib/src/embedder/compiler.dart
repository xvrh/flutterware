import 'dart:io';

import 'package:path/path.dart' as p;

import 'flutter_cache.dart';
import 'frontend_server.dart';

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

  var server = await FrontendServer.start(
    executable: cache.dartAotRuntime,
    snapshot: cache.frontendServerSnapshot,
    entrypoint: entrypoint,
    outputDill: outputDill,
    packageConfig: packageConfig,
    sdkRoot: cache.flutterPatchedSdkDir,
    platformDill: cache.platformDill,
    // Nothing here attributes a diagnostic to anything — an error is thrown
    // with the compiler's own words in it — so this only decides how the paths
    // in that message read. The package config sits at
    // `<root>/.dart_tool/package_config.json`, so its grandparent is the root
    // the message should be relative to.
    workingDirectory: p.dirname(p.dirname(p.absolute(packageConfig))),
  );
  try {
    var result = await server.compile();
    if (result.dillOutput == null) {
      throw StateError('frontend_server produced no kernel output.');
    }
    if (result.errorCount > 0) {
      throw StateError('Compilation failed:\n${result.output.join('\n')}');
    }
    server.accept();
    return File(result.dillOutput!);
  } finally {
    await server.shutdown();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/catalog/asset_bundle.dart';
import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:path/path.dart' as p;

/// Asks whether `flutter build bundle` is actually needed to run the guest.
///
/// Renders the same scene twice — once against a bundle the Flutter tool
/// produced, once against a directory of symlinks assembled here — and compares
/// the rendered frames byte for byte. The scene uses Material icons and text,
/// because fonts are what a hand-assembled bundle is most likely to get wrong.
///
/// ```sh
/// cd app && dart run tool/catalog/bundle_probe.dart
/// ```
Future<void> main() async {
  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var repoRoot = p.dirname(packageRoot);
  var cache = FlutterCache.fromRunningSdk();
  var work = Directory(p.join(packageRoot, 'build', 'bundle_probe'))
    ..createSync(recursive: true);

  var scene = File(p.join(work.path, 'scene.dart'))
    ..writeAsStringSync('''
import 'package:flutter/material.dart';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.home_outlined, size: 48),
                Icon(Icons.settings_outlined, size: 48),
                Icon(Icons.table_chart_outlined, size: 48),
              ],
            ),
            SizedBox(height: 24),
            Text('Bundle probe', style: TextStyle(fontSize: 32)),
          ],
        ),
      ),
    ),
  ),
);
''');

  await ensureEmbedderFramework(cache, p.join(packageRoot, '.engine'));
  var hostPath = await buildHost(
    nativeSourceDir: p.join(packageRoot, 'native'),
    nativeBuildDir: p.join(packageRoot, 'build', 'catalog', 'native'),
    engineDir: p.join(packageRoot, '.engine'),
  );

  // A — what the Flutter tool builds.
  var toolDir = p.join(work.path, 'tool_bundle');
  var watch = Stopwatch()..start();
  var built = await Process.run(p.join(cache.flutterRoot, 'bin', 'flutter'), [
    'build',
    'bundle',
    '-t',
    scene.path,
    '--asset-dir',
    toolDir,
  ], workingDirectory: packageRoot);
  if (built.exitCode != 0) {
    stderr.writeln('flutter build bundle failed:\n${built.stderr}');
    exit(1);
  }
  stdout.writeln('flutter build bundle : ${watch.elapsedMilliseconds}ms');

  // B — manifests written, payloads symlinked.
  var fastDir = p.join(work.path, 'fast_bundle');
  watch.reset();
  await AssetBundleBuilder(
    cache: cache,
    rootPackageRoot: packageRoot,
    packageConfigPath: p.join(repoRoot, '.dart_tool', 'package_config.json'),
  ).build(fastDir);
  stdout.writeln('AssetBundleBuilder   : ${watch.elapsedMilliseconds}ms');

  // The same kernel in both, so only the asset half differs.
  await compileScene(
    scenePath: scene.path,
    kernelBlob: p.join(toolDir, 'kernel_blob.bin'),
    packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
    cache: cache,
  );
  File(
    p.join(toolDir, 'kernel_blob.bin'),
  ).copySync(p.join(fastDir, 'kernel_blob.bin'));

  var a = await _render(hostPath, toolDir, cache, work.path, 'tool');
  var b = await _render(hostPath, fastDir, cache, work.path, 'fast');

  stdout.writeln('tool bundle frame    : ${a.length} bytes, ${_digest(a)}');
  stdout.writeln('fast bundle frame    : ${b.length} bytes, ${_digest(b)}');

  var identical = a.length == b.length && _digest(a) == _digest(b);
  stdout.writeln(
    identical
        ? '\nIDENTICAL — the symlinked bundle renders exactly the same frame.'
        : '\nDIFFERENT — the symlinked bundle is not equivalent.',
  );
  exit(identical ? 0 : 1);
}

Future<List<int>> _render(
  String hostPath,
  String assetsDir,
  FlutterCache cache,
  String workDir,
  String label,
) async {
  var socketPath = p.join(workDir, '$label.sock');
  var rawFrame = p.join(workDir, '$label.rawframe');
  for (var path in [socketPath, rawFrame]) {
    var file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
  var server = await ServerSocket.bind(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  );

  var guest = await Process.start(hostPath, [
    assetsDir,
    cache.icuData,
    socketPath,
    '800',
    '600',
    '--capture-raw',
    rawFrame,
  ]);
  unawaited(guest.stdout.drain<void>());
  unawaited(guest.stderr.drain<void>());

  var conn = await server.first;
  var reader = FrameReader();
  loop:
  await for (var chunk in conn) {
    for (var message in reader.addBytes(chunk)) {
      if (message is FrameReadyMessage) break loop;
      if (message is ErrorMessage) {
        stderr.writeln('[$label] guest error: ${message.message}');
        guest.kill();
        exit(1);
      }
    }
  }
  // Let the first frame settle before capturing; fonts resolve asynchronously.
  await Future<void>.delayed(const Duration(seconds: 2));

  conn.add(encodeMessage(const ShutdownMessage()));
  await conn.flush();
  await conn.close();
  await guest.exitCode;
  await server.close();
  var socket = File(socketPath);
  if (socket.existsSync()) socket.deleteSync();
  return File(rawFrame).readAsBytesSync();
}

/// A cheap content fingerprint; the frames are either identical or not.
String _digest(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (var byte in bytes) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

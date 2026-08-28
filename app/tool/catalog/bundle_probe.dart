import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutterware_app/src/previews/asset_bundle.dart';
import 'package:flutterware_app/src/previews/package_config_locator.dart';
import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
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

  var engineDir = await ensureEmbedderEngine(cache);
  var hostPath = await buildHost(
    nativeSourceDir: p.join(packageRoot, 'native'),
    nativeBuildDir: p.join(packageRoot, 'build', 'catalog', 'native'),
    engineDir: engineDir,
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
    packageConfig: requirePackageConfig(packageRoot),
    cache: cache,
  );
  File(p.join(toolDir, 'kernel_blob.bin'))
      .copySync(p.join(fastDir, 'kernel_blob.bin'));

  // The scene never draws the framework shaders, so frame identity cannot
  // vouch for them; their compiled bytes are compared directly instead.
  for (var shader in ['ink_sparkle.frag', 'stretch_effect.frag']) {
    var tool = File(p.join(toolDir, 'shaders', shader)).readAsBytesSync();
    var fast = File(p.join(fastDir, 'shaders', shader)).readAsBytesSync();
    var same = tool.length == fast.length && _digest(tool) == _digest(fast);
    stdout.writeln(
      'shaders/$shader ${same ? '— identical (${tool.length} bytes)' : '— DIFFERENT'}',
    );
    if (!same) exit(1);
  }

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
  // Under the run dir, not [workDir]: a unix socket path is capped at 104
  // bytes, and a build directory inside a worktree already spends most of
  // that. The hash keeps two checkouts' probes apart.
  var key = sha1.convert(utf8.encode(workDir)).toString().substring(0, 12);
  var socketPath = checkSocketPath(
    p.join(flutterwareRunDir(), 'probe-$key-$label.sock'),
  );
  var rawFrame = p.join(workDir, '$label.rawframe');
  for (var path in [socketPath, rawFrame]) {
    var file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
  var server = await ServerSocket.bind(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  );

  // No `--capture-raw`: that arms a one-shot capture the *first* presented
  // frame consumes, which photographs the scene before anything asynchronous
  // — an image decode above all — has landed. Instead the scene gets a moment
  // to settle after its first frame, and then a capture of a current frame is
  // asked for explicitly.
  var guest = await Process.start(hostPath, [
    assetsDir,
    cache.icuData,
    socketPath,
    '800',
    '600',
  ]);
  unawaited(guest.stdout.drain<void>());
  unawaited(guest.stderr.drain<void>());

  var conn = await server.first;
  var reader = FrameReader();
  var sawFrame = Completer<void>();
  var captured = Completer<void>();
  var subscription = conn.listen((chunk) {
    for (var message in reader.addBytes(chunk)) {
      if (message is FrameReadyMessage && !sawFrame.isCompleted) {
        sawFrame.complete();
      }
      if (message is CapturedMessage) captured.complete();
      if (message is ErrorMessage) {
        stderr.writeln('[$label] guest error: ${message.message}');
        guest.kill();
        exit(1);
      }
    }
  });
  await sawFrame.future;
  await Future<void>.delayed(const Duration(seconds: 2));
  conn.add(encodeMessage(CaptureMessage(rawFrame)));
  await conn.flush();
  await captured.future;
  await subscription.cancel();

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

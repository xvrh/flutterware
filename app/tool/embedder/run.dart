import 'dart:async';
import 'dart:io';

import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:flutterware_app/src/embedder/raw_frame.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Spawns the embedder guest, captures its first rendered frame, and encodes
/// it to a PNG at `build/embedder/scene.png`.
Future<void> main() async {
  // <app>/tool/embedder/run.dart -> <app>
  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var repoRoot = p.dirname(packageRoot);
  var cache = FlutterCache.fromRunningSdk();

  var buildDir = p.join(packageRoot, 'build', 'embedder');
  var assetsDir = p.join(buildDir, 'assets');
  var kernelBlob = p.join(assetsDir, 'kernel_blob.bin');
  var nativeBuildDir = p.join(buildDir, 'native');
  var engineDir = p.join(packageRoot, '.engine');
  var rawFrame = p.join(buildDir, 'scene.rawframe');
  var pngPath = p.join(buildDir, 'scene.png');
  var socketPath = p.join(buildDir, 'embedder.sock');

  Directory(buildDir).createSync(recursive: true);

  await ensureEmbedderFramework(cache, engineDir);
  await compileScene(
    scenePath: p.join(packageRoot, 'tool', 'embedder', 'scene.dart'),
    kernelBlob: kernelBlob,
    packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
    cache: cache,
  );
  var hostPath = await buildHost(
    nativeSourceDir: p.join(packageRoot, 'native'),
    nativeBuildDir: nativeBuildDir,
    engineDir: engineDir,
  );

  var socketFile = File(socketPath);
  if (socketFile.existsSync()) socketFile.deleteSync();
  var server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix), 0);

  stdout.writeln('[run] spawning guest');
  var guest = await Process.start(
    hostPath,
    [
      assetsDir,
      cache.icuData,
      socketPath,
      '800',
      '600',
      '--capture-raw',
      rawFrame
    ],
    mode: ProcessStartMode.inheritStdio,
  );

  var conn = await server.first;
  var reader = FrameReader();
  var gotFrame = false;
  loop:
  await for (var chunk in conn) {
    for (var message in reader.addBytes(chunk)) {
      if (message is FrameReadyMessage) {
        gotFrame = true;
        break loop;
      }
      if (message is ErrorMessage) {
        stderr.writeln('[run] guest error: ${message.message}');
        guest.kill();
        await server.close();
        exit(1);
      }
    }
  }

  conn.add(encodeMessage(const ShutdownMessage()));
  await conn.flush();
  await conn.close();
  await guest.exitCode;
  await server.close();
  if (socketFile.existsSync()) socketFile.deleteSync();

  if (!gotFrame) {
    stderr.writeln('[run] guest closed the socket before rendering a frame');
    exit(1);
  }

  stdout.writeln('[run] encoding PNG');
  var image = decodeRawFrame(File(rawFrame).readAsBytesSync());
  File(pngPath).writeAsBytesSync(img.encodePng(image));
  stdout.writeln('[run] wrote $pngPath');
}

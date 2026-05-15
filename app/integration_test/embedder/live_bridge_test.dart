import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('guest streams live frames and re-allocates surfaces on resize',
      () async {
    // `dart test` runs with the package root (<app>) as the current directory.
    var packageRoot = Directory.current.path;
    var repoRoot = p.dirname(packageRoot);
    var cache = FlutterCache.fromRunningSdk();

    var buildDir = p.join(packageRoot, 'build', 'embedder');
    var assetsDir = p.join(buildDir, 'assets');
    var engineDir = p.join(packageRoot, '.engine');
    var socketPath = p.join(buildDir, 'embedder_test.sock');
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

    var socketFile = File(socketPath);
    if (socketFile.existsSync()) socketFile.deleteSync();
    var server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix), 0);

    var guest = await Process.start(
      hostPath,
      [assetsDir, cache.icuData, socketPath, '800', '600'],
      mode: ProcessStartMode.inheritStdio,
    );
    addTearDown(() async {
      guest.kill();
      await server.close();
      if (socketFile.existsSync()) socketFile.deleteSync();
    });

    var conn = await server.first;
    var reader = FrameReader();
    // ignore: close_sinks, closed below via the socket's onDone handler.
    var incoming = StreamController<EmbedderMessage>();
    conn.listen((chunk) {
      for (var message in reader.addBytes(chunk)) {
        incoming.add(message);
      }
    }, onDone: incoming.close);
    var messages = StreamQueue<EmbedderMessage>(incoming.stream);

    Future<T> next<T extends EmbedderMessage>() async {
      while (true) {
        var message = await messages.next.timeout(const Duration(seconds: 30));
        if (message is ErrorMessage) {
          fail('guest error: ${message.message}');
        }
        if (message is T) return message;
      }
    }

    // Startup: Ready then SurfacesAllocated for an 800x600 ring of 3.
    await next<ReadyMessage>();
    var first = await next<SurfacesAllocatedMessage>();
    expect(first.width, 800);
    expect(first.height, 600);
    expect(first.surfaceIds, hasLength(3));
    expect(first.surfaceIds.every((id) => id != 0), isTrue);

    // Continuous frames: collect several with strictly increasing frameIds.
    var frameIds = <int>[];
    while (frameIds.length < 5) {
      frameIds.add((await next<FrameReadyMessage>()).frameId);
    }
    for (var i = 1; i < frameIds.length; i++) {
      expect(frameIds[i], greaterThan(frameIds[i - 1]),
          reason: 'frameId must increase: $frameIds');
    }

    // Resize: the guest re-allocates surfaces at the new size.
    conn.add(encodeMessage(
        const ResizeMessage(width: 1024, height: 768, pixelRatio: 1.0)));
    await conn.flush();
    var resized = await next<SurfacesAllocatedMessage>();
    expect(resized.width, 1024);
    expect(resized.height, 768);
    expect(resized.generation, greaterThan(first.generation));

    // Frames keep flowing after the resize.
    await next<FrameReadyMessage>();

    conn.add(encodeMessage(const ShutdownMessage()));
    await conn.flush();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

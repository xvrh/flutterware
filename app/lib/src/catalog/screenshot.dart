import 'dart:async';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../embedder/protocol.dart';
import '../embedder/raw_frame.dart';
import 'compiler_daemon_client.dart';
import 'protocol.dart';

/// Renders one catalog entry to a PNG, with no GUI involved.
///
/// This is the first of the artifact commands the plan calls the AI surface:
/// the same pipeline the GUI drives, invoked by whoever asks — a button, `fw`,
/// or an agent. Nothing here touches Flutter, so it runs anywhere the daemon
/// does.
///
/// The guest is spawned with `--capture-raw`, which writes the composited frame
/// the user would have seen rather than re-rasterising it.
class CatalogScreenshot {
  CatalogScreenshot({
    required this.dartExecutable,
    required this.hostPath,
    required this.config,
  });

  /// A real Dart VM — the Flutter SDK's `dart`, never the running executable
  /// when that is a Flutter app.
  final String dartExecutable;

  /// The built embedder host binary.
  final String hostPath;

  final DaemonConfig config;

  /// Screenshots [entryId] into [output].
  ///
  /// Starts a daemon, compiles the entry, renders one frame, and shuts
  /// everything down. Fine for one entry; a batch wants a session that stays
  /// warm, which is why [captureAll] exists.
  Future<File> capture({
    required String entryId,
    required String output,
    int width = 900,
    int height = 700,
  }) async {
    var results = await captureAll(
      entryIds: [entryId],
      outputFor: (_) => output,
      width: width,
      height: height,
    );
    return results.values.single;
  }

  /// Screenshots several entries against **one** daemon.
  ///
  /// The asset bundle and the C host are built once, but each entry still pays
  /// a full compile, because `host.c` captures only its first frame
  /// (`g_captured`) so every entry needs its own guest, and a fresh guest reads
  /// the whole kernel rather than a delta. Making this as cheap as browsing
  /// means teaching the host to capture on demand — then one warm guest could
  /// reload between entries at ~70ms each.
  Future<Map<String, File>> captureAll({
    required List<String> entryIds,
    required String Function(String entryId) outputFor,
    int width = 900,
    int height = 700,
  }) async {
    var (daemon, ready) = await CompilerDaemonClient.start(
      dartExecutable: dartExecutable,
      config: config,
    );
    try {
      var known = {for (var entry in ready.entries) entry.id};
      for (var id in entryIds) {
        if (!known.contains(id)) {
          throw ArgumentError.value(
            id,
            'entryId',
            'no such entry. Known ids: ${known.join(', ')}',
          );
        }
      }

      var captured = <String, File>{};
      for (var id in entryIds) {
        // Full, not incremental: each screenshot spawns its own guest, and a
        // delta means nothing to a process that was never running.
        var compiled = await daemon.select(id, full: true);
        if (!compiled.ok) {
          throw StateError('$id did not compile:\n${compiled.error}');
        }
        captured[id] = await _renderOnce(
          assetsDir: ready.assetsDir,
          icuData: ready.icuData,
          output: outputFor(id),
          width: width,
          height: height,
        );
      }
      return captured;
    } finally {
      await daemon.shutdown();
    }
  }

  /// Spawns the guest, waits for a composited frame, and encodes it.
  ///
  /// A fresh guest per entry: the daemon has already done the expensive work,
  /// and a guest that renders once and exits needs no reload plumbing.
  Future<File> _renderOnce({
    required String assetsDir,
    required String icuData,
    required String output,
    required int width,
    required int height,
  }) async {
    var workDir = p.join(config.appPackageRoot, 'build', 'catalog');
    var socketPath = p.join(workDir, 'screenshot.sock');
    var rawFrame = p.join(workDir, 'screenshot.rawframe');
    for (var path in [socketPath, rawFrame]) {
      var file = File(path);
      if (file.existsSync()) file.deleteSync();
    }

    var server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    Process? guest;
    try {
      guest = await Process.start(hostPath, [
        assetsDir,
        icuData,
        socketPath,
        '$width',
        '$height',
        '--capture-raw',
        rawFrame,
      ]);
      unawaited(guest.stdout.drain<void>());
      unawaited(guest.stderr.drain<void>());

      var connection = await Future.any<Object?>([
        server.first,
        guest.exitCode,
      ]);
      if (connection is! Socket) {
        throw StateError('the guest exited before rendering');
      }

      var reader = FrameReader();
      var rendered = Completer<void>();
      connection.listen((chunk) {
        for (var message in reader.addBytes(chunk)) {
          if (message is FrameReadyMessage && !rendered.isCompleted) {
            rendered.complete();
          }
          if (message is ErrorMessage && !rendered.isCompleted) {
            rendered.completeError(StateError(message.message));
          }
        }
      });
      await rendered.future.timeout(const Duration(seconds: 30));
      // The first frame can precede the fonts resolving; let it settle so the
      // artifact matches what a viewer would see.
      await Future<void>.delayed(const Duration(seconds: 1));

      connection.add(encodeMessage(const ShutdownMessage()));
      await connection.flush();
      await connection.close();

      var image = decodeRawFrame(File(rawFrame).readAsBytesSync());
      var file = File(output);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(img.encodePng(image));
      return file;
    } finally {
      guest?.kill();
      await server.close();
      for (var path in [socketPath, rawFrame]) {
        var file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
    }
  }
}

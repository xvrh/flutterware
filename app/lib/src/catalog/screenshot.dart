import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../embedder/protocol.dart';
import '../embedder/raw_frame.dart';
import '../embedder/guest_vm_service.dart';
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

  /// Screenshots several entries against **one** daemon and **one** guest.
  ///
  /// The first entry pays a cold compile and a guest launch. Every entry after
  /// it is a hot reload and a capture request — the same economics as browsing,
  /// because it is the same mechanism.
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
    _GuestSession? guest;
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
        if (guest == null) {
          // The guest loads the kernel from disk at launch, so the first entry
          // needs a whole one; afterwards a delta is all a live isolate wants.
          var compiled = await daemon.select(id, full: true);
          if (!compiled.ok) {
            throw StateError('$id did not compile:\n${compiled.error}');
          }
          guest = await _GuestSession.start(
            hostPath: hostPath,
            assetsDir: ready.assetsDir,
            icuData: ready.icuData,
            workDir: p.join(config.appPackageRoot, 'build', 'catalog'),
            width: width,
            height: height,
          );
        } else {
          var compiled = await daemon.select(id);
          if (!compiled.ok) {
            throw StateError('$id did not compile:\n${compiled.error}');
          }
          await guest.reload(compiled.dill!);
        }
        captured[id] = await guest.capture(outputFor(id));
      }
      return captured;
    } finally {
      await guest?.close();
      await daemon.shutdown();
    }
  }
}

/// One embedder guest, kept alive across captures.
class _GuestSession {
  _GuestSession._(
    this._guest,
    this._connection,
    this._server,
    this._reader,
    this._vmService,
    this._workDir,
  );

  final Process _guest;
  final Socket _connection;
  final ServerSocket _server;
  final FrameReader _reader;
  final GuestVmService _vmService;
  final String _workDir;

  final _captures = <String, Completer<void>>{};

  static Future<_GuestSession> start({
    required String hostPath,
    required String assetsDir,
    required String icuData,
    required String workDir,
    required int width,
    required int height,
  }) async {
    var socketPath = p.join(workDir, 'screenshot.sock');
    var socket = File(socketPath);
    if (socket.existsSync()) socket.deleteSync();
    var server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );

    var guest = await Process.start(hostPath, [
      assetsDir,
      icuData,
      socketPath,
      '$width',
      '$height',
    ]);
    var vmServiceUri = Completer<String>();
    guest.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
          if (match != null && !vmServiceUri.isCompleted) {
            vmServiceUri.complete(match.group(1));
          }
        });
    unawaited(guest.stderr.drain<void>());

    var connected = await Future.any<Object?>([server.first, guest.exitCode]);
    if (connected is! Socket) {
      throw StateError('the guest exited before connecting');
    }

    var session = _GuestSession._(
      guest,
      connected,
      server,
      FrameReader(),
      await GuestVmService.connect(await vmServiceUri.future),
      workDir,
    );
    connected.listen(session._onData);
    return session;
  }

  void _onData(List<int> chunk) {
    for (var message in _reader.addBytes(chunk)) {
      if (message is CapturedMessage) {
        _captures.remove(message.path)?.complete();
      } else if (message is ErrorMessage) {
        for (var pending in _captures.values) {
          if (!pending.isCompleted) {
            pending.completeError(StateError(message.message));
          }
        }
        _captures.clear();
      }
    }
  }

  Future<void> reload(String dill) => _vmService.reload(dill);

  /// Asks the guest to write its next frame, and waits for the ack.
  Future<File> capture(String output) async {
    var rawFrame = p.join(_workDir, 'screenshot.rawframe');
    var raw = File(rawFrame);
    if (raw.existsSync()) raw.deleteSync();

    var done = _captures[rawFrame] = Completer<void>();
    _connection.add(encodeMessage(CaptureMessage(rawFrame)));
    await _connection.flush();
    await done.future.timeout(const Duration(seconds: 30));

    var image = decodeRawFrame(raw.readAsBytesSync());
    var file = File(output);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(image));
    raw.deleteSync();
    return file;
  }

  Future<void> close() async {
    await _vmService.close();
    _connection.add(encodeMessage(const ShutdownMessage()));
    await _connection.flush();
    await _connection.close();
    _guest.kill();
    await _server.close();
  }
}

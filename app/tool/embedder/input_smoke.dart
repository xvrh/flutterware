import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:path/path.dart' as p;

/// Drives an already-built guest (see `run.dart` / the live-bridge test for
/// the build) with the full pointer vocabulary — moves, a click, a scroll
/// wheel and a trackpad pan-zoom sequence — and checks frames keep flowing
/// after each. A guest that mis-parses an event dies or stops compositing;
/// either shows up here as a timeout or an early exit.
Future<void> main() async {
  var packageRoot = Directory.current.path;
  var buildDir = p.join(packageRoot, 'build', 'embedder');
  var hostPath = p.join(buildDir, 'native', 'host');
  var assetsDir = p.join(buildDir, 'assets');
  var icuData = FlutterCache.fromRunningSdk().icuData;

  // Not under the build dir: a worktree's absolute path overflows the 104-byte
  // unix socket cap.
  var socketPath = p.join(
    Directory.systemTemp.createTempSync('fw-smoke').path,
    's.sock',
  );
  var server = await ServerSocket.bind(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  );

  var guest = await Process.start(hostPath, [
    assetsDir,
    icuData,
    socketPath,
    '800',
    '600',
  ], mode: ProcessStartMode.inheritStdio);

  var conn = await server.first;
  var reader = FrameReader();
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
        throw StateError('guest error: ${message.message}');
      }
      if (message is T) return message;
    }
  }

  void send(EmbedderMessage message) => conn.add(encodeMessage(message));
  var now = DateTime.now().microsecondsSinceEpoch;
  PointerEventMessage pointer(
    PointerPhase phase, {
    int buttons = 0,
    double scrollDeltaY = 0,
    double panY = 0,
    double scale = 1,
  }) => PointerEventMessage(
    phase: phase,
    x: 400,
    y: 300,
    buttons: buttons,
    scrollDeltaX: 0,
    scrollDeltaY: scrollDeltaY,
    timestampMicros: now,
    panY: panY,
    scale: scale,
  );

  await next<ReadyMessage>();
  await next<SurfacesAllocatedMessage>();
  var last = (await next<FrameReadyMessage>()).frameId;

  Future<void> expectFramesAfter(String what) async {
    var id = (await next<FrameReadyMessage>()).frameId;
    if (id <= last) throw StateError('$what: frameId did not advance');
    last = id;
    stdout.writeln('[smoke] frames still flowing after $what');
  }

  send(pointer(PointerPhase.add));
  send(pointer(PointerPhase.hover));
  send(pointer(PointerPhase.down, buttons: 1));
  send(pointer(PointerPhase.up));
  await conn.flush();
  await expectFramesAfter('click');

  send(pointer(PointerPhase.hover, scrollDeltaY: -53));
  await conn.flush();
  await expectFramesAfter('scroll wheel');

  send(pointer(PointerPhase.panZoomStart));
  send(pointer(PointerPhase.panZoomUpdate, panY: -40));
  send(pointer(PointerPhase.panZoomUpdate, panY: -90, scale: 1.1));
  send(pointer(PointerPhase.panZoomEnd));
  await conn.flush();
  await expectFramesAfter('trackpad pan-zoom');

  send(const ShutdownMessage());
  await conn.flush();
  await conn.close();
  var code = await guest.exitCode.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      guest.kill();
      return -1;
    },
  );
  stdout.writeln('[smoke] guest exited with $code');
  await server.close();
  exit(code == 0 ? 0 : 1);
}

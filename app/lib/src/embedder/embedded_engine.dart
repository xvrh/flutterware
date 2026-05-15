import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'protocol.dart';

enum EmbeddedEnginePhase { building, running, error }

/// Drives an out-of-process Flutter-engine guest and bridges its rendered
/// frames into a host external texture.
class EmbeddedEngine extends ChangeNotifier {
  EmbeddedEngine({required this.appPackageRoot, required this.flutterSdkRoot});

  /// Absolute path to the `flutterware_app` package root (the `app/` dir).
  final String appPackageRoot;

  /// Absolute path to the Flutter SDK checkout root.
  final String flutterSdkRoot;

  static const _channel = MethodChannel('flutterware/embedder_texture');

  EmbeddedEnginePhase phase = EmbeddedEnginePhase.building;
  String? errorMessage;
  int? textureId;
  int textureWidth = 0;
  int textureHeight = 0;

  ServerSocket? _server;
  Socket? _conn;
  Process? _guest;
  final FrameReader _reader = FrameReader();
  int _currentGeneration = -1;
  bool _disposed = false;

  String get _dartExecutable => p.join(flutterSdkRoot, 'bin', 'dart');

  /// Builds and launches the guest. Call once.
  Future<void> start({int width = 800, int height = 600}) async {
    try {
      var build = await _runBuild();
      if (_disposed) return;

      var buildDir = p.join(appPackageRoot, 'build', 'embedder');
      var socketPath = p.join(buildDir, 'embedder_gui.sock');
      var socketFile = File(socketPath);
      if (socketFile.existsSync()) socketFile.deleteSync();
      _server = await ServerSocket.bind(
          InternetAddress(socketPath, type: InternetAddressType.unix), 0);

      _guest = await Process.start(
        build.hostPath,
        [
          build.assetsDir,
          build.icuData,
          socketPath,
          '$width',
          '$height',
        ],
        mode: ProcessStartMode.normal,
      );
      _guest!.stdout.transform(const SystemEncoding().decoder).listen((line) {
        debugPrint('[guest] $line');
      });
      _guest!.stderr.transform(const SystemEncoding().decoder).listen((line) {
        debugPrint('[guest:err] $line');
      });

      _conn = await _server!.first;
      _conn!.listen(_onSocketData, onDone: _onSocketClosed);
    } catch (e) {
      _fail('$e');
    }
  }

  Future<({String hostPath, String assetsDir, String icuData})>
      _runBuild() async {
    var result = await Process.run(
      _dartExecutable,
      ['run', p.join('tool', 'embedder', 'build_guest.dart')],
      workingDirectory: appPackageRoot,
    );
    if (result.exitCode != 0) {
      throw StateError('build_guest.dart failed:\n${result.stderr}');
    }
    String? extract(String key) {
      for (var line in (result.stdout as String).split('\n')) {
        if (line.startsWith('$key=')) return line.substring(key.length + 1);
      }
      return null;
    }

    var hostPath = extract('HOST_PATH');
    var assetsDir = extract('ASSETS_DIR');
    var icuData = extract('ICU_DATA');
    if (hostPath == null || assetsDir == null || icuData == null) {
      throw StateError('build_guest.dart did not print the expected paths');
    }
    return (hostPath: hostPath, assetsDir: assetsDir, icuData: icuData);
  }

  void _onSocketData(Uint8List chunk) {
    for (var message in _reader.addBytes(chunk)) {
      unawaited(_handle(message));
    }
  }

  Future<void> _handle(EmbedderMessage message) async {
    switch (message) {
      case ReadyMessage():
        break;
      case SurfacesAllocatedMessage():
        await _onSurfaces(message);
      case FrameReadyMessage():
        if (textureId != null) {
          await _channel.invokeMethod('markFrameAvailable', {
            'textureId': textureId,
            'ringIndex': message.ringIndex,
          });
        }
      case ErrorMessage():
        _fail(message.message);
      case ResizeMessage():
      case PointerEventMessage():
      case KeyEventMessage():
      case ShutdownMessage():
        break; // GUI-to-guest messages; never received here.
    }
  }

  Future<void> _onSurfaces(SurfacesAllocatedMessage message) async {
    textureWidth = message.width;
    textureHeight = message.height;
    if (textureId == null) {
      textureId = await _channel.invokeMethod<int>('createTexture', {
        'surfaceIds': message.surfaceIds,
      });
      phase = EmbeddedEnginePhase.running;
    } else if (message.generation != _currentGeneration) {
      await _channel.invokeMethod('updateSurfaces', {
        'textureId': textureId,
        'surfaceIds': message.surfaceIds,
      });
    }
    _currentGeneration = message.generation;
    notifyListeners();
  }

  void _onSocketClosed() {
    if (phase != EmbeddedEnginePhase.error && !_disposed) {
      _fail('the embedder guest exited');
    }
  }

  void _fail(String message) {
    errorMessage = message;
    phase = EmbeddedEnginePhase.error;
    notifyListeners();
  }

  void _send(EmbedderMessage message) {
    var conn = _conn;
    if (conn != null && phase == EmbeddedEnginePhase.running) {
      conn.add(encodeMessage(message));
    }
  }

  /// Forwards a new physical-pixel size to the guest.
  void resize(int width, int height, double pixelRatio) {
    _send(ResizeMessage(width: width, height: height, pixelRatio: pixelRatio));
  }

  void sendPointer({
    required PointerPhase phaseKind,
    required double x,
    required double y,
    int buttons = 0,
    double scrollDeltaX = 0,
    double scrollDeltaY = 0,
  }) {
    _send(PointerEventMessage(
      phase: phaseKind,
      x: x,
      y: y,
      buttons: buttons,
      scrollDeltaX: scrollDeltaX,
      scrollDeltaY: scrollDeltaY,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
    ));
  }

  void sendKey({
    required KeyEventKind kind,
    required int physicalKey,
    required int logicalKey,
  }) {
    _send(KeyEventMessage(
      kind: kind,
      physicalKey: physicalKey,
      logicalKey: logicalKey,
      modifiers: 0,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
    ));
  }

  @override
  void dispose() {
    _disposed = true;
    if (_conn != null && phase == EmbeddedEnginePhase.running) {
      _conn!.add(encodeMessage(const ShutdownMessage()));
    }
    if (textureId != null) {
      unawaited(_channel.invokeMethod(
          'disposeTexture', {'textureId': textureId}).catchError((_) {}));
    }
    unawaited(_conn?.close());
    unawaited(_server?.close());
    _guest?.kill();
    super.dispose();
  }
}

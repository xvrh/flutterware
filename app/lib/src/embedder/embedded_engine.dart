import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../utils/run_dir.dart';
import 'protocol.dart';

enum EmbeddedEnginePhase { building, running, error }

/// Drives an out-of-process Flutter-engine guest and bridges its rendered
/// frames into a host external texture.
typedef GuestBuild = ({String hostPath, String assetsDir, String icuData});

class EmbeddedEngine extends ChangeNotifier {
  EmbeddedEngine({
    required this.appPackageRoot,
    required this.flutterSdkRoot,
    this.buildGuest,
    this.name = 'gui',
  });

  /// Distinguishes this engine's guest socket from any other's.
  ///
  /// A fixed name meant a second GUI deleted the first one's socket and bound
  /// its own. Pass the daemon's session id: two clients of one daemon are now
  /// an ordinary case — a panel open while an agent screenshots — rather than
  /// something to refuse.
  final String name;

  /// Produces the guest's binary and assets. Defaults to running
  /// `tool/embedder/build_guest.dart`, which compiles the fixed harness scene;
  /// a caller with its own entrypoint and resident compiler supplies its own.
  final Future<GuestBuild> Function()? buildGuest;

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
  // Socket messages must be handled strictly in arrival order; each handler is
  // chained after the previous one completes rather than run concurrently.
  Future<void> _handleChain = Future.value();
  int _currentGeneration = -1;
  bool _disposed = false;
  final Completer<String> _vmServiceUri = Completer<String>();

  /// The guest's VM-service URI, which it prints on stdout at startup. Needed
  /// to hot-reload the live guest.
  Future<String> get vmServiceUri => _vmServiceUri.future;

  String get _dartExecutable => p.join(flutterSdkRoot, 'bin', 'dart');

  /// Builds and launches the guest. Call once.
  Future<void> start({int width = 800, int height = 600}) async {
    try {
      var build = await (buildGuest ?? _runBuild)();
      if (_disposed) return;

      // Not under the build directory: the CLI installs the GUI at
      // `~/.flutterware/<sha1>/app/`, and a socket below that overflows the
      // 104-byte cap on a unix socket path.
      var socketPath = checkSocketPath(
        p.join(flutterwareRunDir(), 'g-$name.sock'),
      );
      var socketFile = File(socketPath);
      if (socketFile.existsSync()) socketFile.deleteSync();
      _server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );

      _guest = await Process.start(build.hostPath, [
        build.assetsDir,
        build.icuData,
        socketPath,
        '$width',
        '$height',
      ], mode: ProcessStartMode.normal);
      _guest!.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
            debugPrint('[guest] $line');
            _rememberGuestOutput(line);
            var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
            if (match != null && !_vmServiceUri.isCompleted) {
              _vmServiceUri.complete(match.group(1));
            }
          });
      _guest!.stderr.transform(const SystemEncoding().decoder).listen((line) {
        debugPrint('[guest:err] $line');
        _rememberGuestOutput(line);
      });

      // Accept the guest's connection, but don't hang forever if the guest
      // dies before connecting — race the accept against the process exit.
      Socket? connected;
      var accepted = _server!.first.then((c) => connected = c);
      await Future.any([accepted, _guest!.exitCode]);
      if (connected == null) {
        throw StateError('the embedder guest exited before connecting');
      }
      _conn = connected;
      _conn!.listen(_onSocketData, onDone: _onSocketClosed);
    } catch (e) {
      _fail('$e');
    }
  }

  Future<GuestBuild> _runBuild() async {
    var result = await Process.run(_dartExecutable, [
      'run',
      p.join('tool', 'embedder', 'build_guest.dart'),
    ], workingDirectory: appPackageRoot);
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
      _handleChain = _handleChain
          .then((_) => _handle(message))
          .catchError((Object e) => _fail('$e'));
    }
  }

  Future<void> _handle(EmbedderMessage message) async {
    switch (message) {
      case ReadyMessage():
        break;
      case SurfacesAllocatedMessage():
        await _onSurfaces(message);
      case FrameReadyMessage():
        // Discard frames composited against superseded surfaces; their ring
        // slots no longer match the texture the plugin currently holds.
        if (textureId != null && message.generation == _currentGeneration) {
          await _channel.invokeMethod('markFrameAvailable', {
            'textureId': textureId,
            'ringIndex': message.ringIndex,
          });
        }
      case ErrorMessage():
        _fail(message.message);
      case CapturedMessage():
        break; // Awaited by whoever asked for the capture, not here.
      case ResizeMessage():
      case PointerEventMessage():
      case KeyEventMessage():
      case ShutdownMessage():
      case CaptureMessage():
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
      // With what it last said. "the embedder guest exited" on its own names
      // the symptom and nothing else, and the guest is the only thing that
      // knows why it went.
      var tail = _guestLog.isEmpty
          ? ' (it printed nothing)'
          : ':\n${_guestLog.join('\n')}';
      _fail('the embedder guest exited$tail');
    }
  }

  /// The guest's last few lines, kept for the message above.
  final _guestLog = <String>[];

  void _rememberGuestOutput(String line) {
    _guestLog.add(line);
    if (_guestLog.length > 20) _guestLog.removeAt(0);
  }

  void _fail(String message) {
    if (!_vmServiceUri.isCompleted) {
      _vmServiceUri.completeError(StateError(message));
    }
    // Notifying after dispose throws, and every socket error routes here —
    // including the ones a teardown causes.
    if (_disposed) return;
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
  void resize(
    int width,
    int height,
    double pixelRatio, {
    EdgeInsets insets = EdgeInsets.zero,
  }) {
    _send(
      ResizeMessage(
        width: width,
        height: height,
        pixelRatio: pixelRatio,
        insetTop: insets.top,
        insetRight: insets.right,
        insetBottom: insets.bottom,
        insetLeft: insets.left,
      ),
    );
  }

  void sendPointer({
    required PointerPhase phaseKind,
    required double x,
    required double y,
    int buttons = 0,
    double scrollDeltaX = 0,
    double scrollDeltaY = 0,
  }) {
    _send(
      PointerEventMessage(
        phase: phaseKind,
        x: x,
        y: y,
        buttons: buttons,
        scrollDeltaX: scrollDeltaX,
        scrollDeltaY: scrollDeltaY,
        timestampMicros: DateTime.now().microsecondsSinceEpoch,
      ),
    );
  }

  void sendKey({
    required KeyEventKind kind,
    required int physicalKey,
    required int logicalKey,
  }) {
    _send(
      KeyEventMessage(
        kind: kind,
        physicalKey: physicalKey,
        logicalKey: logicalKey,
        modifiers: 0,
        timestampMicros: DateTime.now().microsecondsSinceEpoch,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    if (_conn != null && phase == EmbeddedEnginePhase.running) {
      _conn!.add(encodeMessage(const ShutdownMessage()));
    }
    if (textureId != null) {
      unawaited(
        _channel
            .invokeMethod('disposeTexture', {'textureId': textureId})
            .catchError((_) {}),
      );
    }
    unawaited(_conn?.close());
    unawaited(_server?.close());
    _guest?.kill();
    super.dispose();
  }
}

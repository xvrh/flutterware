import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import '../utils/run_dir.dart';
import 'frame_capture.dart';
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

  /// Every engine currently backing a texture, by the id the host gave it.
  ///
  /// **Static, and worth defending.** A window capture finds its guests by
  /// walking the render tree for `TextureBox`, which yields texture ids and
  /// nothing else — the widget that built one is long out of reach by then.
  /// Something has to turn an id back into the engine that owns it, and a
  /// texture id is already a process-wide identifier issued by the platform
  /// side, so a process-wide map is the same scope rather than a wider one.
  static final _byTextureId = <int, EmbeddedEngine>{};

  /// The engine behind [textureId], or null when nothing here owns it.
  static EmbeddedEngine? withTexture(int textureId) => _byTextureId[textureId];

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

  /// Photographs the guest — the same exchange the headless pipeline uses.
  ///
  /// Worth having on the *live* engine specifically: this frame is the demo as
  /// the person driving it left it, which nothing rendered fresh can reproduce.
  /// It is also the only way to get one from here, since the texture belongs to
  /// the compositor rather than to Flutter and `toImage` cannot read it.
  late final _capture = FrameCapture(
    send: (message) async {
      var conn = _conn;
      if (conn == null || phase != EmbeddedEnginePhase.running) {
        throw StateError('the guest is not running');
      }
      conn.add(encodeMessage(message));
      await conn.flush();
    },
    // Per engine, so two panels capturing at once do not write one path.
    workDir: p.join(flutterwareRunDir(), 'cap-$name'),
  );

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
      // Every failure path completes the URI through [_fail] — except a guest
      // that runs happily without ever printing the line the scrape above
      // expects. Bound that one too, or `await vmServiceUri` waits forever
      // and a panel sits on "building".
      _uriDeadline = Timer(const Duration(seconds: 30), () {
        if (_vmServiceUri.isCompleted) return;
        // Not [_fail]: the engine may be rendering fine — only inspection is
        // lost — and a consumer that never asks for the VM service should not
        // see an error for it. The pre-attached listener keeps the error off
        // the zone for exactly that consumer.
        unawaited(_vmServiceUri.future.catchError((_) => ''));
        _vmServiceUri.completeError(
          StateError('the guest connected but never announced its VM service'),
        );
      });
    } catch (e) {
      _fail('$e');
    }
  }

  Timer? _uriDeadline;

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
        // Before failing the engine: a guest that has errored will not finish
        // writing a frame, and a caller left on the capture timeout learns
        // thirty seconds later, in less detail, what this already says.
        _capture.failAll(StateError(message.message));
        _fail(message.message);
      case CapturedMessage():
        _capture.acknowledge(message);
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
      if (textureId case var id?) _byTextureId[id] = this;
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

  /// The frame the guest draws next, as PNG bytes.
  ///
  /// PNG rather than an image, because both callers — the clipboard and the
  /// save dialog — want encoded bytes, and the one that does not is welcome to
  /// decode them.
  ///
  /// Pass [crop] to cut it to a node's box, in the guest's logical coordinates:
  /// the space [InspectLayout] reports, which is why a node's rect from the
  /// inspect panel crops its own picture with no transform.
  Future<Uint8List> capturePng({
    InspectLayout? crop,
    List<InspectNode> annotate = const [],
    double pixelRatio = 1,
  }) async => img.encodePng(
    await captureImage(crop: crop, annotate: annotate, pixelRatio: pixelRatio),
  );

  /// The same frame, undecoded.
  ///
  /// For the one caller that is going to draw with it rather than write it out:
  /// a window capture pastes this into the hole the guest's texture leaves in
  /// the host's raster, and encoding a PNG just to decode it again would be the
  /// only step in that path that did nothing.
  Future<img.Image> captureImage({
    InspectLayout? crop,
    List<InspectNode> annotate = const [],
    double pixelRatio = 1,
  }) =>
      _capture.capture(crop: crop, annotate: annotate, pixelRatio: pixelRatio);

  @override
  void dispose() {
    _disposed = true;
    _uriDeadline?.cancel();
    // Nothing outstanding survives the guest, and a caller waiting on the
    // 30-second timeout would otherwise outlive the panel it belongs to.
    _capture.failAll(StateError('the panel was closed'));
    if (_conn != null && phase == EmbeddedEnginePhase.running) {
      _conn!.add(encodeMessage(const ShutdownMessage()));
    }
    if (textureId case var id?) {
      _byTextureId.remove(id);
      unawaited(
        _channel
            .invokeMethod('disposeTexture', {'textureId': id})
            .catchError((_) {}),
      );
    }
    unawaited(_conn?.close());
    unawaited(_server?.close());
    _guest?.kill();
    // Frames delete themselves as they are read; this picks up the scratch
    // directory itself, which would otherwise accumulate one per session id.
    // The run-dir sweep ages out what a crash skips.
    try {
      Directory(
        p.join(flutterwareRunDir(), 'cap-$name'),
      ).deleteSync(recursive: true);
    } on FileSystemException {
      // Housekeeping only.
    }
    super.dispose();
  }
}

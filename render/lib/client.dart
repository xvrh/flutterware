/// The pure-Dart side of the render story: a [RenderPool] spawns resident
/// guests from a directory produced by `fw render bundle` and invokes the
/// app's render points fully typed.
///
/// ```dart
/// var renders = await RenderPool.start(bundle: '/opt/acme/render', warm: 2);
/// var svg = await renders.svg(monthlyChart, ChartRequest(...),
///     size: const RenderSize(412, 230));
/// ```
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'contract.dart';
import 'protocol.dart';

export 'contract.dart';
export 'protocol.dart' show RenderPointInfo, RenderPointKind;

/// A pool of resident render guests over one bundle directory.
///
/// Each guest is a `flutter_tester` process running the app's registrar;
/// requests take a free guest (queueing when all are busy), and a guest
/// that dies fails only its own in-flight request — the next request
/// respawns one.
class RenderPool {
  RenderPool._(this._bundleDir, this.manifest, this._warm, this._onGuestLog);

  static Future<RenderPool> start({
    required String bundle,
    int warm = 1,
    void Function(String line)? onGuestLog,
  }) async {
    var bundleDir = p.absolute(bundle);
    var manifestFile = File(p.join(bundleDir, 'manifest.json'));
    if (!manifestFile.existsSync()) {
      throw StateError(
        'not a render bundle: ${manifestFile.path} does not exist '
        '(produce one with `fw render bundle`)',
      );
    }
    var manifest = RenderBundleManifest.fromJson(
      (jsonDecode(manifestFile.readAsStringSync()) as Map)
          .cast<String, Object?>(),
    );
    if (manifest.protocol != renderProtocolVersion) {
      throw StateError(
        'this client speaks render protocol $renderProtocolVersion but the '
        'bundle was built for ${manifest.protocol}; rebuild the bundle or '
        'upgrade flutterware_render',
      );
    }
    var pool = RenderPool._(bundleDir, manifest, warm, onGuestLog);
    try {
      await Future.wait([for (var i = 0; i < warm; i++) pool._spawn()]);
    } catch (_) {
      // One spawn failing must not orphan the ones that succeeded: they are
      // --run-forever processes nobody else can reach.
      await pool.close();
      rethrow;
    }
    return pool;
  }

  final String _bundleDir;
  final RenderBundleManifest manifest;
  final int _warm;
  final void Function(String line)? _onGuestLog;

  final _guests = <_Guest>[];
  final _idle = <_Guest>[];
  final _waiters = Queue<Completer<_Guest>>();
  var _closed = false;

  /// The render points the guest announced, from the first guest's ready
  /// event.
  List<RenderPointInfo> get points =>
      _guests.isEmpty ? const [] : _guests.first.points;

  Future<SvgResult> svg<A>(
    WidgetRender<A> point,
    A args, {
    required RenderSize size,
    RenderOptions options = const RenderOptions(),
  }) async {
    var result = await _request({
      'method': 'render',
      'point': point.name,
      'as': 'svg',
      'args': point.encodeArgs(args),
      'size': size.toJson(),
      'options': options.toJson(),
    });
    return SvgResult(result['svg']! as String, _warnings(result));
  }

  Future<PngResult> png<A>(
    WidgetRender<A> point,
    A args, {
    required RenderSize size,
    double pixelRatio = 3,
  }) async {
    var result = await _request({
      'method': 'render',
      'point': point.name,
      'as': 'png',
      'args': point.encodeArgs(args),
      'size': size.toJson(),
      'pixelRatio': pixelRatio,
    });
    return PngResult(
      base64Decode(result['bytes']! as String),
      _warnings(result),
    );
  }

  /// The same widget entry as a single-page PDF.
  Future<PdfResult> pdfPage<A>(
    WidgetRender<A> point,
    A args, {
    required RenderSize size,
    RenderOptions options = const RenderOptions(),
  }) async {
    var result = await _request({
      'method': 'render',
      'point': point.name,
      'as': 'pdf',
      'args': point.encodeArgs(args),
      'size': size.toJson(),
      'options': options.toJson(),
    });
    return PdfResult(
      base64Decode(result['bytes']! as String),
      _warnings(result),
    );
  }

  /// A document entry: the guest composes the whole PDF itself.
  Future<PdfResult> pdf<A>(
    DocumentRender<A> point,
    A args, {
    RenderOptions options = const RenderOptions(),
  }) async {
    var result = await _request({
      'method': 'render',
      'point': point.name,
      'as': 'pdf',
      'args': point.encodeArgs(args),
      'options': options.toJson(),
    });
    return PdfResult(
      base64Decode(result['bytes']! as String),
      _warnings(result),
    );
  }

  Future<void> close() async {
    _closed = true;
    for (var guest in _guests.toList()) {
      guest.dispose();
    }
    _guests.clear();
    _idle.clear();
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(StateError('render pool closed'));
    }
  }

  List<RenderWarning> _warnings(Map<String, Object?> result) => [
    for (var warning in result['warnings'] as List? ?? const [])
      RenderWarning.fromJson((warning as Map).cast<String, Object?>()),
  ];

  Future<Map<String, Object?>> _request(Map<String, Object?> body) async {
    if (_closed) throw StateError('render pool is closed');
    var guest = await _acquire();
    try {
      return await guest.request(body);
    } finally {
      _release(guest);
    }
  }

  Future<_Guest> _acquire() async {
    while (_idle.isNotEmpty) {
      var guest = _idle.removeLast();
      if (!guest.dead) return guest;
      _guests.remove(guest);
    }
    if (_guests.length + _spawning < _warm) {
      await _spawn();
      return _acquire();
    }
    var waiter = Completer<_Guest>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release(_Guest guest) {
    if (guest.dead) {
      _guests.remove(guest);
      // The dead guest's slot may be the one a queued request is waiting
      // for; without a respawn here that request would hang forever.
      _respawnForWaiters();
      return;
    }
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(guest);
    } else {
      _idle.add(guest);
    }
  }

  void _respawnForWaiters() {
    if (_closed || _waiters.isEmpty) return;
    if (_guests.length + _spawning >= _warm) return;
    unawaited(
      _spawn()
          .then((_) {
            if (_waiters.isNotEmpty && _idle.isNotEmpty) {
              _waiters.removeFirst().complete(_idle.removeLast());
            }
          })
          .catchError((Object error, StackTrace stack) {
            // The replacement could not come up: the queued requests would
            // otherwise wait on a pool that has nothing left to give them.
            while (_waiters.isNotEmpty) {
              _waiters.removeFirst().completeError(error, stack);
            }
          }),
    );
  }

  var _spawning = 0;

  Future<void> _spawn() async {
    _spawning++;
    try {
      var guest = await _Guest.spawn(_bundleDir, manifest, _onGuestLog);
      _guests.add(guest);
      _idle.add(guest);
    } finally {
      _spawning--;
    }
  }
}

/// A remote failure inside the guest, stack included.
class RenderException implements Exception {
  RenderException(this.message, {this.remoteStack});

  final String message;
  final String? remoteStack;

  @override
  String toString() =>
      'RenderException: $message'
      '${remoteStack != null ? '\n$remoteStack' : ''}';
}

class _Guest {
  _Guest._(this._process, this._onLog);

  static Future<_Guest> spawn(
    String bundleDir,
    RenderBundleManifest manifest,
    void Function(String line)? onLog,
  ) async {
    var process = await Process.start(
      p.join(bundleDir, manifest.tester),
      [
        '--run-forever',
        '--non-interactive',
        '--disable-vm-service',
        '--icu-data-file-path=${p.join(bundleDir, manifest.icuData)}',
        if (manifest.assets != null)
          '--flutter-assets-dir=${p.join(bundleDir, manifest.assets!)}',
        p.join(bundleDir, manifest.kernel),
      ],
      workingDirectory: bundleDir,
      environment: {'FW_RENDER_BUNDLE': bundleDir},
    );
    var guest = _Guest._(process, onLog);
    // allowMalformed + onError: a stray binary byte on the guest's stdout is
    // a log problem, never a reason to crash the process hosting the pool.
    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(guest._onStdout, onDone: guest._onExit, onError: (Object _) {});
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(guest._log, onError: (Object _) {});
    unawaited(process.exitCode.then((_) => guest._onExit()));
    await guest._ready.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        guest.dispose();
        throw StateError(
          'render guest did not become ready within 60s '
          '(pass onGuestLog to RenderPool.start to see its output)',
        );
      },
    );
    return guest;
  }

  final Process _process;
  final void Function(String line)? _onLog;
  final _ready = Completer<void>();
  final _pending = <int, Completer<Map<String, Object?>>>{};
  var _nextId = 1;
  var dead = false;
  var points = <RenderPointInfo>[];

  Future<Map<String, Object?>> request(Map<String, Object?> body) {
    if (dead) throw StateError('render guest is gone');
    var id = _nextId++;
    var completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _process.stdin.writeln(jsonEncode({'id': id, ...body}));
    return completer.future;
  }

  void _onStdout(String line) {
    if (line.isEmpty) return;
    if (!line.startsWith(renderProtocolMarker)) {
      _log(line);
      return;
    }
    var message = (jsonDecode(
      line.substring(renderProtocolMarker.length),
    ) as Map).cast<String, Object?>();
    if (message['event'] == 'ready') {
      points = [
        for (var point in message['points'] as List? ?? const [])
          RenderPointInfo.fromJson((point as Map).cast<String, Object?>()),
      ];
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    var completer = _pending.remove(message['id']);
    if (completer == null) return;
    if (message['error'] case Map error) {
      completer.completeError(
        RenderException(
          error['message']! as String,
          remoteStack: error['stack'] as String?,
        ),
      );
    } else {
      completer.complete((message['result']! as Map).cast<String, Object?>());
    }
  }

  void _onExit() => _fail('render guest exited mid-request');

  void _fail(String message) {
    if (dead) return;
    dead = true;
    for (var pending in _pending.values) {
      pending.completeError(RenderException(message));
    }
    _pending.clear();
    if (!_ready.isCompleted) {
      _ready.completeError(RenderException('render guest exited on startup'));
    }
  }

  void _log(String line) => _onLog?.call(line);

  void dispose() {
    // In-flight requests fail now rather than waiting on a killed process
    // whose exit handler the dead flag would have silenced.
    _fail('render pool closed');
    _process.kill();
  }
}

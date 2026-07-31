import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutterware_app/src/catalog/compiler_daemon_client.dart';
import 'package:flutterware_app/src/catalog/devices.dart';
import 'package:flutterware_app/src/catalog/package_config_locator.dart';
import 'package:flutterware_app/src/catalog/protocol.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:flutterware_app/src/embedder/protocol.dart' as ipc;
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:path/path.dart' as p;

/// The Motion transport, checked against a live guest.
///
/// Began as spike S5 with its extensions faked inside a bespoke stage; it now
/// drives the published ones — `ext.flutterware.motion.list`, `.seek`,
/// `.transport` — against an ordinary demo, so what it measures is what a panel
/// will get. The two questions are still the ones the editor rests on:
///
///   1. Does a seek cost one frame? Scrubbing must be a transport RPC and a
///      rebuild, never a compile or a reload.
///   2. Does the guest report the three states — tuned, read, offered — well
///      enough that a panel can draw lanes off it and nothing else?
///
/// ```sh
/// cd app && dart run tool/catalog/motion_probe.dart [entry-substring]
/// ```
Future<void> main(List<String> args) async {
  var wanted = args.isEmpty ? 'motion_inbox' : args.first;
  var appPackageRoot = p.dirname(
    p.dirname(p.dirname(p.fromUri(Platform.script))),
  );
  var cache = FlutterCache.fromRunningSdk();

  var watch = Stopwatch()..start();
  var (daemon, ready) = await CompilerDaemonClient.connect(
    dartExecutable: p.join(cache.flutterRoot, 'bin', 'dart'),
    config: DaemonConfig(
      appPackageRoot: appPackageRoot,
      projectRoot: appPackageRoot,
      packageConfig: requirePackageConfig(appPackageRoot),
      flutterSdkRoot: cache.flutterRoot,
      roots: ['tool/catalog/demos'],
      trackWidgetCreation: true,
    ),
  );
  stdout.writeln(
    '[motion] daemon ready in ${watch.elapsedMilliseconds}ms '
    '(${ready.reused ? 'attached' : 'started'})',
  );

  var ids = [for (var entry in ready.entries) entry.id]..sort();
  var matched = ids.where((id) => id.contains(wanted)).toList();
  if (matched.isEmpty) {
    stderr.writeln('[motion] nothing matched "$wanted" among ${ids.length}');
    exit(1);
  }
  var entryId = matched.first;
  stdout.writeln('[motion] entry $entryId');

  _Guest? guest;
  try {
    var compiled = await daemon.select(entryId, full: true);
    if (!compiled.ok) {
      stderr.writeln('[motion] did not compile:\n${compiled.error}');
      exit(1);
    }
    guest = await _Guest.start(
      hostPath: ready.hostPath,
      assetsDir: ready.assetsDir,
      icuData: ready.icuData,
      workDir: p.join(appPackageRoot, 'build', 'catalog'),
    );
    await guest.renderScratchFrame();

    await _reportRegistration(guest);
    await _reportStates(guest);
    await _reportSeekCost(guest);
    await _reportTransport(guest);
  } finally {
    await guest?.close();
    await daemon.close();
  }
  exit(0);
}

Future<Map<String, dynamic>> _list(_Guest guest) async {
  var response = await guest.vmService.callExtension(
    'ext.flutterware.motion.list',
  );
  return (response ?? const {}).cast<String, dynamic>();
}

Map<String, dynamic> _sole(Map<String, dynamic> listed) {
  var scopes = (listed['scopes'] as List).cast<Map<String, dynamic>>();
  if (scopes.length != 1) {
    throw StateError('expected one mounted scope, got ${scopes.length}');
  }
  return scopes.single;
}

/// A `MotionScope` registers when it mounts, not before `runApp` — so the
/// question is whether the extensions are there by the time a host looks.
Future<void> _reportRegistration(_Guest guest) async {
  stdout.writeln('\n=== registration ===');
  var isolate = await guest.vmService.service.getIsolate(
    guest.vmService.isolateId,
  );
  var rpcs = isolate.extensionRPCs ?? const <String>[];
  for (var wanted in const [
    'ext.flutterware.motion.list',
    'ext.flutterware.motion.seek',
    'ext.flutterware.motion.transport',
  ]) {
    stdout.writeln('${rpcs.contains(wanted) ? 'YES' : 'no '}  $wanted');
  }

  var errors = await guest.vmService.callExtension('ext.flutterware.errors');
  var list = errors?['errors'];
  stdout.writeln('guest errors: ${list is List ? list.length : errors}');
  if (list is List) {
    for (var error in list.take(2)) {
      stdout.writeln('  ${jsonEncode(error).replaceAll(r'\n', '\n  ')}');
    }
  }
}

/// Everything a lane is drawn from, printed as the panel will group it.
Future<void> _reportStates(_Guest guest) async {
  stdout.writeln('\n=== what the panel gets ===');
  var scope = _sole(await _list(guest));
  stdout.writeln(
    'scope ${scope['id']}  ${scope['durationMs']}ms  '
    't=${scope['progress']}  playing=${scope['playing']}',
  );
  for (var target in (scope['targets'] as List).cast<Map<String, dynamic>>()) {
    var offered = (target['offered'] as List).length;
    stdout.writeln(
      '  ${target['name']}'
      '${target['named'] == true ? '' : '  (tuned, never named - prunable)'}'
      '${offered == 0 ? '' : '  +$offered offered'}',
    );
    for (var property
        in (target['properties'] as List).cast<Map<String, dynamic>>()) {
      var segments = (property['segments'] as List)
          .cast<Map<String, dynamic>>();
      // The guest decides this, not us: `offered` counts as wiring for a
      // tuned property, and the first run of this probe re-derived it wrong.
      var state =
          '${property['state']}'
          '${property['read'] == true ? ' (read)' : ' (MotionBox)'}';
      var spans = segments
          .map(
            (s) =>
                '[${s['startMs']}-${s['endMs']}ms ${s['curve'] ?? 'custom'}]',
          )
          .join(' ');
      stdout.writeln(
        '      ${property['name'].toString().padRight(13)} '
        '${state.padRight(16)} = ${property['value']}'
        '${spans.isEmpty ? '' : '  $spans'}',
      );
    }
  }
}

/// The number the whole design rests on.
Future<void> _reportSeekCost(_Guest guest) async {
  stdout.writeln('\n=== seek cost ===');

  Future<int> seek(double t) async {
    var watch = Stopwatch()..start();
    await guest.vmService.callExtension(
      'ext.flutterware.motion.seek',
      args: {'t': '$t'},
    );
    return watch.elapsedMicroseconds;
  }

  // The first RPC on a fresh connection is not the loop.
  for (var i = 0; i < 5; i++) {
    await seek(i / 10);
  }

  var rpcOnly = <int>[];
  for (var i = 0; i < 60; i++) {
    rpcOnly.add(await seek(i / 60));
  }
  _summarise('seek RPC (waits for the frame)', rpcOnly);

  var withCapture = <int>[];
  for (var i = 0; i < 30; i++) {
    var watch = Stopwatch()..start();
    await guest.vmService.callExtension(
      'ext.flutterware.motion.seek',
      args: {'t': '${i / 30}'},
    );
    await guest.renderScratchFrame();
    withCapture.add(watch.elapsedMicroseconds);
  }
  _summarise('seek + capture               ', withCapture);

  var scope = _sole(await _list(guest));
  stdout.writeln('landed at t=${scope['progress']} (${scope['ms']}ms)');
}

/// `ms` and `t` are two ways of saying one thing, and transport is the third.
Future<void> _reportTransport(_Guest guest) async {
  stdout.writeln('\n=== transport ===');

  await guest.vmService.callExtension(
    'ext.flutterware.motion.seek',
    args: {'ms': '390'},
  );
  var seeked = _sole(await _list(guest));
  stdout.writeln('seek ms=390 -> ${seeked['ms']}ms, t=${seeked['progress']}');

  await guest.vmService.callExtension(
    'ext.flutterware.motion.transport',
    args: {'verb': 'restart'},
  );
  var started = _sole(await _list(guest));
  await Future<void>.delayed(const Duration(milliseconds: 300));
  var later = _sole(await _list(guest));
  stdout.writeln(
    'restart -> playing=${started['playing']}, '
    't ${started['progress']} then ${later['progress']} 300ms on',
  );

  await guest.vmService.callExtension(
    'ext.flutterware.motion.transport',
    args: {'verb': 'pause'},
  );
  var paused = _sole(await _list(guest));
  await Future<void>.delayed(const Duration(milliseconds: 200));
  var stillPaused = _sole(await _list(guest));
  stdout.writeln(
    'pause -> playing=${paused['playing']}, '
    't ${paused['progress']} still ${stillPaused['progress']} 200ms on',
  );
}

void _summarise(String label, List<int> micros) {
  if (micros.isEmpty) return;
  var sorted = [...micros]..sort();
  String ms(int v) => (v / 1000).toStringAsFixed(2);
  stdout.writeln(
    '$label n=${sorted.length}  min ${ms(sorted.first)}ms  '
    'median ${ms(sorted[sorted.length ~/ 2])}ms  '
    'p90 ${ms(sorted[(sorted.length * 0.9).floor()])}ms  '
    'max ${ms(sorted.last)}ms',
  );
}

/// The `_GuestSession` dance from `headless_catalog`, reduced to what a probe
/// needs. Lifted from `inspect_spike.dart`, deliberately unshared.
class _Guest {
  _Guest._(
    this._process,
    this._connection,
    this._server,
    this.vmService,
    this._workDir,
  );

  final Process _process;
  final Socket _connection;
  final ServerSocket _server;
  final GuestVmService vmService;
  final String _workDir;

  final _reader = ipc.FrameReader();
  final _captures = <String, Completer<void>>{};

  static Future<_Guest> start({
    required String hostPath,
    required String assetsDir,
    required String icuData,
    required String workDir,
    CaptureViewport viewport = CaptureViewport.panel,
  }) async {
    var key = sha1
        .convert(utf8.encode('$workDir-motion'))
        .toString()
        .substring(0, 12);
    var socketPath = checkSocketPath(
      p.join(flutterwareRunDir(), 'motion-$key.sock'),
    );
    var socket = File(socketPath);
    if (socket.existsSync()) socket.deleteSync();
    var server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );

    var process = await Process.start(hostPath, [
      assetsDir,
      icuData,
      socketPath,
      '${viewport.width}',
      '${viewport.height}',
    ]);
    var vmServiceUri = Completer<String>();
    process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
          if (match != null && !vmServiceUri.isCompleted) {
            vmServiceUri.complete(match.group(1));
          }
          if (line.startsWith('FW-ERROR:')) stdout.writeln('  [guest] $line');
        });
    unawaited(process.stderr.drain<void>());

    var connected = await Future.any<Object?>([server.first, process.exitCode]);
    if (connected is! Socket) {
      throw StateError('the guest exited before connecting');
    }

    var guest = _Guest._(
      process,
      connected,
      server,
      await GuestVmService.connect(await vmServiceUri.future),
      workDir,
    );
    connected.listen(guest._onData);
    connected.add(
      ipc.encodeMessage(
        ipc.ResizeMessage(
          width: viewport.width,
          height: viewport.height,
          pixelRatio: viewport.pixelRatio,
        ),
      ),
    );
    return guest;
  }

  void _onData(List<int> chunk) {
    for (var message in _reader.addBytes(chunk)) {
      if (message is ipc.CapturedMessage) {
        _captures.remove(message.path)?.complete();
      } else if (message is ipc.ErrorMessage) {
        for (var pending in _captures.values) {
          if (!pending.isCompleted) {
            pending.completeError(StateError(message.message));
          }
        }
        _captures.clear();
      }
    }
  }

  Future<void> renderScratchFrame() async {
    var path = p.join(_workDir, 'motion-scratch.raw');
    File(path).parent.createSync(recursive: true);
    var done = Completer<void>();
    _captures[path] = done;
    _connection.add(ipc.encodeMessage(ipc.CaptureMessage(path)));
    await done.future.timeout(const Duration(seconds: 10));
  }

  Future<void> close() async {
    _connection.add(ipc.encodeMessage(const ipc.ShutdownMessage()));
    await vmService.close();
    await _connection.close();
    await _server.close();
    _process.kill();
    await _process.exitCode;
  }
}

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

/// Spike S5 — `docs/superpowers/specs/2026-07-31-motion-design.md`.
///
/// Two questions, both upstream of the Motion API:
///
///   1. Does a seek cost one frame? The whole editor rests on scrubbing being
///      a transport RPC plus a rebuild, never a compile or a reload.
///   2. Is the guest's clock ours? If a free-running ticker in the stage
///      advances on wall time, the stage's own implicit animations fight the
///      playhead and v1 has to say so out loud.
///
/// ```sh
/// cd app && dart run tool/catalog/motion_spike.dart
/// ```
Future<void> main(List<String> args) async {
  var appPackageRoot = p.dirname(
    p.dirname(p.dirname(p.fromUri(Platform.script))),
  );
  var cache = FlutterCache.fromRunningSdk();
  stdout.writeln('[s5] app $appPackageRoot');

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
    '[s5] daemon ready in ${watch.elapsedMilliseconds}ms '
    '(${ready.reused ? 'attached' : 'started'})',
  );

  var ids = [for (var entry in ready.entries) entry.id]..sort();
  var motion = ids.where((id) => id.contains('motion')).toList();
  if (motion.isEmpty) {
    stderr.writeln('[s5] no motion entry found among ${ids.length} entries');
    stderr.writeln(ids.join('\n'));
    exit(1);
  }
  var entryId = motion.first;
  stdout.writeln('[s5] entry $entryId');

  _Guest? guest;
  try {
    var compiled = await daemon.select(entryId, full: true);
    if (!compiled.ok) {
      stderr.writeln('[s5] did not compile:\n${compiled.error}');
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
    await _reportSeekCost(guest);
    await _reportBuildScope(guest);
    await _reportClock(guest);
  } finally {
    await guest?.close();
    await daemon.close();
  }
  exit(0);
}

Future<Map<String, dynamic>> _probe(_Guest guest) async {
  var response = await guest.vmService.callExtension(
    'ext.flutterware.motion.probe',
  );
  return (response ?? const {}).cast<String, dynamic>();
}

/// Did the guest register the transport at all, and does it see the reads?
Future<void> _reportRegistration(_Guest guest) async {
  stdout.writeln('\n=== registration ===');
  var isolate = await guest.vmService.service.getIsolate(
    guest.vmService.isolateId,
  );
  var rpcs = isolate.extensionRPCs ?? const <String>[];
  for (var wanted in const [
    'ext.flutterware.motion.seek',
    'ext.flutterware.motion.probe',
    'ext.flutterware.motion.dilate',
  ]) {
    stdout.writeln('${rpcs.contains(wanted) ? 'YES' : 'no '}  $wanted');
  }

  var probe = await _probe(guest);
  stdout.writeln('targets in the const:      ${probe['targets']}');
  stdout.writeln('reads, last build:         ${probe['reads']}');
  stdout.writeln('offered by MotionBox:      ${probe['offered']}');
  stdout.writeln('builds so far:             ${probe['builds']}');

  // A build that increments its counter but records no reads means the builder
  // threw. Ask rather than guess.
  var errors = await guest.vmService.callExtension('ext.flutterware.errors');
  var list = errors?['errors'];
  stdout.writeln(
    'guest errors:              '
    '${list is List ? '${list.length}' : errors}',
  );
  if (list is List) {
    for (var error in list.take(3)) {
      stdout.writeln('  ${jsonEncode(error).replaceAll(r'\n', '\n  ')}');
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

  // Warm the path — the first RPC on a fresh connection is not the loop.
  for (var i = 0; i < 5; i++) {
    await seek(i * 10);
  }

  var rpcOnly = <int>[];
  for (var i = 0; i < 60; i++) {
    rpcOnly.add(await seek((i * 700 / 60).toDouble()));
  }
  _summarise('seek RPC only          ', rpcOnly);

  var withFrame = <int>[];
  for (var i = 0; i < 30; i++) {
    var watch = Stopwatch()..start();
    await guest.vmService.callExtension(
      'ext.flutterware.motion.seek',
      args: {'t': '${i * 700 / 30}'},
    );
    await guest.renderScratchFrame();
    withFrame.add(watch.elapsedMicroseconds);
  }
  _summarise('seek + frame + capture ', withFrame);

  var captureOnly = <int>[];
  for (var i = 0; i < 30; i++) {
    var watch = Stopwatch()..start();
    await guest.renderScratchFrame();
    captureOnly.add(watch.elapsedMicroseconds);
  }
  _summarise('frame + capture alone  ', captureOnly);
}

/// One seek should dirty the scope and nothing else.
Future<void> _reportBuildScope(_Guest guest) async {
  stdout.writeln('\n=== build scope ===');
  var before = await _probe(guest);
  for (var i = 0; i < 10; i++) {
    await guest.vmService.callExtension(
      'ext.flutterware.motion.seek',
      args: {'t': '${i * 70}'},
    );
    await guest.renderScratchFrame();
  }
  var after = await _probe(guest);
  var builds = (after['builds'] as num) - (before['builds'] as num);
  stdout.writeln('10 seeks -> $builds builds of the scope');
  stdout.writeln('t landed at ${after['t']}');
}

/// S5b. Does anything move when we are not looking?
Future<void> _reportClock(_Guest guest) async {
  stdout.writeln('\n=== the guest clock (S5b) ===');

  Future<void> sample(String label) async {
    var first = await _probe(guest);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    var second = await _probe(guest);
    var ticks = (second['freeTicks'] as num) - (first['freeTicks'] as num);
    var frameDelta =
        (second['lastFrameMs'] as num) - (first['lastFrameMs'] as num);
    stdout.writeln(
      '$label: free-running ticker ${first['freeRunning']} -> '
      '${second['freeRunning']}, $ticks ticks in 600ms, '
      'frame stamp advanced ${frameDelta}ms',
    );
  }

  await sample('timeDilation 1  ');

  await guest.vmService.callExtension(
    'ext.flutterware.motion.dilate',
    args: {'value': '100000'},
  );
  await sample('timeDilation 1e5');

  await guest.vmService.callExtension(
    'ext.flutterware.motion.dilate',
    args: {'value': '1'},
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

/// The `_GuestSession` dance from `headless_catalog`, reduced to what a spike
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

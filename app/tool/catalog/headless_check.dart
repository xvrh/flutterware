import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';

import 'package:flutterware_app/src/catalog/catalog_entry.dart';
import 'package:flutterware_app/src/catalog/daemon_protocol.dart';
import 'package:flutterware_app/src/catalog/stub_entries.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:path/path.dart' as p;

/// Proves the catalog loop end to end **without the GUI**: the compiler daemon,
/// the real embedder guest, and reload-to-switch.
///
/// The texture bridge is the only piece left out — everything upstream of it is
/// exercised here, and it is verified by asserting what the guest actually
/// renders, not merely that a reload reported success.
///
/// ```sh
/// cd app && dart run tool/catalog/headless_check.dart
/// ```
Future<void> main(List<String> args) async {
  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var repoRoot = p.dirname(packageRoot);
  var cache = FlutterCache.fromRunningSdk();
  var buildDir = p.join(packageRoot, 'build', 'catalog');
  Directory(buildDir).createSync(recursive: true);

  var config = DaemonConfig(
    appPackageRoot: packageRoot,
    projectRoot: repoRoot,
    packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
    entries: stubEntries,
    emitProbe: true,
  );
  var configFile = File(p.join(buildDir, 'daemon_config.json'))
    ..writeAsStringSync(config.encode());

  var failures = <String>[];
  void check(bool condition, String description) {
    stdout.writeln('${condition ? '  ok  ' : ' FAIL '} $description');
    if (!condition) failures.add(description);
  }

  // 1. The daemon: a plain Dart process, spawned the way the GUI would.
  stdout.writeln('[check] starting the compiler daemon');
  var daemon = await Process.start(p.join(cache.flutterRoot, 'bin', 'dart'), [
    'run',
    p.join('tool', 'catalog', 'compiler_daemon.dart'),
    configFile.path,
  ], workingDirectory: packageRoot);
  daemon.stderr.transform(utf8.decoder).listen(stderr.write);

  // ignore: close_sinks — the process exits at the end of this script.
  var messages = StreamController<Map<String, Object?>>.broadcast();
  daemon.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
    line,
  ) {
    if (line.trim().isEmpty) return;
    try {
      messages.add(jsonDecode(line) as Map<String, Object?>);
    } catch (_) {
      stdout.writeln('  [daemon] $line');
    }
  });

  var first = await messages.stream.first.timeout(
    const Duration(minutes: 5),
    onTimeout: () => {'type': 'error', 'message': 'daemon timed out'},
  );
  if (first['type'] != 'ready') {
    stderr.writeln('daemon failed: ${first['message']}\n${first['stack']}');
    daemon.kill();
    exit(1);
  }
  var ready = DaemonReady.fromJson(first);
  stdout.writeln(
    '[check] daemon ready — cold compile ${ready.coldCompile.inMilliseconds}ms',
  );
  check(File(ready.hostPath).existsSync(), 'the C host was built');

  // 2. The guest: the real embedder host, headless.
  var socketPath = p.join(buildDir, 'headless_check.sock');
  var socketFile = File(socketPath);
  if (socketFile.existsSync()) socketFile.deleteSync();
  var server = await ServerSocket.bind(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  );

  stdout.writeln('[check] spawning the guest');
  var guest = await Process.start(ready.hostPath, [
    ready.assetsDir,
    ready.icuData,
    socketPath,
    '800',
    '600',
  ]);
  // ignore: close_sinks — the process exits at the end of this script.
  var probes = StreamController<String>.broadcast();
  var vmServiceUri = Completer<String>();
  // Dart `print` in the guest goes through the engine's log handler, which
  // writes to stderr — so both streams have to be watched.
  StreamGroup.merge([
    guest.stdout,
    guest.stderr,
  ]).transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    // host.c tags every engine log line, so the probe arrives as
    // `[embedder] FW-PROBE: ...` rather than at the start of the line.
    var probe = line.indexOf('FW-PROBE:');
    if (probe >= 0) {
      probes.add(line.substring(probe + 'FW-PROBE:'.length).trim());
    }
    var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
    if (match != null && !vmServiceUri.isCompleted) {
      vmServiceUri.complete(match.group(1));
    }
  });

  // Drain the embedder socket so the guest never blocks writing frames.
  var frames = 0;
  var connected = await Future.any<Object?>([server.first, guest.exitCode]);
  if (connected is! Socket) {
    stderr.writeln('the guest exited before connecting');
    exit(1);
  }
  var reader = FrameReader();
  connected.listen((chunk) {
    for (var message in reader.addBytes(chunk)) {
      if (message is FrameReadyMessage) frames++;
    }
  });

  var vmService = await GuestVmService.connect(await vmServiceUri.future);
  var firstProbe = await _nextProbe(probes.stream, const Duration(seconds: 20));
  stdout.writeln('[check] rendering: $firstProbe');
  check(
    firstProbe.contains(stubEntries.first.id),
    'the guest renders the first entry',
  );
  check(
    firstProbe.contains('Dr. Sarah Chen'),
    'the entry wrapper and demo body both ran',
  );

  // 3. Switch through every entry, then revisit one.
  for (var entry in [...stubEntries.skip(1), stubEntries.first]) {
    daemon.stdin.writeln(jsonEncode({'type': 'select', 'id': entry.id}));
    var compiled = DaemonCompiled.fromJson(
      await messages.stream.firstWhere((m) => m['type'] == 'compiled'),
    );
    if (!compiled.ok) {
      check(false, 'compiling ${entry.name}: ${compiled.error}');
      continue;
    }

    var watch = Stopwatch()..start();
    await vmService.reload(compiled.dill!);
    var reloadMs = watch.elapsedMilliseconds;

    var probe = await _nextProbe(probes.stream, const Duration(seconds: 10), (
      line,
    ) {
      return line.contains(entry.id);
    });
    stdout.writeln(
      '[check] ${entry.name.padRight(10)} '
      'compile ${compiled.compile.inMilliseconds}ms · reload ${reloadMs}ms · '
      '+${compiled.newSourceCount} libs',
    );
    check(probe.contains(entry.id), 'switched to ${entry.name} by hot reload');
  }

  var lastProbe = await _nextProbe(probes.stream, const Duration(seconds: 10));
  check(
    lastProbe.contains('Dr. Sarah Chen'),
    'revisiting the first entry renders it again',
  );
  check(frames > 0, 'the guest composited frames ($frames)');

  daemon.stdin.writeln(jsonEncode({'type': 'shutdown'}));
  connected.add(encodeMessage(const ShutdownMessage()));
  await connected.flush();
  await vmService.close();
  await connected.close();
  guest.kill();
  await guest.exitCode;
  await daemon.exitCode.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      daemon.kill();
      return 0;
    },
  );
  await server.close();
  if (socketFile.existsSync()) socketFile.deleteSync();

  stdout.writeln(
    failures.isEmpty
        ? '\n[check] PASSED — the loop works without the GUI'
        : '\n[check] FAILED:\n${failures.map((f) => '  - $f').join('\n')}',
  );
  exit(failures.isEmpty ? 0 : 1);
}

Future<String> _nextProbe(
  Stream<String> probes,
  Duration timeout, [
  bool Function(String)? where,
]) {
  var stream = where == null ? probes : probes.where(where);
  return stream.first.timeout(timeout, onTimeout: () => '<no probe>');
}

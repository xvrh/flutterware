import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';

import 'package:flutterware_app/src/catalog/catalog_entry.dart';
import 'package:flutterware_app/src/catalog/compiler_daemon_client.dart';
import 'package:flutterware_app/src/catalog/protocol.dart';
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
    // The demos live under `app/tool/catalog/`, so the app package is both the
    // scan root and the entrypoint's package.
    projectRoot: packageRoot,
    packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
    flutterSdkRoot: cache.flutterRoot,
    roots: const ['tool/catalog'],
    emitProbe: true,
  );
  var failures = <String>[];
  void check(bool condition, String description) {
    stdout.writeln('${condition ? '  ok  ' : ' FAIL '} $description');
    if (!condition) failures.add(description);
  }

  // Through the real client, so this exercises what the GUI uses — including
  // the precompiled daemon binary.
  stdout.writeln('[check] starting the compiler daemon');
  var spawn = Stopwatch()..start();
  var (daemon, ready) = await CompilerDaemonClient.start(
    dartExecutable: p.join(cache.flutterRoot, 'bin', 'dart'),
    config: config,
    onLog: (line) => stdout.writeln('  [daemon] $line'),
  );
  stdout.writeln('[check] spawn->ready ${spawn.elapsedMilliseconds}ms');
  var entries = ready.entries;
  stdout.writeln(
    '[check] daemon ready — cold compile ${ready.coldCompile.inMilliseconds}ms, '
    '${entries.length} entries discovered',
  );
  for (var diagnostic in ready.diagnostics) {
    stdout.writeln('  [scan] $diagnostic');
  }
  check(File(ready.hostPath).existsSync(), 'the C host was built');
  check(entries.length >= 5, 'discovery found the demo entries');
  check(
    entries.any((e) => e.group == 'Avatar tile'),
    'a file with several entries derived a group',
  );

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
    firstProbe.contains(entries.first.id),
    'the guest renders the first entry',
  );
  // Order-independent: entries are sorted by id, so which one is first is not
  // this check's business. That the probe carries rendered text at all means
  // the wrapper ran, the builder ran, and the tree was walked.
  check(
    firstProbe.split('|').last.trim().isNotEmpty,
    'the entry wrapper and demo body both ran',
  );

  // 3. Switch through every entry, then revisit one.
  for (var entry in [...entries.skip(1), entries.first]) {
    var compiled = await daemon.select(entry.id);
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
    if (entry.name == 'Members') {
      check(
        probe.contains('Dr. Sarah Chen'),
        'the Members entry rendered its own content',
      );
    }
  }

  var lastProbe = await _nextProbe(probes.stream, const Duration(seconds: 10));
  check(
    lastProbe.contains(entries.first.id),
    'revisiting the first entry renders it again',
  );
  check(frames > 0, 'the guest composited frames ($frames)');

  await daemon.shutdown();
  connected.add(encodeMessage(const ShutdownMessage()));
  await connected.flush();
  await vmService.close();
  await connected.close();
  guest.kill();
  await guest.exitCode;
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

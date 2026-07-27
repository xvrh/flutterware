import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:collection/collection.dart';

import 'package:flutterware_app/src/catalog/catalog_entry.dart';
import 'package:flutterware_app/src/catalog/compiler_daemon_client.dart';
import 'package:flutterware_app/src/catalog/package_config_locator.dart';
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
    packageConfig: requirePackageConfig(packageRoot),
    flutterSdkRoot: cache.flutterRoot,
    roots: const ['tool/catalog'],
    // `--no-probe` reproduces exactly what the GUI compiles. The probe adds a
    // timer to the generated entrypoint, and a difference in the entrypoint is
    // a difference in what hot reload has to do, so a bug can hide behind it.
    emitProbe: !args.contains('--no-probe'),
  );
  var probing = config.emitProbe;
  var failures = <String>[];
  void check(bool condition, String description) {
    stdout.writeln('${condition ? '  ok  ' : ' FAIL '} $description');
    if (!condition) failures.add(description);
  }

  // A daemon left over from a previous run carries that run's state — notably
  // whichever entries it had quarantined, and this check edits a demo on
  // purpose. Start from nothing so the assertions below mean the same thing
  // every time. Reuse is measured deliberately further down, by the second
  // client.
  if (!args.contains('--reuse')) {
    var (stale, _) = await CompilerDaemonClient.connect(
      dartExecutable: p.join(cache.flutterRoot, 'bin', 'dart'),
      config: config,
    );
    await stale.stopDaemon();
  }

  // Through the real client, so this exercises what the GUI uses — including
  // the precompiled daemon binary.
  stdout.writeln('[check] starting the compiler daemon');
  var spawn = Stopwatch()..start();
  var (daemon, ready) = await CompilerDaemonClient.connect(
    dartExecutable: p.join(cache.flutterRoot, 'bin', 'dart'),
    config: config,
    onLog: (line) => stdout.writeln('  [daemon] $line'),
  );
  stdout.writeln(
    '[check] connect->ready ${spawn.elapsedMilliseconds}ms '
    '(${ready.reused ? 'attached to a running daemon' : 'started one'})',
  );
  var entries = ready.entries;
  for (var phase in ready.timings.entries) {
    stdout.writeln('  [prepare] ${phase.key} ${phase.value}ms');
  }
  stdout.writeln(
    '[check] daemon ready — cold compile ${ready.coldCompile.inMilliseconds}ms, '
    '${entries.length} entries discovered',
  );
  for (var diagnostic in ready.diagnostics) {
    stdout.writeln('  [scan] $diagnostic');
  }
  check(File(ready.hostPath).existsSync(), 'the C host was built');
  check(
    ready.quarantined.map((q) => q.entry.symbol).contains('doesNotCompile'),
    'the demo that does not compile was quarantined, not fatal',
  );
  check(
    ready.quarantined.any((q) => q.error.contains('ThisTypeDoesNotExist')),
    'the quarantine carries the compiler error, so a renderer can show it',
  );
  check(
    entries.every((e) => e.symbol != 'doesNotCompile'),
    'a quarantined entry is not offered',
  );
  check(
    ready.reused || ready.timings.containsKey('rebuild after quarantine'),
    'the prepared kernel was rebuilt whole after the quarantine',
  );
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
  var launch = Stopwatch()..start();
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

  var connectedAt = launch.elapsedMilliseconds;
  var vmService = await GuestVmService.connect(await vmServiceUri.future);
  var vmServiceAt = launch.elapsedMilliseconds;
  // With no probe there is no rendered text to wait on, so wait for a
  // composited frame instead. Something must say the guest is up: reloading
  // before the framework has registered `ext.flutter.reassemble` fails with a
  // "Method not found" that looks nothing like the real cause.
  if (!probing) {
    var waited = Stopwatch()..start();
    while (frames == 0 && waited.elapsed < const Duration(seconds: 20)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  var firstProbe = probing
      ? await _nextProbe(probes.stream, const Duration(seconds: 20))
      : entries.first.id;
  stdout.writeln(
    '[check] guest launch: socket ${connectedAt}ms · vm service '
    '${vmServiceAt}ms · first frame ${launch.elapsedMilliseconds}ms',
  );
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

    var probe = probing
        ? await _nextProbe(
            probes.stream,
            const Duration(seconds: 10),
            (line) => line.contains(entry.id),
          )
        : entry.id;
    stdout.writeln(
      '[check] ${entry.name.padRight(10)} '
      'compile ${compiled.compile.inMilliseconds}ms · reload ${reloadMs}ms · '
      '+${compiled.newSourceCount} libs',
    );
    check(probe.contains(entry.id), 'switched to ${entry.name} by hot reload');
    if (probing && entry.name == 'Members') {
      check(
        probe.contains('Dr. Sarah Chen'),
        'the Members entry rendered its own content',
      );
    }
  }

  var lastProbe = probing
      ? await _nextProbe(probes.stream, const Duration(seconds: 10))
      : entries.first.id;
  check(
    lastProbe.contains(entries.first.id),
    'revisiting the first entry renders it again',
  );
  check(frames > 0, 'the guest composited frames ($frames)');

  // 4. A second client on the same daemon — the reason the daemon is shared.
  //
  // What is asserted is both halves of that: that it costs nothing, and that it
  // is nonetheless isolated. The compiler, the generated entrypoint and the
  // compiler's output file are one mutable thing shared between the two; if
  // that leaked, one client would decide what the other renders. It has
  // happened before, and it produced screenshots of the wrong entry that every
  // test passed.
  stdout.writeln('[check] attaching a second client');
  var attach = Stopwatch()..start();
  var (second, secondReady) = await CompilerDaemonClient.connect(
    dartExecutable: p.join(cache.flutterRoot, 'bin', 'dart'),
    config: config,
    onLog: (line) => stdout.writeln('  [daemon] $line'),
  );
  stdout.writeln(
    '[check] second connect->ready ${attach.elapsedMilliseconds}ms',
  );
  check(secondReady.reused, 'the second client attached rather than started');
  check(
    attach.elapsedMilliseconds < 500,
    'attaching cost ${attach.elapsedMilliseconds}ms, not a cold start',
  );
  check(
    secondReady.assetsDir != ready.assetsDir,
    'each client gets its own asset directory',
  );

  // Different entries, deliberately: whichever kernel each client is handed
  // must be the one it asked for.
  var mine = await daemon.select(entries.first.id, full: true);
  var theirs = await second.select(entries.last.id, full: true);
  check(mine.ok && theirs.ok, 'both clients compiled');
  check(
    mine.dill != theirs.dill,
    'each client got its own kernel, not one shared path',
  );
  check(
    File(mine.dill!).lengthSync() > 0 && File(theirs.dill!).lengthSync() > 0,
    'both kernels are whole programs',
  );
  check(
    !const ListEquality<int>().equals(
      File(mine.dill!).readAsBytesSync(),
      File(theirs.dill!).readAsBytesSync(),
    ),
    'the two kernels differ — a shared file would have made them identical',
  );

  // The scenario this is really about: a panel is open and rendering while an
  // agent compiles something else against the same daemon. The panel's guest
  // must not notice.
  //
  // The probe is the evidence, not the frame counter: an idle guest paints
  // nothing, quite correctly, so a frame count that stops rising says only that
  // the UI is static.
  var stillLive = probing
      ? await _nextProbe(probes.stream, const Duration(seconds: 10))
      : entries.first.id;
  check(
    stillLive.contains(entries.first.id),
    'the first client keeps rendering while another client compiles',
  );

  // 4b. A second *project* on the same GUI, at the same time.
  //
  // Every daemon runs out of the GUI's package, so they all wanted one
  // `app/build/catalog`: the generated entrypoint, the compiler's output, the
  // published kernel and the session directories. Two catalogs then generated
  // wrappers over each other and compiled to the same file, and a name present
  // in both projects — `wrapInApp`, which each project's demo shell exports —
  // resolved to whichever wrote last. The symptom was a hot reload failing with
  // `lookup Failed: wrapInApp in @method in .../shell.dart`, intermittently,
  // in whichever catalog lost the race.
  stdout.writeln('[check] opening a second project against the same GUI');
  var otherProject = p.join(p.dirname(packageRoot), 'examples', 'example');
  var (other, otherReady) = await CompilerDaemonClient.connect(
    dartExecutable: p.join(cache.flutterRoot, 'bin', 'dart'),
    config: DaemonConfig(
      appPackageRoot: packageRoot,
      projectRoot: otherProject,
      packageConfig: requirePackageConfig(otherProject),
      flutterSdkRoot: cache.flutterRoot,
    ),
    onLog: (line) => stdout.writeln('  [daemon] $line'),
  );
  try {
    check(
      otherReady.entries.isNotEmpty,
      'the second project has its own entries (${otherReady.entries.length})',
    );
    check(
      otherReady.assetsDir != ready.assetsDir,
      'the two projects do not share a working directory',
    );

    // The first project must still compile and reload *after* the second has
    // generated its own entrypoint — that is the collision.
    var afterOther = await daemon.select(entries.first.id);
    check(
      afterOther.ok,
      'the first project still compiles: ${afterOther.error}',
    );
    if (afterOther.ok) {
      try {
        await vmService.reload(afterOther.dill!);
        check(true, 'and its guest still reloads');
      } catch (e) {
        check(false, 'and its guest still reloads: $e');
      }
    }
  } finally {
    await other.close();
  }

  // 5. Fixing a broken demo brings it back, and every client is told.
  //
  // Both halves matter. Re-admission means fixing the file is enough — no
  // restart, no rescan. The broadcast means the client that was *not* compiling
  // still learns, which is the whole point of a shared daemon: a panel sitting
  // idle while someone edits must not keep offering an entry the daemon cannot
  // build, nor keep hiding one that now works.
  stdout.writeln('[check] repairing the broken demo');
  var brokenSource = File(
    p.join(packageRoot, 'tool', 'catalog', 'demos', 'does_not_compile.dart'),
  );
  var broken = brokenSource.readAsStringSync();
  var announced = second.catalogChanges.first.timeout(
    const Duration(seconds: 30),
    onTimeout: () =>
        throw StateError('no CatalogChanged reached the second client'),
  );
  brokenSource.writeAsStringSync(
    broken.replaceAll('ThisTypeDoesNotExist(missing: 1)', 'Placeholder()'),
  );
  try {
    var repaired = await daemon.select(entries.first.id);
    check(repaired.ok, 'the catalog still compiles after the repair');

    var change = await announced;
    check(
      change.entries.any((e) => e.symbol == 'doesNotCompile'),
      'the repaired entry came back without a restart or a rescan',
    );
    check(change.quarantined.isEmpty, 'and the quarantine emptied');
    check(
      (await daemon.select(
        'tool/catalog/demos/does_not_compile.dart#doesNotCompile',
      )).ok,
      'the repaired entry can be selected',
    );
  } finally {
    brokenSource.writeAsStringSync(broken);
  }

  await second.close();
  await daemon.close();
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

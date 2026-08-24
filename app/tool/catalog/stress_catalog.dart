import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutterware_app/src/previews/compiler_daemon_client.dart';
import 'package:flutterware_app/src/previews/package_config_locator.dart';
import 'package:flutterware_app/src/previews/protocol.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart';

/// Switches entries as fast as the pipeline allows, and says what the guest
/// actually had when a reload is refused.
///
/// Nothing in CI switches entries against a live guest any more, and this is
/// where that is still done by hand: in a loop, which is what a person clicking
/// around does. When `reloadSources` refuses,
/// the message is of the form
///
///     lookup Failed: <name> in @method in file:///.../shell.dart
///
/// which says a library the delta refers to is not in the running program the
/// way the delta expects. That is only diagnosable by asking the isolate what
/// it has, so this prints the VM's verbatim report **and** the isolate's own
/// library list, rather than leaving the next person to reason about which of
/// the two is wrong.
///
/// ```sh
/// cd app && dart run tool/catalog/stress_catalog.dart [rounds]
/// ```
Future<void> main(List<String> args) async {
  var rounds = args.isEmpty ? 5 : int.parse(args.first);
  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var cache = FlutterCache.fromRunningSdk();

  var (daemon, ready) = await CompilerDaemonClient.connect(
    dartExecutable: p.join(cache.flutterRoot, 'bin', 'dart'),
    config: DaemonConfig(
      appPackageRoot: packageRoot,
      projectRoot: packageRoot,
      packageConfig: requirePackageConfig(packageRoot),
      flutterSdkRoot: cache.flutterRoot,
      roots: const ['tool/catalog'],
    ),
    onLog: (line) => stdout.writeln('  [daemon] $line'),
  );
  stdout.writeln(
    '[stress] ${ready.entries.length} entries, '
    '${ready.quarantined.length} quarantined',
  );

  var socketPath = p.join(
    Directory.systemTemp.createTempSync('fw_stress').path,
    's.sock',
  );
  var server = await ServerSocket.bind(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  );
  var guest = await Process.start(ready.hostPath, [
    ready.assetsDir,
    ready.icuData,
    socketPath,
    '800',
    '600',
  ]);
  var vmServiceUri = Completer<String>();
  var guestLog = <String>[];
  StreamGroup.merge([guest.stdout, guest.stderr])
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        guestLog.add(line);
        var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
        if (match != null && !vmServiceUri.isCompleted) {
          vmServiceUri.complete(match.group(1));
        }
      });

  var connected = await Future.any<Object?>([server.first, guest.exitCode]);
  if (connected is! Socket) {
    stderr.writeln(
      'the guest exited before connecting:\n${guestLog.join('\n')}',
    );
    exit(1);
  }
  var frames = 0;
  var reader = FrameReader();
  connected.listen((chunk) {
    for (var message in reader.addBytes(chunk)) {
      if (message is FrameReadyMessage) frames++;
    }
  });

  var vm = await GuestVmService.connect(await vmServiceUri.future);
  while (frames == 0) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  var failures = 0;
  for (var round = 0; round < rounds; round++) {
    for (var entry in ready.entries) {
      var compiled = await daemon.select(entry.id);
      if (!compiled.ok) {
        stderr.writeln(
          '[stress] compile refused ${entry.id}: ${compiled.error}',
        );
        failures++;
        continue;
      }
      try {
        await vm.reload(compiled.dill!);
      } catch (e) {
        failures++;
        stderr.writeln('\n[stress] RELOAD REFUSED on ${entry.id}\n$e');
        await _dumpIsolate(vm, guestLog);
        exit(1);
      }
    }
    stdout.writeln('[stress] round ${round + 1}/$rounds ok ($frames frames)');
  }

  // Switching away from a catalog and back: the GUI disposes the session and
  // makes a new one, which launches a *fresh* guest from the prepared kernel.
  // That kernel is the baseline as of prepare time, while the daemon's compiler
  // has accepted every compile since — so the delta it hands this guest is
  // computed against a baseline the guest has never been at.
  stdout.writeln('[stress] re-opening: a new session after $rounds rounds');
  var (second, secondReady) = await CompilerDaemonClient.connect(
    dartExecutable: p.join(cache.flutterRoot, 'bin', 'dart'),
    config: DaemonConfig(
      appPackageRoot: packageRoot,
      projectRoot: packageRoot,
      packageConfig: requirePackageConfig(packageRoot),
      flutterSdkRoot: cache.flutterRoot,
      roots: const ['tool/catalog'],
    ),
  );
  var reopened = await _launchGuest(secondReady, 'reopen');
  for (var entry in secondReady.entries) {
    var compiled = await second.select(entry.id);
    if (!compiled.ok) continue;
    try {
      await reopened.vm.reload(compiled.dill!);
    } catch (e) {
      failures++;
      stderr.writeln(
        '\n[stress] RELOAD REFUSED on a re-opened session, ${entry.id}\n$e',
      );
      await _dumpIsolate(reopened.vm, reopened.log);
      break;
    }
  }
  if (failures == 0) {
    stdout.writeln('[stress] a re-opened session reloads cleanly');
  }
  reopened.guest.kill();
  await second.close();

  stdout.writeln(
    failures == 0 ? '[stress] PASSED' : '[stress] $failures failures',
  );
  await vm.close();
  guest.kill();
  await daemon.close();
  await server.close();
  exit(failures == 0 ? 0 : 1);
}

typedef _Guest = ({Process guest, GuestVmService vm, List<String> log});

/// A guest launched exactly the way the GUI launches one: from the session's
/// own asset directory, whose kernel is whatever the daemon prepared.
Future<_Guest> _launchGuest(DaemonReady ready, String name) async {
  var socketPath = p.join(
    Directory.systemTemp.createTempSync('fw_$name').path,
    's.sock',
  );
  var server = await ServerSocket.bind(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  );
  var guest = await Process.start(ready.hostPath, [
    ready.assetsDir,
    ready.icuData,
    socketPath,
    '800',
    '600',
  ]);
  var uri = Completer<String>();
  var log = <String>[];
  StreamGroup.merge([guest.stdout, guest.stderr])
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        log.add(line);
        var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
        if (match != null && !uri.isCompleted) uri.complete(match.group(1));
      });
  var connected = await Future.any<Object?>([server.first, guest.exitCode]);
  if (connected is! Socket) {
    throw StateError('the $name guest exited before connecting');
  }
  var frames = 0;
  var reader = FrameReader();
  connected.listen((chunk) {
    for (var m in reader.addBytes(chunk)) {
      if (m is FrameReadyMessage) frames++;
    }
  });
  var vm = await GuestVmService.connect(await uri.future);
  while (frames == 0) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return (guest: guest, vm: vm, log: log);
}

/// What the running isolate actually holds, which is the other half of any
/// "lookup Failed" — the message names what the delta wanted, never what was
/// there.
Future<void> _dumpIsolate(GuestVmService vm, List<String> guestLog) async {
  try {
    var isolate = await vm.service.getIsolate(vm.isolateId);
    var libraries = [for (var l in isolate.libraries ?? <LibraryRef>[]) l.uri!];
    var generated = libraries.where(
      (u) => u.contains('/build/catalog/') || u.contains('/demos/'),
    );
    stdout.writeln(
      '[stress] the isolate holds ${libraries.length} libraries; '
      'the ones this catalog generated or reads:',
    );
    for (var uri in generated) {
      stdout.writeln('    $uri');
    }
  } catch (e) {
    stdout.writeln('[stress] could not read the isolate: $e');
  }
  if (guestLog.isNotEmpty) {
    stdout.writeln('[stress] last guest output:');
    for (var line in guestLog.skip(
      guestLog.length > 15 ? guestLog.length - 15 : 0,
    )) {
      stdout.writeln('    $line');
    }
  }
}

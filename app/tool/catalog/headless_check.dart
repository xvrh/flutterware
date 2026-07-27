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
  // A demo that throws while building leaves the compile and the reload both
  // reporting success. Without this the check is blind to it.
  var guestErrors = <String>[];
  var vmServiceUri = Completer<String>();
  // Dart `print` in the guest goes through the engine's log handler, which
  // writes to stderr — so both streams have to be watched.
  StreamGroup.merge([
    guest.stdout,
    guest.stderr,
  ]).transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    // host.c tags every engine log line, so the probe arrives as
    // `[embedder] FW-PROBE: ...` rather than at the start of the line.
    if (line.contains('FW-ERROR:')) {
      guestErrors.add(line.substring(line.indexOf('FW-ERROR:')));
    }
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
  check(
    guestErrors.isEmpty,
    'the guest reported no framework errors'
    '${guestErrors.isEmpty ? '' : ':\n    ${guestErrors.join('\n    ')}'}',
  );

  // 3b. An edit to a demo, put on screen by a reload of the entry already
  // showing.
  //
  // The invalidation is the daemon's to do: `frontend_server` recompiles
  // exactly the files a `recompile` request names and nothing else. Without the
  // stat sweep this reload compiles, reloads, reports success in milliseconds
  // and renders the file as it was when the daemon started — which is what it
  // did before this check existed.
  if (probing) {
    stdout.writeln('[check] editing a demo and reloading it');
    var members = entries.firstWhere((e) => e.symbol == 'avatarTileMembers');
    var source = File(p.join(packageRoot, members.path));
    var original = source.readAsStringSync();
    await _renderEntry(daemon, vmService, probes, members);
    try {
      source.writeAsStringSync(
        original.replaceAll('Dr. Sarah Chen', 'Dr. Sarah Chen (edited)'),
      );
      var edited = await daemon.select(members.id);
      check(edited.ok, 'the edited demo compiled: ${edited.error}');
      check(
        edited.editedCount == 1,
        'the sweep found exactly the edited file (${edited.editedCount})',
      );
      if (edited.ok) {
        var watch = Stopwatch()..start();
        await vmService.reload(edited.dill!);
        var probe = await _nextProbe(
          probes.stream,
          const Duration(seconds: 10),
          (line) => line.contains('(edited)'),
        );
        check(probe.contains('(edited)'), 'the reload put the edit on screen');
        stdout.writeln(
          '[check] edit->screen: compile ${edited.compile.inMilliseconds}ms · '
          'reload ${watch.elapsedMilliseconds}ms',
        );
      }
    } finally {
      source.writeAsStringSync(original);
    }
    var reverted = await daemon.select(members.id);
    check(
      reverted.editedCount == 1,
      'and the revert is an edit like any other',
    );
    if (reverted.ok) await vmService.reload(reverted.dill!);
    var back = await _nextProbe(probes.stream, const Duration(seconds: 10));
    check(!back.contains('(edited)'), 'reverting the file reverts the screen');

    // What the checks below expect the guest to be rendering.
    await _renderEntry(daemon, vmService, probes, entries.first);

    // 3c. The contract the focus-triggered reload rests on: a request nobody
    // pressed must cost nothing when nothing was edited. A reload that always
    // works reassembles the guest and resets the demo's state, which would make
    // alt-tabbing back to the panel a way to lose your place.
    var quiet = await daemon.select(entries.first.id, ifChanged: true);
    check(quiet.unchanged, 'ifChanged does nothing when nothing was edited');
    check(quiet.dill == null, 'and hands back no kernel to reload');

    try {
      source.writeAsStringSync(
        original.replaceAll('No members yet', 'Nobody yet'),
      );
      var noisy = await daemon.select(entries.first.id, ifChanged: true);
      check(!noisy.unchanged, 'and does not skip when a file did move');
      check(noisy.ok, 'compiling what changed: ${noisy.error}');
      check(noisy.editedCount == 1, 'having found the one edited file');
      if (noisy.ok) await vmService.reload(noisy.dill!);
      var probe = await _nextProbe(
        probes.stream,
        const Duration(seconds: 10),
        (line) => line.contains('Nobody yet'),
      );
      check(probe.contains('Nobody yet'), 'and put it on screen');
    } finally {
      source.writeAsStringSync(original);
    }

    // 3d. A resize alone repaints.
    //
    // What the device picker rests on: choosing a phone resizes the guest and
    // nothing else happens, so if metrics alone did not produce a frame the
    // new size would not appear until something unrelated made the guest
    // paint. Metrics *do* schedule a frame — this is here to keep it that way,
    // since the capture path a few lines below already had to learn that the
    // engine renders nothing when nothing changed.
    var before = frames;
    connected.add(
      encodeMessage(
        // With a phone's safe areas, to see where the engine puts them.
        const ResizeMessage(
          width: 500,
          height: 900,
          pixelRatio: 2,
          insetTop: 94,
          insetBottom: 68,
        ),
      ),
    );
    await connected.flush();
    var waited = Stopwatch()..start();
    while (frames == before && waited.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    check(frames > before, 'a resize on a static scene paints a frame');

    // Where the embedder's view insets land, which decides whether a device's
    // notch can reach a demo's AppBar at all: `padding` is what SafeArea and
    // AppBar read, and the embedder API exposes only `physical_view_inset_*`.
    var metrics = await _nextProbe(
      probes.stream,
      const Duration(seconds: 10),
      (line) => line.contains('padding'),
    );
    stdout.writeln('[check] view metrics after an inset resize: $metrics');
    check(
      metrics.contains('insets 94.0'),
      'the safe areas reach the guest — $metrics',
    );
    check(
      metrics.contains('padding 0.0'),
      'as view *insets*: the embedder API has no padding field, which is why '
      'the demo shell has to translate them — $metrics',
    );

    // And that the translation works, read from a demo rather than from the
    // view: what an AppBar respects is the MediaQuery it is built under.
    var probe = entries.firstWhere((e) => e.symbol == 'paddingProbe');
    await _renderEntry(daemon, vmService, probes, probe);
    var seen = await _nextProbe(
      probes.stream,
      const Duration(seconds: 10),
      (line) => line.contains('PADDING'),
    );
    check(
      // Logical pixels: the host sends the safe areas in physical ones, and a
      // MediaQuery is in the demo's own coordinates — 94 and 68 over a ratio
      // of 2.
      seen.contains('PADDING 47.0,34.0'),
      'the demo sees the device safe areas as padding — $seen',
    );

    // 3e. Hover reaches the guest.
    //
    // The phase travels the whole way — GUI socket, `input.c`, engine, demo —
    // and only the demo can confirm it arrived: hover leaves nothing behind but
    // a colour, so the probe reads a demo that turns it into text.
    stdout.writeln('[check] hovering the guest');
    var hover = entries.firstWhere((e) => e.symbol == 'hoverProbe');
    await _renderEntry(daemon, vmService, probes, hover);
    var resting = await _nextProbe(probes.stream, const Duration(seconds: 10));
    check(resting.contains('POINTER OUT'), 'the demo starts un-hovered');

    // The hover has to land somewhere other than the add: the engine drops a
    // hover that does not move, so sending both at one point proves nothing.
    for (var (phase, x, y) in [
      (PointerPhase.add, 400.0, 300.0),
      (PointerPhase.hover, 420.0, 320.0),
    ]) {
      connected.add(
        encodeMessage(
          PointerEventMessage(
            phase: phase,
            x: x,
            y: y,
            buttons: 0,
            scrollDeltaX: 0,
            scrollDeltaY: 0,
            timestampMicros: DateTime.now().microsecondsSinceEpoch,
          ),
        ),
      );
    }
    await connected.flush();
    var hovered = await _nextProbe(
      probes.stream,
      const Duration(seconds: 10),
      (line) => line.contains('POINTER IN'),
    );
    check(hovered.contains('POINTER IN'), 'the guest received the hover');
    check(
      !hovered.contains('no hover yet'),
      'carrying a position, so onHover fired and not only onEnter — $hovered',
    );

    // And the pairing: a device that leaves has to be removed, or the hover
    // state it left behind never lifts.
    connected.add(
      encodeMessage(
        PointerEventMessage(
          phase: PointerPhase.remove,
          x: 420,
          y: 320,
          buttons: 0,
          scrollDeltaX: 0,
          scrollDeltaY: 0,
          timestampMicros: DateTime.now().microsecondsSinceEpoch,
        ),
      ),
    );
    await connected.flush();
    var left = await _nextProbe(
      probes.stream,
      const Duration(seconds: 10),
      (line) => line.contains('POINTER OUT'),
    );
    check(left.contains('POINTER OUT'), 'and the hover lifts when it leaves');

    await _renderEntry(daemon, vmService, probes, entries.first);
  }

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
  // 5. Retrying, then fixing, a demo that does not compile.
  //
  // Selecting a quarantined entry is the retry, and it has to be: nothing else
  // compiles that entry, so an id the daemon refuses to look up is an entry
  // only an edit to some *other* file could ever bring back.
  const brokenId = 'tool/catalog/demos/does_not_compile.dart#doesNotCompile';
  var retried = await daemon.select(brokenId);
  check(!retried.ok, 'selecting a broken entry does not pretend to succeed');
  check(
    retried.error?.contains('ThisTypeDoesNotExist') ?? false,
    'and answers with the compiler error, not "no such entry"',
  );
  check(
    (await daemon.select(entries.first.id)).ok,
    'the catalog still compiles after a failed retry',
  );

  // 4b-bis. Knobs: declared by building, read and set over the VM service.
  //
  // No platform channels exist in a guest, so this is the only bidirectional
  // channel there is — and a value must *not* travel as a reload, or turning a
  // knob would cost a compile and reset the demo's state.
  if (probing) {
    stdout.writeln('[check] turning a knob');
    var knobs = entries.firstWhere((e) => e.symbol == 'knobs');
    await _renderEntry(daemon, vmService, probes, knobs);
    var resting = await _nextProbe(
      probes.stream,
      const Duration(seconds: 10),
      (line) => line.contains('KNOB'),
    );
    check(
      resting.contains('KNOB Hello x2 roomy'),
      'the demo renders its defaults — $resting',
    );

    var described = await vmService.callExtension('ext.flutterware.parameters');
    var declared = [
      for (var p in (described?['parameters'] as List? ?? []))
        (p as Map)['name'] as String,
    ];
    check(
      declared.join(',') == 'label,count,dense',
      'the knobs it read while building are the knobs it reports — $declared',
    );

    var set = await vmService.callExtension(
      'ext.flutterware.setParameter',
      args: {
        'payload': jsonEncode({'name': 'label', 'value': 'Turned'}),
      },
    );
    check(set?['applied'] == true, 'setting a declared knob is accepted');
    var turned = await _nextProbe(
      probes.stream,
      const Duration(seconds: 10),
      (line) => line.contains('Turned'),
    );
    check(
      turned.contains('KNOB Turned x2 roomy'),
      'and the demo rebuilds with it — $turned',
    );

    var refused = await vmService.callExtension(
      'ext.flutterware.setParameter',
      args: {
        'payload': jsonEncode({'name': 'nope', 'value': 1}),
      },
    );
    check(
      refused?['applied'] == false,
      'a knob the build never declared is refused, not invented',
    );
  }

  // 4c. A demo that did not exist when the daemon started.
  //
  // Discovery runs once at startup, so without a rescan a file you add while
  // the catalog is open is a file the catalog will never mention — and the
  // daemon outlives the panel, so "restart it" means closing the worktree.
  stdout.writeln('[check] adding a demo while the catalog is open');
  var addedSource = File(
    p.join(packageRoot, 'tool', 'catalog', 'demos', 'added_while_open.dart'),
  );
  var appeared = daemon.catalogChanges.first.timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw StateError('no CatalogChanged announced the entry'),
  );
  addedSource.writeAsStringSync('''
import 'package:flutter/material.dart';

import 'package:flutterware/ui_catalog.dart';

import 'shell.dart';

@Demo(name: 'Added', wrapper: wrapInApp)
Widget addedWhileOpen() => const Center(child: Text('ADDED LATE'));
''');
  const addedId = 'tool/catalog/demos/added_while_open.dart#addedWhileOpen';
  try {
    // Discovered by the *other* client, which is the case that separates a
    // shared daemon from a private one — and the harder one. Whoever compiles
    // first puts the new wrapper into the compiler's baseline; every delta
    // after that leaves it out, being unchanged, so a guest that was not there
    // for that compile would reload a program referring to a library it has
    // never had. Nothing here reloads into this check's guest on purpose.
    // A refresh, not a select: this is the panel's timer, which must notice
    // the file without compiling anything or touching anybody's guest.
    second.refresh();
    var announced = await appeared;
    check(
      announced.entries.any((e) => e.id == addedId),
      'and every client is told it exists',
    );

    var compiled = await daemon.select(addedId);
    check(compiled.ok, 'the new entry compiles: ${compiled.error}');
    if (compiled.ok) {
      await vmService.reload(compiled.dill!);
      var probe = probing
          ? await _nextProbe(
              probes.stream,
              const Duration(seconds: 10),
              (line) => line.contains('ADDED LATE'),
            )
          : 'ADDED LATE';
      check(probe.contains('ADDED LATE'), 'and it renders');
    }
  } finally {
    addedSource.deleteSync();
  }

  // And gone again: the entry has to leave the list it just joined.
  var removed = daemon.catalogChanges.first.timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw StateError('no CatalogChanged withdrew the entry'),
  );
  var afterDelete = await daemon.select(entries.first.id);
  check(afterDelete.ok, 'the catalog still compiles once it is deleted');
  check(
    !(await removed).entries.any((e) => e.id == addedId),
    'and the entry is withdrawn',
  );

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

/// Puts [entry] on the guest's screen and waits until the probe says so.
Future<void> _renderEntry(
  CompilerDaemonClient daemon,
  GuestVmService vmService,
  StreamController<String> probes,
  CatalogEntry entry,
) async {
  var compiled = await daemon.select(entry.id);
  if (!compiled.ok) return;
  await vmService.reload(compiled.dill!);
  await _nextProbe(
    probes.stream,
    const Duration(seconds: 10),
    (line) => line.contains(entry.id),
  );
}

Future<String> _nextProbe(
  Stream<String> probes,
  Duration timeout, [
  bool Function(String)? where,
]) {
  var stream = where == null ? probes : probes.where(where);
  return stream.first.timeout(timeout, onTimeout: () => '<no probe>');
}

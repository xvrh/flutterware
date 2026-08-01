import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutterware_app/src/previews/asset_bundle.dart';
import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/frontend_server.dart';
import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:path/path.dart' as p;

/// S1 spike host: builds and spawns the embedder guest running
/// `scenario_scene.dart`, then collects each step's text projection and
/// rendered frame over a second Unix socket.
///
/// With `--hot`, runs the scenario, edits the scenario source, hot-reloads the
/// *live* guest through its VM service, and re-runs — without restarting.
///
/// Flags: `--hot`.
Future<void> main(List<String> args) async {
  var hot = args.contains('--hot');

  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var repoRoot = p.dirname(packageRoot);
  var cache = FlutterCache.fromRunningSdk();

  var buildDir = p.join(packageRoot, 'build', 'embedder');
  var assetsDir = p.join(buildDir, 'scenario_assets');
  var outDir = p.join(buildDir, 'scenario');
  var scenePath = p.join(
    packageRoot,
    'tool',
    'embedder',
    'scenario_scene.dart',
  );
  // Not under the build directory: a unix socket path is capped at 104 bytes
  // on macOS, which a long checkout path overflows. Pid so parallel runs
  // don't unlink each other's sockets.
  var guestSocketPath = checkSocketPath(
    p.join(flutterwareRunDir(), 'sc-g-$pid.sock'),
  );
  var controlSocketPath = checkSocketPath(
    p.join(flutterwareRunDir(), 'sc-c-$pid.sock'),
  );

  Directory(buildDir).createSync(recursive: true);
  var out = Directory(outDir);
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  var engineDir = await ensureEmbedderFramework(cache);
  // The asset bundle (fonts, MaterialIcons, compiled shaders, manifests) is
  // what makes the guest behave like a real app — the ink-sparkle shader in
  // particular, which the FilledButton tap below loads on first use.
  // Milliseconds, so it is rebuilt every start; the kernel is compiled over it
  // by the fast compiler below.
  await AssetBundleBuilder(
    cache: cache,
    rootPackageRoot: packageRoot,
    packageConfigPath: p.join(repoRoot, '.dart_tool', 'package_config.json'),
  ).build(assetsDir);

  // A *resident* compiler: the first compile is cold, every later one is an
  // incremental recompile of just the edited library.
  var watch = Stopwatch()..start();
  var compiler = await FrontendServer.start(
    executable: cache.dartAotRuntime,
    snapshot: cache.frontendServerSnapshot,
    entrypoint: scenePath,
    outputDill: p.join(assetsDir, 'kernel_blob.bin'),
    packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
    sdkRoot: cache.flutterPatchedSdkDir,
    platformDill: cache.platformDill,
  );
  var first = await compiler.compile();
  if (first.errorCount > 0) {
    stderr.writeln(first.output.join('\n'));
    exit(1);
  }
  compiler.accept();
  stdout.writeln('[scenario] cold compile ${watch.elapsedMilliseconds}ms');

  var hostPath = await buildHost(
    nativeSourceDir: p.join(packageRoot, 'native'),
    nativeBuildDir: p.join(buildDir, 'native'),
    engineDir: engineDir,
  );

  var guestServer = await _bind(guestSocketPath);
  var controlServer = await _bind(controlSocketPath);

  stdout.writeln('[scenario] spawning guest');
  var guest = await Process.start(
    hostPath,
    [assetsDir, cache.icuData, guestSocketPath, '800', '600'],
    environment: {'FW_SCENARIO_SOCKET': controlSocketPath},
  );
  guest.stderr.transform(utf8.decoder).listen(stderr.write);

  // The guest prints its VM service URI on stdout; capture it for hot reload.
  var vmServiceUri = Completer<String>();
  guest.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
    line,
  ) {
    stdout.writeln('[guest] $line');
    var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
    if (match != null && !vmServiceUri.isCompleted) {
      vmServiceUri.complete(match.group(1));
    }
  });

  // Drain the embedder control socket so the guest never blocks writing frames.
  var guestConn = await guestServer.first;
  var reader = FrameReader();
  var frames = 0;
  guestConn.listen((chunk) {
    for (var message in reader.addBytes(chunk)) {
      if (message is FrameReadyMessage) frames++;
      if (message is ErrorMessage) {
        stderr.writeln('[scenario] guest error: ${message.message}');
      }
    }
  });

  var exitCodeFuture = guest.exitCode;
  var accepted = await Future.any<Object?>([
    controlServer.first,
    exitCodeFuture,
  ]);
  if (accepted is! Socket) {
    stderr.writeln('[scenario] guest exited before opening the control socket');
    exit(1);
  }
  var control = accepted;
  var lines = StreamQueue(
    control
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((l) => jsonDecode(l) as Map<String, Object?>),
  );

  var hello = await lines.next;
  stdout.writeln(
    '[scenario] guest dart:io alive — pid=${hello['pid']} '
    'env=${hello['envCount']} vars, Dart ${hello['dartVersion']}',
  );

  var plugins = await lines.next;
  stdout.writeln(
    '[scenario] unfaked plugin channel → ${plugins['outcome']} '
    'after ${plugins['ms']}ms',
  );

  var ok = await _runOnce(control, lines, outDir, 'run-0');

  if (ok && hot) {
    ok = await _hotCycle(
      compiler: compiler,
      scenePath: scenePath,
      vmServiceUri: await vmServiceUri.future,
      control: control,
      lines: lines,
      outDir: outDir,
    );
  }

  control.add(utf8.encode('${jsonEncode({'type': 'quit'})}\n'));
  await control.flush();
  guestConn.add(encodeMessage(const ShutdownMessage()));
  await guestConn.flush();
  await guestConn.close();
  await exitCodeFuture;
  await guestServer.close();
  await controlServer.close();
  await compiler.shutdown();
  for (var path in [guestSocketPath, controlSocketPath]) {
    var f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  stdout.writeln(
    '[scenario] ${ok ? 'OK' : 'FAILED'} — $frames guest frames, '
    'output in $outDir',
  );
  exit(ok ? 0 : 1);
}

/// Sends one `run` command and collects steps until `done`.
Future<bool> _runOnce(
  Socket control,
  StreamQueue<Map<String, Object?>> lines,
  String outDir,
  String runName,
) async {
  Directory(p.join(outDir, runName)).createSync(recursive: true);
  var watch = Stopwatch()..start();
  control.add(utf8.encode('${jsonEncode({'type': 'run'})}\n'));

  while (await lines.hasNext) {
    var message = await lines.next;
    switch (message['type']) {
      case 'step':
        var index = message['index']! as int;
        var png = base64Decode(message['png']! as String);
        File(p.join(outDir, runName, 'step-$index.png')).writeAsBytesSync(png);
        stdout.writeln(
          '[$runName] step $index "${message['label']}" — ${png.length}B png, '
          'texts=${(message['texts']! as List).cast<String>()}',
        );
      case 'done':
        if (message['ok'] != true) {
          stderr.writeln('[$runName] FAILED: ${message['error']}');
          stderr.writeln(message['stack']);
          return false;
        }
        stdout.writeln(
          '[$runName] completed in ${watch.elapsedMilliseconds}ms',
        );
        return true;
    }
  }
  return false;
}

/// Edits the scenario source, recompiles incrementally, pushes the delta into
/// the live guest via the VM service, and re-runs the scenario.
Future<bool> _hotCycle({
  required FrontendServer compiler,
  required String scenePath,
  required String vmServiceUri,
  required Socket control,
  required StreamQueue<Map<String, Object?>> lines,
  required String outDir,
}) async {
  var file = File(scenePath);
  var original = file.readAsStringSync();
  // One edit touching both halves: the app's UI *and* the scenario's assertion.
  var edited = original
      .replaceAll(r"'Taps: $_taps'", r"'Count: $_taps'")
      .replaceAll("const expected = 'Taps: 2';", "const expected = 'Count: 2';")
      .replaceAll("_capture('initial')", "_capture('initial (reloaded)')");
  if (edited == original) {
    stderr.writeln('[hot] the scenario edit matched nothing — aborting');
    return false;
  }

  try {
    file.writeAsStringSync(edited);
    stdout.writeln('[hot] edited the scenario, recompiling');

    var watch = Stopwatch()..start();
    var result = await compiler.compile([file.uri]);
    if (result.errorCount > 0) {
      stderr.writeln(result.output.join('\n'));
      await compiler.reject();
      return false;
    }
    compiler.accept();
    var compileMs = watch.elapsedMilliseconds;

    watch.reset();
    var vmService = await GuestVmService.connect(vmServiceUri);
    await vmService.reload(result.dillOutput!);
    await vmService.close();
    var reloadMs = watch.elapsedMilliseconds;
    stdout.writeln(
      '[hot] incremental compile ${compileMs}ms · reload ${reloadMs}ms',
    );

    // Awaited so the restore below happens after the run rather than during
    // it. `_runOnce` only drives the guest over the control socket and never
    // re-reads the scene, so this changes when the file goes back, not what
    // the run measures.
    return await _runOnce(control, lines, outDir, 'run-1-hot');
  } finally {
    file.writeAsStringSync(original);
  }
}

Future<ServerSocket> _bind(String path) async {
  var file = File(path);
  if (file.existsSync()) file.deleteSync();
  return ServerSocket.bind(
    InternetAddress(path, type: InternetAddressType.unix),
    0,
  );
}

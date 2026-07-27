import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:frontend_server_client/frontend_server_client.dart';
import 'package:path/path.dart' as p;

/// S1 spike host: builds and spawns the embedder guest running
/// `scenario_scene.dart`, then collects each step's text projection and
/// rendered frame over a second Unix socket.
///
/// With `--hot`, runs the scenario, edits the scenario source, hot-reloads the
/// *live* guest through its VM service, and re-runs — without restarting.
///
/// Flags: `--hot`, `--rebuild-assets`.
Future<void> main(List<String> args) async {
  var hot = args.contains('--hot');
  var forceAssets = args.contains('--rebuild-assets');

  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var repoRoot = p.dirname(packageRoot);
  var cache = FlutterCache.fromRunningSdk();

  var buildDir = p.join(packageRoot, 'build', 'embedder');
  var assetsDir = p.join(buildDir, 'scenario_assets');
  var outDir = p.join(buildDir, 'scenario');
  var engineDir = p.join(packageRoot, '.engine');
  var scenePath = p.join(
    packageRoot,
    'tool',
    'embedder',
    'scenario_scene.dart',
  );
  var guestSocketPath = p.join(buildDir, 'scenario_guest.sock');
  var controlSocketPath = p.join(buildDir, 'scenario_control.sock');

  Directory(buildDir).createSync(recursive: true);
  var out = Directory(outDir);
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  await ensureEmbedderFramework(cache, engineDir);
  // The asset bundle (fonts, MaterialIcons, AssetManifest) is what makes the
  // guest behave like a real app. It is slow (~11s) and changes rarely, so it
  // is cached; the kernel is recompiled over it by the fast compiler below.
  await _ensureAssetBundle(
    packageRoot: packageRoot,
    scenePath: scenePath,
    assetsDir: assetsDir,
    cache: cache,
    force: forceAssets,
  );

  // A *resident* compiler: the first compile is cold, every later one is an
  // incremental recompile of just the edited library.
  var watch = Stopwatch()..start();
  var compiler = await FrontendServerClient.start(
    scenePath,
    p.join(assetsDir, 'kernel_blob.bin'),
    cache.platformDill,
    sdkRoot: cache.flutterPatchedSdkDir,
    target: 'flutter',
    packagesJson: p.join(repoRoot, '.dart_tool', 'package_config.json'),
  );
  var first = await compiler.compile();
  if (first.errorCount > 0) {
    stderr.writeln(first.compilerOutputLines.join('\n'));
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
  required FrontendServerClient compiler,
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
      stderr.writeln(result.compilerOutputLines.join('\n'));
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

    return _runOnce(control, lines, outDir, 'run-1-hot');
  } finally {
    file.writeAsStringSync(original);
  }
}

Future<void> _ensureAssetBundle({
  required String packageRoot,
  required String scenePath,
  required String assetsDir,
  required FlutterCache cache,
  required bool force,
}) async {
  if (File(p.join(assetsDir, 'FontManifest.json')).existsSync() && !force) {
    return;
  }
  stdout.writeln('[scenario] building the Flutter asset bundle');
  var result = await Process.run(p.join(cache.flutterRoot, 'bin', 'flutter'), [
    'build',
    'bundle',
    '-t',
    scenePath,
    '--asset-dir',
    assetsDir,
  ], workingDirectory: packageRoot);
  if (result.exitCode != 0) {
    throw StateError('flutter build bundle failed:\n${result.stderr}');
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

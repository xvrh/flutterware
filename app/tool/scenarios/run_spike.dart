import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/frontend_server.dart';
import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:path/path.dart' as p;

/// S4 spike host: spawns the SDK's `flutter_tester` binary **directly** — no
/// `flutter run`, no `flutter test` — feeds it a kernel from our own resident
/// `frontend_server`, and drives a FakeAsync scenario in it over the VM
/// service.
///
/// Deliberately does NOT pass `--use-test-fonts` / `--disable-asset-fonts`,
/// the two flags `flutter test` always passes — they are what forces Ahem and
/// blocks system font fallback. Owning the spawn is what lets us drop them.
///
/// Flags: `--hot` (edit + reload + rerun cycle), `--rebuild-assets`.
Future<void> main(List<String> args) async {
  var hot = args.contains('--hot');
  var forceAssets = args.contains('--rebuild-assets');

  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var repoRoot = p.dirname(packageRoot);
  var exampleDir = p.join(repoRoot, 'examples', 'example');
  var cache = FlutterCache.fromRunningSdk();

  var buildDir = p.join(packageRoot, 'build', 'scenarios');
  var assetsDir = p.join(buildDir, 'spike_assets');
  var outDir = p.join(buildDir, 'spike_out');
  var scenePath = p.join(packageRoot, 'tool', 'scenarios', 'spike_scene.dart');
  var testerPath = p.join(
    cache.cacheDir,
    'artifacts',
    'engine',
    'darwin-x64', // spike is macOS; linux-x64/windows-x64 ship the same binary
    'flutter_tester',
  );

  Directory(buildDir).createSync(recursive: true);
  var out = Directory(outDir);
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  // The asset bundle comes from examples/example — a real project with real
  // fonts (two Roboto weights) and uses-material-design, so FontManifest.json
  // is the honest input. Slow, changes rarely, cached.
  await _ensureAssetBundle(
    exampleDir: exampleDir,
    assetsDir: assetsDir,
    cache: cache,
    force: forceAssets,
  );

  var watch = Stopwatch()..start();
  var compiler = await FrontendServer.start(
    executable: cache.dartAotRuntime,
    snapshot: cache.frontendServerSnapshot,
    entrypoint: scenePath,
    outputDill: p.join(buildDir, 'spike.dill'),
    packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
    sdkRoot: cache.flutterPatchedSdkDir,
    platformDill: cache.platformDill,
    workingDirectory: repoRoot,
  );
  var first = await compiler.compile();
  if (first.errorCount > 0) {
    stderr.writeln(first.output.join('\n'));
    exit(1);
  }
  compiler.accept();
  stdout.writeln('[spike] cold compile ${watch.elapsedMilliseconds}ms');

  watch.reset();
  stdout.writeln('[spike] spawning flutter_tester');
  var guest = await Process.start(
    testerPath,
    [
      '--vm-service-port=0',
      '--disable-service-auth-codes',
      '--icu-data-file-path=${cache.icuData}',
      '--enable-checked-mode',
      '--verify-entry-points',
      '--enable-software-rendering',
      '--skia-deterministic-rendering',
      '--enable-dart-profiling',
      '--non-interactive',
      '--run-forever',
      // No --use-test-fonts, no --disable-asset-fonts. See the doc comment.
      '--packages=${p.join(repoRoot, '.dart_tool', 'package_config.json')}',
      '--flutter-assets-dir=$assetsDir',
      p.join(buildDir, 'spike.dill'),
    ],
    environment: {'FLUTTER_TEST': 'true', 'FW_SPIKE_OUT': outDir},
  );
  guest.stderr.transform(utf8.decoder).listen(stderr.write);

  var vmServiceUri = Completer<String>();
  var guestReady = Completer<void>();
  guest.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
    line,
  ) {
    stdout.writeln('[guest] $line');
    var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
    if (match != null && !vmServiceUri.isCompleted) {
      vmServiceUri.complete(match.group(1));
    }
    if (line.contains('S4 guest ready') && !guestReady.isCompleted) {
      guestReady.complete();
    }
  });
  unawaited(
    guest.exitCode.then((code) {
      if (!guestReady.isCompleted) {
        guestReady.completeError(
          StateError('flutter_tester exited with $code before ready'),
        );
      }
    }),
  );

  var ok = false;
  GuestVmService? vm;
  try {
    await guestReady.future.timeout(const Duration(seconds: 30));
    stdout.writeln(
      '[spike] guest ready in ${watch.elapsedMilliseconds}ms '
      '(spawn → fonts loaded → extension registered)',
    );

    vm = await GuestVmService.connect(await vmServiceUri.future);
    ok = await _runOnce(vm, 'run-0');

    if (ok && hot) {
      ok = await _hotCycle(compiler: compiler, scenePath: scenePath, vm: vm);
    }
  } finally {
    await vm?.close();
    guest.kill();
    await guest.exitCode;
    await compiler.shutdown();
  }

  stdout.writeln('[spike] ${ok ? 'OK' : 'FAILED'} — output in $outDir');
  exit(ok ? 0 : 1);
}

Future<bool> _runOnce(GuestVmService vm, String runId) async {
  var watch = Stopwatch()..start();
  var result = await vm.requireExtension('ext.spike.run', args: {'run': runId});
  var wallMs = watch.elapsedMilliseconds;
  var steps = (result!['steps']! as List).cast<Map<String, dynamic>>();
  for (var (index, step) in steps.indexed) {
    stdout.writeln(
      '[$runId] step $index "${step['label']}" — ${step['bytes']}B png, '
      'texts=${(step['texts'] as List).cast<String>()}',
    );
  }
  if (result['ok'] != true) {
    stderr.writeln('[$runId] FAILED:');
    for (var error in (result['errors'] as List).cast<String>()) {
      stderr.writeln(error);
    }
    return false;
  }
  stdout.writeln(
    '[$runId] completed — scenario ${result['ms']}ms, wall ${wallMs}ms',
  );
  return true;
}

/// Edits the scene (app text, assertion, and step label), recompiles
/// incrementally, reloads the live guest, re-runs — and checks the counter
/// went back to zero, which is the harness's per-run state reset at work.
Future<bool> _hotCycle({
  required FrontendServer compiler,
  required String scenePath,
  required GuestVmService vm,
}) async {
  var file = File(scenePath);
  var original = file.readAsStringSync();
  var edited = original
      .replaceAll(
        "const _counterPrefix = 'Taps';",
        "const _counterPrefix = 'Count';",
      )
      .replaceAll(
        "const _expectedAfterTwoTaps = 'Taps: 2';",
        "const _expectedAfterTwoTaps = 'Count: 2';",
      )
      .replaceAll(
        "const _initialLabel = 'initial';",
        "const _initialLabel = 'initial reloaded';",
      );
  if (edited == original) {
    stderr.writeln('[hot] the scene edit matched nothing — aborting');
    return false;
  }

  try {
    file.writeAsStringSync(edited);
    stdout.writeln('[hot] edited the scene, recompiling');

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
    // reloadSources only — deliberately NOT `ext.flutter.reassemble`.
    // Reassemble exists to rebuild a live tree in place; this harness has no
    // live tree between runs, and under a test binding outside a test the
    // reassemble awaits a frame that never comes. The re-run builds a fresh
    // tree from the reloaded code, which is the FakeAsync model working as
    // designed.
    var report = await vm.service.reloadSources(
      vm.isolateId,
      rootLibUri: result.dillOutput,
    );
    if (report.success != true) {
      stderr.writeln('[hot] reloadSources refused: ${report.json}');
      return false;
    }
    var reloadMs = watch.elapsedMilliseconds;
    stdout.writeln(
      '[hot] incremental compile ${compileMs}ms · reload ${reloadMs}ms',
    );

    var ok = await _runOnce(vm, 'run-1-hot');
    if (!ok) return false;

    // State reset: the reloaded run must start from zero, not from the taps
    // the previous run left behind.
    var check = await vm.requireExtension(
      'ext.spike.run',
      args: {'run': 'run-2-reset-check'},
    );
    var steps = (check!['steps']! as List).cast<Map<String, dynamic>>();
    var initialTexts = (steps.first['texts'] as List).cast<String>();
    var resets = initialTexts.contains('Count: 0');
    stdout.writeln(
      '[hot] state reset between runs: ${resets ? 'yes' : 'NO'} '
      '(initial texts: $initialTexts)',
    );
    return resets && check['ok'] == true;
  } finally {
    file.writeAsStringSync(original);
  }
}

Future<void> _ensureAssetBundle({
  required String exampleDir,
  required String assetsDir,
  required FlutterCache cache,
  required bool force,
}) async {
  if (File(p.join(assetsDir, 'FontManifest.json')).existsSync() && !force) {
    return;
  }
  stdout.writeln('[spike] building the example asset bundle');
  var result = await Process.run(p.join(cache.flutterRoot, 'bin', 'flutter'), [
    'build',
    'bundle',
    '--asset-dir',
    assetsDir,
  ], workingDirectory: exampleDir);
  if (result.exitCode != 0) {
    throw StateError('flutter build bundle failed:\n${result.stderr}');
  }
}

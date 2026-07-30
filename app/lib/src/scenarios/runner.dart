import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../catalog/package_config_locator.dart';
import '../embedder/flutter_cache.dart';
import '../embedder/frontend_server.dart';
import '../embedder/guest_vm_service.dart';
import 'discovery.dart';
import 'harness_entrypoint.dart';

/// One scenario listed by the live harness — ground truth, where the scan is
/// provisional.
class ScenarioListing {
  ScenarioListing({required this.file, required this.name});

  final String file;
  final String name;
}

/// Runs a package's scenarios in a directly-spawned `flutter_tester`, exactly
/// as spike S4 proved (`2026-07-30-s4-flutter-tester-findings.md`): our own
/// resident `frontend_server`, the SDK's tester binary, FakeAsync inside,
/// driven over the VM service.
///
/// Deliberately Flutter-free: `fw run scenarios run` links this, and the
/// purity guardrail (`entry_point_purity_test.dart`) holds it to that.
///
/// Not passing `--use-test-fonts` / `--disable-asset-fonts` — the two flags
/// `flutter test` always passes — is what makes captures render real fonts;
/// the harness loads `FontManifest.json` on top.
class ScenarioRunner {
  ScenarioRunner({
    required this.packageRoot,
    required this.directory,
    required this.flutterSdkRoot,
    this.onLog,
  });

  final String packageRoot;

  /// Scenario directory relative to [packageRoot].
  final String directory;

  final String flutterSdkRoot;
  final void Function(String line)? onLog;

  late final FlutterCache _cache = FlutterCache(
    p.join(flutterSdkRoot, 'bin', 'cache'),
  );

  FrontendServer? _compiler;
  Process? _guest;
  GuestVmService? _vm;
  var _started = false;
  var _disposed = false;

  String get _buildDir => p.join(packageRoot, 'build', 'flutterware');

  /// Builds everything and leaves a warm guest behind: scan → generated
  /// entrypoint → asset bundle → compile → spawn → connect. Idempotent.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    var scan = ScenarioScanner(
      packageRoot: packageRoot,
      directory: directory,
    ).scan();
    var files = {for (var ref in scan.scenarios) ref.file}.toList();
    if (files.isEmpty) {
      throw StateError(
        'No scenarios found under $directory in $packageRoot. '
        "Write one with scenario('…', (s) async { … }).",
      );
    }
    var entrypoint = writeHarnessEntrypoint(packageRoot, files);
    var packageConfig = requirePackageConfig(packageRoot);

    var assetsDir = p.join(_buildDir, 'scenarios_assets');
    await _ensureAssetBundle(assetsDir);

    var compiler = _compiler = await FrontendServer.start(
      executable: _cache.dartAotRuntime,
      snapshot: _cache.frontendServerSnapshot,
      entrypoint: entrypoint,
      outputDill: p.join(_buildDir, 'scenarios.dill'),
      packageConfig: packageConfig,
      sdkRoot: _cache.flutterPatchedSdkDir,
      platformDill: _cache.platformDill,
      // Source locations in the per-step tree dumps come from the widget
      // inspector, which reads them only when creation tracking is compiled
      // in.
      extraArguments: ['--track-widget-creation'],
    );
    var compiled = await compiler.compile();
    if (compiled.errorCount > 0) {
      throw StateError(
        'The scenario harness does not compile:\n'
        '${compiled.output.join('\n')}',
      );
    }
    compiler.accept();

    var guest = _guest = await Process.start(
      _cache.flutterTester,
      [
        '--vm-service-port=0',
        '--disable-service-auth-codes',
        '--icu-data-file-path=${_cache.testerIcuData}',
        '--enable-checked-mode',
        '--verify-entry-points',
        '--enable-software-rendering',
        '--skia-deterministic-rendering',
        '--enable-dart-profiling',
        '--non-interactive',
        // The engine exits with `main` otherwise — S4's discovered flag.
        '--run-forever',
        '--packages=$packageConfig',
        '--flutter-assets-dir=$assetsDir',
        p.join(_buildDir, 'scenarios.dill'),
      ],
      environment: {'FLUTTER_TEST': 'true'},
    );

    guest.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog?.call('[tester] $line'));

    var vmServiceUri = Completer<String>();
    var ready = Completer<void>();
    guest.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        onLog?.call('[tester] $line');
        var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
        if (match != null && !vmServiceUri.isCompleted) {
          vmServiceUri.complete(match.group(1));
        }
        if (line.contains('scenarios harness ready') && !ready.isCompleted) {
          ready.complete();
        }
      },
    );
    unawaited(
      guest.exitCode.then((code) {
        if (!ready.isCompleted) {
          ready.completeError(
            StateError('flutter_tester exited with $code before ready'),
          );
        }
      }),
    );

    await ready.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () =>
          throw TimeoutException('the scenario harness never became ready'),
    );
    _vm = await GuestVmService.connect(await vmServiceUri.future);
  }

  /// The real `flutter build bundle`, cached against the pubspec.
  ///
  /// Not [AssetBundleBuilder], deliberately: its fast bundle carries fonts and
  /// images but not the **compiled Material shader** (`ink_sparkle.frag`), and
  /// the first tap of a Material 3 button loads that shader — so a scenario
  /// died on its first tap. Teaching the fast builder about shaders is the
  /// follow-up that swaps this back; seconds-once-then-cached is the honest
  /// price today.
  Future<void> _ensureAssetBundle(String assetsDir) async {
    var stampFile = File(p.join(assetsDir, '.pubspec.stamp'));
    var pubspec = File(p.join(packageRoot, 'pubspec.yaml'));
    var stamp = '${pubspec.statSync().modified.microsecondsSinceEpoch}';
    if (File(p.join(assetsDir, 'FontManifest.json')).existsSync() &&
        stampFile.existsSync() &&
        stampFile.readAsStringSync() == stamp) {
      return;
    }
    onLog?.call('[scenarios] building the asset bundle');
    var result = await Process.run(p.join(flutterSdkRoot, 'bin', 'flutter'), [
      'build',
      'bundle',
      '--asset-dir',
      assetsDir,
    ], workingDirectory: packageRoot);
    if (result.exitCode != 0) {
      throw StateError('flutter build bundle failed:\n${result.stderr}');
    }
    stampFile.writeAsStringSync(stamp);
  }

  Future<List<ScenarioListing>> list() async {
    await start();
    var response = await _vm!.requireExtension(
      'ext.flutterware.scenarios.list',
    );
    return [
      for (var entry
          in (response!['scenarios']! as List).cast<Map<String, dynamic>>())
        ScenarioListing(
          file: entry['file']! as String,
          name: entry['name']! as String,
        ),
    ];
  }

  /// Runs scenarios — all of them, one file's, or one — writing each step's
  /// PNG and tree under [outDir] and returning the harness's report verbatim.
  Future<Map<String, Object?>> run({
    required String outDir,
    String? file,
    String? scenario,
  }) async {
    await start();
    Directory(outDir).createSync(recursive: true);
    var response = await _vm!.requireExtension(
      'ext.flutterware.scenarios.run',
      args: {'out': outDir, 'file': ?file, 'scenario': ?scenario},
    );
    if (response!['error'] case String error) {
      throw StateError('the harness failed:\n$error\n${response['stack']}');
    }
    return response.cast<String, Object?>();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _vm?.close();
    _guest?.kill();
    if (_guest != null) await _guest!.exitCode;
    if (_compiler != null) await _compiler!.shutdown();
  }
}

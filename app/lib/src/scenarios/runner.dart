import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../catalog/package_config_locator.dart';
import '../embedder/flutter_cache.dart';
import '../embedder/frontend_server.dart';
import '../embedder/guest_vm_service.dart';
import '../embedder/source_invalidator.dart';
import 'axes.dart';
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
///
/// A warm runner stays honest: [run] re-syncs with the sources on disk before
/// every warm run, so the Run button never replays code that has since been
/// edited. See [refresh] for the two lanes that takes.
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

  /// Called for every step the harness announces **mid-run** — the streaming
  /// half of a run, `{file, scenario, step}` with the artifacts already on
  /// disk. The blocking [run] response remains the complete report; this is
  /// how a panel fills the flow in while the scenario executes.
  ///
  /// Mutable rather than constructor-fixed so the owner can attach after the
  /// runner exists.
  void Function(Map<String, Object?> event)? onStep;

  late final FlutterCache _cache = FlutterCache(
    p.join(flutterSdkRoot, 'bin', 'cache'),
  );

  FrontendServer? _compiler;
  Process? _guest;
  GuestVmService? _vm;
  StreamSubscription<Map<String, Object?>>? _stepEvents;
  Future<void>? _starting;
  var _disposed = false;

  /// The scenario files the running harness was generated from, sorted.
  var _files = const <String>[];

  /// Sources edited since the last accepted compile. Kept across a failed
  /// compile — the invalidator's baseline has already consumed their mtimes,
  /// so forgetting them here would make the next refresh see nothing to do.
  final _dirty = <Uri>{};

  SourceInvalidator? _invalidator;
  String? _packageConfig;
  String? _assetsDir;

  /// One conversation with the harness at a time: the declarer and the test
  /// binding are not reentrant, so overlapping run/refresh calls would
  /// interleave inside the guest.
  Future<void> _turn = Future.value();

  Future<T> _exclusive<T>(Future<T> Function() action) {
    var mine = _turn.then((_) => action());
    _turn = mine.then<void>((_) {}).catchError((Object _) {});
    return mine;
  }

  String get _buildDir => p.join(packageRoot, 'build', 'flutterware');

  /// Builds everything and leaves a warm guest behind: scan → generated
  /// entrypoint → asset bundle → compile → spawn → connect. Idempotent, and
  /// concurrent callers share the one startup.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    _files = _scanFiles();
    var entrypoint = writeHarnessEntrypoint(packageRoot, _files);
    var packageConfig = _packageConfig = requirePackageConfig(packageRoot);

    var assetsDir = _assetsDir = p.join(_buildDir, 'scenarios_assets');
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
    // The baseline every later sweep is read against — taken now, so an edit
    // during the guest's startup still counts as an edit.
    _invalidator = SourceInvalidator(ignoredRoots: [flutterSdkRoot])
      ..sweep(compiler.sources);

    await _spawnGuest(
      compiled.dillOutput ?? p.join(_buildDir, 'scenarios.dill'),
    );
  }

  List<String> _scanFiles() {
    var scan = ScenarioScanner(
      packageRoot: packageRoot,
      directory: directory,
    ).scan();
    var files = {for (var ref in scan.scenarios) ref.file}.toList()..sort();
    if (files.isEmpty) {
      throw StateError(
        'No scenarios found under $directory in $packageRoot. '
        "Write one with scenario('…', (s) async { … }).",
      );
    }
    return files;
  }

  Future<void> _spawnGuest(String dill) async {
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
        '--packages=$_packageConfig',
        '--flutter-assets-dir=$_assetsDir',
        dill,
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
    var vm = _vm = await GuestVmService.connect(await vmServiceUri.future);
    _stepEvents = vm
        .extensionEvents('flutterware.scenarios.step')
        .listen((event) => onStep?.call(event));
  }

  /// The real `flutter build bundle`, cached against the pubspec.
  ///
  /// Not [AssetBundleBuilder], deliberately: its fast bundle carries fonts and
  /// images but not the **compiled Material shader** (`ink_sparkle.frag`), and
  /// the first tap of a Material 3 button loads that shader — so a scenario
  /// died on its first tap. Teaching the fast builder about shaders is the
  /// follow-up that swaps this back; seconds-once-then-cached is the honest
  /// price today.
  /// One string that changes when anything the bundle is built from changes:
  /// the pubspec itself plus the mtime of **every declared asset, font and
  /// shader file** — a directory entry is walked, so editing an image or
  /// dropping a new one into `assets/images/` is seen, pubspec untouched.
  ///
  /// What it still cannot see: assets living in *dependencies*
  /// (`packages/...` entries resolve outside this package and stamp as
  /// `missing`, constant either way). The full-restart action is the manual
  /// override for those.
  String _assetStamp() {
    var pubspec = File(p.join(packageRoot, 'pubspec.yaml'));
    var buffer = StringBuffer()
      ..writeln(
        'pubspec:${pubspec.statSync().modified.microsecondsSinceEpoch}',
      );

    void stamp(String relative) {
      var path = p.join(packageRoot, relative);
      if (relative.endsWith('/')) {
        var dir = Directory(path);
        if (!dir.existsSync()) {
          buffer.writeln('$relative:missing');
          return;
        }
        var files = dir.listSync(recursive: true).whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (var file in files) {
          buffer.writeln(
            '${file.path}:${file.statSync().modified.microsecondsSinceEpoch}',
          );
        }
      } else {
        var file = File(path);
        buffer.writeln(
          file.existsSync()
              ? '$relative:${file.statSync().modified.microsecondsSinceEpoch}'
              : '$relative:missing',
        );
      }
    }

    Object? flutter;
    try {
      flutter = (loadYaml(pubspec.readAsStringSync()) as Map?)?['flutter'];
    } on Object {
      // An unparseable pubspec fails the build loudly on its own; the stamp
      // only has to change when the file does, and its mtime above covers
      // that.
    }
    if (flutter is Map) {
      for (var asset in flutter['assets'] as List? ?? const []) {
        switch (asset) {
          case String path:
            stamp(path);
          case Map map when map['path'] is String:
            stamp(map['path'] as String);
        }
      }
      for (var family in flutter['fonts'] as List? ?? const []) {
        if (family is Map && family['fonts'] is List) {
          for (var font in family['fonts'] as List) {
            if (font is Map && font['asset'] is String) {
              stamp(font['asset'] as String);
            }
          }
        }
      }
      for (var shader in flutter['shaders'] as List? ?? const []) {
        if (shader is String) stamp(shader);
      }
    }
    return buffer.toString();
  }

  bool _assetBundleFresh(String assetsDir) {
    var stampFile = File(p.join(assetsDir, '.assets.stamp'));
    return File(p.join(assetsDir, 'FontManifest.json')).existsSync() &&
        stampFile.existsSync() &&
        stampFile.readAsStringSync() == _assetStamp();
  }

  Future<void> _ensureAssetBundle(String assetsDir) async {
    if (_assetBundleFresh(assetsDir)) return;
    var stamp = _assetStamp();
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
    File(p.join(assetsDir, '.assets.stamp')).writeAsStringSync(stamp);
  }

  /// Brings a warm harness up to date with the sources on disk.
  ///
  /// Body edits take the fast lane: an incremental compile of what changed,
  /// pushed with `reloadSources` — and **never `ext.flutter.reassemble`**,
  /// which awaits a frame that never comes under a test binding outside a test
  /// (the S4 rule). The next run re-declares and rebuilds from scratch anyway,
  /// which is everything reassemble would have been for.
  ///
  /// A changed *file set* restarts the guest instead: the generated
  /// entrypoint's `main` has already run, and no reload re-runs `main`, so its
  /// scenario map can never grow an import it did not start with.
  Future<void> refresh() => _exclusive(_refresh);

  Future<void> _refresh() async {
    await start();
    var files = _scanFiles();
    var filesChanged = !const ListEquality<String>().equals(files, _files);
    if (filesChanged) {
      _files = files;
      writeHarnessEntrypoint(packageRoot, files);
    }
    // A changed asset — edited, added to a declared directory, or a pubspec
    // edit — restarts too: the guest holds the bundle directory open, so the
    // rebuild happens around a fresh process, never under a live one.
    if (filesChanged || !_assetBundleFresh(_assetsDir!)) {
      await _restartGuest();
      return;
    }

    _dirty.addAll(_invalidator!.sweep(_compiler!.sources));
    if (_dirty.isEmpty) return;

    onLog?.call('[scenarios] reloading ${_dirty.length} edited source(s)');
    var compiled = await _compiler!.compile(_dirty.toList());
    if (compiled.errorCount > 0 || compiled.dillOutput == null) {
      await _compiler!.reject();
      throw StateError(
        'The scenario harness does not compile:\n'
        '${compiled.output.join('\n')}',
      );
    }
    _compiler!.accept();
    _dirty.clear();
    _invalidator!.sweep(_compiler!.sources);

    var report = await _vm!.service.reloadSources(
      _vm!.isolateId,
      rootLibUri: compiled.dillOutput,
    );
    if (report.success != true) {
      // A delta the VM cannot apply — a changed field shape, usually. The
      // restart recovers everything the reload cannot.
      onLog?.call('[scenarios] hot reload refused, restarting the harness');
      await _restartGuest();
    }
  }

  /// Kills the guest and starts a fresh one from a full kernel, reusing the
  /// warm compiler and the asset bundle.
  Future<void> _restartGuest() async {
    await _stepEvents?.cancel();
    _stepEvents = null;
    await _vm?.close();
    _vm = null;
    if (_guest case var guest?) {
      guest.kill();
      await guest.exitCode;
    }
    _guest = null;

    // With the old guest gone, the bundle can be rebuilt if the pubspec
    // moved. A no-op when it is fresh.
    await _ensureAssetBundle(_assetsDir!);

    var compiler = _compiler!;
    _dirty.addAll(_invalidator!.sweep(compiler.sources));
    // A launched guest reads a file, and a delta is not a program.
    compiler.reset();
    var compiled = await compiler.compile(_dirty.toList());
    if (compiled.errorCount > 0 || compiled.dillOutput == null) {
      await compiler.reject();
      throw StateError(
        'The scenario harness does not compile:\n'
        '${compiled.output.join('\n')}',
      );
    }
    compiler.accept();
    _dirty.clear();
    _invalidator!.sweep(compiler.sources);

    await _spawnGuest(compiled.dillOutput!);
  }

  Future<List<ScenarioListing>> list() => _exclusive(() async {
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
  });

  /// Runs scenarios — all of them, one file's, or one — writing each step's
  /// PNG and tree under [outDir] and returning the harness's report verbatim.
  /// [axes] is applied for the whole request and reset after it.
  ///
  /// A warm runner refreshes first, so what runs is always what is on disk.
  Future<Map<String, Object?>> run({
    required String outDir,
    String? file,
    String? scenario,
    ScenarioAxes axes = const ScenarioAxes(),
    double? captureScale,
  }) => _exclusive(() async {
    var wasWarm = _starting != null;
    await start();
    if (wasWarm) await _refresh();
    Directory(outDir).createSync(recursive: true);
    var response = await _vm!.requireExtension(
      'ext.flutterware.scenarios.run',
      args: {
        'out': outDir,
        'file': ?file,
        'scenario': ?scenario,
        if (captureScale != null) 'captureScale': '$captureScale',
        ...axes.harnessArgs(),
      },
    );
    if (response!['error'] case String error) {
      throw StateError('the harness failed:\n$error\n${response['stack']}');
    }
    return response.cast<String, Object?>();
  });

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stepEvents?.cancel();
    await _vm?.close();
    _guest?.kill();
    if (_guest != null) await _guest!.exitCode;
    if (_compiler != null) await _compiler!.shutdown();
  }
}

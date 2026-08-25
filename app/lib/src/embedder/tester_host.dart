import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import '../previews/asset_bundle.dart';
import '../previews/package_config_locator.dart';
import 'flutter_cache.dart';
import 'frontend_server.dart';
import 'guest_vm_service.dart';
import 'source_invalidator.dart';

/// What a [TesterHost] runs: the program it generates, and how to recognise the
/// guest that comes up holding it.
///
/// Everything else about driving a `flutter_tester` — the flag list, the warm
/// compiler, the two refresh lanes, the respawn — is the same whoever is
/// asking, which is why it lives in [TesterHost] and this is all a caller has
/// to say.
abstract class TesterProgram {
  /// Names the artifacts and prefixes the log lines — `scenarios`, `previews`.
  /// The dill is `<name>.dill` and the bundle `<name>_assets`, both under the
  /// package's `build/flutterware/`.
  String get name;

  /// The line the guest prints on stdout once it can be asked questions.
  String get readyLine;

  /// An extension event stream to forward to [TesterHost.onEvent], for a
  /// program that narrates while it works. Null for one that only answers.
  String? get eventStream => null;

  /// Extra frontend-server arguments.
  ///
  /// `--track-widget-creation` by default, and both programs want it: source
  /// locations in a widget tree come from the inspector, which reads them only
  /// when creation tracking is compiled in.
  List<String> get compilerArguments => const ['--track-widget-creation'];

  /// The sources the entrypoint is generated from, sorted.
  ///
  /// A change to this list restarts the guest rather than reloading it: the
  /// generated `main` has already run, and no reload re-runs `main`, so the
  /// program can never grow an import it did not start with.
  List<String> sources();

  /// Writes the generated entrypoint for [sources] and returns its path.
  ///
  /// Must leave the file alone when its content is already right — a touched
  /// mtime makes [SourceInvalidator] recompile for nothing.
  String writeEntrypoint(List<String> sources);
}

/// A `flutter_tester` kept warm, with our own resident `frontend_server` behind
/// it — the arrangement spike S4 proved
/// (`2026-07-30-s4-flutter-tester-findings.md`): the SDK's tester binary,
/// FakeAsync inside, driven over the VM service.
///
/// Deliberately Flutter-free: `fw` links this, and the purity guardrail
/// (`entry_point_purity_test.dart`) holds it to that.
///
/// Not passing `--use-test-fonts` / `--disable-asset-fonts` — the two flags
/// `flutter test` always passes — is what makes this render real fonts, where a
/// program run under `flutter test` measures unstyled text in the test font and
/// reports overflows that never happened. Spawning the tester ourselves is the
/// only way to omit them; the program on top loads `FontManifest.json`.
///
/// A warm host stays honest: [sync] brings it up to date with what is on disk,
/// so a caller never replays code that has since been edited.
class TesterHost {
  TesterHost({
    required this.packageRoot,
    required this.flutterSdkRoot,
    required this.program,
    this.buildDirectory = defaultBuildDirectory,
    this.onLog,
  });

  /// Where every artifact of the default lane lives, relative to the package.
  static const defaultBuildDirectory = 'build/flutterware';

  final String packageRoot;
  final String flutterSdkRoot;
  final TesterProgram program;

  /// Where this host's artifacts — dill, asset bundle, log — live, relative to
  /// [packageRoot].
  ///
  /// [exclusive] serializes calls *within* one host and says nothing about a
  /// second host on the same package: two of those with one directory are two
  /// `frontend_server`s writing one dill and two generators rewriting one
  /// entrypoint under each other. Anyone who cannot rule the panel's warm
  /// runner out — the comparison renders the very worktree it lives in — takes
  /// a directory of its own. The program's generated entrypoint must sit under
  /// the same directory, which is the owner's job to arrange: this host never
  /// sees that path, only the dill the compiler makes of it.
  final String buildDirectory;

  final void Function(String line)? onLog;

  /// Called for every event on [TesterProgram.eventStream].
  ///
  /// Mutable rather than constructor-fixed so the owner can attach after the
  /// host exists.
  void Function(Map<String, Object?> event)? onEvent;

  late final FlutterCache _cache = FlutterCache(
    p.join(flutterSdkRoot, 'bin', 'cache'),
  );

  FrontendServer? _compiler;
  Process? _guest;
  GuestVmService? _vm;
  StreamSubscription<Map<String, Object?>>? _events;
  Future<void>? _starting;
  var _disposed = false;

  /// Whether the spawned guest is still running. Watched because a tester that
  /// dies mid-session is otherwise invisible: the VM service simply starts
  /// refusing calls, and every later call fails with a disposed-connection
  /// error instead of a fresh process.
  var _guestAlive = false;

  /// The sources the running program was generated from, sorted.
  var _sources = const <String>[];

  /// Sources edited since the last accepted compile. Kept across a failed
  /// compile — the invalidator's baseline has already consumed their mtimes,
  /// so forgetting them here would make the next sync see nothing to do.
  final _dirty = <Uri>{};

  SourceInvalidator? _invalidator;
  String? _packageConfig;
  String? _assetsDir;

  /// The connected guest. Only valid after [ensureGuest].
  GuestVmService get vm => _vm!;

  /// Whether a guest has already been started, read *before* [ensureGuest] by a
  /// caller deciding whether it also needs to [sync] — a cold start is already
  /// current, and a warm one is what may have gone stale.
  bool get isWarm => _starting != null;

  /// One conversation with the guest at a time: the declarer and the test
  /// binding are not reentrant, so overlapping calls would interleave inside
  /// it.
  Future<void> _turn = Future.value();

  Future<T> exclusive<T>(Future<T> Function() action) {
    var mine = _turn.then((_) => action());
    _turn = mine.then<void>((_) {}).catchError((Object _) {});
    return mine;
  }

  String get _buildDir => p.join(packageRoot, buildDirectory);

  /// Where the guest's console goes, whole. The live pipes feed a one-line
  /// narration (`onLog`), which is the right size for a spinner caption and
  /// the wrong size for a diagnosis — before this file the process's output
  /// was read once for the VM-service URI and discarded. What lands here is
  /// what escapes the harness's structured lanes: engine noise, a crash on
  /// the way up, a print from outside any test zone.
  String get logPath => p.join(_buildDir, '${program.name}.log');

  RandomAccessFile? _logFile;

  /// Builds everything and leaves a warm guest behind: sources → generated
  /// entrypoint → asset bundle → compile → spawn → connect. Idempotent, and
  /// concurrent callers share the one startup.
  ///
  /// A **failed** start is forgotten rather than remembered: what it choked on
  /// — a compile error, an empty directory — is exactly what the user goes and
  /// fixes, so memoizing the failure would make every later call replay a
  /// diagnostic that is no longer true.
  Future<void> start() => _starting ??= _startOnce();

  Future<void> _startOnce() async {
    try {
      await _start();
    } catch (_) {
      _starting = null;
      // Whatever the attempt did spawn before it threw goes with it, or the
      // retry would leave a compiler (and possibly a tester) behind.
      await _teardown();
      rethrow;
    }
  }

  /// A live guest, whatever it takes: the one-time cold start, plus a respawn
  /// when the guest is gone. It can be gone two ways — a [restartGuest] that
  /// failed after its teardown but before its compile succeeded, or a process
  /// that died on its own after startup — and both used to leave every later
  /// call dereferencing a dead service until somebody found the restart action.
  ///
  /// Call inside [exclusive].
  Future<void> ensureGuest() async {
    await start();
    if (_vm == null || !_guestAlive) await restartGuest();
  }

  Future<void> _start() async {
    _sources = program.sources();
    var entrypoint = program.writeEntrypoint(_sources);
    var packageConfig = _packageConfig = requirePackageConfig(packageRoot);

    _assetsDir = p.join(_buildDir, '${program.name}_assets');
    await _syncAssetBundle();

    var compiler = _compiler = await FrontendServer.start(
      executable: _cache.dartAotRuntime,
      snapshot: _cache.frontendServerSnapshot,
      entrypoint: entrypoint,
      outputDill: p.join(_buildDir, '${program.name}.dill'),
      packageConfig: packageConfig,
      sdkRoot: _cache.flutterPatchedSdkDir,
      platformDill: _cache.platformDill,
      // What [CompileBlame] resolves a diagnostic against, so it is what the
      // compiler has to be speaking relative to. Stated rather than inherited:
      // this host runs both inside the GUI, whose directory is the worktree,
      // and under a `dart run` from the package, and blame silently attributed
      // nothing in the first case — one unbuildable demo failed the catalog.
      workingDirectory: packageRoot,
      extraArguments: program.compilerArguments,
    );
    // The cold start's long pole, and now its only slow step — narrated
    // because the panel shows the last line the host said, and a silent one
    // reads as a hung one.
    onLog?.call('[${program.name}] compiling the harness');
    var compiled = await compiler.compile();
    if (compiled.errorCount > 0) {
      throw TesterCompileException(program.name, compiled.output);
    }
    compiler.accept();
    // The baseline every later sweep is read against — taken now, so an edit
    // during the guest's startup still counts as an edit.
    _invalidator = SourceInvalidator(ignoredRoots: [flutterSdkRoot])
      ..sweep(compiler.sources);

    await _spawnGuest(
      compiled.dillOutput ?? p.join(_buildDir, '${program.name}.dill'),
    );
  }

  Future<void> _spawnGuest(String dill) async {
    _guestAlive = true;
    _logFile?.closeSync();
    // Truncated per process, so the file is the current guest's life — and
    // written synchronously line by line, because the lines that matter most
    // arrive right before a run report is read and a buffered sink would
    // still be holding them.
    var log = File(logPath)..parent.createSync(recursive: true);
    var logSink = _logFile = log.openSync(mode: FileMode.write);
    void tee(String line) {
      try {
        logSink.writeStringSync('$line\n');
      } on FileSystemException {
        // The guest outlived its log: teardown closed the file first.
      }
    }

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
      // Deliberately *not* `UNIT_TEST_ASSETS`, which is how `flutter test`
      // makes an asset read complete under FakeAsync — it installs a handler
      // that answers `flutter/assets` from Dart. Measured on a real suite:
      // that deadlocks any `tester.runAsync` that itself loads an asset, and
      // is why `flutter test` hangs on a scenario that generates a PDF. The
      // program gives the boot a real-async turn instead.
      environment: {'FLUTTER_TEST': 'true'},
      // `flutter test` runs the tester from the package root, so a fixture
      // read at a relative path resolves there. Inherited, this would be
      // wherever `fw` happened to be started from.
      workingDirectory: packageRoot,
    );

    guest.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        tee(line);
        onLog?.call('[tester] $line');
      },
    );

    var vmServiceUri = Completer<String>();
    var ready = Completer<void>();
    guest.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        tee(line);
        onLog?.call('[tester] $line');
        var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
        if (match != null && !vmServiceUri.isCompleted) {
          vmServiceUri.complete(match.group(1));
        }
        if (line.contains(program.readyLine) && !ready.isCompleted) {
          ready.complete();
        }
      },
    );
    unawaited(
      guest.exitCode.then((code) {
        // Identity-checked: a later guest's life is not this listener's to
        // end.
        if (identical(_guest, guest)) _guestAlive = false;
        if (!ready.isCompleted) {
          ready.completeError(
            StateError('flutter_tester exited with $code before ready'),
          );
        } else {
          onLog?.call('[${program.name}] the harness exited ($code)');
        }
      }),
    );

    await ready.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw TimeoutException(
        'the ${program.name} harness never became ready',
      ),
    );
    var vm = _vm = await GuestVmService.connect(await vmServiceUri.future);
    if (program.eventStream case var stream?) {
      _events = vm
          .extensionEvents(stream)
          .listen((event) => onEvent?.call(event));
    }
  }

  /// The asset directory the guest reads, assembled by [AssetBundleBuilder] —
  /// manifests written, payloads symlinked, framework shaders compiled once per
  /// engine revision.
  ///
  /// Not `flutter build bundle`, which this used to shell out to. That command
  /// builds a *program*, so it insists on an entrypoint — and a package whose
  /// tests are its only entry (a library, a package whose app lives elsewhere)
  /// has no `lib/main.dart` to give it, which is where scenarios stopped with
  /// `Target file "lib/main.dart" not found`. The bundle wanted nothing from
  /// that kernel: the harness's own dill is what the tester is handed.
  ///
  /// Returns whether the directory changed, which is what decides a restart:
  /// the builder rebuilds in place under a live guest by design, but a guest
  /// registers `FontManifest.json` when it starts, so a changed bundle reaches
  /// one only through a fresh process.
  Future<bool> _syncAssetBundle() async {
    var sync = await AssetBundleBuilder(
      cache: _cache,
      rootPackageRoot: packageRoot,
      packageConfigPath: _packageConfig!,
    ).build(_assetsDir!);
    if (sync.changed) onLog?.call('[${program.name}] the asset bundle changed');
    return sync.changed;
  }

  /// Brings a warm guest up to date with the sources on disk, taking the turn.
  Future<void> refresh() => exclusive(sync);

  /// [refresh] for a caller that already holds the turn.
  ///
  /// Body edits take the fast lane: an incremental compile of what changed,
  /// pushed with `reloadSources` — and **never `ext.flutter.reassemble`**,
  /// which awaits a frame that never comes under a test binding outside a test
  /// (the S4 rule). The next call re-declares and rebuilds from scratch anyway,
  /// which is everything reassemble would have been for.
  ///
  /// A changed *source set* restarts the guest instead: the generated
  /// entrypoint's `main` has already run, and no reload re-runs `main`, so its
  /// table can never grow an import it did not start with.
  Future<void> sync() async {
    await start();
    var sources = program.sources();
    var sourcesChanged = !const ListEquality<String>().equals(
      sources,
      _sources,
    );
    if (sourcesChanged) {
      _sources = sources;
      program.writeEntrypoint(sources);
    }
    // A changed asset — edited, added to a declared directory, or a pubspec
    // edit — restarts too: what the running engine registered at startup is
    // what it keeps. So does a guest that is simply gone (see [ensureGuest]) —
    // the reload lane below would talk to a dead service.
    var guestGone = _vm == null || !_guestAlive;
    var assetsChanged = await _syncAssetBundle();
    if (sourcesChanged || guestGone || assetsChanged) {
      await restartGuest();
      return;
    }

    _dirty.addAll(_invalidator!.sweep(_compiler!.sources));
    if (_dirty.isEmpty) return;

    onLog?.call(
      '[${program.name}] reloading ${_dirty.length} edited source(s)',
    );
    var compiled = await _compiler!.compile(_dirty.toList());
    if (compiled.errorCount > 0 || compiled.dillOutput == null) {
      await _compiler!.reject();
      throw TesterCompileException(program.name, compiled.output);
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
      onLog?.call(
        '[${program.name}] hot reload refused, restarting the harness',
      );
      await restartGuest();
    }
  }

  /// Kills the guest and starts a fresh one from a full kernel, reusing the
  /// warm compiler and the asset bundle. Call inside [exclusive].
  Future<void> restartGuest() async {
    // From what is on disk *now*: a restart is the lane that rebuilds the
    // program, and it is reachable without a preceding sync (a dead guest, the
    // restart action), so compiling the previous source set would fail on a
    // file deleted since — or silently omit one added.
    _sources = program.sources();
    program.writeEntrypoint(_sources);

    await _events?.cancel();
    _events = null;
    await _vm?.close();
    _vm = null;
    if (_guest case var guest?) {
      guest.kill();
      await guest.exitCode;
    }
    _guest = null;

    // The fresh guest reads what is on disk now. ~15ms when nothing moved,
    // which is why every path here re-syncs rather than tracking whether the
    // caller already did.
    await _syncAssetBundle();

    var compiler = _compiler!;
    _dirty.addAll(_invalidator!.sweep(compiler.sources));
    // A launched guest reads a file, and a delta is not a program.
    compiler.reset();
    var compiled = await compiler.compile(_dirty.toList());
    if (compiled.errorCount > 0 || compiled.dillOutput == null) {
      await compiler.reject();
      throw TesterCompileException(program.name, compiled.output);
    }
    compiler.accept();
    _dirty.clear();
    _invalidator!.sweep(compiler.sources);

    await _spawnGuest(compiled.dillOutput!);
  }

  /// Kills the guest without replacing it, leaving the compiler warm.
  ///
  /// Exists for the recovery test — an owner exposes it as its own
  /// `@visibleForTesting` seam — so that a test can assert the next call
  /// notices and respawns rather than talking to a dead service. Awaits the
  /// exit, so what follows is testing the recovery rather than racing the kill.
  Future<void> killGuest() async {
    if (_guest case var guest?) {
      guest.kill();
      await guest.exitCode;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _teardown();
  }

  /// Everything this host spawned, gone. Shared with the failed-start path,
  /// which has the same job and no business marking the host disposed.
  Future<void> _teardown() async {
    await _events?.cancel();
    _events = null;
    await _vm?.close();
    _vm = null;
    if (_guest case var guest?) {
      guest.kill();
      await guest.exitCode;
    }
    _guest = null;
    _guestAlive = false;
    _logFile?.closeSync();
    _logFile = null;
    if (_compiler case var compiler?) await compiler.shutdown();
    _compiler = null;
  }
}

/// The generated program did not compile, with the compiler's own diagnostics.
///
/// Carries [output] rather than only a message because a caller may be able to
/// do something with it: `CompileBlame` reads these lines to work out which
/// entries to drop and serve the rest, where a plain string could only be
/// reported.
class TesterCompileException implements Exception {
  TesterCompileException(this.program, this.output);

  final String program;
  final List<String> output;

  @override
  String toString() =>
      'The $program harness does not compile:\n${output.join('\n')}';
}

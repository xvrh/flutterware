import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../embedder/embedded_engine.dart';
import '../embedder/guest_vm_service.dart';
import 'catalog_entry.dart';
import 'compiler_daemon_client.dart';
import 'protocol.dart';
import 'session_lock.dart';

enum CatalogSessionPhase { starting, ready, error }

/// How the last switch went, for the UI to show.
class SwitchReport {
  SwitchReport({
    required this.entry,
    required this.compile,
    required this.reload,
    required this.newSourceCount,
    this.error,
  });

  final CatalogEntry entry;
  final Duration compile;
  final Duration reload;
  final int newSourceCount;

  /// Compiler diagnostics when the entry did not build. The guest keeps
  /// rendering whatever it had.
  final String? error;

  bool get ok => error == null;
}

/// Owns the warm catalog loop from the GUI's side: the compiler daemon, one
/// embedder guest, and the VM-service connection that pushes entries into it.
///
/// Switching an entry is a hot reload, not a restart — the engine, the isolate
/// and the compiler all stay warm.
///
/// **Nothing here compiles in-process.** All building and compiling happens in
/// the daemon, a separate plain-Dart process; see [CompilerDaemonClient] for
/// why that is not a style preference.
class CatalogSession extends ChangeNotifier {
  CatalogSession({
    required this.appPackageRoot,
    required this.flutterSdkRoot,
    required this.projectRoot,
    this.roots = const ['demo'],
  });

  /// Everything discovery found, populated when the daemon reports ready.
  List<CatalogEntry> entries = const [];

  /// Warnings the scan produced; the daemon refuses to start on errors.
  List<String> diagnostics = const [];

  /// The `flutterware_app` package root, which owns `native/` and the build dir.
  final String appPackageRoot;
  final String flutterSdkRoot;

  /// Root the entries' paths are relative to.
  final String projectRoot;

  /// Directories to scan, relative to [projectRoot].
  final List<String> roots;

  CatalogSessionPhase phase = CatalogSessionPhase.starting;
  String? errorMessage;

  /// What the guest is currently rendering.
  CatalogEntry? active;
  SwitchReport? lastSwitch;
  Duration? coldCompile;

  EmbeddedEngine? get engine => _engine;
  EmbeddedEngine? _engine;

  CompilerDaemonClient? _daemon;
  GuestVmService? _vmService;
  SessionLock? _lock;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// Brings up the daemon, the guest and the reload channel.
  Future<void> start({int width = 900, int height = 700}) async {
    try {
      _lock = SessionLock.acquire(p.join(appPackageRoot, 'build', 'catalog'));

      var (daemon, ready) = await CompilerDaemonClient.start(
        dartExecutable: p.join(flutterSdkRoot, 'bin', 'dart'),
        config: DaemonConfig(
          appPackageRoot: appPackageRoot,
          projectRoot: projectRoot,
          packageConfig: p.join(
            p.dirname(appPackageRoot),
            '.dart_tool',
            'package_config.json',
          ),
          roots: roots,
        ),
        onLog: (line) => debugPrint('[catalog] $line'),
      );
      _daemon = daemon;
      coldCompile = ready.coldCompile;
      entries = ready.entries;
      diagnostics = ready.diagnostics;
      if (_disposed) return;

      var engine = _engine = EmbeddedEngine(
        appPackageRoot: appPackageRoot,
        flutterSdkRoot: flutterSdkRoot,
        buildGuest: () async => (
          hostPath: ready.hostPath,
          assetsDir: ready.assetsDir,
          icuData: ready.icuData,
        ),
      );
      engine.addListener(_onEngineChanged);
      await engine.start(width: width, height: height);
      if (_disposed) return;

      _vmService = await GuestVmService.connect(await engine.vmServiceUri);
      if (_disposed) return;

      active = entries.first;
      phase = CatalogSessionPhase.ready;
      notifyListeners();
    } catch (e) {
      _fail('$e');
    }
  }

  /// Switches the guest to [entry] by hot reload.
  ///
  /// Switches are serialised: the daemon and the isolate each tolerate one
  /// in-flight operation, and a click-happy user must not interleave them.
  Future<void> switchTo(CatalogEntry entry) {
    _queue = _queue.then((_) => _switchTo(entry)).catchError((Object e) {
      _fail('$e');
    });
    return _queue;
  }

  Future<void> _switchTo(CatalogEntry entry) async {
    var daemon = _daemon;
    var vmService = _vmService;
    if (_disposed ||
        phase != CatalogSessionPhase.ready ||
        daemon == null ||
        vmService == null) {
      return;
    }

    var compiled = await daemon.select(entry.id);
    if (!compiled.ok) {
      // The guest keeps rendering the previous entry; a broken demo is a
      // reportable event, not the end of the session.
      lastSwitch = SwitchReport(
        entry: entry,
        compile: compiled.compile,
        reload: Duration.zero,
        newSourceCount: compiled.newSourceCount,
        error: compiled.error,
      );
      notifyListeners();
      return;
    }

    var watch = Stopwatch()..start();
    await vmService.reload(compiled.dill!);
    watch.stop();

    active = entry;
    lastSwitch = SwitchReport(
      entry: entry,
      compile: compiled.compile,
      reload: watch.elapsed,
      newSourceCount: compiled.newSourceCount,
    );
    notifyListeners();
  }

  void _onEngineChanged() {
    if (_engine?.phase == EmbeddedEnginePhase.error) {
      _fail(_engine!.errorMessage ?? 'the embedder guest failed');
    } else {
      notifyListeners();
    }
  }

  void _fail(String message) {
    if (_disposed) return;
    // Also to stdout: a failure that only lands in the UI is invisible to
    // whoever is driving the harness through `flutter run`.
    debugPrint('[catalog] failed: $message');
    errorMessage = message;
    phase = CatalogSessionPhase.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    unawaited(_vmService?.close());
    unawaited(_daemon?.shutdown());
    _lock?.release();
    super.dispose();
  }
}

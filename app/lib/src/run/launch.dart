import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../utils/daemon/events.dart';
import '../utils/daemon/protocol.dart';
import '../utils/flutter_sdk.dart';
import '../utils/run_dir.dart';
import 'handle.dart';

final _logger = Logger('run_launch');

/// Starts `flutter run --machine` as a process nobody is waiting on, and
/// announces it in the run dir.
///
/// **Detached, with its output going to a file.** Detached because the thing
/// that launched an app must not be the thing that keeps it alive: a `fw
/// launch` returns, a GUI window closes, and the phone keeps running the app.
/// To a file because the `--machine` stream carries the build progress and the
/// VM-service URI, and a client that arrives *after* the interesting part
/// scrolled past still has to be able to read them — which is also what makes
/// the handle self-healing (see [refreshFromLog]).
///
/// The child owns the port forward, so on hardware it is a process nobody
/// waits on and everybody depends on. Its death is detected rather than
/// prevented: see [RunProbe].
Future<RunHandle> launchApp({
  required FlutterSdkPath sdk,
  required String runDir,
  required String worktree,
  required String worktreeName,
  required String packageRoot,
  required String device,
  required String entrypoint,
  String? package,
  String? entrypointName,
  String? deviceName,
  Map<String, String> knobs = const {},
}) async {
  if (Platform.isWindows) {
    // `ProcessStartMode.detached` gives no stdio to redirect, and the POSIX
    // trick below needs a shell that is not there. Said plainly rather than
    // failing somewhere less legible.
    throw UnsupportedError(
      'Launching is implemented for macOS and Linux hosts. The child has to '
      'outlive this process with its output going to a file, and that is done '
      'with a shell redirect this platform has no equivalent of yet.',
    );
  }

  var logPath = p.join(
    runDir,
    '${runHandleKey(worktree, device, entrypoint)}.log',
  );
  // **Emptied here, not by the shell's `>` below.** The key is stable across
  // relaunch by design, so a second run of the same entry point on the same
  // device writes to the same file — and the redirect only truncates it once
  // the child is actually running. Between `Process.start` returning and that
  // moment, the *previous* run's log is still on disk, complete with its
  // `app.debugPort` and `app.started`. [awaitLaunch] starts polling
  // immediately, reads them, and reports the new app as up at the old app's VM
  // service address, which is dead. Measured: a relaunch inherited a URI from a
  // run two hours older.
  try {
    File(logPath).writeAsStringSync('');
  } on FileSystemException catch (e) {
    // Not fatal on its own — the shell redirect will still create it — so this
    // must not stop a launch. It only means the window above is open again.
    _logger.warning('Could not clear $logPath before launching: $e');
  }
  var command = [
    sdk.flutter,
    'run',
    '--machine',
    '--device-id',
    device,
    '--target',
    entrypoint,
    for (var knob in knobs.entries) ...[
      '--dart-define',
      '${knob.key}=${knob.value}',
    ],
  ];

  // `exec "$@"` replaces the shell with flutter, so the pid this returns *is*
  // the launcher's — which matters, because the handle's `launcherPid` is what
  // every other process checks to decide whether reload is still on offer.
  // The log path travels in the environment rather than in the script, so no
  // amount of punctuation in a path can turn into shell syntax.
  var process = await Process.start(
    '/bin/sh',
    ['-c', r'exec "$@" > "$FW_RUN_LOG" 2>&1 < /dev/null', 'sh', ...command],
    workingDirectory: packageRoot,
    environment: {'FW_RUN_LOG': logPath},
    mode: ProcessStartMode.detached,
  );

  var handle = RunHandle(
    worktree: worktree,
    worktreeName: worktreeName,
    device: device,
    deviceName: deviceName,
    entrypoint: entrypoint,
    entrypointName: entrypointName,
    package: package,
    launcherPid: process.pid,
    knobs: knobs,
    logPath: logPath,
    startedAt: DateTime.now(),
  );
  // Published before there is anything to connect to, deliberately: a cold
  // Android build takes a minute and a half, and for all of it the device is
  // taken. A ledger that only listed apps that had finished starting would
  // report a busy phone as free for exactly as long as it takes two people to
  // collide on it.
  return handle.publish(runDir);
}

/// What a launcher's log says so far.
///
/// The log is the source of truth about a run and the handle is a cache of it,
/// which is what lets any process — the GUI that started it, a `fw` in another
/// terminal, an agent — bring a handle up to date without having been present
/// when the app started.
class LaunchLog {
  const LaunchLog({
    this.appId,
    this.vmService,
    this.progress,
    this.error,
    this.output,
    this.started = false,
    this.stopped = false,
  });

  final String? appId;

  /// The app's VM service as a `ws://` URI, once `app.debugPort` has arrived.
  final String? vmService;

  /// The most recent thing the tool said it was doing — `Installing and
  /// launching…`. The only narration a ninety-second cold build has.
  final String? progress;

  /// The most recent error the launcher *reported* — a `daemon.logMessage` at
  /// error level, an errored `app.log`, or the exception `app.stop` carried.
  ///
  /// Structured only, and that distinction is load-bearing: this is what
  /// [awaitLaunch] treats as terminal, and a plain line is not one. `flutter
  /// run` opens with `No devices found yet. Checking for wireless devices…`,
  /// which is a sentence about waiting and would end the wait if it counted.
  final String? error;

  /// The last plain line the launcher printed — everything in machine mode
  /// that is not an event.
  ///
  /// Context rather than a verdict. It is where the ugly failures land, so it
  /// is what explains a launcher that died without saying anything structured;
  /// while one is still alive it means nothing at all.
  final String? output;

  /// `app.started` has arrived: the build is done and the app is up.
  final bool started;

  /// The launcher reported the app stopping.
  final bool stopped;

  /// Reads [path], tolerating everything.
  ///
  /// A log that does not exist yet, is half-written, or has a line from a
  /// tool version this build does not know is not an error — it is a log that
  /// says less than it will in a second.
  static LaunchLog read(String path) {
    List<String> lines;
    try {
      lines = File(path).readAsLinesSync();
    } on FileSystemException {
      return const LaunchLog();
    }
    String? appId, vmService, progress, error, plain;
    var started = false;
    var stopped = false;
    for (var line in lines) {
      var object = DaemonProtocol.tryReadLine(line);
      if (object == null) {
        // Not an event. Kept as context, never as a verdict — see [output].
        if (line.trim().isNotEmpty) plain = line.trim();
        continue;
      }
      switch (DaemonProtocol.tryReadEvent(object)) {
        case AppStartEvent(appId: var id):
          appId = id;
        case AppDebugPortEvent(:var wsUri, appId: var id):
          vmService = wsUri.toString();
          // Also from here, not only from `app.start`. The two carry the same
          // id, and this one has fewer required fields — so a tool that adds
          // or renames something on `app.start` costs the id nothing.
          appId ??= id;
        case AppStartedEvent():
          started = true;
        case AppStopEvent(error: var why):
          stopped = true;
          if (why != null) error = why;
        case AppProgressEvent(:var message, :var finished):
          if (message != null && !finished) progress = message;
        case DaemonLogMessageEvent(level: MessageLevel.error, :var message):
          error = message;
        case DaemonLogEvent(:var log, error: true):
          error = log;
        default:
          break;
      }
    }
    return LaunchLog(
      appId: appId,
      vmService: vmService,
      progress: progress,
      error: error,
      output: plain,
      started: started,
      stopped: stopped,
    );
  }

  /// Why this run is not going to work, or null.
  ///
  /// [error] when the launcher said something structured, and the last plain
  /// line only once the launcher is gone — at which point a stray sentence is
  /// a worse answer than a real error and a much better one than silence.
  String? failure({required bool launcherAlive}) =>
      error ?? (launcherAlive || started ? null : output);

  /// The launcher's own last word, for a row that has to say something.
  String get summary {
    if (error != null) return error!;
    if (stopped) return 'stopped';
    if (started) return 'running';
    if (vmService != null) return 'started';
    return progress ?? 'starting';
  }
}

/// Brings [handle] up to date from its log, rewriting the file when it learns
/// something.
///
/// Returns the handle as it now stands — the same object when the log had
/// nothing new. Any process may call this; the one that launched the app has
/// no special standing, and usually is not running any more.
RunHandle refreshFromLog(RunHandle handle) {
  var path = handle.logPath;
  if (path == null) return handle;
  // **The log wins, even when the handle already has an answer.** This used to
  // return early once both fields were set, which made a wrong value permanent:
  // a handle that started life with a stale URI could never be corrected, and
  // the app looked dead to everything that probed it. The early return also
  // saved nothing — `_probeAll` reads this same file for every handle on every
  // pass regardless, to show the progress line.
  var log = LaunchLog.read(path);
  if (log.vmService == null && log.appId == null) return handle;
  if (log.vmService == handle.vmService && log.appId == handle.appId) {
    return handle;
  }
  var updated = handle.withService(
    vmService: log.vmService ?? handle.vmService,
    appId: log.appId ?? handle.appId,
  );
  updated.save();
  _logger.fine('Handle ${handle.handlePath} learned ${log.vmService}');
  return updated;
}

/// Waits for [handle]'s app to come up, or for the launcher to die trying.
///
/// Polls the log rather than holding a pipe, for the same reason the log
/// exists at all: whoever asks this question is not necessarily the process
/// that started the app, and on a second `fw` it certainly is not.
Future<(RunHandle, LaunchLog)> awaitLaunch(
  RunHandle handle,
  Duration timeout, {
  Duration poll = const Duration(milliseconds: 250),
}) async {
  var deadline = DateTime.now().add(timeout);
  var current = handle;
  while (true) {
    current = refreshFromLog(current);
    var log = LaunchLog.read(current.logPath ?? '');
    if (log.started || log.stopped || log.error != null) return (current, log);
    if (!isProcessAlive(current.launcherPid)) {
      // The launcher is gone and the log never said anything structured. That
      // is its own answer, and a more useful one than timing out on it — and
      // the log is now complete, so the plain lines in it can be trusted to be
      // the whole story rather than the first sentence of one.
      await Future<void>.delayed(poll);
      return (current, LaunchLog.read(current.logPath ?? ''));
    }
    if (DateTime.now().isAfter(deadline)) return (current, log);
    await Future<void>.delayed(poll);
  }
}

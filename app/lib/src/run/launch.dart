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

/// Enough for an Xcode signing failure with its four remediation steps, which
/// is the longest real one measured. Past that it is a build log, not a reason.
const _maxFailureLines = 40;

/// Lines that name a fault rather than narrate one. Used only to pick a
/// headline out of a block that is reported in full either way, so a miss
/// costs a worse first line and never a lost reason.
final _saysError = RegExp(
  r'^\s*(error|exception|failed|failure|could not|unable to|no such)\b',
  caseSensitive: false,
);

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
  String? flavor,
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
    '${runHandleKey(worktree, device, entrypoint, flavor)}.log',
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
    // Before the defines, because a flavor decides which variant is built and
    // the defines only decide what goes into it.
    if (flavor != null) ...['--flavor', flavor],
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
    flavor: flavor,
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
    this.trailing = const [],
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

  /// Every plain line since the last structured event, in order.
  ///
  /// **A build failure's last line is its least useful one.** Measured, an iOS
  /// signing failure ends `App failed to start` — and the reason, `No Account
  /// for Team "B7V224LKE4"`, is twenty lines above it, along with the four
  /// steps that fix it. [output] alone reported the summary and threw the cause
  /// away.
  ///
  /// Delimited by the last structured event rather than by matching words in
  /// the text, because `flutter run --machine` emits **nothing structured at
  /// all** for a build failure — no `daemon.logMessage`, no error on
  /// `app.stop`, measured on the log this was written for. The tool's last
  /// event is its final `app.progress`, so everything plain after it is the
  /// failure and nothing else is.
  final List<String> trailing;

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
    var trailing = <String>[];
    for (var line in lines) {
      Map<String, dynamic>? object;
      try {
        object = DaemonProtocol.tryReadLine(line);
      } on FormatException {
        // A line the launcher is still writing can be `[{`-shaped and not yet
        // valid JSON. This method is read repeatedly *while* another process
        // appends to the file, so that is a normal thing to see and not an
        // error — treat it as plain text and let the next read have the whole
        // line.
        object = null;
      }
      if (object == null) {
        // Not an event. Kept as context, never as a verdict — see [output].
        if (line.trim().isNotEmpty) {
          plain = line.trim();
          trailing.add(line.trimRight());
        }
        continue;
      }
      // A structured line closes the plain block before it: whatever the tool
      // was narrating is finished, and anything printed after this belongs to
      // what comes next. `app.stop` is the exception because it is emitted
      // *before* the tool's parting words, so honouring it would clear the
      // very block those words are being collected into.
      if (object['event'] != 'app.stop') trailing.clear();
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
      trailing: trailing,
      started: started,
      stopped: stopped,
    );
  }

  /// Why this run is not going to work, or null.
  ///
  /// [error] when the launcher said something structured, and the plain block
  /// only once the launcher is gone or the app stopped before it ever started —
  /// at which point stray sentences are a worse answer than a real error and a
  /// much better one than silence.
  String? failure({required bool launcherAlive}) {
    if (error != null) return error;
    if (started || (launcherAlive && !stopped)) return null;
    var block = _failureBlock();
    return block.isEmpty ? output : block.join('\n');
  }

  /// The one line a row has room for.
  ///
  /// The first line of the block that names something gone wrong, because the
  /// summary line the tool ends on — `App failed to start` — is true of every
  /// failure and tells you which one you have in no case at all.
  String? get failureHeadline {
    if (error != null) return error!.split('\n').first;
    var block = _failureBlock();
    for (var line in block) {
      if (_saysError.hasMatch(line)) return line.trim();
    }
    return block.isNotEmpty ? block.first.trim() : output;
  }

  /// The trailing plain lines, minus the blank ones a terminal used for
  /// spacing, capped so a runaway build log cannot become the error message.
  List<String> _failureBlock() {
    var kept = [
      for (var line in trailing)
        if (line.trim().isNotEmpty) line,
    ];
    return kept.length <= _maxFailureLines
        ? kept
        : kept.sublist(kept.length - _maxFailureLines);
  }

  /// The launcher's own last word, for a row that has to say something.
  String get summary {
    if (error != null) return error!;
    if (stopped) return 'stopped';
    if (started) return 'running';
    if (vmService != null) return 'started';
    return progress ?? 'starting';
  }
}

/// A run that ended before it ever started, kept after its handle is gone.
///
/// **The handle has to go and the reason has to stay.** A launcher that never
/// came up is not holding the device, so leaving its handle in the ledger would
/// tell the next person a phone is busy running something that is not there —
/// which is why both the sweeper and a failed `launch` delete it. But the chip
/// deleted with it was the only thing on screen, so a failed launch bounced you
/// back to the form with nothing said. This is what the panel shows instead.
///
/// Held in memory rather than written next to the log: the log *is* the durable
/// record, [logPath] points at it, and a failure worth surviving a restart is
/// one you should be reading the log for anyway.
class RunFailure {
  const RunFailure({
    required this.key,
    required this.device,
    required this.entrypoint,
    required this.at,
    this.deviceName,
    this.entrypointName,
    this.package,
    this.flavor,
    this.headline,
    this.detail,
    this.logPath,
  });

  /// [runHandleKey], so the address that pointed at the run still points at
  /// the reason it is gone.
  final String key;

  final String device;
  final String? deviceName;
  final String entrypoint;
  final String? entrypointName;
  final String? package;
  final String? flavor;

  /// One line naming the fault, for a chip or a row.
  final String? headline;

  /// The launcher's parting words in full, newline-separated.
  final String? detail;

  final String? logPath;

  final DateTime at;

  String get deviceLabel => deviceName ?? device;
  String get entrypointLabel => entrypointName ?? entrypoint;

  /// Matches [RunHandle.runLabel], so the chip does not rename itself when the
  /// run it stands for dies.
  String get runLabel =>
      flavor == null ? entrypointLabel : '$entrypointLabel ($flavor)';

  /// What to say when the log yielded nothing at all — a launcher killed with
  /// `SIGKILL` writes no parting words, and silence is still an answer.
  String get message =>
      detail ?? headline ?? 'The launcher stopped before the app started.';
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
    // Only a started app is worth returning on the spot. Every other way out
    // of here is a failure, and a failure's reason is still being written.
    if (log.started) return (current, log);
    if (log.stopped ||
        log.error != null ||
        !isProcessAlive(current.launcherPid)) {
      return (current, await _readWhenSettled(current, poll));
    }
    if (DateTime.now().isAfter(deadline)) return (current, log);
    await Future<void>.delayed(poll);
  }
}

/// Reads [handle]'s log once its launcher has stopped adding to it.
///
/// **A launcher is not finished talking when it says it stopped.** `app.stop`
/// arrives *before* the tool prints why — measured on an iOS signing failure,
/// where everything that explains it comes after that event. Returning at the
/// event caught the log mid-sentence, and worse, caught the launcher still
/// alive, which made `failure(launcherAlive: true)` answer null and turned a
/// failed launch into a bare `stopped` with no reason attached to it.
///
/// Bounded, because this is only ever tidying up an answer we already have: if
/// the launcher lingers, the log as it stands is still returned.
Future<LaunchLog> _readWhenSettled(
  RunHandle handle,
  Duration poll, {
  Duration grace = const Duration(seconds: 3),
}) async {
  var until = DateTime.now().add(grace);
  while (isProcessAlive(handle.launcherPid) && DateTime.now().isBefore(until)) {
    await Future<void>.delayed(poll);
  }
  // One more poll after it goes, for the lines already in the pipe.
  await Future<void>.delayed(poll);
  return LaunchLog.read(handle.logPath ?? '');
}

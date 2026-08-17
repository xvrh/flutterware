import 'dart:io';

import '../utils/daemon/events.dart';
import '../utils/daemon/protocol.dart';

/// Who said it.
///
/// The split matters more than it looks. A launcher log interleaves the build
/// — Xcode noise, CocoaPods advice, progress lines — with what the app itself
/// printed, and they are answers to different questions. Somebody debugging
/// their app wants [app] and nothing else; somebody debugging a launch that
/// never came up wants [tool].
enum RunLogSource {
  /// The app's own output.
  ///
  /// **Recognised by the `flutter: ` prefix, not by an event.** This was
  /// written against `app.log` first, which was wrong: `flutter run --machine`
  /// sends that event only when a stop or a restart fails. Everything the app
  /// prints goes to plain stdout with the same `flutter: ` prefix a plain
  /// `flutter run` shows, *interleaved* with the machine protocol rather than
  /// carried by it. Measured, after reading the tool's source suggested
  /// otherwise — see the tests, which pin the real shape.
  app,

  /// `flutter run` talking about itself: `daemon.logMessage`, and every other
  /// plain line — the build, Xcode, the engine's own stderr.
  tool,

  /// The platform's own log, read by us rather than forwarded by the launcher.
  ///
  /// **Not in the launcher's log file, and no amount of forwarding would put
  /// it there.** `flutter run` reads the device log through a filter that keeps
  /// only the app's *main executable* and the engine, so every line a plugin's
  /// framework logs is dropped before it reaches anything we could read.
  /// `NativeLogSource` is what reads the platform log itself.
  native,
}

/// One line of a run's log.
class RunLogLine {
  const RunLogLine(this.source, this.text, {this.error = false});

  final RunLogSource source;
  final String text;

  /// The launcher marked it as an error — an errored `app.log`, or a
  /// `daemon.logMessage` at error level.
  ///
  /// Not inferred from the text. A line containing the word "error" is
  /// extremely often a line about not having one.
  final bool error;

  Map<String, Object?> toJson() => {
    'source': source.name,
    'text': text,
    if (error) 'error': true,
  };
}

/// Everything a run's launcher wrote, decoded.
///
/// **The log is the source of truth, and it needs no VM service.** It is
/// written by the detached `flutter run` from the moment it starts, so it
/// covers the build — before any app exists to connect to — and it survives the
/// app it describes. A crashed run is exactly the case where the logs matter
/// most and the app cannot be asked anything, which is why this reads a file
/// rather than subscribing to `Stdout`.
///
/// Tolerates everything, like [LaunchLog.read]: a log half-written, absent, or
/// carrying an event from a tool version this build does not know is a log that
/// says less than it will in a second, not an error.
List<RunLogLine> readRunLog(
  String path, {
  RunLogSource? only,
  bool errorsOnly = false,
  int? tail,
}) {
  List<String> lines;
  try {
    lines = File(path).readAsLinesSync();
  } on FileSystemException {
    return const [];
  }

  var result = <RunLogLine>[];
  void add(RunLogSource source, String text, {bool error = false}) {
    if (only != null && source != only) return;
    if (errorsOnly && !error) return;
    if (text.trim().isEmpty) return;
    result.add(RunLogLine(source, text.trimRight(), error: error));
  }

  for (var line in lines) {
    var object = DaemonProtocol.tryReadLine(line);
    if (object == null) {
      if (line.startsWith(_appPrefix)) {
        add(RunLogSource.app, line.substring(_appPrefix.length));
      } else {
        add(RunLogSource.tool, line);
      }
      continue;
    }
    switch (DaemonProtocol.tryReadEvent(object)) {
      // Only ever a failed stop or restart, but it is about the app and the
      // tool has already marked it as an error.
      case DaemonLogEvent(:var log, :var error):
        add(RunLogSource.app, log, error: error);
      case DaemonLogMessageEvent(:var level, :var message, :var stackTrace):
        // `trace` and `status` are the tool narrating its own progress and are
        // already covered by `app.progress`, which the panel shows as a
        // progress line rather than as scrollback.
        if (level == MessageLevel.trace || level == MessageLevel.status) break;
        add(
          RunLogSource.tool,
          stackTrace == null ? message : '$message\n$stackTrace',
          error: level == MessageLevel.error,
        );
      case AppStopEvent(error: var why?):
        add(RunLogSource.tool, why, error: true);
      default:
        break;
    }
  }

  if (tail != null && result.length > tail) {
    return result.sublist(result.length - tail);
  }
  return result;
}

/// What `flutter run` puts in front of a line the app printed.
///
/// The tool's own convention, the same one a plain `flutter run` shows in a
/// terminal, and the only signal separating app output from build output in a
/// `--machine` log.
const _appPrefix = 'flutter: ';

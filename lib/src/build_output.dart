import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Whether anything printed is going to a person watching it happen.
///
/// One gate for every decoration in the CLI. The alternative is each call site
/// deciding for itself, and the one that decides wrong is the one that writes
/// escape sequences into a CI log.
bool get outputIsInteractive => isInteractiveOutput(
  hasTerminal: stdout.hasTerminal,
  supportsAnsi: stdout.supportsAnsiEscapes,
  environment: Platform.environment,
);

/// The decision itself, with its inputs passed in so a test can state them.
///
/// `CI` and `NO_COLOR` are honoured even on a real terminal. Both are set by
/// someone who means it, and a terminal is precisely where they would otherwise
/// be ignored — a CI runner that allocates a tty is the case this exists for.
bool isInteractiveOutput({
  required bool hasTerminal,
  required bool supportsAnsi,
  required Map<String, String> environment,
}) {
  if (!hasTerminal || !supportsAnsi) return false;
  if (environment['TERM'] == 'dumb') return false;
  if (environment.containsKey('NO_COLOR')) return false;
  if (environment.containsKey('CI')) return false;
  return true;
}

/// Whether progress narration has to keep off stdout.
///
/// Two ways to lose stdout and they are the same answer. A command that speaks
/// a protocol on it — `mcp` — loses the connection to a progress panel. A
/// command whose stdout is not a person loses something quieter and worse: an
/// action prints its result as JSON whether or not `--json` was typed, so a
/// cold run put `build the CLI… (~10s)` on the line above the object something
/// was about to parse, and only on the first run of a fresh machine — which is
/// every run CI makes.
///
/// [interactive] is [isInteractiveOutput], which already answers "is stdout a
/// person": false when it is piped, redirected, or a CI log.
bool narrationOwnsStderr({
  required bool speaksProtocol,
  required bool interactive,
}) => speaksProtocol || !interactive;

/// A step long enough that someone will wonder whether it is stuck.
///
/// The answer to that is not a spinner. It is the elapsed time next to the
/// expected one, because `23s / ~25s` reads as fine and `80s / ~25s` reads as
/// wrong, and a spinner animates identically through both.
///
/// Off a terminal it degrades to the single line it would have printed anyway,
/// at the moment it would have printed it: a log gets told the step started and
/// nothing else, which is what makes the failure lines below the only unusual
/// thing in it.
class Step {
  Step(
    this.label, {
    required this.out,
    required this.interactive,
    this.budget,
    this.note,
  });

  /// What is happening, in the present tense and without trailing punctuation —
  /// the ellipsis and the timing are appended.
  final String label;

  final StringSink out;

  /// Whether to draw. See [outputIsInteractive]; passed in rather than read so
  /// that a test writing to a [StringBuffer] gets the non-drawing rendering.
  final bool interactive;

  /// Roughly how long this takes when it is behaving.
  final Duration? budget;

  /// Why it is slow, when that is worth saying once — "first run only".
  final String? note;

  final _watch = Stopwatch();
  Timer? _ticker;

  Duration get elapsed => _watch.elapsed;

  /// Narrates [body], and stops narrating whatever it does.
  ///
  /// [ok] decides which ending is printed, because the failures here are exit
  /// codes rather than exceptions. Passing it is what makes the ticker
  /// impossible to leak: there is no path out of this method that skips the
  /// `finally`.
  Future<T> run<T>(
    Future<T> Function() body, {
    bool Function(T result) ok = _alwaysOk,
  }) async {
    _begin();
    var succeeded = false;
    try {
      var result = await body();
      succeeded = ok(result);
      return result;
    } finally {
      _end(succeeded);
    }
  }

  void _begin() {
    _watch.start();
    if (!interactive) {
      var aside = _describeBudget();
      out.writeln('$label…${aside.isEmpty ? '' : ' ($aside)'}');
      return;
    }
    _paint(_timing());
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _paint(_timing()),
    );
  }

  void _end(bool ok) {
    _ticker?.cancel();
    _watch.stop();
    if (!interactive) return;
    _paint(
      ok ? 'done in ${_seconds(elapsed)}' : 'failed after ${_seconds(elapsed)}',
    );
    out.writeln();
  }

  /// Rewrites the line in place. `\r` returns to its start and `\x1b[K` clears
  /// what the previous, possibly longer, timing left behind.
  void _paint(String suffix) => out.write('\r\x1b[K$label… $suffix');

  String _timing() =>
      '${_seconds(elapsed)}${budget == null ? '' : ' / ~${_seconds(budget!)}'}';

  String _describeBudget() =>
      [if (budget case var budget?) '~${_seconds(budget)}', ?note].join(', ');

  static bool _alwaysOk(Object? result) => true;

  static String _seconds(Duration duration) => '${duration.inSeconds}s';
}

/// Runs a process with its output going to [log] rather than to the terminal.
///
/// Twenty-three seconds of `flutter build` output is not information: it is the
/// same output every time, and the one run in a hundred where it matters is the
/// one that failed — which is what [ProcessLog.tail] is for. Keeping it out of
/// the terminal is also what makes a live [Step] possible at all, since two
/// writers on one stdout cannot both own the last line.
///
/// Deliberately not used for `flutter run`, which owns the terminal on purpose:
/// its `r`/`R`/`q` console is the dev loop, and capturing it would be capturing
/// a UI.
///
/// [verbose] hands the child the terminal instead, and captures nothing — the
/// `-v` escape hatch. Not "capture and also print": a captured child sees a
/// pipe and stops colouring and animating its output, so teeing would show a
/// degraded copy of the very thing being asked for. Handing the terminal over
/// gives it back exactly as the tool meant it, at the cost of the log — which
/// is a fair trade when someone is at the terminal watching.
Future<ProcessLog> runLogged(
  String executable,
  List<String> arguments, {
  required File log,
  String? workingDirectory,
  Map<String, String>? environment,
  bool append = false,
  bool verbose = false,
}) async {
  if (verbose) {
    var process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      mode: ProcessStartMode.inheritStdio,
    );
    // No file: whatever `log` holds is from an earlier run, and reporting a
    // stale tail as this failure's evidence is worse than reporting none.
    return ProcessLog(await process.exitCode, null);
  }

  log.parent.createSync(recursive: true);
  var sink = log.openWrite(mode: append ? FileMode.append : FileMode.write);
  try {
    // So a log holding two commands says which output belongs to which.
    sink.writeln('\$ $executable ${arguments.join(' ')}');
    var process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    // `forEach` rather than `addStream`: both streams are live at once, and an
    // IOSink refuses a second addStream while the first is running.
    await Future.wait([
      process.stdout.forEach(sink.add),
      process.stderr.forEach(sink.add),
    ]);
    return ProcessLog(await process.exitCode, log);
  } finally {
    await sink.flush();
    await sink.close();
  }
}

/// What a captured process left behind.
class ProcessLog {
  ProcessLog(this.exitCode, this.file);

  final int exitCode;

  /// Where the output went, or null when the child was given the terminal and
  /// nothing was captured.
  final File? file;

  bool get ok => exitCode == 0;

  /// Every non-blank line, oldest first.
  ///
  /// Malformed bytes are allowed through: a build tool that emitted something
  /// undecodable has still failed, and refusing to read its log would replace a
  /// real error with a decoding one.
  List<String> lines() {
    if (file case var file? when file.existsSync()) {
      return const LineSplitter()
          .convert(utf8.decode(file.readAsBytesSync(), allowMalformed: true))
          .where((line) => line.trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  /// How many lines of a log a failure quotes.
  ///
  /// Named because two callers need the same window off two different reads:
  /// [tail], and [describeFailure], which slices a list it already holds so
  /// that quoting and recognising cost one read between them.
  static const tailLines = 20;

  /// The last [count] non-blank lines — what a failure is actually about.
  List<String> tail([int count = tailLines]) => lastOf(lines(), count);

  /// The tail of a log already read, so a caller holding [lines] does not
  /// read the file again to quote the end of it.
  static List<String> lastOf(List<String> all, [int count = tailLines]) =>
      all.length <= count ? all : all.sublist(all.length - count);
}

/// How a failed step reports itself: the end of the log, then where the rest is.
///
/// One function so that every failure has both halves. The tail alone is
/// truncated evidence and the path alone is homework.
///
/// Under `-v` there is neither, and that is right: the output the tail would
/// quote already went past on its way to the screen.
///
/// What is quoted and what is *recognised* are deliberately two different
/// reads of the same log. A build tool reports its cause and then keeps going,
/// so the line that explains the failure is routinely nowhere near the end:
/// measured on a consumer's stale hook cache, the kernel-version line sat
/// above the twenty the tail keeps, and a recogniser fed the tail alone stayed
/// silent about the one failure it exists for. The tail is what a person can
/// read; the whole log is what a pattern is matched against. Both come off one
/// [ProcessLog.lines] read, so the second costs nothing.
void describeFailure(StringSink err, String message, ProcessLog log) {
  err.writeln('fw: $message');
  if (log.file case var file?) {
    var all = log.lines();
    for (var line in ProcessLog.lastOf(all)) {
      err.writeln('  $line');
    }
    if (recogniseFailure(all) case var hint?) {
      err.writeln('  $hint');
    }
    err.writeln('  full log: ${file.path}');
  }
}

/// A fix for a failure whose message does not contain one, or null.
///
/// One entry so far and no framework around it: a list of patterns earns its
/// keep when there is a second thing to put in it.
///
/// This can only speak for a process *flutterware* spawned. The same stale
/// cache breaks `dart run flutterware` itself, and that one dies before a line
/// of this package runs — nothing here can reach it.
String? recogniseFailure(List<String> lines) {
  // A build hook is compiled by the SDK that ran it and cached; the next SDK
  // rejects its own cache's kernels and the surfaced error — "Running build
  // hooks failed" — names neither the cache nor the SDK bump that invalidated
  // it. Cost a consumer a few minutes the first time.
  var stale = lines.any(
    (line) => line.contains('Invalid kernel binary format version'),
  );
  if (!stale) return null;
  return 'Those kernels were compiled by a different Dart SDK. Delete the '
      'hook cache and resolve again: '
      '`rm -rf .dart_tool/hooks_runner && dart pub get`.';
}

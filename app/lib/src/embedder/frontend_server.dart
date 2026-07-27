import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';

/// One `frontend_server` process, driven over its line protocol.
///
/// This replaces `package:frontend_server_client`, which spawns the compiler as
/// `Platform.resolvedExecutable <snapshot>` and offers no way to say otherwise.
/// Two things follow from that, and both cost us:
///
/// * inside a Flutter app `resolvedExecutable` is the app binary, so compiling
///   relaunches the app — recursively. That is what forced the compiler out of
///   the GUI in the first place.
/// * it derives the SDK from the same path and hard-codes the argument list, so
///   `--initialize-from-dill` — the flag that turns a cold compile into a warm
///   one — is simply unreachable.
///
/// Neither is a platform limit. `flutter_tools` spawns the compiler itself for
/// exactly these reasons (`packages/flutter_tools/lib/src/compile.dart`), and
/// so do we. [executable] is required and never inferred.
class FrontendServer {
  FrontendServer._(this._process, this._stdout, this._entrypoint);

  final Process _process;
  final StreamQueue<String> _stdout;
  final String _entrypoint;

  var _compiled = false;

  /// Spawns the compiler.
  ///
  /// [executable] is normally `dartaotruntime` and [snapshot] the engine's
  /// `frontend_server_aot.dart.snapshot` — `FlutterCache.dartAotRuntime` and
  /// `FlutterCache.frontendServerSnapshot` name both.
  ///
  /// [initializeFromDill] primes the compiler's incremental state from a kernel
  /// an earlier run produced, which is what makes the *first* compile of a
  /// session incremental rather than cold. A missing or stale file is not an
  /// error — the compiler falls back to compiling everything.
  static Future<FrontendServer> start({
    required String executable,
    required String snapshot,
    required String entrypoint,
    required String outputDill,
    required String packageConfig,
    required String sdkRoot,
    required String platformDill,
    String target = 'flutter',
    String? initializeFromDill,
    List<String> extraArguments = const [],
  }) async {
    File(outputDill).parent.createSync(recursive: true);
    var process = await Process.start(executable, [
      snapshot,
      '--sdk-root', sdkRoot,
      '--platform', platformDill,
      '--target=$target',
      '--output-dill', outputDill,
      '--packages', packageConfig,
      '--incremental',
      if (initializeFromDill != null) ...[
        '--initialize-from-dill',
        initializeFromDill,
      ],
      // The compiler's warnings are not ours to relay; errors come back through
      // the protocol either way.
      '--verbosity=error',
      ...extraArguments,
    ]);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(stderr.writeln);
    return FrontendServer._(
      process,
      StreamQueue(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
      entrypoint,
    );
  }

  /// Compiles, first fully and then incrementally.
  ///
  /// [invalidated] is what changed since the last accepted compile; the
  /// compiler does no invalidation of its own. It is ignored on the first call.
  Future<FrontendServerResult> compile([List<Uri> invalidated = const []]) {
    if (!_compiled) {
      _compiled = true;
      return _run('compile $_entrypoint');
    }
    // The boundary key delimits the uri list; the compiler echoes nothing, so
    // any unique string does. A counter is enough — this is one process talking
    // to one compiler over a pipe.
    var key = 'fw-invalidate-${_boundary++}';
    return _run(
      [
        'recompile $_entrypoint $key',
        ...invalidated.map((u) => '$u'),
        key,
      ].join('\n'),
    );
  }

  var _boundary = 0;

  /// Keeps the last compile's result, so the next one is a delta against it.
  void accept() => _send('accept');

  /// Throws the last compile away, so the next one recompiles the same sources.
  ///
  /// Must be awaited: the compiler replies, and a compile sent before that
  /// reply lands would read it as its own.
  Future<void> reject() async {
    _send('reject');
    var key = await _expectResultLine();
    while (await _stdout.hasNext) {
      if (await _stdout.next == key) return;
    }
  }

  Future<int> shutdown() async {
    _send('quit');
    var kill = Timer(const Duration(seconds: 1), _process.kill);
    var code = await _process.exitCode;
    kill.cancel();
    unawaited(_stdout.cancel());
    return code;
  }

  void _send(String command) => _process.stdin.writeln(command);

  Future<String> _expectResultLine() async {
    var line = await _stdout.next;
    if (!line.startsWith('result ')) {
      throw StateError(
        'expected `result <key>` from the compiler, got:\n$line',
      );
    }
    return line.substring('result '.length);
  }

  Future<FrontendServerResult> _run(String command) async {
    var watch = Stopwatch()..start();
    _send(command);
    var key = await _expectResultLine();

    // Everything up to the key is diagnostics.
    var output = <String>[];
    while (true) {
      var line = await _stdout.next;
      if (line == key) break;
      output.add(line);
    }

    // Then the source diff, terminated by `<key> <dill> <errors>`.
    var newSources = <Uri>{};
    var removedSources = <Uri>{};
    String? dill;
    var errorCount = 0;
    while (true) {
      var line = await _stdout.next;
      if (line.startsWith(key)) {
        var parts = line.split(' ');
        var path = parts.getRange(1, parts.length - 1).join(' ');
        dill = path.isEmpty ? null : path;
        errorCount = int.parse(parts.last);
        break;
      }
      var uri = Uri.parse(line.substring(1));
      (line.startsWith('+') ? newSources : removedSources).add(uri);
    }

    return FrontendServerResult(
      dillOutput: dill,
      errorCount: errorCount,
      output: output,
      newSources: newSources,
      removedSources: removedSources,
      elapsed: watch.elapsed,
    );
  }
}

/// The result of one [FrontendServer.compile].
class FrontendServerResult {
  FrontendServerResult({
    required this.dillOutput,
    required this.errorCount,
    required this.output,
    required this.newSources,
    required this.removedSources,
    required this.elapsed,
  });

  /// The kernel written: the whole program on the first compile, a delta
  /// afterwards. Null when the compiler produced nothing.
  final String? dillOutput;

  final int errorCount;

  /// The compiler's diagnostics, which is where an error's text lives.
  final List<String> output;

  final Set<Uri> newSources;
  final Set<Uri> removedSources;
  final Duration elapsed;

  bool get ok => errorCount == 0 && dillOutput != null;
}

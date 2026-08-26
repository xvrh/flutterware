import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:path/path.dart' as p;

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

  /// Every source the program currently consists of, accumulated from the
  /// `+`/`-` diff each compile reports.
  ///
  /// This is the set to stat when asking what changed — the compiler will not
  /// look, and it is the only place the answer exists: it spans the project,
  /// its path dependencies and the SDK alike, without anyone having to guess
  /// which of those an entry pulls in.
  ///
  /// Not rolled back by [reject], as `flutter_tools` does not roll its own copy
  /// back either: a source the failed compile mentioned is one whose edits we
  /// want to hear about, whether or not it built.
  Set<Uri> get sources => _sources;
  final _sources = <Uri>{};

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
  ///
  /// **[workingDirectory] decides what a diagnostic's path looks like**, and it
  /// is required rather than inherited because inheriting it makes the compiler
  /// speak differently depending on who launched the app. The compiler reports
  /// `<path>:<line>:<col>: Error:` relative to its own directory, and
  /// `CompileBlame` resolves those paths against a root it was told — so the
  /// two have to be the same directory or every error is attributed to no
  /// entry at all.
  ///
  /// Measured: the same catalog audited from `app/` reported
  /// `tool/catalog/demos/broken.dart` and quarantined it, and audited from the
  /// worktree above it reported `app/tool/catalog/demos/broken.dart`, matched
  /// nothing, and failed the whole catalog on one deliberately broken fixture.
  /// Pass the root whatever reads the diagnostics resolves against.
  static Future<FrontendServer> start({
    required String executable,
    required String snapshot,
    required String entrypoint,
    required String outputDill,
    required String packageConfig,
    required String sdkRoot,
    required String platformDill,
    required String workingDirectory,
    String target = 'flutter',
    String? initializeFromDill,
    List<String> extraArguments = const [],
  }) async {
    File(outputDill).parent.createSync(recursive: true);
    var process = await Process.start(executable, [
      snapshot,
      // Both of these reach the front end as **URIs**, not paths. On Windows a
      // bare `C:\...` parses as the scheme `c:`, which `StandardFileSystem`
      // refuses — measured on a CI runner, where every compile died with
      // "StandardFileSystem only supports file:* and data:* URIs" and the
      // audit reported the package unreachable. `flutter_tools` does the same
      // two conversions for the same reason.
      '--sdk-root', _sdkRootArgument(sdkRoot),
      '--platform', Uri.file(p.absolute(platformDill)).toString(),
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
    ], workingDirectory: workingDirectory);
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

  /// Forgets everything accepted so far, so the next [compile] emits a whole
  /// program rather than a delta.
  ///
  /// This is how a guest that is about to be *launched* gets its kernel: it
  /// reads a file, and a delta is not a program. The compiler keeps its parsed
  /// state, so this is far cheaper than restarting it — and unlike a restart it
  /// does not disturb anyone else holding this compiler.
  void reset() => _send('reset');

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
    _sources
      ..addAll(newSources)
      ..removeAll(removedSources);

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

/// [directory] as the front end wants `--sdk-root`: an absolute path ending in
/// a forward slash.
///
/// A *path*, not a URI — the front end percent-encodes what it is given here,
/// so a `file:` URI comes back as `file%3A///...` and the directory is not
/// found. The trailing slash is what makes it resolve the platform dill
/// *inside* the directory rather than beside it, and `flutter_tools` notes at
/// the same line that the forward slash is right even on Windows.
String _sdkRootArgument(String directory) {
  var root = p.absolute(directory).replaceAll(r'\', '/');
  return root.endsWith('/') ? root : '$root/';
}

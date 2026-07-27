import 'dart:io';

import 'package:path/path.dart' as p;

import 'flutter_cache.dart';
import 'frontend_server.dart';

/// The result of one [ResidentCompiler.compile] call.
class CompileOutcome {
  CompileOutcome({
    required this.dillOutput,
    required this.errorCount,
    required this.output,
    required this.elapsed,
    required this.newSourceCount,
  });

  /// The kernel written for this compile — a full dill on the first call, an
  /// incremental delta afterwards. Null when the compiler produced nothing.
  final String? dillOutput;

  final int errorCount;

  /// The compiler's own diagnostics, which is where an error's text lives.
  final List<String> output;

  final Duration elapsed;

  /// How many libraries this compile added, which is ~0 when revisiting an
  /// entry the compiler has already seen.
  final int newSourceCount;

  bool get ok => errorCount == 0 && dillOutput != null;
}

/// A `frontend_server` kept alive across compiles, so the first call is cold
/// and every later one is an incremental recompile of just what changed.
///
/// This is the difference between a catalog that recompiles the world per entry
/// and one that switches in milliseconds; see
/// `docs/superpowers/specs/2026-07-26-s3-hot-switch-findings.md`.
///
/// The *first* compile is warm too when a `warmDill` is given: the compiler
/// loads a kernel an earlier session produced and recompiles only what has
/// changed since. Measured against `app/tool/catalog/demos`, that is 2396ms
/// cold against 341ms warm, and an edited demo still comes back edited.
class ResidentCompiler {
  ResidentCompiler._(this._server, this.outputDill, this._warmDill);

  final FrontendServer _server;

  /// Where the first, full kernel is written. The guest loads this at startup.
  final String outputDill;

  /// Where that kernel is kept for the *next* session to start warm from, or
  /// null when warm starts are off.
  final String? _warmDill;

  static Future<ResidentCompiler> start({
    required String entrypoint,
    required String outputDill,
    required String packageConfig,
    required FlutterCache cache,

    /// Persist the cold kernel and start from it next time.
    ///
    /// Off by default because it costs a file copy and a correctness
    /// assumption: the cached kernel must have been produced by the same SDK
    /// against the same package config. The daemon owns that decision.
    String? warmDill,
  }) async {
    File(outputDill).parent.createSync(recursive: true);
    var warm = warmDill != null && File(warmDill).existsSync()
        ? warmDill
        : null;
    stderr.writeln(
      warm == null
          ? '[compiler] no warm kernel; this compile is cold'
          : '[compiler] starting from $warm',
    );
    var server = await FrontendServer.start(
      executable: cache.dartAotRuntime,
      snapshot: cache.frontendServerSnapshot,
      entrypoint: entrypoint,
      outputDill: outputDill,
      packageConfig: packageConfig,
      sdkRoot: cache.flutterPatchedSdkDir,
      platformDill: cache.platformDill,
      initializeFromDill: warm,
    );
    return ResidentCompiler._(server, outputDill, warmDill);
  }

  /// Compiles, invalidating [invalidated] first.
  ///
  /// A failed compile is **rejected and swallowed**: the caller keeps its guest
  /// and can compile again. A broken demo must not end the session — S3
  /// measured that the guest survives, and this is what preserves it.
  Future<CompileOutcome> compile([List<Uri> invalidated = const []]) async {
    var result = await _server.compile(invalidated);
    if (result.ok) {
      _server.accept();
    } else {
      await _server.reject();
    }
    return CompileOutcome(
      dillOutput: result.dillOutput,
      errorCount: result.errorCount,
      output: result.output,
      elapsed: result.elapsed,
      newSourceCount: result.newSources.length,
    );
  }

  /// Makes the next [compile] emit a whole program at [outputDill], which is
  /// what a guest launched from scratch loads.
  void reset() => _server.reset();

  /// Saves the full kernel at [outputDill] as the next session's warm start.
  ///
  /// Only meaningful right after a successful *full* compile — an incremental
  /// delta is not a program. Copied rather than pointed at, because the
  /// compiler rewrites [outputDill] and would otherwise be reading the file it
  /// is initialising from.
  void saveWarmStart() {
    var warm = _warmDill;
    if (warm == null || !File(outputDill).existsSync()) return;
    Directory(p.dirname(warm)).createSync(recursive: true);
    File(outputDill).copySync(warm);
  }

  Future<void> shutdown() => _server.shutdown();
}

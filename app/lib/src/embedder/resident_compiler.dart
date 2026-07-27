import 'dart:io';

import 'package:frontend_server_client/frontend_server_client.dart';
import 'package:path/path.dart' as p;

import 'flutter_cache.dart';

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
class ResidentCompiler {
  ResidentCompiler._(this._client, this.outputDill);

  final FrontendServerClient _client;

  /// Where the first, full kernel is written. The guest loads this at startup.
  final String outputDill;

  static Future<ResidentCompiler> start({
    required String entrypoint,
    required String outputDill,
    required String packageConfig,
    FlutterCache? cache,
  }) async {
    _refuseToRunInsideAFlutterApp();
    cache ??= FlutterCache.fromRunningSdk();
    File(outputDill).parent.createSync(recursive: true);
    var client = await FrontendServerClient.start(
      entrypoint,
      outputDill,
      cache.platformDill,
      sdkRoot: cache.flutterPatchedSdkDir,
      target: 'flutter',
      packagesJson: packageConfig,
    );
    return ResidentCompiler._(client, outputDill);
  }

  /// Compiles, invalidating [invalidated] first.
  ///
  /// A failed compile is **rejected and swallowed**: the caller keeps its guest
  /// and can compile again. A broken demo must not end the session — S3
  /// measured that the guest survives, and this is what preserves it.
  Future<CompileOutcome> compile([List<Uri> invalidated = const []]) async {
    var watch = Stopwatch()..start();
    var result = await _client.compile(invalidated);
    watch.stop();

    var outcome = CompileOutcome(
      dillOutput: result.dillOutput,
      errorCount: result.errorCount,
      output: result.compilerOutputLines.toList(),
      elapsed: watch.elapsed,
      newSourceCount: result.newSources.length,
    );
    if (outcome.ok) {
      _client.accept();
    } else {
      await _client.reject();
    }
    return outcome;
  }

  Future<void> shutdown() => _client.shutdown();
}

/// `FrontendServerClient` spawns the compiler as
/// `Platform.resolvedExecutable <frontend_server snapshot>`, and offers no way
/// to override the executable.
///
/// Inside a Flutter GUI app `resolvedExecutable` is **the app binary**, so that
/// spawns another copy of the app. If the app starts a compiler on launch, each
/// copy starts another — an exponential fork bomb that fills the machine in
/// seconds. Observed, not theorised.
///
/// This is the concrete reason the catalog pipeline has to stay Flutter-free
/// and run in a plain Dart process, as the master plan already required. Fail
/// loudly rather than let it happen again.
void _refuseToRunInsideAFlutterApp() {
  var executable = p.basenameWithoutExtension(Platform.resolvedExecutable);
  if (executable == 'dart' || executable == 'dartvm') return;
  throw StateError(
    'ResidentCompiler must run in a plain Dart process, but this one is '
    '"${Platform.resolvedExecutable}".\n'
    'FrontendServerClient launches the compiler via Platform.resolvedExecutable, '
    'so running it inside a Flutter app relaunches the app instead — '
    'recursively. Drive it from a separate Dart process.',
  );
}

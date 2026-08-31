import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One data-free viewer bundle: a `flutter build web` target in the app
/// package, compiled once into a fixed directory and copied beside whatever
/// data file an export just wrote.
///
/// Both exporters — scenarios and comparison — are this plus their own data
/// collection, and the half in here is the half that was identical twice:
/// build the bundle if the build system says it is stale, copy it, and be
/// killable, because a `flutter build web` is tens of seconds and a child
/// started with `Process.start` is not killed when the Dart parent exits on
/// macOS.
class ViewerBundle {
  ViewerBundle({
    required this.flutterExecutable,
    required this.appToolRoot,
    required this.target,
    required this.buildDirName,
    required this.label,
  });

  final String flutterExecutable;

  /// Where `flutterware_app` lives — this checkout's `app/`, or the unpacked
  /// copy under `~/.flutterware/` for a hosted install. `flutter build web`
  /// runs here.
  final String appToolRoot;

  /// The entry point, relative to [appToolRoot] — `lib/main_scenarios_web.dart`
  /// or its comparison twin.
  final String target;

  /// The directory under `build/` the bundle compiles to.
  final String buildDirName;

  /// What the bundle is called in the error when it will not compile.
  final String label;

  /// Where the viewer bundle is compiled to.
  ///
  /// A fixed directory under the app package, so `flutter build web`'s own
  /// incremental build decides whether a rebuild is needed. Hand-rolling that
  /// question — hashing a version, stamping a manifest — would be a second
  /// answer to it, and the one that goes stale is always the hand-rolled one.
  String get viewerDir => p.join(appToolRoot, 'build', buildDirName);

  /// Stands in for the `flutter build web` that produces the viewer, so a test
  /// can exercise everything after it — which is where all the logic is —
  /// without a toolchain and a minute of compiling. Reached through the owning
  /// exporter's own `@visibleForTesting` member, which is why this one is not
  /// annotated.
  Future<int> Function(List<String> arguments)? debugCompile;

  /// Compiles the viewer, or lets the build system decide it need not.
  Future<void> build({
    required bool offline,
    void Function(String line)? onOutput,
  }) async {
    onOutput?.call('[export] building the viewer (this is cached after once)');
    var exitCode = await _run([
      'build',
      'web',
      '--release',
      '--target',
      target,
      '--output',
      viewerDir,
      // The page carries its own CanvasKit rather than fetching it from
      // Google's CDN — for a CI artifact read behind a firewall, or after the
      // engine revision it was built against stops being hosted.
      if (offline) '--no-web-resources-cdn',
    ], onOutput);
    if (cancelled) return;
    if (exitCode != 0) {
      throw StateError(
        'The $label did not compile (exit $exitCode). It is '
        "flutterware's own code in $appToolRoot — the error above is a bug in "
        'the tool, not in your project.',
      );
    }
  }

  /// Copies the compiled bundle into [output].
  void copyTo(String output) =>
      _copyDirectory(Directory(viewerDir), Directory(output));

  static void _copyDirectory(Directory source, Directory destination) {
    for (var entity in source.listSync()) {
      var target = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        Directory(target).createSync(recursive: true);
        _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        Directory(p.dirname(target)).createSync(recursive: true);
        entity.copySync(target);
      }
    }
  }

  Process? _process;
  var _cancelled = false;

  /// Whether [cancel] was called — what an exporter checks between its steps.
  bool get cancelled => _cancelled;

  /// Ends the build, if one is running.
  Future<void> cancel() async {
    _cancelled = true;
    _process?.kill();
    _process = null;
  }

  Future<int> _run(
    List<String> arguments,
    void Function(String)? onOutput,
  ) async {
    if (debugCompile case var compile?) return compile(arguments);
    var process = _process = await Process.start(
      flutterExecutable,
      arguments,
      workingDirectory: appToolRoot,
    );
    if (_cancelled) process.kill();
    var lines = <Future<void>>[
      for (var stream in [process.stdout, process.stderr])
        stream
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .forEach((line) => onOutput?.call(line)),
    ];
    var exitCode = await process.exitCode;
    await Future.wait(lines);
    _process = null;
    return exitCode;
  }
}

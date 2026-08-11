import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'frame_ref.dart';
import 'shot_cache.dart';
import 'shot_png.dart';

/// Writes a comparison out as a browsable page.
///
/// The same two halves as `ScenarioWebExporter`, and only the first is a
/// compile. The **viewer** is ours and carries no data —
/// `lib/main_comparison_web.dart` fetches its `index.json` at run time — so it
/// is built from the app package once and reused for every export after that.
/// The **index** is the comparison the caller just ran, with every frame it
/// names encoded to PNG beside it and every reference rewritten to point at
/// the copy.
///
/// Encoding is the one cost the cache's raw-frames rule pays back here: a
/// hosted page downloading 2.5MB of raw rgba per frame is the worse deal, and
/// an export happens once where a capture happens per entry per run.
///
/// The page must be **served**, not opened off the filesystem: it fetches
/// `index.json` and every frame relative to itself, and a browser refuses
/// those on a `file://` page.
class ComparisonWebExporter {
  ComparisonWebExporter({
    required this.flutterExecutable,
    required this.appToolRoot,
  });

  final String flutterExecutable;

  /// Where `flutterware_app` lives — this checkout's `app/`, or the unpacked
  /// copy under `~/.flutterware/` for a hosted install. `flutter build web`
  /// runs here.
  final String appToolRoot;

  /// Where the viewer bundle is compiled to.
  ///
  /// A fixed directory under the app package, so `flutter build web`'s own
  /// incremental build decides whether a rebuild is needed — the same
  /// one-answer rule the scenario exporter wrote down first.
  String get viewerDir => p.join(appToolRoot, 'build', 'comparison_web_viewer');

  /// Preview frames inside a page, relative to it.
  static const shotsDir = 'shots';

  /// Scenario step frames inside a page, relative to it.
  static const framesDir = 'frames';

  /// Stands in for the `flutter build web` that produces the viewer, so a test
  /// can exercise everything after it — which is where all the logic is —
  /// without a toolchain and a minute of compiling.
  @visibleForTesting
  Future<int> Function(List<String> arguments)? debugCompile;

  /// Writes the page: the viewer bundle, the rewritten `index.json`, and a
  /// PNG per frame the index names.
  ///
  /// [index] is the artifact's JSON — `ComparisonArtifact.toJson()`, which is
  /// fresh maps on every call, so rewriting it in place mutates nobody else's
  /// state. [against] is what the page's header says the comparison is
  /// against; the artifact records only the sha.
  Future<ComparisonWebExport> export({
    required Map<String, Object?> index,
    required ShotCache cache,
    required String against,
    required String output,
    String? baseHref,
    bool offline = false,
    void Function(String line)? onOutput,
  }) async {
    var stopwatch = Stopwatch()..start();
    await _buildViewer(offline: offline, onOutput: onOutput);
    if (_cancelled) throw StateError('The export was cancelled.');

    var outputDir = Directory(output);
    // Cleared rather than merged into: an entry renamed since the last export
    // would otherwise keep its frames in the page's tree, where nothing links
    // to them and nothing ever removes them.
    if (outputDir.existsSync()) outputDir.deleteSync(recursive: true);
    outputDir.createSync(recursive: true);

    onOutput?.call('[export] copying the viewer');
    _copyDirectory(Directory(viewerDir), outputDir);
    if (baseHref != null) _setBaseHref(p.join(output, 'index.html'), baseHref);

    onOutput?.call('[export] encoding the frames');
    index['against'] = against;
    var frames = _collect(index, cache: cache, output: output);

    File(
      p.join(output, 'index.json'),
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(index));

    return ComparisonWebExport(
      output: output,
      indexHtml: p.join(output, 'index.html'),
      frames: frames,
      duration: stopwatch.elapsed,
    );
  }

  /// Encodes every frame the index names into the page and rewrites the
  /// references in place: a preview row's cache keys become `shots/<key>.png`,
  /// a scenario step's absolute frame paths become `frames/s<i>/<name>.png`.
  ///
  /// The rewrite is done on the JSON rather than on the model for the same
  /// reason the scenario export's is: this is the whole of it, and a page
  /// whose names point at the copies beside it instead of a cache the reader
  /// does not have.
  int _collect(
    Map<String, Object?> index, {
    required ShotCache cache,
    required String output,
  }) {
    var encoded = 0;

    // The same key twice — the unchanged side of two rows, say — is one file.
    var byKey = <String, String?>{};
    String? shot(String key) => byKey.putIfAbsent(key, () {
      var bytes = cache.read(key);
      var record = cache.meta(key);
      if (bytes == null || record == null) return null;
      var name = p.url.join(shotsDir, '$key.png');
      var file = File(p.join(output, shotsDir, '$key.png'));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(
        encodeRgbaPng(bytes, width: record.width, height: record.height),
      );
      encoded++;
      return name;
    });

    var previews = index['previews'] as Map<String, Object?>? ?? const {};
    for (var item in previews['items'] as List? ?? const []) {
      var shots = (item as Map)['shots'] as Map?;
      if (shots == null) continue;
      for (var side in const ['base', 'head']) {
        var key = shots[side];
        if (key is! String) continue;
        // A key whose frame is gone — evicted mid-export — stays a key: the
        // page 404s on it and the stage says nothing rendered, which is
        // nearer the truth than dropping the reference altogether.
        var name = shot(key);
        if (name != null) shots[side] = name;
      }
    }

    var byPath = <String, String?>{};
    var scenarios = index['scenarios'] as Map<String, Object?>?;
    var scenarioIndex = 0;
    for (var scenario in scenarios?['items'] as List? ?? const []) {
      var into = 's${scenarioIndex++}';
      var taken = <String>{};
      for (var step in (scenario as Map)['steps'] as List? ?? const []) {
        var frames = (step as Map)['frames'] as Map?;
        if (frames == null) continue;
        for (var side in const ['base', 'head']) {
          var frame = frames[side];
          if (frame is! Map) continue;
          var ref = FrameRef.fromJson(frame.cast<String, Object?>());
          if (ref == null || !ref.isDrawable) continue;
          var name = byPath.putIfAbsent(ref.path, () {
            var source = File(ref.path);
            if (!source.existsSync()) return null;
            var base = p.basenameWithoutExtension(ref.path);
            var claimed = '$base.png';
            for (var n = 2; !taken.add(claimed); n++) {
              claimed = '$base-$n.png';
            }
            var file = File(p.join(output, framesDir, into, claimed));
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(
              encodeRgbaPng(
                source.readAsBytesSync(),
                width: ref.width,
                height: ref.height,
              ),
            );
            encoded++;
            return p.url.join(framesDir, into, claimed);
          });
          if (name != null) frame['path'] = name;
        }
      }
    }

    return encoded;
  }

  /// Compiles the viewer, or lets the build system decide it need not.
  Future<void> _buildViewer({
    required bool offline,
    void Function(String line)? onOutput,
  }) async {
    onOutput?.call('[export] building the viewer (this is cached after once)');
    var exitCode = await _run([
      'build',
      'web',
      '--release',
      '--target',
      'lib/main_comparison_web.dart',
      '--output',
      viewerDir,
      // The page carries its own CanvasKit rather than fetching it from
      // Google's CDN — for a CI artifact read behind a firewall, or after the
      // engine revision it was built against stops being hosted.
      if (offline) '--no-web-resources-cdn',
    ], onOutput);
    if (_cancelled) return;
    if (exitCode != 0) {
      throw StateError(
        'The comparison page viewer did not compile (exit $exitCode). It is '
        "flutterware's own code in $appToolRoot — the error above is a bug in "
        'the tool, not in your project.',
      );
    }
  }

  /// Points the page at where it will actually be mounted.
  ///
  /// `flutter build web --base-href` only ever edits this one attribute, so
  /// doing it here instead is what lets one compiled bundle serve every mount
  /// point.
  void _setBaseHref(String indexHtml, String baseHref) {
    var file = File(indexHtml);
    if (!file.existsSync()) return;
    file.writeAsStringSync(
      file.readAsStringSync().replaceAll(
        RegExp(r'<base href="[^"]*">'),
        '<base href="$baseHref">',
      ),
    );
  }

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

  /// Ends the export, if one is running.
  ///
  /// A `flutter build web` is tens of seconds, and a child started with
  /// `Process.start` is not killed when the Dart parent exits on macOS.
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

/// What a finished export produced.
class ComparisonWebExport {
  ComparisonWebExport({
    required this.output,
    required this.indexHtml,
    required this.frames,
    required this.duration,
  });

  /// The directory to serve. Absolute.
  final String output;

  final String indexHtml;

  /// PNGs encoded in beside the page.
  final int frames;

  final Duration duration;
}

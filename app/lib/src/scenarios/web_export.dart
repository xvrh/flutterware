import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'web_report.dart';

/// Writes a run out as a browsable page.
///
/// Two halves, and only the first is a compile. The **viewer** is ours and
/// carries no data — `lib/main_scenarios_web.dart` fetches its report at run
/// time — so it is built from the app package once and reused for every export
/// after that. The **report** is the run the caller just did, with every
/// artifact copied in beside it and every path rewritten to point at the copy.
///
/// So an export is: build the viewer if the build system says it is stale, copy
/// a few hundred kilobytes, and write one JSON file. The compile is the
/// exception rather than the cost.
///
/// The page must be **served**, not opened off the filesystem: it fetches
/// `report.json` and every artifact relative to itself, and a browser refuses
/// those on a `file://` page. `CatalogWebServer` is what the GUI and
/// `--serve` put in front of it.
///
/// See `2026-08-11-scenario-web-export-design.md`.
class ScenarioWebExporter {
  ScenarioWebExporter({
    required this.flutterExecutable,
    required this.appToolRoot,
    required this.worktreeRoot,
  });

  final String flutterExecutable;

  /// Where `flutterware_app` lives — this checkout's `app/`, or the unpacked
  /// copy under `~/.flutterware/` for a hosted install. `flutter build web`
  /// runs here.
  final String appToolRoot;

  /// What the run's artifact paths are relative to.
  final String worktreeRoot;

  /// Where the page goes when nobody says. Package-relative, and spelled with
  /// `/` because it is also what the dialog puts in a text field and what the
  /// action's help says.
  static const defaultOutput = 'build/scenarios/web';

  static String defaultOutputIn(String packageRoot) =>
      p.join(packageRoot, 'build', 'scenarios', 'web');

  /// Where the viewer bundle is compiled to.
  ///
  /// A fixed directory under the app package, so `flutter build web`'s own
  /// incremental build decides whether a rebuild is needed. Hand-rolling that
  /// question — hashing a version, stamping a manifest — would be a second
  /// answer to it, and the one that goes stale is always the hand-rolled one.
  String get viewerDir => p.join(appToolRoot, 'build', 'scenario_web_viewer');

  /// The artifact directory inside a page, relative to it.
  static const artifactsDir = 'artifacts';

  /// Stands in for the `flutter build web` that produces the viewer, so a test
  /// can exercise everything after it — which is where all the logic is —
  /// without a toolchain and a minute of compiling.
  @visibleForTesting
  Future<int> Function(List<String> arguments)? debugCompile;

  Future<ScenarioWebExport> export({
    required ScenarioWebReport report,
    required String output,
    String? baseHref,
    bool offline = false,
    void Function(String line)? onOutput,
  }) async {
    var stopwatch = Stopwatch()..start();
    await _buildViewer(offline: offline, onOutput: onOutput);
    if (_cancelled) throw StateError('The export was cancelled.');

    var outputDir = Directory(output);
    // Cleared rather than merged into: a scenario deleted since the last export
    // would otherwise keep its screenshots in the page's artifact tree, where
    // nothing links to them and nothing ever removes them.
    if (outputDir.existsSync()) outputDir.deleteSync(recursive: true);
    outputDir.createSync(recursive: true);

    onOutput?.call('[export] copying the viewer');
    _copyDirectory(Directory(viewerDir), outputDir);
    if (baseHref != null) _setBaseHref(p.join(output, 'index.html'), baseHref);

    onOutput?.call('[export] collecting the artifacts');
    var json = report.toJson();
    var copied = _collect(
      (json['run']! as Map).cast<String, Object?>(),
      output,
    );

    File(
      p.join(output, scenarioWebReportFile),
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));

    return ScenarioWebExport(
      output: output,
      indexHtml: p.join(output, 'index.html'),
      scenarios: report.outcomes.length,
      steps: report.outcomes.fold(0, (n, entry) => n + entry.$2.steps.length),
      artifacts: copied,
      duration: stopwatch.elapsed,
    );
  }

  /// Copies every artifact the run names into the page and rewrites its paths
  /// in place. [run] is the serialized [ScenarioRunResult] — the envelope's
  /// `run`, not the envelope.
  ///
  /// The rewrite is done on the JSON rather than on the model because that is
  /// the whole of it: five path fields per step, and a page whose paths point
  /// at the copies beside it instead of at a worktree the reader does not have.
  ///
  /// Laid out one directory per scenario, keeping each file's own name — a
  /// human opening `artifacts/` should recognise what they are looking at, and
  /// the harness already names steps after the shot that took them.
  int _collect(Map<String, Object?> run, String output) {
    var copied = 0;
    var scenarioIndex = 0;
    for (var package in (run['packages'] as List? ?? const [])) {
      for (var outcome
          in ((package as Map)['scenarios'] as List? ?? const [])) {
        var into = 's${scenarioIndex++}';
        var taken = <String>{};

        /// A page-relative name under this scenario's directory that no
        /// sibling has taken.
        String claim(String source) {
          var name = p.basename(source);
          for (var n = 2; !taken.add(name); n++) {
            name =
                '${p.basenameWithoutExtension(source)}-$n'
                '${p.extension(source)}';
          }
          return name;
        }

        for (var step in ((outcome as Map)['steps'] as List? ?? const [])) {
          for (var key in const ['image', 'tree', 'semantics', 'events']) {
            var source = (step as Map)[key];
            if (source is! String) continue;
            var from = File(p.join(worktreeRoot, source));
            if (!from.existsSync()) {
              // The report keeps naming it, and the page says the file is
              // gone — which is the truth, and better than a path that
              // resolves to nothing with no explanation.
              continue;
            }
            var name = claim(source);
            var destination = p.join(output, artifactsDir, into, name);
            Directory(p.dirname(destination)).createSync(recursive: true);
            from.copySync(destination);
            step[key] = p.url.join(artifactsDir, into, name);
            copied++;
          }

          // What the flow produced, on the same terms as the four above: a
          // page a reviewer downloads is exactly where a generated document
          // is worth having, and it is the one artifact that is the point of
          // the step rather than a description of it.
          for (var attachment
              in ((step as Map)['attachments'] as List? ?? const [])) {
            var source = (attachment as Map)['file'];
            if (source is! String) continue;
            var from = File(p.join(worktreeRoot, source));
            if (!from.existsSync()) continue;
            var name = claim(source);
            var destination = p.join(output, artifactsDir, into, name);
            Directory(p.dirname(destination)).createSync(recursive: true);
            from.copySync(destination);
            attachment['file'] = p.url.join(artifactsDir, into, name);
            copied++;
          }

          // The recorded transition is **not** exported (owner, 2026-08-11:
          // "this would be too big"). A recording is by far the bulkiest thing
          // a run produces — every frame of every transition, against five
          // small files for the step itself — and a page is a thing people
          // download.
          //
          // Stripped rather than merely not copied: a run that recorded is
          // reachable (the panel records by default), and a step that kept its
          // frame fields with no frames beside them would put a play button on
          // the page that fetches nothing and never moves. The viewer asks
          // `hasMotion`, and this is the answer.
          for (var key in const [
            'frames',
            'frameCount',
            'frameWidth',
            'frameHeight',
            'frameIntervalMs',
            'framesDropped',
          ]) {
            (step as Map).remove(key);
          }
        }
      }
    }
    return copied;
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
      'lib/main_scenarios_web.dart',
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
        'The scenario page viewer did not compile (exit $exitCode). It is '
        "flutterware's own code in $appToolRoot — the error above is a bug in "
        'the tool, not in your project.',
      );
    }
  }

  /// Points the page at where it will actually be mounted.
  ///
  /// `flutter build web --base-href` only ever edits this one attribute, so
  /// doing it here instead is what lets one compiled bundle serve every mount
  /// point — including two exports of the same run to two different ones.
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
class ScenarioWebExport {
  ScenarioWebExport({
    required this.output,
    required this.indexHtml,
    required this.scenarios,
    required this.steps,
    required this.artifacts,
    required this.duration,
  });

  /// The directory to serve. Absolute.
  final String output;

  final String indexHtml;
  final int scenarios;
  final int steps;

  /// Files copied in beside the page — screenshots, trees, semantics, events.
  final int artifacts;

  final Duration duration;
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import '../scenarios/runner.dart';
import 'build_directory.dart';
import 'frame_ref.dart';
import 'scenario_alignment.dart';
import 'scenario_comparison.dart';

/// Running one checkout's scenarios and reading back what they captured.
///
/// The scenario twin of `PreviewsSide`, and shaped differently for a reason
/// the design doc argues at length: a preview is one picture and a scenario is
/// a *tree* of them, so there is nothing here that fits the entry-shaped
/// runner. What it produces is what [ScenarioComparison] aligns.
class ScenariosSide {
  ScenariosSide({
    required this.flutterSdkRoot,
    required this.packagePath,
    required this.directory,
  });

  final String flutterSdkRoot;

  /// The package inside each checkout, relative to its top level.
  final String packagePath;

  /// The scenario directory inside the package, as the project declares it.
  ///
  /// Taken from the **head** checkout for both sides, like the previews scan
  /// root: a branch that moved its scenarios would otherwise compare the old
  /// directory against the new one and report every scenario as removed and
  /// re-added.
  final String directory;

  /// What `clock.now()` reads inside every scenario of both runs.
  ///
  /// The same pin previews got, for the same reason and through the harness's
  /// own `clock` argument: a scenario that shows a date differs from itself
  /// every day otherwise. `ScenarioRunArgs.clockOrigin`'s doc comment named
  /// this feature as its purpose before the feature existed.
  static final clock = DateTime(2026, 1, 1, 9, 41);

  /// An id is `<file>#<scenario>` — the same grammar a preview entry uses, and
  /// the same reason: the file alone does not name one, since a file holds
  /// several.
  static String idFor({required String file, required String scenario}) =>
      '$file#$scenario';

  /// Where a scenario's source lives, relative to a checkout root.
  String fileOf(String id) {
    var hash = id.indexOf('#');
    return p.normalize(
      p.join(packagePath, hash < 0 ? id : id.substring(0, hash)),
    );
  }

  /// Every scenario [checkout] declares, as ids.
  ///
  /// Live rather than scanned: only the running harness knows a scenario's
  /// tags and its folder profile, and this has to start a runner to run
  /// anything anyway.
  Future<List<String>> scenarios(ScenarioRunner runner) async => [
    for (var listing in await runner.list())
      idFor(file: listing.file, scenario: listing.name),
  ];

  /// A runner for [checkout], building in a claimed directory of its own.
  ///
  /// Never the default `build/flutterware`: the head checkout is the very
  /// worktree the panel's warm runner lives on, the base checkout is shared
  /// by every comparison on the machine, and `TesterHost.exclusive`
  /// serializes nothing across hosts. Whoever disposes the runner releases
  /// the claim — `LiveScenarioSource.dispose` does.
  ScenarioRunner runnerFor(String checkout) {
    var packageRoot = p.normalize(p.join(checkout, packagePath));
    return ScenarioRunner(
      packageRoot: packageRoot,
      directory: directory,
      flutterSdkRoot: flutterSdkRoot,
      buildDirectory: claimComparisonBuildDirectory(packageRoot),
    );
  }

  /// Runs [id] and reads back every step it captured.
  ///
  /// Raw captures, never PNG, and not for the 31% it happens to be worth
  /// here: the diff reads every pixel, and `fw compare` is a CLI command, so
  /// the decode PNG would force has no engine codec to do it with. It would
  /// fall to `package:image` in pure Dart, on every frame of both sides, to
  /// undo an encode this had just paid for. See `ScenarioRunArgs.captureRaw`.
  ///
  /// The clock is pinned so two runs a day apart produce the same pictures.
  Future<List<ScenarioStepShot>> run(
    ScenarioRunner runner,
    String id, {
    required String outDir,
  }) async {
    var hash = id.indexOf('#');
    var response = await runner.run(
      outDir: outDir,
      file: hash < 0 ? id : id.substring(0, hash),
      scenario: hash < 0 ? null : id.substring(hash + 1),
      captureRaw: true,
      clock: clock,
    );
    var scenarios = (response['scenarios'] as List?) ?? const [];
    var outcome = scenarios.firstOrNull;
    if (outcome is! Map) return const [];
    return [
      for (var step in (outcome['steps'] as List?) ?? const [])
        if (step is Map) _shotOf(step.cast<String, Object?>()),
    ];
  }

  static ScenarioStepShot _shotOf(Map<String, Object?> step) {
    var image = step['image'] as String?;
    return ScenarioStepShot(
      step: AlignableStep(
        index: step['index']! as int,
        position: step['position'] as String? ?? '',
        parent: step['parent'] as int?,
        branch: step['branch'] as String?,
        name: step['name'] as String?,
        verb: step['verb'] as String?,
        target: step['target'] as String?,
      ),
      // Only a raw capture is comparable as pixels. A PNG here would mean the
      // run was asked for one, which this never does — and decoding it to
      // compare would undo the reason raw exists.
      rgba: step['format'] == 'raw' && image != null ? _bytes(image) : null,
      width: step['width'] as int? ?? 0,
      height: step['height'] as int? ?? 0,
      tree: _tree(step['tree'] as String?),
      texts: (step['texts'] as List?)?.cast<String>() ?? const [],
      events: _events(step['events'] as String?),
      failure: step['failure'] as String?,
      frame: step['format'] == 'raw' && image != null
          ? FrameRef(
              path: image,
              width: step['width'] as int? ?? 0,
              height: step['height'] as int? ?? 0,
            )
          : null,
    );
  }

  static Uint8List? _bytes(String path) {
    var file = File(path);
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  static InspectNode? _tree(String? path) {
    if (path == null) return null;
    var file = File(path);
    if (!file.existsSync()) return null;
    try {
      var json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?>) return null;
      // The harness writes `InspectTree.toJson`, whose root is the node.
      var root = json['root'];
      return root is Map<String, Object?> ? InspectNode.fromJson(root) : null;
    } on FormatException {
      return null;
    }
  }

  static List<Map<String, Object?>> _events(String? path) {
    if (path == null) return const [];
    var file = File(path);
    if (!file.existsSync()) return const [];
    try {
      var json = jsonDecode(file.readAsStringSync());
      var list = json is Map ? json['events'] : json;
      return [
        for (var event in list as List? ?? const [])
          if (event is Map) event.cast<String, Object?>(),
      ];
    } on FormatException {
      return const [];
    }
  }
}

/// The disk-facing half of the run report — what a `tool/` script calls.
///
/// Split from `report.dart` because the model itself must stay importable in
/// a browser (the exported scenario page parses it), and this half reads
/// files.
library;

import 'dart:convert';
import 'dart:io';

import '../app_events/events.dart';
import 'report.dart';

/// A written run, read back.
///
/// ```dart
/// var report = await ScenarioRunReport.read('build/flutterware/screenshots');
/// for (var package in report.run.packages) {
///   for (var scenario in package.scenarios) {
///     if (scenario.ok) continue;
///     var step = scenario.steps.last;
///     await service.upload(report.file(step.image), scenario.name);
///   }
/// }
/// ```
class ScenarioRunReport {
  const ScenarioRunReport({
    required this.directory,
    this.root = '.',
    required this.run,
  });

  /// Where `run.json` was found.
  final String directory;

  /// What a step's artifact paths resolve against — the worktree the run
  /// executed in, not [directory]. They are recorded worktree-relative so the
  /// report survives being read on another machine; a reader elsewhere passes
  /// its own checkout here. Not serialized, for the same reason.
  final String root;

  final ScenarioRunResult run;

  /// Reads the `run.json` in [directory].
  ///
  /// [root] is what [file] will resolve artifact paths against — the worktree
  /// the run executed in; the default only suits a script running at that
  /// worktree's root.
  ///
  /// Throws [FormatException] when the directory holds no report, or holds one
  /// this version cannot read. Both name what was found and what was expected:
  /// the reader of this message is looking at somebody else's build output.
  static Future<ScenarioRunReport> read(
    String directory, {
    String root = '.',
  }) async {
    var file = File(
      '$directory${Platform.pathSeparator}$scenarioRunReportFile',
    );
    if (!file.existsSync()) {
      throw FormatException(
        'No $scenarioRunReportFile in "$directory". '
        'Run `fw run scenarios run` first.',
      );
    }
    return ScenarioRunReport(
      directory: directory,
      root: root,
      run: ScenarioRunResult.fromJson(switch (jsonDecode(
        await file.readAsString(),
      )) {
        Map json => json.cast<String, Object?>(),
        var other => throw FormatException(
          '${file.path} is ${other.runtimeType}, not an object.',
        ),
      }),
    );
  }

  /// Turns a step's artifact path — [ScenarioRunStep.image], its tree, its
  /// events — into a file. Worktree-relative paths resolve against [root]; a
  /// run sent outside the worktree with `--output` records absolute paths,
  /// which pass through.
  File file(String path) {
    var native = path.replaceAll('/', Platform.pathSeparator);
    return File(
      File(native).isAbsolute
          ? native
          : '$root${Platform.pathSeparator}$native',
    );
  }

  /// The transition's events for [step], typed — empty for a quiet
  /// transition, which is most of them.
  List<AppEvent> events(ScenarioRunStep step) {
    var path = step.events;
    if (path == null) return const [];
    var eventsFile = file(path);
    if (!eventsFile.existsSync()) return const [];
    return [
      for (var event in jsonDecode(eventsFile.readAsStringSync()) as List)
        if (event is Map) AppEvent.fromJson(event.cast<String, Object?>()),
    ];
  }
}

/// Reads the `index.json` a matrix run wrote at the root of its output tree.
///
/// Each entry's [ScenarioRunIndexEntry.output] is relative to [directory];
/// the directory it names holds that point's own `run.json`, which
/// [ScenarioRunReport.read] takes from there.
///
/// Throws [FormatException] when the directory holds no index, or holds one
/// this version cannot read.
Future<ScenarioRunIndex> readScenarioRunIndex(String directory) async {
  var file = File('$directory${Platform.pathSeparator}$scenarioRunIndexFile');
  if (!file.existsSync()) {
    throw FormatException(
      'No $scenarioRunIndexFile in "$directory". Only a matrix run '
      '(`devices=` / `languages=`) writes one, at the root of its output '
      'tree.',
    );
  }
  return ScenarioRunIndex.fromJson(switch (jsonDecode(
    await file.readAsString(),
  )) {
    Map json => json.cast<String, Object?>(),
    var other => throw FormatException(
      '${file.path} is ${other.runtimeType}, not an object.',
    ),
  });
}

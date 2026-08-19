import '../plugins/native/scenarios_results.dart';

/// What the export writes beside the page, and what the page reads back.
///
/// A thin envelope around the run itself rather than a second model of it: the
/// steps, their artifacts and their events are exactly what `fw run scenarios
/// run` produces, so the viewer renders the same widgets the panel does from
/// the same classes. What the envelope adds is the little a page needs and a
/// run does not carry — what to call itself, and when it was made.
///
/// Hand-written rather than generated: three fields, one of which already
/// knows how to serialize itself.
class ScenarioWebReport {
  ScenarioWebReport({
    required this.title,
    required this.generated,
    required this.run,
  });

  factory ScenarioWebReport.fromJson(Map<String, Object?> json) =>
      ScenarioWebReport(
        title: json['title'] as String? ?? 'Scenarios',
        generated:
            DateTime.tryParse(json['generated'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        run: ScenarioRunResult.fromJson(
          (json['run']! as Map).cast<String, Object?>(),
        ),
      );

  /// What the page calls itself — the project, normally.
  final String title;

  /// When the scenarios were run. A page is a photograph, and a photograph
  /// with no date on it is one nobody can tell is stale.
  final DateTime generated;

  final ScenarioRunResult run;

  /// Every scenario of every package, in the order they ran — the list the
  /// page's left pane is built from.
  Iterable<(ScenarioRunPackage, ScenarioRunOutcome)> get outcomes sync* {
    for (var package in run.packages) {
      for (var outcome in package.scenarios) {
        yield (package, outcome);
      }
    }
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'generated': generated.toUtc().toIso8601String(),
    'run': run.toJson(),
  };
}

/// The file the page fetches, relative to itself.
const scenarioWebReportFile = 'report.json';

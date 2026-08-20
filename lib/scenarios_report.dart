/// What a scenario run wrote to disk, typed — the reader for `run.json`.
///
/// Every `fw run scenarios run` writes its whole report beside its artifacts:
/// every step of every scenario, each with its screenshot, widget tree,
/// visible texts, semantics and events as paths. This library reads that back
/// so a project's `tool/` script — a CI gate, a screenshot uploader, a custom
/// report — is a few lines over typed classes rather than a map walk written
/// once per project:
///
/// * [ScenarioRunReport.read] takes a run's output directory and hands back
///   the [ScenarioRunResult] with a way to open what its steps name.
/// * [compareScenarioRuns] takes two of those and says which steps moved —
///   the check that a green suite is also a *deterministic* one.
/// * [readScenarioRunIndex] reads the `index.json` a matrix run leaves at the
///   root of its output tree — the entry point a CI job walks.
/// * [ScenarioEvent.fromJson] (from `package:flutterware/scenarios.dart`)
///   types the `.events.json` a step points at; [ScenarioRunReport.events]
///   does the read.
///
/// **This is published API.** A field renamed here breaks somebody's script,
/// which is why [scenarioRunReportVersion] exists and why the readers refuse
/// a major they do not know rather than handing back a half-decoded object.
///
/// **Plain Dart on purpose — nothing here may import `package:flutter`.** The
/// script that consumes a run executes under a bare `dart run`, exactly like
/// `tool/flutterware.dart` does.
library;

export 'src/scenarios/events.dart' show ScenarioChannel, ScenarioEvent;
export 'src/scenarios/report.dart';
export 'src/scenarios/report_io.dart';

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'scenarios_results.dart';

/// The transition's events, read from the file the harness wrote beside the
/// pixels — empty when there were none, and empty rather than throwing when
/// the file cannot be read: a missing artifact must not take a failure report
/// down with it.
List<Map<String, Object?>> readStepEvents(ScenarioRunStep step) {
  var path = step.events;
  if (path == null) return const [];
  var file = File(p.join(step.root, path));
  if (!file.existsSync()) return const [];
  try {
    return [
      for (var event in jsonDecode(file.readAsStringSync()) as List)
        (event as Map).cast<String, Object?>(),
    ];
  } catch (_) {
    return const [];
  }
}

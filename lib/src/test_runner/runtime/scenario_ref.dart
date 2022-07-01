import 'package:flutterware/src/test_runner/runtime/runner.dart';

import 'scenario.dart';

class ScenarioRef {
  final List<String> name;
  final TestCallback scenario;

  ScenarioRef(this.name, this.scenario);

  static Iterable<ScenarioRef> flatten(Map<String, dynamic> scenarios) {
    return _listScenarios([], scenarios);
  }

  static Iterable<ScenarioRef> _listScenarios(
      List<String> parents, Map<String, dynamic> scenarios) sync* {
    for (var entry in scenarios.entries) {
      var value = entry.value;
      var name = [...parents, entry.key];
      if (value is TestCallback) {
        yield ScenarioRef(name, value);
      } else if (value is Map<String, dynamic>) {
        yield* _listScenarios(name, value);
      } else {
        throw StateError(
            'Scenarios map should only contains Scenario or Map<String, dynamic>');
      }
    }
  }
}

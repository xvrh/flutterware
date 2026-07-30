import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_address.dart';

void main() {
  test('round-trips the package list', () {
    var segments = scenarioSegments('examples/example');
    expect(segments, ['examples/example']);
    expect(scenarioPlace(segments), const ScenarioPlace('examples/example'));
  });

  test('round-trips a file', () {
    var segments = scenarioSegments(
      '.',
      file: 'test/scenarios/counter_test.dart',
    );
    expect(segments, ['.', 'test', 'scenarios', 'counter_test.dart']);
    expect(
      scenarioPlace(segments),
      const ScenarioPlace('.', file: 'test/scenarios/counter_test.dart'),
    );
  });

  test('round-trips a scenario', () {
    var place = const ScenarioPlace(
      'examples/example',
      file: 'test/scenarios/counter_test.dart',
      scenario: 'Counter',
    );
    var segments = scenarioSegments(
      place.package,
      file: place.file,
      scenario: place.scenario,
    );
    expect(scenarioPlace(segments), place);
  });

  test('reads an unrecognised tail as the nearest known place', () {
    expect(scenarioPlace([]), isNull);
    expect(scenarioPlace(['app', 'not-a-file']), const ScenarioPlace('app'));
    expect(
      scenarioPlace(['app', 'a', 'b.dart', 'Name', 'extra']),
      const ScenarioPlace('app', file: 'a/b.dart', scenario: 'Name'),
    );
  });
}

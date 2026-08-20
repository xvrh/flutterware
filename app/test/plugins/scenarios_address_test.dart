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

  test('round-trips a step', () {
    var place = const ScenarioPlace(
      'examples/example',
      file: 'test/scenarios/counter_test.dart',
      scenario: 'Counter',
      step: 3,
    );
    var segments = scenarioSegments(
      place.package,
      file: place.file,
      scenario: place.scenario,
      step: place.step,
    );
    expect(segments.last, '3');
    expect(scenarioPlace(segments), place);
  });

  // A document or a notification is a step of the run like any other, so it
  // is addressed by its own index. There is no level below the step any more:
  // the trailing segment a stale link carries is ignored rather than read as a
  // position inside somebody else's record.
  test('a segment past the step is ignored', () {
    var place = scenarioPlace([
      'examples/example',
      'test',
      'scenarios',
      'counter_test.dart',
      'Counter',
      '3',
      '1',
    ]);
    expect(place?.step, 3);
    expect(
      scenarioSegments(
        place!.package,
        file: place.file,
        scenario: place.scenario,
        step: place.step,
      ).last,
      '3',
    );
  });

  test('round-trips the help page', () {
    var segments = scenarioSegments('examples/example', help: true);
    expect(segments, ['examples/example', 'help']);
    expect(
      scenarioPlace(segments),
      const ScenarioPlace('examples/example', help: true),
    );
    // And it is a place of its own, not the package list wearing a flag.
    expect(
      scenarioPlace(['examples/example']),
      isNot(const ScenarioPlace('examples/example', help: true)),
    );
  });

  test('reads an unrecognised tail as the nearest known place', () {
    expect(scenarioPlace([]), isNull);
    expect(scenarioPlace(['app', 'not-a-file']), const ScenarioPlace('app'));
    // A non-numeric tail past the scenario is not a step.
    expect(
      scenarioPlace(['app', 'a', 'b.dart', 'Name', 'extra']),
      const ScenarioPlace('app', file: 'a/b.dart', scenario: 'Name'),
    );
  });
}

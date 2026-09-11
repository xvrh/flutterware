import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_address.dart';

void main() {
  test('round-trips the package list', () {
    var segments = scenarioSegments('fixtures/probe_app');
    expect(segments, ['fixtures/probe_app']);
    expect(scenarioPlace(segments), const ScenarioPlace('fixtures/probe_app'));
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
      'fixtures/probe_app',
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
      'fixtures/probe_app',
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
      'fixtures/probe_app',
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
    var segments = scenarioSegments('fixtures/probe_app', help: true);
    expect(segments, ['fixtures/probe_app', 'help']);
    expect(
      scenarioPlace(segments),
      const ScenarioPlace('fixtures/probe_app', help: true),
    );
    // And it is a place of its own, not the package list wearing a flag.
    expect(
      scenarioPlace(['fixtures/probe_app']),
      isNot(const ScenarioPlace('fixtures/probe_app', help: true)),
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

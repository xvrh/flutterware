import 'package:flutterware/flutter_test.dart';

/// The one rung of the network ladder that used to lose silently.
///
/// `--network=record` is always a deliberate act at a command line, and a
/// scenario stating its own mode overrules it — correctly, since nearest wins.
/// What was missing is anybody saying so: a consumer ran a record against a
/// scenario declaring `replay`, watched it pass, and found the store empty.
void main() {
  group('recordOverriddenMessage', () {
    test('names the scenario, its mode and the altitude that can record', () {
      var said = recordOverriddenMessage(
        'Store',
        ScenarioNetwork.replay,
        ScenarioNetwork.record,
      );

      expect(said, isNotNull);
      expect(said, contains('"Store"'));
      expect(said, contains('network: replay'));
      expect(said, contains('runScenarios(network: ...)'));
      expect(said, contains('flutter_test_config.dart'));
    });

    test('says nothing when the run asked for anything else', () {
      for (var run in [
        ScenarioNetwork.off,
        ScenarioNetwork.live,
        ScenarioNetwork.replay,
        null,
      ]) {
        expect(
          recordOverriddenMessage('Store', ScenarioNetwork.replay, run),
          isNull,
          reason: 'only a record run loses something it cannot get back',
        );
      }
    });

    test('says nothing when the scenario stated nothing', () {
      expect(
        recordOverriddenMessage('Store', null, ScenarioNetwork.record),
        isNull,
      );
    });

    test('says nothing when the scenario agrees', () {
      expect(
        recordOverriddenMessage(
          'Store',
          ScenarioNetwork.record,
          ScenarioNetwork.record,
        ),
        isNull,
      );
    });
  });

  group('inertNetworkMessage', () {
    String? said(
      ScenarioNetwork reach, {
      bool stated = true,
      int requests = 0,
    }) =>
        inertNetworkMessage('Store', reach, stated: stated, requests: requests);

    test('names the mode and the layer that hides a request from it', () {
      var message = said(ScenarioNetwork.replay);

      expect(message, isNotNull);
      expect(message, contains('"Store"'));
      expect(message, contains('network: replay'));
      expect(message, contains('CachedNetworkImage'));
      expect(message, contains('getFileStream'));
    });

    test('says nothing once a single request was made', () {
      for (var reach in [
        ScenarioNetwork.replay,
        ScenarioNetwork.record,
        ScenarioNetwork.live,
      ]) {
        expect(said(reach, requests: 1), isNull);
      }
    });

    test('says nothing about off, which is what no requests looks like', () {
      expect(said(ScenarioNetwork.off), isNull);
    });

    test('holds only a scenario that stated the mode for itself', () {
      // A folder's `runScenarios(network: ...)` covers a whole suite, where
      // most scenarios legitimately fetch nothing.
      expect(said(ScenarioNetwork.replay, stated: false), isNull);
    });
  });
}

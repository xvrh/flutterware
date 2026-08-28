import 'package:flutterware/plugins.dart';
import 'package:test/test.dart';

/// `fw.network(...)`: the lowest of the four altitudes, and the one a project
/// states once.
void main() {
  test('a project that says nothing carries nothing', () {
    var config = FlutterwareConfig();
    expect(config.toManifest().network, isNull);
  });

  test('what it declares survives the wire', () {
    var config = FlutterwareConfig()..network(ScenarioNetwork.replay);
    var manifest = PluginManifest.fromJson(config.toManifest().toJson());
    expect(manifest.network, ScenarioNetwork.replay);
  });

  test('every mode survives the wire', () {
    for (var mode in ScenarioNetwork.values) {
      var config = FlutterwareConfig()..network(mode);
      expect(
        PluginManifest.fromJson(config.toManifest().toJson()).network,
        mode,
      );
    }
  });

  // Refused rather than resolved, like `fw.clock` and for the same reason: a
  // config with two answers loses one of them, and the loss is silent.
  test('declared twice is a refusal, not a last-writer-wins', () {
    var config = FlutterwareConfig()..network(ScenarioNetwork.replay);
    expect(
      () => config.network(ScenarioNetwork.live),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('fw.network was called twice'),
        ),
      ),
    );
  });

  test('a manifest naming a mode nothing knows decodes as nothing', () {
    var json = (FlutterwareConfig()..network(ScenarioNetwork.live))
        .toManifest()
        .toJson();
    json['network'] = 'sideways';
    expect(PluginManifest.fromJson(json).network, isNull);
  });
}
